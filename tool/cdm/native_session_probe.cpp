// Flutify native Widevine ABI/session probe. No browser, account or network I/O.
// Uses the versioned Chromium CDM interfaces declared in the adjacent header.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <chrono>
#include <cstdint>
#include <functional>
#include <iostream>
#include <new>
#include <string>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

#include "content_decryption_module.h"

using SteadyClock = std::chrono::steady_clock;

class ProbeBuffer final : public cdm::Buffer {
 public:
  explicit ProbeBuffer(uint32_t capacity) : data_(capacity) {}
  void Destroy() override { delete this; }
  uint32_t Capacity() const override { return static_cast<uint32_t>(data_.size()); }
  uint8_t* Data() override { return data_.data(); }
  void SetSize(uint32_t size) override { size_ = size <= Capacity() ? size : 0; }
  uint32_t Size() const override { return size_; }
 private:
  std::vector<uint8_t> data_;
  uint32_t size_ = 0;
};

template <class Cdm>
class ProbeHost final : public Cdm::Host {
 public:
  using KeyStatus = std::conditional_t<Cdm::kVersion == 12, cdm::KeyStatus_2, cdm::KeyStatus>;
  using KeyInformation = std::conditional_t<Cdm::kVersion == 12, cdm::KeyInformation_2, cdm::KeyInformation>;
  Cdm* instance = nullptr;
  bool initialized = false;
  bool initialize_done = false;
  bool rejected = false;
  bool closed = false;
  bool message_received = false;
  std::string session;

  static void* GetHost(int version, void* data) {
    std::cout << "requested_host=" << version << '\n';
    if (version != Cdm::Host::kVersion) return nullptr;
    return static_cast<typename Cdm::Host*>(static_cast<ProbeHost*>(data));
  }
  cdm::Buffer* Allocate(uint32_t capacity) override {
    if (capacity == 0 || capacity > 64 * 1024 * 1024) return nullptr;
    try { return new ProbeBuffer(capacity); } catch (const std::bad_alloc&) { return nullptr; }
  }
  void SetTimer(int64_t delay, void* context) override {
    timers_.push_back({SteadyClock::now() + std::chrono::milliseconds(delay < 0 ? 0 : delay), context});
  }
  cdm::Time GetCurrentWallTime() override {
    return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();
  }
  void OnInitialized(bool success) override {
    initialized = success;
    initialize_done = true;
    std::cout << "initialized=" << success << '\n';
  }
  void OnResolveKeyStatusPromise(uint32_t, KeyStatus) override {}
  void OnResolveNewSessionPromise(uint32_t id, const char* value, uint32_t size) override {
    session.assign(value ? value : "", value ? size : 0);
    std::cout << "session_created promise=" << id << " id_bytes=" << session.size() << '\n';
  }
  void OnResolvePromise(uint32_t id) override { std::cout << "promise_resolved=" << id << '\n'; }
  void OnRejectPromise(uint32_t id, cdm::Exception exception, uint32_t code,
                       const char*, uint32_t size) override {
    rejected = true;
    // Do not print opaque CDM messages, session identifiers or license payloads.
    std::cout << "promise_rejected=" << id << " exception=" << exception
              << " system_code=" << code << " message_bytes=" << size << '\n';
  }
  void OnSessionMessage(const char*, uint32_t, cdm::MessageType type,
                        const char*, uint32_t size) override {
    message_received = size > 0;
    std::cout << "session_message type=" << type << " bytes=" << size << '\n';
  }
  void OnSessionKeysChange(const char*, uint32_t, bool usable,
                          const KeyInformation*, uint32_t count) override {
    std::cout << "key_status_count=" << count << " usable=" << usable << '\n';
  }
  void OnExpirationChange(const char*, uint32_t, cdm::Time) override {}
  void OnSessionClosed(const char*, uint32_t) override {
    closed = true;
    std::cout << "session_closed=1\n";
  }
  void SendPlatformChallenge(const char*, uint32_t, const char*, uint32_t) override {
    pending_.push_back([this] {
      // Platform verification is unavailable in this probe; report failure.
      instance->OnPlatformChallengeResponse(cdm::PlatformChallengeResponse{});
    });
  }
  void EnableOutputProtection(uint32_t) override {}
  void QueryOutputProtectionStatus() override {
    pending_.push_back([this] { instance->OnQueryOutputProtectionStatus(cdm::kQueryFailed, 0, 0); });
  }
  void OnDeferredInitializationDone(cdm::StreamType, cdm::Status) override {}
  cdm::FileIO* CreateFileIO(cdm::FileIOClient*) override { return nullptr; }
  void RequestStorageId(uint32_t version) override {
    pending_.push_back([this, version] { instance->OnStorageId(version, nullptr, 0); });
  }
  // Host_10 has no metrics method; Host_11 and Host_12 use this exact signature.
  void ReportMetrics(cdm::MetricName, uint64_t) {}

  bool WaitUntil(const std::function<bool()>& done) {
    const auto deadline = SteadyClock::now() + std::chrono::seconds(5);
    while (!done() && SteadyClock::now() < deadline) {
      auto pending = std::move(pending_);
      pending_.clear();
      for (auto& callback : pending) callback();
      std::vector<void*> expired;
      const auto now = SteadyClock::now();
      for (auto i = timers_.begin(); i != timers_.end();) {
        if (i->first <= now) { expired.push_back(i->second); i = timers_.erase(i); }
        else { ++i; }
      }
      for (auto context : expired) instance->TimerExpired(context);
      if (!done()) std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return done();
  }
 private:
  std::vector<std::function<void()>> pending_;
  std::vector<std::pair<SteadyClock::time_point, void*>> timers_;
};

using CreateInstance = decltype(&CreateCdmInstance);

template <class Cdm>
bool Run(CreateInstance create) {
  ProbeHost<Cdm> host;
  constexpr char key_system[] = "com.widevine.alpha";
  host.instance = static_cast<Cdm*>(create(Cdm::kVersion, key_system,
      sizeof(key_system) - 1, ProbeHost<Cdm>::GetHost, &host));
  std::cout << "cdm_interface=" << Cdm::kVersion << " created=" << (host.instance != nullptr) << '\n';
  if (!host.instance) return false;
  host.instance->Initialize(false, false, false);
  host.WaitUntil([&] { return host.initialize_done; });
  if (host.initialized) {
    // CENC v0 PSSH with Widevine system ID and a synthetic all-zero key ID.
    // The protobuf payload is field 2 (key_id), 16 bytes. This is metadata,
    // not a content key. The generated message is never sent to a server.
    constexpr uint8_t init_data[] = {
        0, 0, 0, 50, 'p', 's', 's', 'h', 0, 0, 0, 0,
        0xed, 0xef, 0x8b, 0xa9, 0x79, 0xd6, 0x4a, 0xce,
        0xa3, 0xc8, 0x27, 0xdc, 0xd5, 0x1d, 0x21, 0xed,
        0, 0, 0, 18, 0x12, 0x10,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    host.instance->CreateSessionAndGenerateRequest(1, cdm::kTemporary, cdm::kCenc,
        init_data, sizeof(init_data));
    host.WaitUntil([&] { return host.message_received || host.rejected; });
    if (!host.session.empty()) {
      host.instance->CloseSession(2, host.session.data(), static_cast<uint32_t>(host.session.size()));
      host.WaitUntil([&] { return host.closed; });
    }
  }
  const bool passed = host.initialized && host.message_received && host.closed && !host.rejected;
  host.instance->Destroy();
  host.instance = nullptr;
  std::cout << "instance_destroyed=1 session_probe_passed=" << passed << '\n';
  return passed;
}

int wmain(int argc, wchar_t** argv) {
  std::cout << std::unitbuf;
  if (argc != 2) {
    std::cerr << "Usage: native_session_probe.exe <absolute path to installed widevinecdm.dll>\n";
    return 2;
  }
  // Resolve dependencies only from the selected module's directory and System32.
  HMODULE module = LoadLibraryExW(argv[1], nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!module) { std::cerr << "load_error=" << GetLastError() << '\n'; return 3; }
  auto initialize = reinterpret_cast<decltype(&INITIALIZE_CDM_MODULE)>(GetProcAddress(module, "InitializeCdmModule_4"));
  auto deinitialize = reinterpret_cast<decltype(&DeinitializeCdmModule)>(GetProcAddress(module, "DeinitializeCdmModule"));
  auto version = reinterpret_cast<decltype(&GetCdmVersion)>(GetProcAddress(module, "GetCdmVersion"));
  auto create = reinterpret_cast<CreateInstance>(GetProcAddress(module, "CreateCdmInstance"));
  if (!initialize || !deinitialize || !version || !create) {
    std::cerr << "required_exports_missing=1\n";
    FreeLibrary(module);
    return 4;
  }
  std::cout << "cdm_version=" << version() << '\n';
  initialize();
  std::cout << "module_initialized=1\n";
  // Each instance receives its actual Host ABI; never cast between versions.
  const bool v12 = Run<cdm::ContentDecryptionModule_12>(create);
  const bool v11 = Run<cdm::ContentDecryptionModule_11>(create);
  const bool v10 = Run<cdm::ContentDecryptionModule_10>(create);
  deinitialize();
  FreeLibrary(module);
  std::cout << "module_unloaded=1\n";
  return v12 || v11 || v10 ? 0 : 5;
}

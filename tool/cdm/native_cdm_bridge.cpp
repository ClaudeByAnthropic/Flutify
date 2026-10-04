// Experimental, out-of-process Widevine host. The pipe is private binary IPC;
// stdout never contains logs. No CDM binary, keys or plaintext are persisted.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>
#include "content_decryption_module.h"

namespace {
using Bytes = std::vector<uint8_t>;
using Clock = std::chrono::steady_clock;
constexpr uint32_t kMaxFrame = 8 * 1024 * 1024;
struct WipeOnExit {
  Bytes& bytes;
  ~WipeOnExit() {
    if (!bytes.empty()) SecureZeroMemory(bytes.data(), bytes.size());
  }
};
// Frame: uint32 LE payload size, uint8 kind, payload. Responses:
// 0 = success; 1 = license message; 2 = numeric error, never an opaque payload.
void Send(uint8_t kind, const Bytes& bytes = {}) {
  const uint32_t size = static_cast<uint32_t>(bytes.size()) + 1;
  if (fwrite(&size, 4, 1, stdout) != 1 || fwrite(&kind, 1, 1, stdout) != 1 ||
      (!bytes.empty() && fwrite(bytes.data(), bytes.size(), 1, stdout) != 1) ||
      fflush(stdout) != 0) throw std::runtime_error("pipe_write");
}
void Number(uint8_t kind, uint32_t value) {
  Bytes bytes(4); memcpy(bytes.data(), &value, 4); Send(kind, bytes);
}
struct Reader {
  const Bytes& bytes;
  size_t pos = 0;
  uint32_t U32() {
    if (pos + 4 > bytes.size()) throw std::runtime_error("short_integer");
    uint32_t value; memcpy(&value, bytes.data() + pos, 4); pos += 4; return value;
  }
  Bytes Blob(uint32_t limit = kMaxFrame) {
    auto size = U32();
    if (size > limit || size > bytes.size() - pos) throw std::runtime_error("short_blob");
    Bytes result(bytes.begin() + pos, bytes.begin() + pos + size); pos += size; return result;
  }
};
class Buffer final : public cdm::Buffer {
 public:
  explicit Buffer(uint32_t capacity) : bytes_(capacity) {}
  ~Buffer() override {
    if (!bytes_.empty()) SecureZeroMemory(bytes_.data(), bytes_.size());
  }
  void Destroy() override { delete this; }
  uint32_t Capacity() const override { return static_cast<uint32_t>(bytes_.size()); }
  uint8_t* Data() override { return bytes_.data(); }
  void SetSize(uint32_t size) override { size_ = size <= Capacity() ? size : 0; }
  uint32_t Size() const override { return size_; }
 private:
  Bytes bytes_;
  uint32_t size_ = 0;
};
class Block final : public cdm::DecryptedBlock {
 public:
  ~Block() override { if (buffer_) buffer_->Destroy(); }
  void SetDecryptedBuffer(cdm::Buffer* buffer) override {
    if (buffer_ && buffer_ != buffer) buffer_->Destroy();
    buffer_ = buffer;
  }
  cdm::Buffer* DecryptedBuffer() override { return buffer_; }
  void SetTimestamp(int64_t value) override { time_ = value; }
  int64_t Timestamp() const override { return time_; }
 private:
  cdm::Buffer* buffer_ = nullptr;
  int64_t time_ = 0;
};

template <class Cdm>
class Host final : public Cdm::Host {
 public:
  Cdm* cdm = nullptr;
  bool initialized = false, init_done = false, closed = false;
  uint32_t resolved = 0, rejected = 0, error = 0;
  std::string session;
  std::vector<Bytes> messages;
  ~Host() { if (cdm) cdm->Destroy(); }
  static void* GetHost(int version, void* user) {
    return version == Cdm::Host::kVersion ?
        static_cast<typename Cdm::Host*>(static_cast<Host*>(user)) : nullptr;
  }
  cdm::Buffer* Allocate(uint32_t size) override {
    if (size == 0 || size > kMaxFrame) return nullptr;
    try { return new Buffer(size); } catch (...) { return nullptr; }
  }
  void SetTimer(int64_t delay, void* context) override {
    timers_.push_back({Clock::now() + std::chrono::milliseconds(std::max<int64_t>(delay, 0)), context});
  }
  cdm::Time GetCurrentWallTime() override {
    return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();
  }
  void OnInitialized(bool success) override { initialized = success; init_done = true; }
  void OnResolveKeyStatusPromise(uint32_t id, cdm::KeyStatus) override { resolved = id; }
  void OnResolveNewSessionPromise(uint32_t id, const char* value, uint32_t size) override {
    session.assign(value, size); resolved = id;
  }
  void OnResolvePromise(uint32_t id) override { resolved = id; }
  void OnRejectPromise(uint32_t id, cdm::Exception exception, uint32_t,
                       const char*, uint32_t) override {
    rejected = id; error = 100 + static_cast<uint32_t>(exception);
  }
  void OnSessionMessage(const char*, uint32_t, cdm::MessageType type,
                        const char* value, uint32_t size) override {
    if ((type == cdm::kLicenseRequest || type == cdm::kLicenseRenewal) &&
        size > 0 && size < kMaxFrame) messages.emplace_back(value, value + size);
  }
  void OnSessionKeysChange(const char*, uint32_t, bool,
                          const cdm::KeyInformation*, uint32_t) override {}
  void OnExpirationChange(const char*, uint32_t, cdm::Time) override {}
  void OnSessionClosed(const char*, uint32_t) override { closed = true; }
  void SendPlatformChallenge(const char*, uint32_t, const char*, uint32_t) override {
    pending_.push_back([this] { cdm->OnPlatformChallengeResponse(cdm::PlatformChallengeResponse{}); });
  }
  void EnableOutputProtection(uint32_t) override {}
  void QueryOutputProtectionStatus() override {
    pending_.push_back([this] { cdm->OnQueryOutputProtectionStatus(cdm::kQueryFailed, 0, 0); });
  }
  void OnDeferredInitializationDone(cdm::StreamType, cdm::Status) override {}
  cdm::FileIO* CreateFileIO(cdm::FileIOClient*) override { return nullptr; }
  void RequestStorageId(uint32_t version) override {
    pending_.push_back([this, version] { cdm->OnStorageId(version, nullptr, 0); });
  }
  void ReportMetrics(cdm::MetricName, uint64_t) {}
  void Pump() {
    auto pending = std::move(pending_); pending_.clear();
    for (auto& callback : pending) callback();
    std::vector<void*> expired;
    for (auto it = timers_.begin(); it != timers_.end();) {
      if (it->first <= Clock::now()) { expired.push_back(it->second); it = timers_.erase(it); }
      else ++it;
    }
    for (auto context : expired) cdm->TimerExpired(context);
  }
  bool Wait(const std::function<bool()>& done) {
    const auto deadline = Clock::now() + std::chrono::seconds(8);
    while (!done() && Clock::now() < deadline) { Pump(); std::this_thread::sleep_for(std::chrono::milliseconds(2)); }
    return done();
  }
  void ReplyPromise(uint32_t id, bool need_message = false) {
    const bool complete = Wait([&] { return rejected == id ||
      (resolved == id && (!need_message || !messages.empty())); });
    if (!complete || rejected == id) { Number(2, rejected == id ? error : 200); return; }
    for (auto& message : messages) Send(1, message);
    messages.clear(); Send(0);
  }
 private:
  std::vector<std::function<void()>> pending_;
  std::vector<std::pair<Clock::time_point, void*>> timers_;
};

template <class Cdm>
bool Run(decltype(&CreateCdmInstance) create) {
  Host<Cdm> host;
  constexpr char system[] = "com.widevine.alpha";
  host.cdm = static_cast<Cdm*>(create(Cdm::kVersion, system, sizeof(system) - 1, Host<Cdm>::GetHost, &host));
  if (!host.cdm) return false;
  host.cdm->Initialize(false, false, false);
  if (!host.Wait([&] { return host.init_done; }) || !host.initialized) return false;
  Number(0, Cdm::kVersion);
  uint32_t promise = 0;
  for (;;) {
    // Poll input so CDM timers continue while Dart performs a license request.
    DWORD available = 0;
    if (!PeekNamedPipe(GetStdHandle(STD_INPUT_HANDLE), nullptr, 0, nullptr, &available, nullptr)) break;
    if (available < 4) { host.Pump(); std::this_thread::sleep_for(std::chrono::milliseconds(2)); continue; }
    uint32_t size = 0;
    if (fread(&size, 4, 1, stdin) != 1) break;
    if (size < 1 || size > kMaxFrame) throw std::runtime_error("invalid_frame");
    uint8_t command;
    if (fread(&command, 1, 1, stdin) != 1) break;
    Bytes payload(size - 1);
    if (!payload.empty() && fread(payload.data(), payload.size(), 1, stdin) != 1) break;
    host.Pump();
    ++promise;
    switch (command) {
      case 1: // fresh service certificate
        host.cdm->SetServerCertificate(promise, payload.data(), static_cast<uint32_t>(payload.size()));
        host.ReplyPromise(promise); break;
      case 2: // real CENC initialization data
        if (!host.session.empty()) { Number(2, 201); break; }
        host.cdm->CreateSessionAndGenerateRequest(promise, cdm::kTemporary, cdm::kCenc,
            payload.data(), static_cast<uint32_t>(payload.size()));
        host.ReplyPromise(promise, true); break;
      case 3: // opaque server response, unchanged
        if (host.session.empty()) { Number(2, 202); break; }
        host.cdm->UpdateSession(promise, host.session.data(), static_cast<uint32_t>(host.session.size()),
            payload.data(), static_cast<uint32_t>(payload.size()));
        host.ReplyPromise(promise); break;
      case 4: { // bounded batch of CENC audio samples, one IPC round-trip
        Reader r{payload};
        const auto sample_count = r.U32();
        if (sample_count == 0 || sample_count > 256) throw std::runtime_error("batch_size");
        Bytes decrypted;
        // Reserve once, so vector growth cannot leave earlier plaintext copies.
        decrypted.reserve(payload.size());
        WipeOnExit wipe{decrypted};
        uint32_t failure = 0;
        for (uint32_t sample = 0; sample < sample_count; ++sample) {
        auto kid = r.Blob(16), iv = r.Blob(16);
        const auto count = r.U32();
        if (kid.size() != 16 || (iv.size() != 8 && iv.size() != 16) || count > 65536)
          throw std::runtime_error("invalid_sample");
        std::vector<cdm::SubsampleEntry> subs;
        uint64_t covered = 0;
        for (uint32_t i = 0; i < count; ++i) {
          cdm::SubsampleEntry entry{r.U32(), r.U32()};
          covered += static_cast<uint64_t>(entry.clear_bytes) + entry.cipher_bytes; subs.push_back(entry);
        }
        auto data = r.Blob();
        if (data.empty() || (count && covered != data.size()))
          throw std::runtime_error("invalid_sample_size");
        cdm::InputBuffer_2 input{};
        input.data = data.data(); input.data_size = static_cast<uint32_t>(data.size());
        input.encryption_scheme = cdm::EncryptionScheme::kCenc;
        input.key_id = kid.data(); input.key_id_size = static_cast<uint32_t>(kid.size());
        input.iv = iv.data(); input.iv_size = static_cast<uint32_t>(iv.size());
        input.subsamples = subs.data(); input.num_subsamples = count;
        Block output;
        const auto status = host.cdm->Decrypt(input, &output);
        if (status != cdm::kSuccess) { failure = 300 + static_cast<uint32_t>(status); break; }
        auto buffer = output.DecryptedBuffer();
        if (!buffer || buffer->Size() != data.size()) { failure = 310; break; }
        decrypted.insert(decrypted.end(), buffer->Data(), buffer->Data() + buffer->Size());
        }
        if (failure) Number(2, failure);
        else {
          if (r.pos != payload.size()) throw std::runtime_error("extra_batch_bytes");
          Send(0, decrypted);
        }
        break;
      }
      case 5:
        if (!host.session.empty()) {
          host.cdm->CloseSession(promise, host.session.data(), static_cast<uint32_t>(host.session.size()));
          host.Wait([&] { return host.closed || host.rejected == promise; });
        }
        Send(0); return true;
      default: throw std::runtime_error("unknown_command");
    }
  }
  return true;
}
} // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);
  // No stdio read-ahead: PeekNamedPipe must see pending command headers.
  setvbuf(stdin, nullptr, _IONBF, 0);
  const auto module = LoadLibraryExW(argv[1], nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!module) { Number(2, 400); return 3; }
  auto init = reinterpret_cast<decltype(&INITIALIZE_CDM_MODULE)>(GetProcAddress(module, "InitializeCdmModule_4"));
  auto fini = reinterpret_cast<decltype(&DeinitializeCdmModule)>(GetProcAddress(module, "DeinitializeCdmModule"));
  auto create = reinterpret_cast<decltype(&CreateCdmInstance)>(GetProcAddress(module, "CreateCdmInstance"));
  int result = 0;
  if (!init || !fini || !create) { Number(2, 401); result = 4; }
  else {
    init();
    try {
      if (!Run<cdm::ContentDecryptionModule_11>(create) && !Run<cdm::ContentDecryptionModule_10>(create)) {
        Number(2, 402); result = 5;
      }
    } catch (...) { Number(2, 403); result = 6; }
    fini();
  }
  FreeLibrary(module); return result;
}

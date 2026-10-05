// Opt-in local diagnostic using the real executable and the loaded CDM.
// Reuses the production host/IPC; never substitutes another program's identity.
// Default to the Dart metadata-only harness; live requests require explicit opt-in.
#define wmain UnusedNativeBridgeMain
#include "native_cdm_bridge.cpp"
#undef wmain
#include "content_decryption_module_ext.h"

namespace {
// Trace only callback names, never payloads or identifiers. Every callback and
// return value is forwarded unchanged to the production host.
template <class H>
class TracingHost final : public H {
 public:
  TracingHost(H* target, FILE* log) : target_(target), log_(log) {}
  cdm::Buffer* Allocate(uint32_t capacity) override {
    Event("Allocate"); return target_->Allocate(capacity);
  }
  void SetTimer(int64_t delay, void* context) override {
    Event("SetTimer"); target_->SetTimer(delay, context);
  }
  cdm::Time GetCurrentWallTime() override {
    Event("GetCurrentWallTime"); return target_->GetCurrentWallTime();
  }
  void OnInitialized(bool success) override {
    Event("OnInitialized"); target_->OnInitialized(success);
  }
  void OnResolveKeyStatusPromise(uint32_t id, cdm::KeyStatus status) override {
    Event("OnResolveKeyStatusPromise");
    target_->OnResolveKeyStatusPromise(id, status);
  }
  void OnResolveNewSessionPromise(uint32_t id, const char* session,
                                  uint32_t size) override {
    Event("OnResolveNewSessionPromise");
    target_->OnResolveNewSessionPromise(id, session, size);
  }
  void OnResolvePromise(uint32_t id) override {
    Event("OnResolvePromise"); target_->OnResolvePromise(id);
  }
  void OnRejectPromise(uint32_t id, cdm::Exception exception, uint32_t code,
                       const char* message, uint32_t size) override {
    Event("OnRejectPromise");
    target_->OnRejectPromise(id, exception, code, message, size);
  }
  void OnSessionMessage(const char* session, uint32_t session_size,
                        cdm::MessageType type, const char* message,
                        uint32_t message_size) override {
    Event("OnSessionMessage");
    target_->OnSessionMessage(session, session_size, type, message, message_size);
  }
  void OnSessionKeysChange(const char* session, uint32_t size, bool usable,
                           const cdm::KeyInformation* keys,
                           uint32_t count) override {
    Event("OnSessionKeysChange");
    target_->OnSessionKeysChange(session, size, usable, keys, count);
  }
  void OnExpirationChange(const char* session, uint32_t size,
                          cdm::Time expiry) override {
    Event("OnExpirationChange");
    target_->OnExpirationChange(session, size, expiry);
  }
  void OnSessionClosed(const char* session, uint32_t size) override {
    Event("OnSessionClosed"); target_->OnSessionClosed(session, size);
  }
  void SendPlatformChallenge(const char* service, uint32_t service_size,
                             const char* challenge,
                             uint32_t challenge_size) override {
    Event("SendPlatformChallenge");
    target_->SendPlatformChallenge(service, service_size, challenge,
                                   challenge_size);
  }
  void EnableOutputProtection(uint32_t mask) override {
    Event("EnableOutputProtection"); target_->EnableOutputProtection(mask);
  }
  void QueryOutputProtectionStatus() override {
    Event("QueryOutputProtectionStatus"); target_->QueryOutputProtectionStatus();
  }
  void OnDeferredInitializationDone(cdm::StreamType stream,
                                    cdm::Status status) override {
    Event("OnDeferredInitializationDone");
    target_->OnDeferredInitializationDone(stream, status);
  }
  cdm::FileIO* CreateFileIO(cdm::FileIOClient* client) override {
    Event("CreateFileIO"); return target_->CreateFileIO(client);
  }
  void RequestStorageId(uint32_t version) override {
    Event("RequestStorageId"); target_->RequestStorageId(version);
  }
  void ReportMetrics(cdm::MetricName name, uint64_t value) {
    Event("ReportMetrics");
    if constexpr (H::kVersion >= 11) target_->ReportMetrics(name, value);
  }
 private:
  void Event(const char* name) {
    fprintf(log_, "host_callback=%s\n", name);
    fflush(log_);
  }
  H* target_;
  FILE* log_;
};

struct TracingFactory {
  decltype(&CreateCdmInstance) create;
  FILE* log;
  GetCdmHostFunc get_host = nullptr;
  void* user = nullptr;
  std::unique_ptr<TracingHost<cdm::Host_10>> host10;
  std::unique_ptr<TracingHost<cdm::Host_11>> host11;

  static void* GetHost(int version, void* opaque) {
    auto& self = *static_cast<TracingFactory*>(opaque);
    void* actual = self.get_host(version, self.user);
    fprintf(self.log, "host_interface_requested=%d available=%u\n", version,
            actual ? 1u : 0u);
    fflush(self.log);
    if (!actual) return nullptr;
    if (version == 11) {
      if (!self.host11) self.host11 =
          std::make_unique<TracingHost<cdm::Host_11>>(
              static_cast<cdm::Host_11*>(actual), self.log);
      return static_cast<cdm::Host_11*>(self.host11.get());
    }
    if (version == 10) {
      if (!self.host10) self.host10 =
          std::make_unique<TracingHost<cdm::Host_10>>(
              static_cast<cdm::Host_10*>(actual), self.log);
      return static_cast<cdm::Host_10*>(self.host10.get());
    }
    return actual;
  }
};

// The probe creates one CDM at a time. This context outlives Run(), including
// Host's CDM Destroy(), and module deinitialization.
TracingFactory* active_factory = nullptr;
void* TracingCreateCdmInstance(int version, const char* key_system,
                               uint32_t key_system_size,
                               GetCdmHostFunc get_host, void* user) {
  auto& self = *active_factory;
  self.host10.reset();
  self.host11.reset();
  self.get_host = get_host;
  self.user = user;
  return self.create(version, key_system, key_system_size,
                     TracingFactory::GetHost, &self);
}

bool DiagnosticFlag(const wchar_t* name) {
  wchar_t value[2]{};
  return GetEnvironmentVariableW(name, value, 2) == 1 && value[0] == L'1';
}

std::wstring ModulePath(HMODULE module) {
  std::vector<wchar_t> path(32768);
  const auto size = GetModuleFileNameW(module, path.data(),
                                     static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) throw std::runtime_error("module_path");
  return std::wstring(path.data(), size);
}

class ReadOnlyFile {
 public:
  explicit ReadOnlyFile(const std::wstring& path)
      : handle_(CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr)) {}
  ~ReadOnlyFile() { if (valid()) CloseHandle(handle_); }
  ReadOnlyFile(const ReadOnlyFile&) = delete;
  ReadOnlyFile& operator=(const ReadOnlyFile&) = delete;
  bool valid() const { return handle_ != INVALID_HANDLE_VALUE; }
  HANDLE release() { return std::exchange(handle_, INVALID_HANDLE_VALUE); }
 private:
  HANDLE handle_;
};

void VerifyActualHost(HMODULE module, FILE* log) {
  const auto verify = reinterpret_cast<decltype(&VerifyCdmHost_0)>(
      GetProcAddress(module, "VerifyCdmHost_0"));
  fprintf(log, "verification_export_present=%u\n", verify ? 1u : 0u);
  if (!verify) return;
  const auto host_path = ModulePath(nullptr);
  const auto cdm_path = ModulePath(module);
  ReadOnlyFile host(host_path), host_sig(host_path + L".sig");
  ReadOnlyFile cdm_file(cdm_path), cdm_sig(cdm_path + L".sig");
  fprintf(log, "actual_host_readable=%u host_signature_readable=%u\n",
          host.valid() ? 1u : 0u, host_sig.valid() ? 1u : 0u);
  fprintf(log, "loaded_cdm_readable=%u cdm_signature_readable=%u\n",
          cdm_file.valid() ? 1u : 0u, cdm_sig.valid() ? 1u : 0u);
  if (!host.valid() || !cdm_file.valid()) throw std::runtime_error("file_missing");
  // Chromium also passes invalid signature handles if opening them fails.
  // Ownership of all handles transfers to the CDM, including on false return.
  cdm::HostFile files[] = {
      {host_path.c_str(), host.release(), host_sig.release()},
      {cdm_path.c_str(), cdm_file.release(), cdm_sig.release()},
  };
  const bool started = verify(files, 2);
  // True means accepted for asynchronous processing, NOT verified or licensed.
  fprintf(log, "verification_call_accepted=%u\n", started ? 1u : 0u);
  fflush(log);
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  FILE* log = nullptr;
  wchar_t* log_path = nullptr;
  size_t log_path_size = 0;
  if (_wdupenv_s(&log_path, &log_path_size, L"FLUTIFY_CDM_HOST_PROBE_LOG")) return 2;
  const std::unique_ptr<wchar_t, decltype(&free)> owned_path(log_path, &free);
  if (!log_path || _wfopen_s(&log, log_path, L"w") || !log) return 2;
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
  setvbuf(stdin, nullptr, _IONBF, 0);
  const auto module = LoadLibraryExW(argv[1], nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!module) { fclose(log); return 3; }
  // Chromium loads the real system DXVA library before host verification.
  // Keep it alive until after CDM teardown; never search the working directory.
  HMODULE dxva2 = nullptr;
  if (DiagnosticFlag(L"FLUTIFY_CDM_HOST_PROBE_PRELOAD_DXVA2")) {
    dxva2 = LoadLibraryExW(L"dxva2.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    fprintf(log, "system_dxva2_loaded=%u\n", dxva2 ? 1u : 0u);
    if (!dxva2) { FreeLibrary(module); fclose(log); return 3; }
  }
  const auto init = reinterpret_cast<decltype(&INITIALIZE_CDM_MODULE)>(
      GetProcAddress(module, "InitializeCdmModule_4"));
  const auto fini = reinterpret_cast<decltype(&DeinitializeCdmModule)>(
      GetProcAddress(module, "DeinitializeCdmModule"));
  const auto create = reinterpret_cast<decltype(&CreateCdmInstance)>(
      GetProcAddress(module, "CreateCdmInstance"));
  int result = 0;
  if (!init || !fini || !create) {
    result = 4;
  } else {
    bool initialized = false;
    TracingFactory factory{create, log};
    active_factory = &factory;
    try {
      // Matches Chromium: host verification precedes InitializeCdmModule.
      VerifyActualHost(module, log);
      init();
      initialized = true;
      if (!Run<cdm::ContentDecryptionModule_11>(TracingCreateCdmInstance) &&
          !Run<cdm::ContentDecryptionModule_10>(TracingCreateCdmInstance)) result = 5;
    } catch (...) {
      fprintf(log, "probe_failed=true\n");
      result = 6;
    }
    if (initialized) fini();
    active_factory = nullptr;
  }
  FreeLibrary(module);
  if (dxva2) FreeLibrary(dxva2);
  fprintf(log, "probe_exit=%d\n", result);
  fclose(log);
  return result;
}

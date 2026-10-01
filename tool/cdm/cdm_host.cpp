// Widevine CDM 宿主（接口 v10）：license 交换 + 逐样本解密。
// 与桌面客户端的 CEF 用法同款：LoadLibrary(widevinecdm.dll) → CreateCdmInstance(10)
// → CreateSessionAndGenerateRequest(PSSH) → POST license → UpdateSession → Decrypt()。
//
// 用法：
//   cdm_host --dll <widevinecdm.dll> --pssh <pssh.bin> --license-url <url>
//            --auth <Bearer ...> --client-token <tok> --samples <samples.bin>
//            --out <out.aac> [--scheme cenc|cbcs]
//
// samples.bin 记录流（小端）：
//   u32 iv_size | iv | u32 nsub | (u32 clear, u32 cipher)* | u32 data_size | data
#include <windows.h>
#include <winhttp.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <thread>
#include <chrono>
#include <vector>
#include <mutex>
#include <functional>
#include <algorithm>

#include "content_decryption_module.h"

// ---------------------------------------------------------------------------
// 宿主对象
// ---------------------------------------------------------------------------

class HostBuffer : public cdm::Buffer {
 public:
  explicit HostBuffer(uint32_t cap) : cap_(cap), data_(new uint8_t[cap]) {}
  ~HostBuffer() override { delete[] data_; }
  void Destroy() override { delete this; }
  uint32_t Capacity() const override { return cap_; }
  uint8_t* Data() override { return data_; }
  void SetSize(uint32_t size) override { size_ = size; }
  uint32_t Size() const override { return size_; }

 private:
  uint32_t cap_, size_ = 0;
  uint8_t* data_;
};

class HostDecryptedBlock : public cdm::DecryptedBlock {
 public:
  void SetDecryptedBuffer(cdm::Buffer* b) override { buf_ = b; }
  cdm::Buffer* DecryptedBuffer() override { return buf_; }
  void SetTimestamp(int64_t t) override { ts_ = t; }
  int64_t Timestamp() const override { return ts_; }

 private:
  cdm::Buffer* buf_ = nullptr;
  int64_t ts_ = 0;
};

struct TimerItem {
  int64_t due_ms;
  void* ctx;
};

class Host : public cdm::Host_10 {
 public:
  cdm::ContentDecryptionModule_10* cdm = nullptr;
  std::mutex mu;
  bool initialized = false;
  bool init_ok = false;
  std::string session_id;
  std::vector<uint8_t> license_request;
  bool got_message = false;
  bool keys_usable = false;
  bool promise_resolved = false;
  bool promise_rejected = false;
  std::string reject_msg;
  std::vector<TimerItem> timers;

  // --- Host_10 ---
  cdm::Buffer* Allocate(uint32_t capacity) override { return new HostBuffer(capacity); }

  void SetTimer(int64_t delay_ms, void* context) override {
    std::lock_guard<std::mutex> g(mu);
    timers.push_back({wall_ms() + delay_ms, context});
  }

  cdm::Time GetCurrentWallTime() override { return wall_ms() / 1000.0; }

  void OnInitialized(bool success) override {
    std::lock_guard<std::mutex> g(mu);
    initialized = true;
    init_ok = success;
  }

  void OnResolveKeyStatusPromise(uint32_t, cdm::KeyStatus) override {}

  void OnResolveNewSessionPromise(uint32_t, const char* sid, uint32_t sz) override {
    std::lock_guard<std::mutex> g(mu);
    session_id.assign(sid, sz);
    promise_resolved = true;
  }

  void OnResolvePromise(uint32_t) override {
    std::lock_guard<std::mutex> g(mu);
    promise_resolved = true;
  }

  void OnRejectPromise(uint32_t, cdm::Exception, uint32_t, const char* msg,
                       uint32_t sz) override {
    std::lock_guard<std::mutex> g(mu);
    promise_rejected = true;
    reject_msg.assign(msg ? msg : "", msg ? sz : 0);
  }

  void OnSessionMessage(const char* sid, uint32_t, cdm::MessageType,
                        const char* message, uint32_t size) override {
    std::lock_guard<std::mutex> g(mu);
    session_id.assign(sid, strlen(sid));
    license_request.assign(message, message + size);
    got_message = true;
  }

  void OnSessionKeysChange(const char*, uint32_t, bool has_usable,
                           const cdm::KeyInformation* keys_info, uint32_t keys_info_count) override {
    std::lock_guard<std::mutex> g(mu);
    if (has_usable) keys_usable = true;
    fprintf(stderr, "[cdm] OnSessionKeysChange count=%u has_usable=%d\n", keys_info_count, has_usable);
    for (uint32_t i = 0; i < keys_info_count; i++) {
      std::string k_hex;
      for (uint32_t k = 0; k < keys_info[i].key_id_size; k++) {
        char buf[3]; sprintf(buf, "%02x", keys_info[i].key_id[k]);
        k_hex += buf;
      }
      fprintf(stderr, "[cdm] Key#%u: kid=%s sz=%u status=%d sys_code=%u\n",
              i, k_hex.c_str(), keys_info[i].key_id_size,
              (int)keys_info[i].status, keys_info[i].system_code);
    }
  }

  void OnExpirationChange(const char*, uint32_t, cdm::Time) override {}
  void OnSessionClosed(const char*, uint32_t) override {}

  void SendPlatformChallenge(const char*, uint32_t, const char*, uint32_t) override {
    fprintf(stderr, "[cdm] SendPlatformChallenge（未预期）\n");
  }
  void EnableOutputProtection(uint32_t) override {}
  void QueryOutputProtectionStatus() override {
    if (cdm) cdm->OnQueryOutputProtectionStatus(cdm::kQuerySucceeded, 0, 0);
  }
  void OnDeferredInitializationDone(cdm::StreamType, cdm::Status) override {}
  cdm::FileIO* CreateFileIO(cdm::FileIOClient*) override { return nullptr; }
  void RequestStorageId(uint32_t version) override {
    // 同步回调（测试宿主常用做法）：返回空 ID。
    if (cdm) cdm->OnStorageId(version, nullptr, 0);
  }

  static int64_t wall_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
  }
};

static Host g_host;

static void* GetHostFunc(int host_interface_version, void*) {
  if (host_interface_version == cdm::Host_10::kVersion) return &g_host;
  fprintf(stderr, "[cdm] 未知宿主接口 v%d\n", host_interface_version);
  return nullptr;
}

// ---------------------------------------------------------------------------
// HTTP POST（WinHTTP）
// ---------------------------------------------------------------------------

static std::vector<uint8_t> http_post(const std::wstring& url,
                                      const std::string& auth,
                                      const std::string& client_token,
                                      const std::vector<uint8_t>& body,
                                      int* status_out) {
  std::vector<uint8_t> out;
  URL_COMPONENTS uc{};
  uc.dwStructSize = sizeof(uc);
  wchar_t host[256] = {}, path[1024] = {};
  uc.lpszHostName = host;
  uc.dwHostNameLength = 256;
  uc.lpszUrlPath = path;
  uc.dwUrlPathLength = 1024;
  if (!WinHttpCrackUrl(url.c_str(), 0, 0, &uc)) return out;

  HINTERNET ses = WinHttpOpen(L"Spotify/130100234 Win32_x86_64/0 (PC desktop)", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                              WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!ses) return out;
  HINTERNET con = WinHttpConnect(ses, host, uc.nPort, 0);
  wchar_t verb[] = L"POST";
  HINTERNET req = WinHttpOpenRequest(con, verb, path, nullptr, WINHTTP_NO_REFERER,
                                     WINHTTP_DEFAULT_ACCEPT_TYPES,
                                     uc.nScheme == INTERNET_SCHEME_HTTPS
                                         ? WINHTTP_FLAG_SECURE
                                         : 0);
  if (!req) {
    WinHttpCloseHandle(ses);
    return out;
  }
  std::wstring headers = L"Content-Type: application/octet-stream\r\n";
  headers += L"User-Agent: Spotify/130100234 Win32_x86_64/0 (PC desktop)\r\n";
  headers += L"app-platform: Win32_x86_64\r\n";
  if (!auth.empty()) {
    headers += L"Authorization: ";
    headers += std::wstring(auth.begin(), auth.end());
    headers += L"\r\n";
  }
  if (!client_token.empty()) {
    headers += L"client-token: ";
    headers += std::wstring(client_token.begin(), client_token.end());
    headers += L"\r\n";
  }
  BOOL ok = WinHttpSendRequest(req, headers.c_str(), (DWORD)headers.size(),
                               (LPVOID)body.data(), (DWORD)body.size(),
                               (DWORD)body.size(), 0);
  if (ok) ok = WinHttpReceiveResponse(req, nullptr);
  if (ok) {
    DWORD status = 0, sz = sizeof(status);
    WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &status, &sz,
                        WINHTTP_NO_HEADER_INDEX);
    *status_out = (int)status;
    char buf[65536];
    DWORD got = 0;
    while (WinHttpReadData(req, buf, sizeof(buf), &got) && got > 0)
      out.insert(out.end(), buf, buf + got);
  } else {
    *status_out = -1;
  }
  WinHttpCloseHandle(req);
  WinHttpCloseHandle(con);
  WinHttpCloseHandle(ses);
  return out;
}

// ---------------------------------------------------------------------------
// 样本解密
// ---------------------------------------------------------------------------

static bool decrypt_samples(cdm::ContentDecryptionModule_10* cdm, Host& host,
                            const std::string& in_path, const std::string& out_path,
                            bool cbcs, uint32_t pattern_crypt, uint32_t pattern_skip,
                            const std::vector<uint8_t>& key_id) {
  std::ifstream in(in_path, std::ios::binary);
  std::ofstream out(out_path, std::ios::binary);
  if (!in || !out) return false;

  auto ru32 = [&](uint32_t* v) { return (bool)in.read((char*)v, 4); };
  uint32_t count = 0;
  in.read((char*)&count, 4);
  fprintf(stderr, "[cdm] 样本数=%u scheme=%s kid=%zuB\n", count, cbcs ? "cbcs" : "cenc", key_id.size());

  uint32_t ok = 0, fail = 0;
  for (uint32_t i = 0; i < count; i++) {
    uint32_t iv_size = 0, nsub = 0, data_size = 0;
    if (!ru32(&iv_size)) break;
    std::vector<uint8_t> iv(iv_size);
    in.read((char*)iv.data(), iv_size);
    in.read((char*)&nsub, 4);
    std::vector<cdm::SubsampleEntry> subs(nsub);
    for (uint32_t s = 0; s < nsub; s++) {
      in.read((char*)&subs[s].clear_bytes, 4);
      in.read((char*)&subs[s].cipher_bytes, 4);
    }
    in.read((char*)&data_size, 4);
    std::vector<uint8_t> data(data_size);
    in.read((char*)data.data(), data_size);
    if (!in) break;

    if (iv_size == 0) {  // 明文样本（无 senc）直接透传
      out.write((char*)data.data(), data_size);
      ok++;
      continue;
    }

    cdm::InputBuffer_2 ib{};
    ib.data = data.data();
    ib.data_size = data_size;
    ib.encryption_scheme = cbcs ? cdm::EncryptionScheme::kCbcs : cdm::EncryptionScheme::kCenc;
    ib.key_id = key_id.empty() ? nullptr : key_id.data();
    ib.key_id_size = (uint32_t)key_id.size();
    ib.iv = iv.data();
    ib.iv_size = iv_size;
    ib.subsamples = nsub ? subs.data() : nullptr;
    ib.num_subsamples = nsub;
    ib.pattern = {pattern_crypt, pattern_skip};
    ib.timestamp = i * 20000LL;

    if (i == 433) {
      std::string iv_hex;
      for (uint8_t b : iv) { char buf[3]; sprintf(buf, "%02x", b); iv_hex += buf; }
      fprintf(stderr, "[cdm] Sample 433 raw: iv_len=%u iv=%s data_len=%u raw_head=%02x%02x%02x%02x%02x%02x\n",
              iv_size, iv_hex.c_str(), data_size,
              data[0], data[1], data[2], data[3], data[4], data[5]);

      // Diagnostic probe
      struct Probe {
        std::string name;
        std::vector<uint8_t> test_iv;
        cdm::EncryptionScheme scheme;
        const uint8_t* k_ptr;
        uint32_t k_sz;
      };
      std::vector<uint8_t> iv8 = iv;
      std::vector<uint8_t> iv16_post = iv; iv16_post.resize(16, 0);
      std::vector<uint8_t> iv16_pre(8, 0); iv16_pre.insert(iv16_pre.end(), iv.begin(), iv.end());
      std::vector<uint8_t> iv8_rev = iv; std::reverse(iv8_rev.begin(), iv8_rev.end());
      std::vector<uint8_t> iv16_rev_post = iv8_rev; iv16_rev_post.resize(16, 0);

      std::vector<Probe> probes = {
        {"orig_iv8_cenc", iv8, cdm::EncryptionScheme::kCenc, key_id.data(), (uint32_t)key_id.size()},
        {"iv16_post_cenc", iv16_post, cdm::EncryptionScheme::kCenc, key_id.data(), (uint32_t)key_id.size()},
        {"iv16_pre_cenc", iv16_pre, cdm::EncryptionScheme::kCenc, key_id.data(), (uint32_t)key_id.size()},
        {"iv8_rev_cenc", iv8_rev, cdm::EncryptionScheme::kCenc, key_id.data(), (uint32_t)key_id.size()},
        {"iv16_rev_post_cenc", iv16_rev_post, cdm::EncryptionScheme::kCenc, key_id.data(), (uint32_t)key_id.size()},
        {"orig_iv8_cbcs", iv8, cdm::EncryptionScheme::kCbcs, key_id.data(), (uint32_t)key_id.size()},
        {"iv16_post_cbcs", iv16_post, cdm::EncryptionScheme::kCbcs, key_id.data(), (uint32_t)key_id.size()},
        {"nokey_orig_iv8", iv8, cdm::EncryptionScheme::kCenc, nullptr, 0},
        {"nokey_iv16_post", iv16_post, cdm::EncryptionScheme::kCenc, nullptr, 0},
      };

      for (auto& p : probes) {
        cdm::InputBuffer_2 tib{};
        tib.data = data.data();
        tib.data_size = data_size;
        tib.encryption_scheme = p.scheme;
        tib.key_id = p.k_ptr;
        tib.key_id_size = p.k_sz;
        tib.iv = p.test_iv.data();
        tib.iv_size = (uint32_t)p.test_iv.size();
        tib.timestamp = i * 20000LL;
        HostDecryptedBlock tblk;
        cdm::Status tst = cdm->Decrypt(tib, &tblk);
        if (tst == cdm::kSuccess && tblk.DecryptedBuffer()) {
          const uint8_t* td = tblk.DecryptedBuffer()->Data();
          fprintf(stderr, "  [probe] %-20s: status=OK head=%02x%02x%02x%02x%02x%02x\n",
                  p.name.c_str(), td[0], td[1], td[2], td[3], td[4], td[5]);
          tblk.DecryptedBuffer()->Destroy();
        } else {
          fprintf(stderr, "  [probe] %-20s: status=%d\n", p.name.c_str(), tst);
        }
      }
    }

    HostDecryptedBlock block;
    cdm::Status st = cdm->Decrypt(ib, &block);
    if (st != cdm::kSuccess || !block.DecryptedBuffer()) {
      fail++;
      if (fail <= 3) fprintf(stderr, "[cdm] Decrypt#%u -> %d\n", i, st);
      continue;
    }
    cdm::Buffer* b = block.DecryptedBuffer();
    if (i == 433) {
      const uint8_t* dec_d = b->Data();
      fprintf(stderr, "[cdm] Sample 433 dec: sz=%u head=%02x%02x%02x%02x%02x%02x\n",
              b->Size(), dec_d[0], dec_d[1], dec_d[2], dec_d[3], dec_d[4], dec_d[5]);
    }
    out.write((char*)b->Data(), b->Size());
    b->Destroy();
    ok++;
  }
  fprintf(stderr, "[cdm] 解密完成 ok=%u fail=%u\n", ok, fail);
  return ok > 0;
}

// ---------------------------------------------------------------------------

int wmain(int argc, wchar_t** argv) {
  std::string dll, pssh, cert, license_url, auth, client_token, samples, out, scheme = "cenc", kid_hex;
  bool allow_distinctive = false, allow_persistent = false;
  for (int i = 1; i < argc - 1; i++) {
    auto val = [&]() { return std::string(); };
    std::wstring a = argv[i];
    std::wstring v = argv[i + 1];
    auto tos = [](const std::wstring& w) { return std::string(w.begin(), w.end()); };
    if (a == L"--dll") dll = tos(v);
    else if (a == L"--pssh") pssh = tos(v);
    else if (a == L"--cert") cert = tos(v);
    else if (a == L"--license-url") license_url = tos(v);
    else if (a == L"--auth") auth = tos(v);
    else if (a == L"--client-token") client_token = tos(v);
    else if (a == L"--samples") samples = tos(v);
    else if (a == L"--out") out = tos(v);
    else if (a == L"--scheme") scheme = tos(v);
    else if (a == L"--kid") kid_hex = tos(v);
    else if (a == L"--distinctive") { allow_distinctive = (v == L"1" || v == L"true"); }
    else if (a == L"--persistent") { allow_persistent = (v == L"1" || v == L"true"); }
    else continue;
    i++;
  }

  // 1) 加载 CDM
  HMODULE mod = LoadLibraryA(dll.c_str());
  if (!mod) { fprintf(stderr, "LoadLibrary 失败 %s\n", dll.c_str()); return 1; }
  auto init = (void (*)())GetProcAddress(mod, "InitializeCdmModule_4");
  auto create = (void* (*)(int, const char*, uint32_t, void* (*)(int, void*), void*))(
      void*)GetProcAddress(mod, "CreateCdmInstance");
  auto deinit = (void (*)())GetProcAddress(mod, "DeinitializeCdmModule");
  auto ver = (const char* (*)())GetProcAddress(mod, "GetCdmVersion");
  if (!init || !create) { fprintf(stderr, "导出缺失\n"); return 1; }
  init();
  fprintf(stderr, "[cdm] version=%s\n", ver ? ver() : "?");

  const char* ks = "com.widevine.alpha";
  auto* cdm = (cdm::ContentDecryptionModule_10*)create(
      cdm::ContentDecryptionModule_10::kVersion, ks, (uint32_t)strlen(ks),
      &GetHostFunc, nullptr);
  if (!cdm) { fprintf(stderr, "CreateCdmInstance 失败\n"); return 1; }
  g_host.cdm = cdm;
  cdm->Initialize(allow_distinctive, allow_persistent, false);
  for (int i = 0; i < 100 && !g_host.initialized; i++)
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  fprintf(stderr, "[cdm] Initialize ok=%d (distinctive=%d, persistent=%d)\n",
          g_host.init_ok, allow_distinctive, allow_persistent);

  auto pump_until = [&](const std::function<bool()>& done) {
    for (int i = 0; i < 500; i++) {
      {
        std::lock_guard<std::mutex> g(g_host.mu);
        if (done() || g_host.promise_rejected) return;
        for (auto it = g_host.timers.begin(); it != g_host.timers.end(); ++it) {
          if (it->due_ms <= Host::wall_ms()) {
            void* ctx = it->ctx;
            g_host.timers.erase(it);
            g_host.mu.unlock();
            cdm->TimerExpired(ctx);
            g_host.mu.lock();
            break;
          }
        }
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  };

  // 1.5) SetServerCertificate（若提供）
  if (!cert.empty()) {
    std::vector<uint8_t> cert_data;
    {
      std::ifstream f(cert, std::ios::binary);
      if (!f) {
        fprintf(stderr, "无法打开证书文件 %s\n", cert.c_str());
        return 1;
      }
      cert_data.assign(std::istreambuf_iterator<char>(f), {});
    }
    g_host.promise_resolved = false;
    g_host.promise_rejected = false;
    cdm->SetServerCertificate(1, cert_data.data(), (uint32_t)cert_data.size());
    pump_until([&]() { return g_host.promise_resolved; });
    fprintf(stderr, "[cdm] SetServerCertificate res=%d rej=%d msg=%s\n",
            g_host.promise_resolved, g_host.promise_rejected, g_host.reject_msg.c_str());
    if (g_host.promise_rejected) {
      fprintf(stderr, "[cdm] SetServerCertificate 失败\n");
      return 10;
    }
  }

  // 2) PSSH → license 请求
  std::vector<uint8_t> pssh_data;
  {
    std::ifstream f(pssh, std::ios::binary);
    pssh_data.assign(std::istreambuf_iterator<char>(f), {});
  }
  g_host.got_message = false;
  g_host.promise_rejected = false;
  cdm->CreateSessionAndGenerateRequest(2, cdm::kTemporary, cdm::kCenc,
                                       pssh_data.data(), (uint32_t)pssh_data.size());
  pump_until([&]() { return g_host.got_message; });
  if (!g_host.got_message) {
    fprintf(stderr, "[cdm] 未产生 license 请求 reject=%s\n", g_host.reject_msg.c_str());
    return 2;
  }
  fprintf(stderr, "[cdm] license 请求 %zu B\n", g_host.license_request.size());
  {
    std::ofstream lf("D:\\tmp\\license_req.bin", std::ios::binary);
    lf.write((const char*)g_host.license_request.data(), g_host.license_request.size());
  }

  // 3) license 交换
  std::wstring wurl(license_url.begin(), license_url.end());
  int status = 0;
  auto resp = http_post(wurl, auth, client_token, g_host.license_request, &status);
  fprintf(stderr, "[cdm] license HTTP %d %zu B\n", status, resp.size());
  if (status != 200) {
    if (!resp.empty()) {
      fprintf(stderr, "[cdm] license 错误返回: %.*s\n",
              (int)std::min<size_t>(resp.size(), 500), (const char*)resp.data());
    }
    return 3;
  }

  cdm->UpdateSession(3, g_host.session_id.c_str(),
                     (uint32_t)g_host.session_id.size(), resp.data(),
                     (uint32_t)resp.size());
  for (int i = 0; i < 300 && !g_host.keys_usable; i++)
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  fprintf(stderr, "[cdm] keys_usable=%d\n", g_host.keys_usable);
  if (!g_host.keys_usable) return 4;

  // 4) 逐样本解密
  std::vector<uint8_t> kid;
  for (size_t i = 0; i + 1 < kid_hex.size(); i += 2)
    kid.push_back((uint8_t)strtol(kid_hex.substr(i, 2).c_str(), nullptr, 16));

  bool cbcs = (scheme == "cbcs");
  bool ok = decrypt_samples(cdm, g_host, samples, out, cbcs,
                            cbcs ? 1 : 0, cbcs ? 9 : 0, kid);
  if (!ok && cbcs) {
    fprintf(stderr, "[cdm] cbcs 1:9 失败，重试 0:0\n");
    ok = decrypt_samples(cdm, g_host, samples, out, cbcs, 0, 0, kid);
  }

  cdm->Destroy();
  if (deinit) deinit();
  FreeLibrary(mod);
  return ok ? 0 : 5;
}

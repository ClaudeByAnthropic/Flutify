#include "windows_trust_store.h"

#include <windows.h>
#include <wincrypt.h>

#include <vector>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateWindowsTrustStoreChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "flutify/windows_trust_store",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "roots") {
      result->NotImplemented();
      return;
    }
    // The current-user logical ROOT store also includes machine roots. Never
    // import the personal or intermediate stores as trust anchors.
    HCERTSTORE store = CertOpenStore(
        CERT_STORE_PROV_SYSTEM_W, 0, 0,
        CERT_SYSTEM_STORE_CURRENT_USER | CERT_STORE_READONLY_FLAG |
            CERT_STORE_OPEN_EXISTING_FLAG,
        L"ROOT");
    if (!store) {
      result->Error("root_store_unavailable", "Cannot open Windows ROOT store");
      return;
    }
    flutter::EncodableList roots;
    PCCERT_CONTEXT cert = nullptr;
    while ((cert = CertEnumCertificatesInStore(store, cert)) != nullptr) {
      // Honor Windows' disabled/disallowed roots and server-auth usage policy.
      // This is a local store read: no certificate downloads on the UI thread.
      LPSTR usage = const_cast<LPSTR>(szOID_PKIX_KP_SERVER_AUTH);
      CERT_CHAIN_PARA parameters{};
      parameters.cbSize = sizeof(parameters);
      parameters.RequestedUsage.dwType = USAGE_MATCH_TYPE_AND;
      parameters.RequestedUsage.Usage.cUsageIdentifier = 1;
      parameters.RequestedUsage.Usage.rgpszUsageIdentifier = &usage;
      PCCERT_CHAIN_CONTEXT chain = nullptr;
      const BOOL built = CertGetCertificateChain(
          nullptr, cert, nullptr, store, &parameters,
          CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL | CERT_CHAIN_DISABLE_AUTH_ROOT_AUTO_UPDATE,
          nullptr, &chain);
      if (built && chain->TrustStatus.dwErrorStatus == CERT_TRUST_NO_ERROR) {
        roots.emplace_back(std::vector<uint8_t>(
            cert->pbCertEncoded, cert->pbCertEncoded + cert->cbCertEncoded));
      }
      if (chain) CertFreeCertificateChain(chain);
    }
    CertCloseStore(store, 0);
    result->Success(flutter::EncodableValue(std::move(roots)));
  });
  return channel;
}

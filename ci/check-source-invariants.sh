#!/bin/sh
# Быстрые регрессии для критичных правил v1.1/v1.2 до тяжёлой PSDK-сборки.
set -eu

CMS_SOURCE="src/pkcs11_cms.cpp"
OBJECT_SOURCE="src/pkcs11_objects.cpp"
TOKEN_PAGE="qml/pages/TokenPage.qml"
CERTIFICATE_PAGE="qml/pages/CertificatePage.qml"
CRYPTOPRO_SOURCE="src/cryptoprosession.cpp"
CRYPTOPRO_HEADER="src/cryptopro_capi_minimal.h"
CRYPTOPRO_PAGE="qml/pages/CryptoProPage.qml"
CRYPTOPRO_CERT_PAGE="qml/pages/CryptoProCertificatePage.qml"
DESKTOP="ru.codeagent43824.rutokentestapp.desktop"
SPEC="rpm/ru.codeagent43824.rutokentestapp.spec"

grep -Fq \
    'const CK_ULONG flags = detached ? PKCS7_DETACHED_SIGNATURE : 0UL;' \
    "$CMS_SOURCE"
if grep -Eq '^[[:space:]]*const CK_ULONG USE_HARDWARE_HASH' "$CMS_SOURCE"; then
    echo "CMS signing must not enable the hardware-hash flag" >&2
    exit 1
fi

grep -Fq 'QDateTime::currentDateTimeUtc() > notAfter.toUTC()' "$CMS_SOURCE"
grep -Fq 'cert.insert(QStringLiteral("expired"), expired);' "$OBJECT_SOURCE"
grep -Fq 'out.append(activeCertificates);' "$OBJECT_SOURCE"
grep -Fq 'out.append(expiredCertificates);' "$OBJECT_SOURCE"

grep -Fq 'opacity: modelData.kind === "certificate" && modelData.expired' "$TOKEN_PAGE"
grep -Fq 'notAfterMs: modelData.notAfterMs ? modelData.notAfterMs : 0' "$TOKEN_PAGE"
grep -Fq 'visible: !page.expired && page.idHex.length > 0' "$CERTIFICATE_PAGE"

for SYMBOL in \
    CryptEnumProvidersA \
    CryptAcquireContextA \
    CryptGetProvParam \
    CertOpenSystemStoreA \
    CertEnumCertificatesInStore \
    CertGetCertificateContextProperty \
    CertFreeCertificateContext \
    CryptAcquireCertificatePrivateKey; do
    grep -Fq "\"$SYMBOL\"" "$CRYPTOPRO_SOURCE"
done
grep -Fq \
    'QStringLiteral("/usr/lib/3rdparty/ru.cryptopro.csp/lib/libcapi20.so")' \
    "$CRYPTOPRO_SOURCE"
grep -Fq \
    'Permissions=NFC;UserDirs;ru.cryptopro.gui@ru.cryptopro.csp' \
    "$DESKTOP"
grep -Fq 'CryptVerifyContext | capi::CryptSilent' "$CRYPTOPRO_SOURCE"
grep -Fq 'CryptAcquireSilentFlag | capi::CryptAcquireCompareKeyFlag' "$CRYPTOPRO_SOURCE"
grep -Fq 'QCryptographicHash::Sha256' "$CRYPTOPRO_SOURCE"
grep -Fq 'exactDuplicateCount' "$CRYPTOPRO_SOURCE"
grep -Fq 'containerCertificateCount' "$CRYPTOPRO_SOURCE"
grep -Fq 'metadataConflict' "$CRYPTOPRO_SOURCE"
grep -Fq 'typedef wchar_t WideChar;' "$CRYPTOPRO_HEADER"
grep -Fq 'QCoreApplication::applicationFilePath()' "$CRYPTOPRO_SOURCE"
grep -Fq 'QStringLiteral("--cryptopro-scan-helper")' "$CRYPTOPRO_SOURCE"
grep -Fq 'RUTOKEN_CRYPTOPRO_JSON:' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxProviders = 128;' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxContainersPerProvider = 512;' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxCertificates = 4096;' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxHelperOutputBytes = 4 * 1024 * 1024;' "$CRYPTOPRO_SOURCE"
grep -Fq 'physicalContainerKey' "$CRYPTOPRO_SOURCE"
grep -Fq 'logicalContainerByKey' "$CRYPTOPRO_SOURCE"
grep -Fq 'status === PageStatus.Active' "$CRYPTOPRO_PAGE"
if grep -Fq 'cryptoProSession.refresh()' "$TOKEN_PAGE"; then
    echo "CryptoPro scan must start only after its page becomes active" >&2
    exit 1
fi

if grep -Eiq 'pkcs11|certmgr|cryptcp|/bin/(sh|bash)|C_Set|CertSet|CryptGen|CryptDestroy' \
        "$CRYPTOPRO_SOURCE" "$CRYPTOPRO_HEADER"; then
    echo "CryptoPro v1.2 adapter must stay internal-helper, CapiLite-only and read-only" >&2
    exit 1
fi
if grep -Eiq '^(Requires|BuildRequires):.*(cprocsp|cryptopro)' "$SPEC"; then
    echo "CryptoPro CSP must remain an optional external runtime" >&2
    exit 1
fi

grep -Fq 'model: cryptoProSession.containers' "$CRYPTOPRO_PAGE"
grep -Fq 'model: cryptoProSession.certificates' "$CRYPTOPRO_PAGE"
grep -Fq 'certificate.sha256' "$CRYPTOPRO_CERT_PAGE"
grep -Fq 'This screen does not change certificates or containers' "$CRYPTOPRO_CERT_PAGE"

echo "Source invariants verified: v1.1 CMS/expiry and v1.2 optional read-only CapiLite"

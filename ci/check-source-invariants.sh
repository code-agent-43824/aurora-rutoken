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
    CryptAcquireCertificatePrivateKey; do
    grep -Fq "\"$SYMBOL\"" "$CRYPTOPRO_SOURCE"
done
grep -Fq 'QStringLiteral("libcapi20.so")' "$CRYPTOPRO_SOURCE"
grep -Fq 'CryptVerifyContext | capi::CryptSilent' "$CRYPTOPRO_SOURCE"
grep -Fq 'CryptAcquireSilentFlag | capi::CryptAcquireCompareKeyFlag' "$CRYPTOPRO_SOURCE"
grep -Fq 'QCryptographicHash::Sha256' "$CRYPTOPRO_SOURCE"
grep -Fq 'exactDuplicateCount' "$CRYPTOPRO_SOURCE"
grep -Fq 'containerCertificateCount' "$CRYPTOPRO_SOURCE"
grep -Fq 'metadataConflict' "$CRYPTOPRO_SOURCE"
grep -Fq 'typedef wchar_t WideChar;' "$CRYPTOPRO_HEADER"

if grep -Eq 'pkcs11|QProcess|certmgr|cryptcp|C_Set|CertSet|CryptGen|CryptDestroy' \
        "$CRYPTOPRO_SOURCE" "$CRYPTOPRO_HEADER"; then
    echo "CryptoPro v1.2 adapter must stay CapiLite-only and read-only" >&2
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

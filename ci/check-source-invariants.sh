#!/bin/sh
# Быстрые регрессии для критичных правил v1.1 до тяжёлой PSDK-сборки.
set -eu

CMS_SOURCE="src/pkcs11_cms.cpp"
OBJECT_SOURCE="src/pkcs11_objects.cpp"
TOKEN_PAGE="qml/pages/TokenPage.qml"
CERTIFICATE_PAGE="qml/pages/CertificatePage.qml"

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

echo "Source invariants verified: CMS flags, expiry guard, sorting and signing UI"

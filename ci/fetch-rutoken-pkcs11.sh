#!/bin/sh
# Download the original official Rutoken PKCS#11 RPM for one architecture,
# verify its pinned digest, then inspect the package inside Aurora PSDK.
set -eu

TARGET_ARCH="${TARGET_ARCH:?TARGET_ARCH is not set}"
PSDK_DIR="$HOME/AuroraPlatformSDK/sdks/aurora_psdk"
VERSION="2.19.0.0"
RELEASE="1"
BASE_URL="https://download.rutoken.ru/Rutoken/PKCS11Lib/$VERSION/Aurora"

case "$TARGET_ARCH" in
    armv7hl)
        URL="$BASE_URL/armv7/ru.rutoken.librtpkcs11ecp-$VERSION-$RELEASE.armv7hl.rpm"
        SHA256="b9f0da43dd884a95b629155cad3c21a4701ddc0220798bcc046c0146b4cd88c3"
        ;;
    aarch64)
        URL="$BASE_URL/aarch64/ru.rutoken.librtpkcs11ecp-$VERSION-$RELEASE.aarch64.rpm"
        SHA256="c16d8c2006631e9330a1ee6c8b2f60e5ddbfaf7112a0d5056e3b21ca92e69921"
        ;;
    *)
        echo "Unsupported TARGET_ARCH: $TARGET_ARCH" >&2
        exit 2
        ;;
esac

mkdir -p RPMS
# Keep the official dependency next to the already verified application RPM.
# A single upload root makes the Actions artifact flat and deterministic.
RPM_PATH="RPMS/${URL##*/}"

echo "== downloading official Rutoken PKCS#11 $VERSION for $TARGET_ARCH"
curl --fail --location --retry 3 --output "$RPM_PATH" "$URL"
printf '%s  %s\n' "$SHA256" "$RPM_PATH" | sha256sum --check --strict

echo "== verifying unchanged official Rutoken RPM"
"$PSDK_DIR/sdk-chroot" ./ci/verify-rutoken-rpm.sh "$TARGET_ARCH" "$RPM_PATH"

echo "== verified official dependency package"
ls -l "$RPM_PATH"

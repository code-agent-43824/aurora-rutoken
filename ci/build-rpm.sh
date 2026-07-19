#!/bin/sh
# Сборка, подпись и проверка одного RPM в чистом matrix job.
# TARGET_ARCH обязан быть ровно armv7hl либо aarch64.
set -eu

PSDK_BUILD="${PSDK_BUILD:?PSDK_BUILD is not set}"
TARGET_ARCH="${TARGET_ARCH:?TARGET_ARCH is not set}"
PSDK_DIR="$HOME/AuroraPlatformSDK/sdks/aurora_psdk"

case "$TARGET_ARCH" in
    armv7hl|aarch64) ;;
    *) echo "Unsupported TARGET_ARCH: $TARGET_ARCH" >&2; exit 2 ;;
esac

if ! "$PSDK_DIR/sdk-chroot" which rpmsign-external >/dev/null 2>&1; then
    echo "== rpmsign-external not found in tooling, installing"
    "$PSDK_DIR/sdk-chroot" sudo zypper --non-interactive install rpmsign-external-tool
fi

rm -rf RPMS

echo "== building for $TARGET_ARCH"
"$PSDK_DIR/sdk-chroot" mb2 -t "AuroraOS-${PSDK_BUILD}-${TARGET_ARCH}" build

set -- RPMS/*.rpm
if [ ! -e "$1" ] || [ "$#" -ne 1 ]; then
    echo "Expected exactly one RPM for $TARGET_ARCH, got $#" >&2
    exit 1
fi
RPM_PATH="$1"

case "$RPM_PATH" in
    *."$TARGET_ARCH".rpm) ;;
    *) echo "Unexpected RPM filename for $TARGET_ARCH: $RPM_PATH" >&2; exit 1 ;;
esac

echo "== signing $RPM_PATH with the OMP regular test key"
"$PSDK_DIR/sdk-chroot" rpmsign-external sign \
    --key ci/keys/regular_key.pem --cert ci/keys/regular_cert.pem "$RPM_PATH"

echo "== verifying package architecture, ELF loader and signature metadata"
"$PSDK_DIR/sdk-chroot" ./ci/verify-rpm.sh "$TARGET_ARCH" "$RPM_PATH"

echo "== verified package"
ls -l "$RPM_PATH"

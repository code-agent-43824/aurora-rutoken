#!/bin/sh
# Минимальная установка Platform SDK chroot для переподписания готовых RPM.
# Tooling и target не нужны: приложение здесь не пересобирается.
set -eu

PSDK_RELEASE="${PSDK_RELEASE:?PSDK_RELEASE is not set}"
PSDK_BUILD="${PSDK_BUILD:?PSDK_BUILD is not set}"

BASE_URL="https://sdk-repo.omprussia.ru/sdk/installers/${PSDK_RELEASE}/${PSDK_BUILD}-release/AuroraPSDK"
CHROOT_TB="Aurora_OS-${PSDK_BUILD}-Aurora_Platform_SDK_Chroot-x86_64.tar.bz2"
PSDK_HOME="$HOME/AuroraPlatformSDK"
PSDK_DIR="$PSDK_HOME/sdks/aurora_psdk"
TARBALLS="$PSDK_HOME/tarballs"

mkdir -p "$PSDK_DIR" "$TARBALLS"

if [ -s "$TARBALLS/$CHROOT_TB" ]; then
    echo "== $CHROOT_TB: found in cache"
else
    echo "== downloading $CHROOT_TB"
    curl -fL --retry 5 --retry-delay 10 -C - \
        -o "$TARBALLS/$CHROOT_TB" "$BASE_URL/$CHROOT_TB"
fi

echo "== extracting Platform SDK chroot"
sudo tar --numeric-owner -p -xjf "$TARBALLS/$CHROOT_TB" -C "$PSDK_DIR"

if ! "$PSDK_DIR/sdk-chroot" which rpmsign-external >/dev/null 2>&1; then
    echo "== installing rpmsign-external-tool"
    "$PSDK_DIR/sdk-chroot" sudo zypper --non-interactive install \
        rpmsign-external-tool
fi

"$PSDK_DIR/sdk-chroot" rpmsign-external --help >/dev/null
echo "== signing tooling is ready"

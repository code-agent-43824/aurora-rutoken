#!/bin/sh
# Установка Аврора Platform SDK (chroot) на ubuntu-раннере GitHub Actions.
# Тарболлы берутся с публичного sdk-repo.omprussia.ru и кэшируются actions/cache.
set -eu

PSDK_RELEASE="${PSDK_RELEASE:?PSDK_RELEASE is not set}"
PSDK_BUILD="${PSDK_BUILD:?PSDK_BUILD is not set}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"

BASE_URL="https://sdk-repo.omprussia.ru/sdk/installers/${PSDK_RELEASE}/${PSDK_BUILD}-release/AuroraPSDK"
CHROOT_TB="Aurora_OS-${PSDK_BUILD}-Aurora_Platform_SDK_Chroot-x86_64.tar.bz2"
TOOLING_TB="Aurora_OS-${PSDK_BUILD}-Aurora_SDK_Tooling-x86_64.tar.7z"
TARGET_TB="Aurora_OS-${PSDK_BUILD}-Aurora_SDK_Target-${TARGET_ARCH}.tar.7z"

PSDK_HOME="$HOME/AuroraPlatformSDK"
PSDK_DIR="$PSDK_HOME/sdks/aurora_psdk"
TARBALLS="$PSDK_HOME/tarballs"

# Освобождаем место на раннере: PSDK + target занимают ~12 ГБ.
sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /opt/hostedtoolcache/CodeQL || true
df -h / | tail -1

mkdir -p "$PSDK_DIR" "$TARBALLS"

for f in "$CHROOT_TB" "$TOOLING_TB" "$TARGET_TB"; do
    if [ -s "$TARBALLS/$f" ]; then
        echo "== $f: found in cache"
    else
        echo "== downloading $f"
        curl -fL --retry 5 --retry-delay 10 -C - -o "$TARBALLS/$f" "$BASE_URL/$f"
    fi
done

echo "== extracting Platform SDK chroot"
sudo tar --numeric-owner -p -xjf "$TARBALLS/$CHROOT_TB" -C "$PSDK_DIR"

echo "== creating tooling AuroraOS-${PSDK_BUILD}"
"$PSDK_DIR/sdk-chroot" sdk-assistant tooling create \
    "AuroraOS-${PSDK_BUILD}" "$TARBALLS/$TOOLING_TB" --non-interactive

echo "== creating target AuroraOS-${PSDK_BUILD}-${TARGET_ARCH}"
"$PSDK_DIR/sdk-chroot" sdk-assistant target create \
    "AuroraOS-${PSDK_BUILD}-${TARGET_ARCH}" "$TARBALLS/$TARGET_TB" --non-interactive

"$PSDK_DIR/sdk-chroot" sdk-assistant list

#!/bin/sh
# Сборка RPM приложения через mb2 в chroot Аврора Platform SDK.
# Запускать из корня проекта. Результат кладётся в ./RPMS/.
set -eu

PSDK_BUILD="${PSDK_BUILD:?PSDK_BUILD is not set}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
PSDK_DIR="$HOME/AuroraPlatformSDK/sdks/aurora_psdk"

"$PSDK_DIR/sdk-chroot" mb2 -t "AuroraOS-${PSDK_BUILD}-${TARGET_ARCH}" build

echo "== built packages:"
ls -l RPMS/

#!/bin/sh
# Сборка RPM приложения через mb2 в chroot Аврора Platform SDK для всех
# архитектур из TARGET_ARCHS и подпись тестовым ключом (профиль regular).
# Без подписи Аврора 5 отклоняет пакет (BadPackageSignature); пакет чужой
# архитектуры — BadPackageArchitecture (телефон владельца — 32-битный armv7hl).
# Запускать из корня проекта. Результат кладётся в ./RPMS/.
set -eu

PSDK_BUILD="${PSDK_BUILD:?PSDK_BUILD is not set}"
TARGET_ARCHS="${TARGET_ARCHS:-armv7hl aarch64}"
PSDK_DIR="$HOME/AuroraPlatformSDK/sdks/aurora_psdk"

# rpmsign-external нужен один раз (живёт в тулинге/чруте, не в таргете).
if ! "$PSDK_DIR/sdk-chroot" which rpmsign-external >/dev/null 2>&1; then
    echo "== rpmsign-external not found in tooling, installing"
    "$PSDK_DIR/sdk-chroot" sudo zypper --non-interactive install rpmsign-external-tool
fi

OUT="RPMS-out"
rm -rf "$OUT" RPMS
mkdir -p "$OUT"

for arch in $TARGET_ARCHS; do
    echo "== building for $arch"
    "$PSDK_DIR/sdk-chroot" mb2 -t "AuroraOS-${PSDK_BUILD}-${arch}" build

    # Подпись публичной тестовой парой ключей OMP (ci/keys/, источник —
    # developer.auroraos.ru, раздел package_signing). Ключ ГОСТ Р 34.10-2012,
    # поэтому подписываем внутри чрута PSDK, где есть ГОСТ-крипто.
    echo "== signing $arch packages with the regular test key"
    for rpm in RPMS/*.rpm; do
        "$PSDK_DIR/sdk-chroot" rpmsign-external sign \
            --key ci/keys/regular_key.pem --cert ci/keys/regular_cert.pem "$rpm"
        "$PSDK_DIR/sdk-chroot" rpmsign-external dump "$rpm"
    done

    mv RPMS/*.rpm "$OUT"/
    rm -rf RPMS
done

mv "$OUT" RPMS
echo "== built packages:"
ls -l RPMS/

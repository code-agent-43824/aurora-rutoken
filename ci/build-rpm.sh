#!/bin/sh
# Сборка RPM приложения через mb2 в chroot Аврора Platform SDK и подпись
# тестовым ключом (профиль regular). Без подписи Аврора 5 отклоняет пакет
# с ошибкой BadPackageSignature даже при разрешённом недоверенном ПО.
# Запускать из корня проекта. Результат кладётся в ./RPMS/.
set -eu

PSDK_BUILD="${PSDK_BUILD:?PSDK_BUILD is not set}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
PSDK_DIR="$HOME/AuroraPlatformSDK/sdks/aurora_psdk"

"$PSDK_DIR/sdk-chroot" mb2 -t "AuroraOS-${PSDK_BUILD}-${TARGET_ARCH}" build

# Подпись публичной тестовой парой ключей OMP (ci/keys/, источник —
# developer.auroraos.ru, раздел package_signing). Ключ ГОСТ Р 34.10-2012,
# поэтому подписываем внутри чрута PSDK, где есть rpmsign-external и ГОСТ.
if ! "$PSDK_DIR/sdk-chroot" which rpmsign-external >/dev/null 2>&1; then
    echo "== rpmsign-external not found in tooling, installing"
    "$PSDK_DIR/sdk-chroot" sudo zypper --non-interactive install rpmsign-external-tool
fi

echo "== signing packages with the regular test key:"
for rpm in RPMS/*.rpm; do
    "$PSDK_DIR/sdk-chroot" rpmsign-external sign \
        --key ci/keys/regular_key.pem --cert ci/keys/regular_cert.pem "$rpm"
    "$PSDK_DIR/sdk-chroot" rpmsign-external dump "$rpm"
done

echo "== built packages:"
ls -l RPMS/

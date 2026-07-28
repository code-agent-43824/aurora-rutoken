#!/bin/sh
# Выполняется внутри Aurora Platform SDK chroot после подписания RPM.
set -eu

TARGET_ARCH="${1:?target architecture is required}"
RPM_PATH="${2:?RPM path is required}"
APP_ID="ru.codeagent43824.rutokentestapp"

case "$TARGET_ARCH" in
    armv7hl)
        EXPECTED_MACHINE='ARM'
        EXPECTED_LOADER='ld-linux-armhf.so.3'
        ;;
    aarch64)
        EXPECTED_MACHINE='AArch64'
        EXPECTED_LOADER='ld-linux-aarch64.so.1'
        ;;
    *)
        echo "Unsupported target architecture: $TARGET_ARCH" >&2
        exit 2
        ;;
esac

RPM_ARCH=$(rpm -qp --qf '%{ARCH}' "$RPM_PATH")
if [ "$RPM_ARCH" != "$TARGET_ARCH" ]; then
    echo "RPM architecture mismatch: expected $TARGET_ARCH, got $RPM_ARCH" >&2
    exit 1
fi

VERIFY_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_DIR"' EXIT HUP INT TERM
rpm2cpio "$RPM_PATH" | (cd "$VERIFY_DIR" && cpio -idm --quiet)

APP_BINARY="$VERIFY_DIR/usr/bin/$APP_ID"
if [ ! -f "$APP_BINARY" ]; then
    echo "Application binary is missing from RPM: /usr/bin/$APP_ID" >&2
    exit 1
fi

# v1.1: launcher перехода на CMS может скомпилироваться, даже если новый QML
# случайно не попал в RPM. Проверяем оба runtime-экрана внутри каждого пакета.
for QML_PAGE in SignFilePage.qml SignDataFilePickerPage.qml; do
    QML_PATH="$VERIFY_DIR/usr/share/$APP_ID/qml/pages/$QML_PAGE"
    if [ ! -s "$QML_PATH" ]; then
        echo "CMS signing QML is missing or empty: $QML_PATH" >&2
        exit 1
    fi
done

DESKTOP_FILE="$VERIFY_DIR/usr/share/applications/$APP_ID.desktop"
if [ ! -f "$DESKTOP_FILE" ] || ! grep -Fxq "Icon=$APP_ID" "$DESKTOP_FILE"; then
    echo "Desktop Icon must match the RPM package name: $APP_ID" >&2
    exit 1
fi
for ICON_SIZE in 86x86 108x108 128x128 172x172; do
    ICON_PATH="$VERIFY_DIR/usr/share/icons/hicolor/$ICON_SIZE/apps/$APP_ID.png"
    if [ ! -s "$ICON_PATH" ]; then
        echo "Launcher icon is missing or empty: $ICON_PATH" >&2
        exit 1
    fi
done
ICON_COUNT=$(find "$VERIFY_DIR/usr/share/icons/hicolor" -type f -path '*/apps/*.png' | wc -l)
if [ "$ICON_COUNT" -ne 4 ]; then
    echo "Expected exactly four canonical launcher PNG files, got $ICON_COUNT" >&2
    exit 1
fi

MACHINE=$(LC_ALL=C readelf -h "$APP_BINARY" | awk -F: '/^[[:space:]]*Machine:/{sub(/^[[:space:]]+/, "", $2); print $2}')
if [ "$MACHINE" != "$EXPECTED_MACHINE" ]; then
    echo "ELF machine mismatch: expected $EXPECTED_MACHINE, got $MACHINE" >&2
    exit 1
fi

INTERPRETER=$(LC_ALL=C readelf -l "$APP_BINARY" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')
case "$INTERPRETER" in
    *"$EXPECTED_LOADER") ;;
    *) echo "ELF loader mismatch: expected $EXPECTED_LOADER, got $INTERPRETER" >&2; exit 1 ;;
esac

SIGNATURE_INFO=$(rpmsign-external dump "$RPM_PATH")
printf '%s\n' "$SIGNATURE_INFO"
printf '%s\n' "$SIGNATURE_INFO" | grep -Fq 'Subject: Noname developer (for testing only, do not use for production)'
printf '%s\n' "$SIGNATURE_INFO" | grep -Fq 'Subgroup: regular'
printf '%s\n' "$SIGNATURE_INFO" | grep -Eq '^Signature: .+'

echo "Verified: rpm_arch=$RPM_ARCH; elf_machine=$MACHINE; loader=$INTERPRETER; cms_qml=present; icon=$APP_ID; signature=OMP regular test"

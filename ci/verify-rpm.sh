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

echo "Verified: rpm_arch=$RPM_ARCH; elf_machine=$MACHINE; loader=$INTERPRETER; signature=OMP regular test"

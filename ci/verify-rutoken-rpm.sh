#!/bin/sh
# Runs inside Aurora Platform SDK chroot. The SHA-256 gate in the caller proves
# this is the exact official package; these checks protect architecture/content.
set -eu

TARGET_ARCH="${1:?target architecture is required}"
RPM_PATH="${2:?RPM path is required}"
PACKAGE_NAME="ru.rutoken.librtpkcs11ecp"
PACKAGE_VERSION="2.19.0.0"
LIB_RELATIVE="usr/lib/3rdparty/$PACKAGE_NAME/librtpkcs11ecp.so"

case "$TARGET_ARCH" in
    armv7hl) EXPECTED_MACHINE='ARM' ;;
    aarch64) EXPECTED_MACHINE='AArch64' ;;
    *) echo "Unsupported target architecture: $TARGET_ARCH" >&2; exit 2 ;;
esac

RPM_NAME=$(rpm -qp --qf '%{NAME}' "$RPM_PATH")
RPM_VERSION=$(rpm -qp --qf '%{VERSION}' "$RPM_PATH")
RPM_RELEASE=$(rpm -qp --qf '%{RELEASE}' "$RPM_PATH")
RPM_ARCH=$(rpm -qp --qf '%{ARCH}' "$RPM_PATH")

[ "$RPM_NAME" = "$PACKAGE_NAME" ]
[ "$RPM_VERSION" = "$PACKAGE_VERSION" ]
[ "$RPM_RELEASE" = "1" ]
[ "$RPM_ARCH" = "$TARGET_ARCH" ]

VERIFY_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_DIR"' EXIT HUP INT TERM
rpm2cpio "$RPM_PATH" | (cd "$VERIFY_DIR" && cpio -idm --quiet)
LIBRARY="$VERIFY_DIR/$LIB_RELATIVE"
[ -f "$LIBRARY" ]

MACHINE=$(LC_ALL=C readelf -h "$LIBRARY" | awk -F: '/^[[:space:]]*Machine:/{sub(/^[[:space:]]+/, "", $2); print $2}')
if [ "$MACHINE" != "$EXPECTED_MACHINE" ]; then
    echo "Rutoken ELF machine mismatch: expected $EXPECTED_MACHINE, got $MACHINE" >&2
    exit 1
fi

SONAME=$(LC_ALL=C readelf -d "$LIBRARY" | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')
[ "$SONAME" = "librtpkcs11ecp.so" ]
LC_ALL=C readelf -d "$LIBRARY" | grep -Fq '[libpcsclite.so.1]'

for symbol in C_GetFunctionList C_Initialize C_Finalize C_GetInfo; do
    LC_ALL=C readelf -Ws "$LIBRARY" | awk '{print $8}' | grep -Fxq "$symbol"
done

echo "Verified Rutoken: name=$RPM_NAME; version=$RPM_VERSION-$RPM_RELEASE; rpm_arch=$RPM_ARCH; elf_machine=$MACHINE; soname=$SONAME"

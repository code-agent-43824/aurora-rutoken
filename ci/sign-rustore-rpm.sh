#!/bin/sh
# Переподписывает один уже проверенный RPM приложения сертификатом разработчика
# RuStore. Запускается только из ручного workflow.
set -eu

TARGET_ARCH="${1:?target architecture is required}"
RPM_PATH="${2:?RPM path is required}"
KEY_PATH="${3:?private key path is required}"
CERT_PATH="${4:?certificate path is required}"
PASS_PATH="${5:?passphrase file path is required}"
PSDK_DIR="$HOME/AuroraPlatformSDK/sdks/aurora_psdk"
APP_ID="ru.codeagent43824.rutokentestapp"
EXPECTED_CERT_SHA256="1989e9224759048af5c4efc70fb65bbc121443413634582e6a7bfbfc7614f6ac"

case "$TARGET_ARCH" in
    armv7hl|aarch64) ;;
    *) echo "Unsupported target architecture: $TARGET_ARCH" >&2; exit 2 ;;
esac

test -s "$RPM_PATH"
test -s "$KEY_PATH"
test -s "$CERT_PATH"
test -s "$PASS_PATH"
test -x "$PSDK_DIR/sdk-chroot"

CERT_SHA256=$(openssl x509 -in "$CERT_PATH" -outform DER | sha256sum | awk '{print $1}')
if [ "$CERT_SHA256" != "$EXPECTED_CERT_SHA256" ]; then
    echo "Unexpected RuStore certificate SHA-256: $CERT_SHA256" >&2
    exit 1
fi

CERT_META=$(openssl x509 -in "$CERT_PATH" -noout -subject -issuer -dates)
printf '%s\n' "$CERT_META"
printf '%s\n' "$CERT_META" | grep -Fq \
    'Open Mobile Platform LLC Root Packages Certificate'

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
chmod 600 "$KEY_PATH"

# Сравниваем canonical SubjectPublicKeyInfo. Несоответствующая пара никогда не
# доходит до подписи, даже если rpmsign-external изменит своё поведение.
"$PSDK_DIR/sdk-chroot" openssl pkey -engine gost \
    -in "$KEY_PATH" -passin "file:$PASS_PATH" -pubout -outform DER \
    > "$TMP_DIR/key-public.der"
"$PSDK_DIR/sdk-chroot" openssl x509 -engine gost \
    -in "$CERT_PATH" -pubkey -noout \
    | "$PSDK_DIR/sdk-chroot" openssl pkey -engine gost -pubin -outform DER \
        > "$TMP_DIR/cert-public.der"
if ! cmp -s "$TMP_DIR/key-public.der" "$TMP_DIR/cert-public.der"; then
    echo "Private key does not match the pinned RuStore certificate" >&2
    exit 1
fi

RPM_NAME=$("$PSDK_DIR/sdk-chroot" rpm -qp --qf '%{NAME}' "$RPM_PATH")
RPM_ARCH=$("$PSDK_DIR/sdk-chroot" rpm -qp --qf '%{ARCH}' "$RPM_PATH")
if [ "$RPM_NAME" != "$APP_ID" ] || [ "$RPM_ARCH" != "$TARGET_ARCH" ]; then
    echo "Unexpected RPM identity: name=$RPM_NAME arch=$RPM_ARCH" >&2
    exit 1
fi

echo "== existing signature"
BEFORE_DUMP=$("$PSDK_DIR/sdk-chroot" rpmsign-external dump "$RPM_PATH")
printf '%s\n' "$BEFORE_DUMP"
printf '%s\n' "$BEFORE_DUMP" | grep -Fq \
    'Subject: Noname developer (for testing only, do not use for production)'

echo "== replacing test signature with the pinned RuStore developer certificate"
"$PSDK_DIR/sdk-chroot" ./ci/rpmsign-with-passphrase.sh "$PASS_PATH" \
    sign --force --key "$KEY_PATH" --cert "$CERT_PATH" "$RPM_PATH"

echo "== resulting signature"
AFTER_DUMP=$("$PSDK_DIR/sdk-chroot" rpmsign-external dump "$RPM_PATH")
printf '%s\n' "$AFTER_DUMP"
if printf '%s\n' "$AFTER_DUMP" | grep -Fq \
    'Noname developer (for testing only, do not use for production)'; then
    echo "Test developer signature is still present" >&2
    exit 1
fi
printf '%s\n' "$AFTER_DUMP" | grep -Eq '^Signature: .+'

echo "== validating the re-signed package with the official Aurora validator"
if "$PSDK_DIR/sdk-chroot" rpm-validator -p regular --color never "$RPM_PATH"; then
    :
else
    VALIDATOR_STATUS=$?
    case "$VALIDATOR_STATUS" in
        2)
            echo "Aurora RPM validator completed with non-blocking warnings" >&2
            ;;
        *)
            echo "Aurora RPM validator rejected the package (exit $VALIDATOR_STATUS)" >&2
            exit "$VALIDATOR_STATUS"
            ;;
    esac
fi

echo "Verified RuStore-signed RPM: name=$RPM_NAME arch=$RPM_ARCH cert_sha256=$CERT_SHA256"

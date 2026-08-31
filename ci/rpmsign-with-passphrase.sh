#!/bin/sh
# Выполняется внутри Platform SDK chroot. rpmsign-external официально принимает
# кодовую фразу только через KEY_PASSPHRASE, поэтому читаем её из закрытого файла
# непосредственно перед exec. Значение не попадает в argv или журнал.
set -eu

PASS_PATH="${1:?passphrase file path is required}"
shift

IFS= read -r KEY_PASSPHRASE < "$PASS_PATH"
export KEY_PASSPHRASE
exec rpmsign-external "$@"

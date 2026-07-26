#!/usr/bin/env bash
# Publish one complete, already verified dual-architecture RPM set.
#
# The build matrix must not write to the rolling release directly. This script
# runs only after both matrix jobs succeeded, snapshots the previous RPM set,
# uploads the new four-file set, verifies GitHub's recorded SHA-256 digests and
# restores the snapshot if any publication step fails.
set -Eeuo pipefail

RPM_DIR="${1:?directory with the four verified RPMs is required}"
RELEASE_TAG="${RELEASE_TAG:-ci-latest}"
APP_ID="ru.codeagent43824.rutokentestapp"
SPEC_PATH="rpm/ru.codeagent43824.rutokentestapp.spec"

for command_name in gh jq sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command is missing: $command_name" >&2
        exit 2
    }
done

VERSION=$(awk '$1 == "Version:" { print $2; exit }' "$SPEC_PATH")
RELEASE=$(awk '$1 == "Release:" { print $2; exit }' "$SPEC_PATH")
[[ -n "$VERSION" && -n "$RELEASE" ]]

expected=(
    "$APP_ID-$VERSION-$RELEASE.armv7hl.rpm"
    "$APP_ID-$VERSION-$RELEASE.aarch64.rpm"
)

shopt -s nullglob
rutoken_arm=("$RPM_DIR"/ru.rutoken.librtpkcs11ecp-*.armv7hl.rpm)
rutoken_a64=("$RPM_DIR"/ru.rutoken.librtpkcs11ecp-*.aarch64.rpm)
[[ ${#rutoken_arm[@]} -eq 1 && ${#rutoken_a64[@]} -eq 1 ]]
expected+=("${rutoken_arm[0]##*/}" "${rutoken_a64[0]##*/}")

mapfile -t local_rpms < <(find "$RPM_DIR" -maxdepth 1 -type f -name '*.rpm' -printf '%f\n' | sort)
mapfile -t expected_sorted < <(printf '%s\n' "${expected[@]}" | sort)
[[ ${#local_rpms[@]} -eq 4 ]]
diff -u <(printf '%s\n' "${expected_sorted[@]}") <(printf '%s\n' "${local_rpms[@]}")

for name in "${expected_sorted[@]}"; do
    [[ -s "$RPM_DIR/$name" ]]
done

echo "Verified local publication set:"
sha256sum "${expected_sorted[@]/#/$RPM_DIR/}"

if [[ "${PUBLISH_DRY_RUN:-0}" == "1" ]]; then
    echo "Dry run: local four-RPM set is valid"
    exit 0
fi

transaction_dir=$(mktemp -d)
backup_dir="$transaction_dir/backup"
old_names="$transaction_dir/old-rpm-names"
mkdir -p "$backup_dir"

gh release view "$RELEASE_TAG" --json assets \
    --jq '.assets[].name | select(endswith(".rpm"))' | sort >"$old_names"

while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    gh release download "$RELEASE_TAG" --pattern "$name" --dir "$backup_dir"
done <"$old_names"

publication_started=0
publication_complete=0

restore_previous_set()
{
    echo "Publication failed; restoring the previous verified RPM set" >&2
    mapfile -t current_names < <(
        gh release view "$RELEASE_TAG" --json assets \
            --jq '.assets[].name | select(endswith(".rpm"))' | sort
    )

    for name in "${current_names[@]}"; do
        if ! grep -Fxq "$name" "$old_names"; then
            gh release delete-asset "$RELEASE_TAG" "$name" --yes || true
        fi
    done

    backup_rpms=("$backup_dir"/*.rpm)
    if [[ ${#backup_rpms[@]} -gt 0 ]]; then
        gh release upload "$RELEASE_TAG" "${backup_rpms[@]}" --clobber
    fi
}

cleanup()
{
    exit_code=$?
    trap - EXIT
    if [[ $exit_code -ne 0 && $publication_started -eq 1 && $publication_complete -eq 0 ]]; then
        set +e
        restore_previous_set
        set -e
    fi
    rm -rf "$transaction_dir"
    exit "$exit_code"
}
trap cleanup EXIT

publication_started=1
gh release upload "$RELEASE_TAG" "${expected_sorted[@]/#/$RPM_DIR/}" --clobber

assets_json="$transaction_dir/assets.json"
gh release view "$RELEASE_TAG" --json assets >"$assets_json"

for name in "${expected_sorted[@]}"; do
    local_digest=$(sha256sum "$RPM_DIR/$name" | awk '{print $1}')
    remote_digest=$(jq -r --arg name "$name" \
        '[.assets[] | select(.name == $name) | .digest] |
         if length == 1 then .[0] else empty end' "$assets_json")
    [[ "$remote_digest" == "sha256:$local_digest" ]]
    echo "Verified release digest: $name $remote_digest"
done

# The complete new set is present and verified. Only now remove stale RPMs.
mapfile -t published_names < <(
    jq -r '.assets[].name | select(endswith(".rpm"))' "$assets_json" | sort
)
for name in "${published_names[@]}"; do
    if ! printf '%s\n' "${expected_sorted[@]}" | grep -Fxq "$name"; then
        echo "Prune stale release asset: $name"
        gh release delete-asset "$RELEASE_TAG" "$name" --yes
    fi
done

mapfile -t final_names < <(
    gh release view "$RELEASE_TAG" --json assets \
        --jq '.assets[].name | select(endswith(".rpm"))' | sort
)
diff -u <(printf '%s\n' "${expected_sorted[@]}") <(printf '%s\n' "${final_names[@]}")

gh release edit "$RELEASE_TAG" --prerelease \
    --title "Последняя CI-сборка (main)" \
    --notes "Проверенный атомарный комплект RPM для ОС Аврора 5.x из коммита ${GITHUB_SHA:-unknown} ($(date -u '+%Y-%m-%d %H:%M UTC')). Публикация выполнена только после успешной сборки и проверки armv7hl и aarch64; при ошибке предыдущий комплект восстанавливается. Для своей архитектуры сначала установите неизменённый официальный ru.rutoken.librtpkcs11ecp RPM, затем $APP_ID. 32-битный телефон — *.armv7hl.rpm, 64-битный — *.aarch64.rpm. Приложение подписано тестовым ключом OMP; нужен режим разработчика и разрешение недоверенного ПО. Лицензия Рутокен: https://www.rutoken.ru/download/license/License_Agreement_Rutoken.pdf"

publication_complete=1
echo "Published one verified four-RPM set to $RELEASE_TAG"

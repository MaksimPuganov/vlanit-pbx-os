#!/usr/bin/env bash
# scripts/sign-release.sh — GPG-подпись контрольных сумм релиза (идея #11).
#
# Подписывает dist/*.sha256 отсоединённой подписью (detached ascii-armored):
#   VLANit-PBX-X.Y.Z-amd64.iso.sha256 -> .sha256.asc
#
# Ключ релиза (ed25519, «VLANit PBX OS Release»):
#   - публичный: rootfs/etc-vlanit-release.pub (в репозитории, в образе ОС)
#   - приватный: CI — секрет RELEASE_GPG_PRIVATE_KEY (GitHub Secrets);
#     локально — GNUPGHOME=$HOME/.vlanit-release-gnupg (как у build-update-package.sh)
#
# Проверка подписи у получателя:
#   gpg --no-default-keyring --keyring rootfs/etc-vlanit-release.pub \
#       --verify VLANit-PBX-1.2.6-amd64.iso.sha256.asc
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# общий префикс: GNUPGHOME, импорт ключа из секрета, gpg_release_sign (ponytail #28)
# shellcheck source=scripts/gpg-release-common.sh
source scripts/gpg-release-common.sh

shopt -s nullglob
SUMS=(dist/*.iso.sha256)
[ "${#SUMS[@]}" -gt 0 ] || { echo "sign-release: dist/*.iso.sha256 не найдены" >&2; exit 1; }

for f in "${SUMS[@]}"; do
    gpg_release_sign "$f"
    echo "sign-release: подписан $f.asc"
done

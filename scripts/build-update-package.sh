#!/usr/bin/env bash
# scripts/build-update-package.sh — сборка подписанного пакета обновления.
#
# Использование:
#   bash scripts/build-update-package.sh <mikopbx-image.tar.zst> <outdir> <distro_min_version>
#
# Требует приватный ключ релиза (GNUPGHOME=~/.vlanit-release-gnupg).
set -Eeuo pipefail

IMG="${1:?укажите образ АТС (*.tar.zst)}"
OUTDIR="${2:?укажите каталог результата}"
MIN_VER="${3:-1.2.0}"
[ -f "$IMG" ] || { echo "образ не найден: $IMG" >&2; exit 1; }
IMG_NAME="$(basename "$IMG")"
NEW_VER="$(echo "$IMG_NAME" | sed -E 's/mikopbx-([0-9.]+(-[a-z0-9]+)?)-.*/\1/')"
IMG_SHA="$(sha256sum "$IMG" | awk '{print $1}')"

mkdir -p "$OUTDIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp "$IMG" "$STAGE/"
cat > "$STAGE/manifest.json" <<EOF
{
  "schema_version": 1,
  "distro_version": "$MIN_VER",
  "target_min_version": "$MIN_VER",
  "mikopbx_image": "$IMG_NAME",
  "mikopbx_image_sha256": "$IMG_SHA",
  "created_at": "$(date -Is)"
}
EOF

PKG="vlanit-update-${MIN_VER}+atsc${NEW_VER}-$(date +%Y%m%d).tar"
tar -C "$STAGE" -cf "$OUTDIR/$PKG" manifest.json "$IMG_NAME"
rm -f "$STAGE/$IMG_NAME" "$STAGE/manifest.json"

# общий префикс: GNUPGHOME, импорт ключа из секрета, gpg_release_sign (ponytail #28)
# shellcheck source=scripts/gpg-release-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/gpg-release-common.sh"
gpg_release_sign "$OUTDIR/$PKG"

echo "пакет: $OUTDIR/$PKG"
echo "подпись: $OUTDIR/$PKG.asc"
sha256sum "$OUTDIR/$PKG" | tee "$OUTDIR/$PKG.sha256"

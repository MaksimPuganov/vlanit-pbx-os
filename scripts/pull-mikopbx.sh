#!/usr/bin/env bash
# scripts/pull-mikopbx.sh — выгрузка официального образа MikoPBX в payload (на хосте).
# Использует docker только как средство скачивания/экспорта на этапе сборки.
# В целевой ОС Docker отсутствует — используется Podman.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD="$PROJECT_ROOT/build/payload"
IMAGE="mikopbx/mikopbx:2026.6.99-amd64"
DIGEST="sha256:6489e2a72ee6c670383ce7f61e21ad419880193ecad964d93e91596256c1c4b0"
TAR_NAME="mikopbx-2026.6.99-amd64.tar"

mkdir -p "$PAYLOAD"
cd "$PAYLOAD"

echo "Pull $IMAGE"
docker pull "$IMAGE"

# Проверка digest после pull (docker обновляет digest при pull)
actual="$(docker inspect --format '{{index .RepoDigests 0}}' "$IMAGE" | sed 's/.*@//')"
if [ "$actual" != "$DIGEST" ]; then
    echo "ОШИБКА: digest образа изменился: $actual (ожидался $DIGEST)" >&2
    echo "Обновите config/build.yaml и config/release-manifest.yaml после проверки." >&2
    exit 1
fi

echo "Экспорт образа -> $TAR_NAME"
docker save "$IMAGE" -o "$TAR_NAME"
zstd -f --rm -19 -T0 "$TAR_NAME" -o "$TAR_NAME.zst"
sha256sum "$TAR_NAME.zst" > "$TAR_NAME.zst.sha256"
rm -f mikopbx.tar.zst mikopbx.tar.zst.sha256
ln -sf "$TAR_NAME.zst" mikopbx.tar.zst
ln -sf "$TAR_NAME.zst.sha256" mikopbx.tar.zst.sha256
cat mikopbx.tar.zst.sha256
echo "Готово: $PAYLOAD/mikopbx.tar.zst"

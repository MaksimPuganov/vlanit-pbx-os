#!/usr/bin/env bash
# scripts/build.sh — оркестратор сборки VLANit PBX OS.
# Выполняется ВНУТРИ привилегированного build-контейнера (scripts/Dockerfile.build).
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$LOG_DIR"

log()  { printf '[build %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { printf '[build] ОШИБКА: %s\n' "$*" >&2; exit 1; }

# --- проверка зависимостей внутри контейнера ---
for t in mmdebstrap xorriso mksquashfs grub-mkimage mcopy zstd tar python3; do
    command -v "$t" >/dev/null || fail "в контейнере нет инструмента: $t"
done

[ -f "$BUILD_DIR/payload/mikopbx.tar.zst" ] || \
    fail "нет build/payload/mikopbx.tar.zst — выполните scripts/pull-mikopbx.sh на хосте"

# --- верификация payload по манифесту ---
log "проверка SHA256 payload"
( cd "$BUILD_DIR/payload" && sha256sum -c mikopbx.tar.zst.sha256 ) || \
    fail "контрольная сумма mikopbx.tar.zst не соответствует манифесту"

STEPS=(10-golden-rootfs 20-live-rootfs 30-initramfs 40-staging 50-iso)
for step in "${STEPS[@]}"; do
    log "=== шаг $step ==="
    bash "$PROJECT_ROOT/scripts/$step.sh" 2>&1 | tee "$LOG_DIR/$step.log" || \
        fail "шаг $step завершился с ошибкой (журнал: build/logs/$step.log)"
done

log "сборка завершена"
ls -la "$PROJECT_ROOT/dist/"

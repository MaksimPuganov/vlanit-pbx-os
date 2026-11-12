#!/usr/bin/env bash
# tools/fetch-tools.sh — загрузка инструментов сборочной машины (БЕЗ root).
#
# Что скачивается (Debian 13 trixie, amd64) и зачем:
#   mmdebstrap            — сборка минимальных rootfs (Golden/Live)
#   xorriso + libisoburn  — создание ISO
#   squashfs-tools        — squashfs Live-окружения
#   ovmf                  — OVMF (UEFI-прошивка) для QEMU-тестов
#
# Пакеты распаковываются в tools/root (локально, в git не входят).
# Требует: apt-get download (работает без root).
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
DEBS=debs
ROOT=root
mkdir -p "$DEBS" "$ROOT"

PKGS="mmdebstrap xorriso squashfs-tools libisoburn1t64 libisofs6t64 libburn4t64 libjte2 ovmf"

echo "== скачивание: $PKGS"
( cd "$DEBS" && apt-get download $PKGS )

echo "== распаковка в $ROOT"
for d in "$DEBS"/*.deb; do
    dpkg -x "$d" "$ROOT"
done

echo "== готово. Проверьте:"
LD_LIBRARY_PATH="$PWD/$ROOT/usr/lib/x86_64-linux-gnu" \
    "$ROOT/usr/bin/xorriso" --version 2>/dev/null | head -1 || true
ls "$ROOT/usr/share/OVMF/" | head -3

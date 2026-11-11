#!/usr/bin/env bash
# scripts/30-initramfs.sh — ядро + initramfs для Live-загрузки.
# Выполняется внутри build-контейнера от root.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS="$BUILD_DIR/rootfs/live"
STAGING="$BUILD_DIR/iso-staging"
mkdir -p "$STAGING/live"

log() { printf '[initramfs] %s\n' "$*"; }

KERNEL_VERSION="$(basename "$(ls -d "$ROOTFS"/lib/modules/* | head -1)")"
log "ядро: $KERNEL_VERSION"

# синхронизация актуальных live-файлов (hook, init) в rootfs
install -D -m 0755 "$PROJECT_ROOT/live/vlanit-init" "$ROOTFS/opt/vlanit/vlanit-init"
install -D -m 0755 "$PROJECT_ROOT/live/initramfs-hook-vlanit-live" \
    "$ROOTFS/etc/initramfs-tools/hooks/vlanit-live"
install -D -m 0755 "$PROJECT_ROOT/installer/vlanit-installer" \
    "$ROOTFS/opt/vlanit/installer/vlanit-installer"
for lib in common hardware disk network deploy; do
    install -D -m 0644 "$PROJECT_ROOT/installer/lib/$lib.sh" \
        "$ROOTFS/opt/vlanit/installer/lib/$lib.sh"
done

log "сборка initramfs (chroot live rootfs)"
chroot "$ROOTFS" sh -c "
    export DEBIAN_FRONTEND=noninteractive
    mkinitramfs -o /boot/initrd-vlanit '$KERNEL_VERSION'
"

VMLINUZ="$ROOTFS/boot/vmlinuz-$KERNEL_VERSION"
INITRD="$ROOTFS/boot/initrd-vlanit"
[ -f "$VMLINUZ" ] || { echo "нет $VMLINUZ"; exit 1; }
[ -f "$INITRD" ] || { echo "нет $INITRD"; exit 1; }

cp "$VMLINUZ" "$STAGING/live/vmlinuz"
cp "$INITRD"  "$STAGING/live/initrd"
log "готово: live/vmlinuz ($(du -h "$STAGING/live/vmlinuz" | cut -f1)), live/initrd ($(du -h "$STAGING/live/initrd" | cut -f1))"

#!/usr/bin/env bash
# scripts/50-iso.sh — GRUB UEFI + сборка ISO через xorriso.
# Выполняется внутри build-контейнера от root.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
STAGING="$BUILD_DIR/iso-staging"
GRUB_DIR="$BUILD_DIR/grub"
DIST_DIR="$PROJECT_ROOT/dist"
ISO_NAME="VLANit-PBX-1.0-amd64.iso"
mkdir -p "$STAGING/boot/grub" "$GRUB_DIR" "$DIST_DIR"

log() { printf '[iso] %s\n' "$*"; }

# --- grub.cfg на ISO ---
cat > "$STAGING/boot/grub/grub.cfg" <<'EOF'
set timeout=5
set default=0

insmod part_gpt
insmod part_msdos
insmod iso9660

search --no-floppy --set=root --label VLANIT_PBX_OS

menuentry "Установить VLANit PBX OS 1.0 (UEFI)" --class debian --class gnu-linux {
    linux /live/vmlinuz ro quiet loglevel=3 console=tty0 console=ttyS0,115200
    initrd /live/initrd
}

menuentry "Установить VLANit PBX OS 1.0 (режим отладки)" {
    linux /live/vmlinuz ro loglevel=7 VLANIT_DEBUG=1 console=tty0 console=ttyS0,115200
    initrd /live/initrd
}
EOF

# --- GRUB EFI-образ ---
log "grub-mkimage (x86_64-efi)"
GRUB_MODS_DIR=""
for d in /usr/lib/grub /usr/lib/grub2; do
    [ -d "$d/x86_64-efi" ] && GRUB_MODS_DIR="$d/x86_64-efi" && break
done
[ -n "$GRUB_MODS_DIR" ] || { echo "модули grub x86_64-efi не найдены"; exit 1; }

grub-mkimage -O x86_64-efi \
    -p /boot/grub \
    -o "$GRUB_DIR/bootx64.efi" \
    part_gpt part_msdos iso9660 normal linux echo test all_video

# --- ESP-образ (FAT16) с BOOTX64.EFI ---
log "EFI System Partition image (efi.img)"
rm -f "$GRUB_DIR/efi.img"
mformat -i "$GRUB_DIR/efi.img" -F 16 -C -v VLANIT_EFI :: 2>/dev/null || \
    mformat -i "$GRUB_DIR/efi.img" -F 16 -C ::
mmd -i "$GRUB_DIR/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$GRUB_DIR/efi.img" "$GRUB_DIR/bootx64.efi" ::/EFI/BOOT/BOOTX64.EFI
cp "$STAGING/boot/grub/grub.cfg" "$GRUB_DIR/grub.cfg"
mmd -i "$GRUB_DIR/efi.img" ::/boot ::/boot/grub
mcopy -i "$GRUB_DIR/efi.img" "$GRUB_DIR/grub.cfg" ::/boot/grub/grub.cfg
cp "$GRUB_DIR/efi.img" "$STAGING/boot/grub/efi.img"

# --- ISO ---
log "xorriso"
ISO_PATH="$DIST_DIR/$ISO_NAME"
rm -f "$ISO_PATH"
xorriso -as mkisofs \
    -V VLANIT_PBX_OS \
    -A "VLANit PBX OS 1.0" \
    -quiet \
    -o "$ISO_PATH" \
    -e boot/grub/efi.img -no-emul-boot \
    -append_partition 2 0xef "$GRUB_DIR/efi.img" \
    -partition_cyl_align all \
    "$STAGING"

log "SHA256"
( cd "$DIST_DIR" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )
# зафиксировать SHA в staging-манифесте (копия уже внутри ISO)
ISO_SHA="$(awk '{print $1}' "$DIST_DIR/$ISO_NAME.sha256")"
sed -i "s/  iso_sha256: null/  iso_sha256: \"$ISO_SHA\"/" "$STAGING/payload/release-manifest.yaml"

ls -la "$DIST_DIR"
log "готово: $ISO_PATH"

#!/usr/bin/env bash
# scripts/20-live-rootfs.sh — Live-среда установщика (Debian 13 + VLANit Installer).
# Выполняется внутри build-контейнера от root.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS="$BUILD_DIR/rootfs/live"
STAGING="$BUILD_DIR/iso-staging"
mkdir -p "$ROOTFS" "$STAGING/live"
rm -rf "${ROOTFS:?}"/* "$STAGING/live/rootfs.squashfs"

log() { printf '[live] %s\n' "$*"; }

LIVE_PACKAGES="
systemd-sysv dbus udev
linux-image-amd64 initramfs-tools busybox-static
dialog locales ncurses-term
gdisk parted
btrfs-progs dosfstools e2fsprogs
openssh-server sudo
curl ca-certificates jq zstd tar
python3 python3-yaml
kbd tzdata
iproute2 iputils-ping ethtool pciutils usbutils nvme-cli dmidecode smartmontools
iptables nftables
grub-common
"

log "mmdebstrap: live rootfs"
mmdebstrap \
    --mode=root \
    --variant=apt \
    --architectures=amd64 \
    --aptopt='APT::Install-Recommends "false"' \
    --components="main contrib non-free-firmware" \
    --include="$LIVE_PACKAGES" \
    trixie "$ROOTFS" http://deb.debian.org/debian

log "локали (en_US.UTF-8, ru_RU.UTF-8)"
chroot "$ROOTFS" sh -c '
    sed -i -e "s/^# *en_US.UTF-8/en_US.UTF-8/" -e "s/^# *ru_RU.UTF-8/ru_RU.UTF-8/" /etc/locale.gen
    locale-gen
'
cat > "$ROOTFS/etc/default/locale" <<'EOF'
LANG=ru_RU.UTF-8
LANGUAGE=ru_RU:en_US
EOF

log "установка VLANit Installer и provisioning"
install -d -m 0755 "$ROOTFS/opt/vlanit"
cp -a "$PROJECT_ROOT/installer/." "$ROOTFS/opt/vlanit/installer/"
cp -a "$PROJECT_ROOT/provisioning/." "$ROOTFS/opt/vlanit/provisioning/"
install -D -m 0755 "$PROJECT_ROOT/live/vlanit-init" "$ROOTFS/opt/vlanit/vlanit-init"
install -D -m 0755 "$PROJECT_ROOT/live/initramfs-hook-vlanit-live" \
    "$ROOTFS/etc/initramfs-tools/hooks/vlanit-live"
install -D -m 0644 "$PROJECT_ROOT/live/vlanit-installer.service" \
    "$ROOTFS/etc/systemd/system/vlanit-installer.service"
install -D -m 0644 "$PROJECT_ROOT/live/99-vlanit-live.preset" \
    "$ROOTFS/etc/systemd/system-preset/99-vlanit-live.preset"
echo "vlanit-pbx-live" > "$ROOTFS/etc/hostname"
# ssh в live-среде не нужен (ключи удалены, сервис падает)
chroot "$ROOTFS" systemctl mask ssh.service 2>/dev/null || true
# preset-файл попадает в rootfs уже после установки пакетов — включаем явно
chroot "$ROOTFS" systemctl enable vlanit-installer.service 2>/dev/null || true

# очистка
rm -f "$ROOTFS/etc/machine-id" "$ROOTFS/var/lib/dbus/machine-id"
touch "$ROOTFS/etc/machine-id"
rm -f "$ROOTFS/etc/ssh/ssh_host_"*
find "$ROOTFS/var/log" -type f -delete 2>/dev/null || true
rm -rf "$ROOTFS/var/cache/apt/"* "$ROOTFS/var/lib/apt/lists/"*

log "squashfs -> live/rootfs.squashfs"
mksquashfs "$ROOTFS" "$STAGING/live/rootfs.squashfs" \
    -comp zstd -Xcompression-level 15 -noappend -quiet
log "готово: $(du -h "$STAGING/live/rootfs.squashfs" | cut -f1)"

# Развёртывание системы на целевой диск: subvolumes, golden image, fstab,
# загрузчик, импорт MikoPBX, firstboot-конфигурация.
# Все деструктивные операции — только после confirm_install() в основном скрипте.

SYS_MNT="/mnt/vlanit-target"

create_filesystems() {
    local disk="$1"
    local efi sys data
    efi="$(partition_device "$disk" 1)"
    sys="$(partition_device "$disk" 2)"
    data="$(partition_device "$disk" 3)"

    log "mkfs.vfat $efi (EFI)"
    mkfs.vfat -F 32 -n VLANIT_EFI "$efi"
    log "mkfs.btrfs $sys (System)"
    mkfs.btrfs -f -L vlanit-system "$sys"
    log "mkfs.btrfs $data (Data)"
    mkfs.btrfs -f -L vlanit-data "$data"

    log "создание subvolumes"
    mount "$sys" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@var_log
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    mount "$data" /mnt
    btrfs subvolume create /mnt/mikopbx-cf
    btrfs subvolume create /mnt/mikopbx-storage
    btrfs subvolume create /mnt/.snapshots
    umount /mnt
}

deploy_golden() {
    local disk="$1"
    local efi sys data
    efi="$(partition_device "$disk" 1)"
    sys="$(partition_device "$disk" 2)"
    data="$(partition_device "$disk" 3)"

    mkdir -p "$SYS_MNT"
    mount -o subvol=@,compress=zstd,noatime "$sys" "$SYS_MNT"
    mkdir -p "$SYS_MNT/boot/efi" "$SYS_MNT/var/log" "$SYS_MNT/.snapshots" \
             "$SYS_MNT/var/spool/mikopbx/cf" "$SYS_MNT/var/spool/mikopbx/storage"

    log "развёртывание Golden Image (tar.zst)"
    tar -C "$SYS_MNT" --zstd -xpf "$PAYLOAD/golden.tar.zst"

    local sys_uuid data_uuid efi_uuid
    sys_uuid="$(blkid -s UUID -o value "$sys")"
    data_uuid="$(blkid -s UUID -o value "$data")"
    efi_uuid="$(blkid -s UUID -o value "$efi")"
    [ -n "$sys_uuid" ] && [ -n "$data_uuid" ] || die "не удалось получить UUID разделов"

    log "fstab (UUID)"
    cat > "$SYS_MNT/etc/fstab" <<EOF
UUID=$efi_uuid /boot/efi vfat umask=0077 0 2
UUID=$sys_uuid / btrfs subvol=@,compress=zstd,noatime 0 1
UUID=$sys_uuid /var/log btrfs subvol=@var_log,noatime 0 2
UUID=$sys_uuid /.snapshots btrfs subvol=@snapshots,noatime 0 2
UUID=$data_uuid /var/spool/mikopbx/cf btrfs subvol=mikopbx-cf,compress=zstd,noatime 0 2
UUID=$data_uuid /var/spool/mikopbx/storage btrfs subvol=mikopbx-storage,compress=zstd,noatime 0 2
EOF

    # EFI-раздел монтируется для grub-install
    mount "$efi" "$SYS_MNT/boot/efi"
}

# Системная конфигурация целевой системы (без chroot там, где возможно)
configure_target_system() {
    local hostname="$1" admin_user="$2" admin_pass="$3" ssh_enabled="$4" tz="$5"
    local kernel_args="${6:-}"

    echo "$hostname" > "$SYS_MNT/etc/hostname"
    echo "$tz" > "$SYS_MNT/etc/timezone"
    cat > "$SYS_MNT/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$hostname
::1	localhost ip6-localhost ip6-loopback
EOF
    ln -sf "/usr/share/zoneinfo/$tz" "$SYS_MNT/etc/localtime"

    # GRUB defaults: uuid корня определяется через fstab/grub-probe
    cat > "$SYS_MNT/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="VLANit PBX OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=tty0 console=ttyS0,115200"
GRUB_CMDLINE_LINUX="$kernel_args"
GRUB_DISABLE_OS_PROBER=true
GRUB_COLOR_NORMAL="white/black"
GRUB_COLOR_HIGHLIGHT="black/yellow"
EOF

    # локальный администратор (chroot)
    local encrypted
    encrypted="$(openssl passwd -6 "$admin_pass")"
    chroot "$SYS_MNT" /bin/sh -c "
        useradd -m -s /bin/bash '$admin_user' 2>/dev/null || true
        usermod -aG sudo '$admin_user'
        echo '$admin_user:$encrypted' | chpasswd -e
    " || die "не удалось создать администратора"

    if [ "$ssh_enabled" = "yes" ]; then
        chroot "$SYS_MNT" systemctl enable ssh.service || true
    else
        chroot "$SYS_MNT" systemctl disable ssh.service || true
    fi
}

configure_target_mikopbx() {
    local pbx_name="$1" admin_login="$2" admin_pass="$3"
    local quadlet="$SYS_MNT/etc/containers/systemd/mikopbx.container"
    [ -f "$quadlet" ] || die "quadlet-файл отсутствует в Golden Image"
    # блок VLANIT-ENV (идемпотентно, маркеры совместимы с vlanit-provision).
    # ВАЖНО: блок должен быть в секции [Container] — Quadlet передаёт
    # Environment= в контейнер (--env) только оттуда; из [Service] переменная
    # остаётся окружением systemd-юнита, контейнер её не видит (дефект 1.2.4:
    # пароль веб-админа «из мастера» не доходил до MikoPBX).
    if ! grep -q "# VLANIT-ENV-BEGIN" "$quadlet"; then
        sed -i 's/^\[Container\]$/[Container]\n# VLANIT-ENV-BEGIN\n# VLANIT-ENV-END/' "$quadlet"
    fi
    python3 - "$quadlet" "$pbx_name" "$admin_login" "$admin_pass" <<'PYEOF'
import sys
path, name, login, passwd = sys.argv[1:5]

def q(v: str) -> str:
    # systemd/quadlet-формат: значения с пробелами/спецсимволами — в кавычках
    if any(c.isspace() for c in v) or '"' in v:
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return v

text = open(path).read()
block = (
    "# VLANIT-ENV-BEGIN\n"
    f"Environment=PBX_NAME={q(name)}\n"
    f"Environment=WEB_ADMIN_LOGIN={q(login)}\n"
    f"Environment=WEB_ADMIN_PASSWORD={q(passwd)}\n"
    "# VLANIT-ENV-END"
)
import re
text = re.sub(r"# VLANIT-ENV-BEGIN.*?# VLANIT-ENV-END", block, text, flags=re.S)
open(path, "w").write(text)
PYEOF
    chmod 600 "$quadlet"   # пароль веб-админа — только root (cso #1)
}

# chroot-операции: initramfs + загрузчик
install_bootloader() {
    log "подготовка initramfs и GRUB (chroot)"
    mount_chroot_fs
    chroot "$SYS_MNT" /bin/sh -c "
        export DEBIAN_FRONTEND=noninteractive
        update-initramfs -u -k all
        grub-install --target=x86_64-efi --efi-directory=/boot/efi \
            --bootloader-id=VLANIT --recheck
        # fallback-загрузка (слабые firmware без надёжного NVRAM)
        mkdir -p /boot/efi/EFI/BOOT
        cp /boot/efi/EFI/VLANIT/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.efi
        grub-mkconfig -o /boot/grub/grub.cfg
    " || die "сбой установки загрузчика"
}

# chroot-окружение: bind /proc /sys /dev /run (нужны podman и grub)
mount_chroot_fs() {
    for d in proc sys dev dev/pts run; do
        mountpoint -q "$SYS_MNT/$d" 2>/dev/null && continue
        mount --rbind "/$d" "$SYS_MNT/$d" 2>/dev/null || true
    done
}

# Импорт образа MikoPBX в rootful Podman целевой системы (офлайн)
import_mikopbx_image() {
    local target_image="localhost/vlanit/mikopbx:2026.6.99-amd64"
    mkdir -p "$SYS_MNT/var/lib/vlanit/payload"
    log "копирование payload MikoPBX в целевую систему"
    cp "$PAYLOAD/mikopbx-2026.6.99-amd64.tar.zst" "$SYS_MNT/var/lib/vlanit/payload/"

    log "импорт образа MikoPBX в Podman (chroot)"
    mount_chroot_fs
    chroot "$SYS_MNT" /bin/sh -c "
        if ! podman image exists '$target_image'; then
            zstd -dc /var/lib/vlanit/payload/mikopbx-2026.6.99-amd64.tar.zst | podman load
            src_tag=\$(podman images --format '{{.Repository}}:{{.Tag}}' | grep mikopbx | head -1)
            [ -n \"\$src_tag\" ] && podman tag \"\$src_tag\" '$target_image'
        fi
        podman image exists '$target_image'
    " || die "импорт образа MikoPBX не выполнен"
}

unmount_target() {
    umount -R "$SYS_MNT" 2>/dev/null || umount -l "$SYS_MNT" 2>/dev/null || true
}

# Диагностика после установки (работает и в autoinstall)
post_install_report() {
    local disk="$1"
    log "post-install report: разметка $disk"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID "$disk" 2>/dev/null | while read -r line; do log "  $line"; done
    log "fstab целевой системы:"
    sed 's/^/  /' "$SYS_MNT/etc/fstab" 2>/dev/null | while read -r line; do log "$line"; done
    log "post-install report: конец"
}

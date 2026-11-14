# Операции с дисками: обнаружение (с защитными проверками) и разметка.
# Никаких фиксированных /dev/sda — всё определяется динамически.

# Устройство, с которого загружена Live-среда (установочный USB/ISO)
live_source_device() {
    local src
    src="$(findmnt -n -o SOURCE "$ISO_MOUNT" 2>/dev/null || true)"
    # /dev/sr0 напрямую; для /dev/mapper/* берём родителя не требуется
    echo "$src"
}

# Список кандидатов: внутренние непереносные диски, не занятые системой
list_candidate_disks() {
    local src
    src="$(live_source_device)"
    lsblk -b -d -n -o NAME,TYPE,RM,RO,SIZE,MODEL,TRAN 2>/dev/null | \
    awk -v src="$src" '
        $2 == "disk" && $3 == "0" && $4 == "0" {
            dev = "/dev/" $1
            if (dev == src || src ~ ("^" dev "[0-9p]")) next
            printf "%s|%s|%s|%s\n", dev, $5, $7, $6
        }'
}

# Защита: диск не должен иметь смонтированных разделов
disk_is_clean_target() {
    local disk="$1"
    findmnt -S "$disk" >/dev/null 2>&1 && return 1
    lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -q '[^[:space:]]' && return 1
    return 0
}

disk_size_bytes() {
    blockdev --getsize64 "$1" 2>/dev/null || lsblk -b -n -o SIZE "$1"
}

# Разметка GPT: EFI 1GiB, System 40GiB, Data — остаток.
# Вызывается ТОЛЬКО после явного подтверждения пользователя.
partition_disk() {
    local disk="$1"
    local sys_mib data_mib
    sys_mib="$(yaml_get "$PAYLOAD/build.yaml" installer.system_size_mib 40960)"

    log "разметка $disk (GPT): EFI 1024MiB, System ${sys_mib}MiB, Data — остаток"
    wipefs -a "$disk"
    sgdisk --zap-all "$disk"
    sgdisk -n1:1MiB:+1024MiB -t1:EF00 -c1:"VLANIT_EFI" "$disk"
    sgdisk -n2:0:+${sys_mib}MiB -t2:8300 -c2:"VLANIT_SYSTEM" "$disk"
    sgdisk -n3:0:0       -t3:8300 -c3:"VLANIT_DATA" "$disk"
    sgdisk -p "$disk"
    partprobe "$disk" || true
    sleep 1
    udevadm settle 2>/dev/null || true
}

# Определение имён разделов: nvme0n1p1 vs sda1
partition_device() {
    local disk="$1" num="$2"
    case "$disk" in
        *nvme*|*mmcblk*) echo "${disk}p${num}" ;;
        *) echo "${disk}${num}" ;;
    esac
}

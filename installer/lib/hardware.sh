# Сбор сведений об оборудовании (Экран 1)
collect_hardware_info() {
    HW_CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
    [ -n "$HW_CPU_MODEL" ] || HW_CPU_MODEL="$(grep -m1 'Model' /proc/cpuinfo | cut -d: -f2- | xargs)"
    HW_CPU_CORES="$(nproc)"
    HW_RAM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    HW_RAM_MB=$((HW_RAM_KB / 1024))
    HW_BOOT_MODE="UEFI"
    [ -d /sys/firmware/efi ] || HW_BOOT_MODE="Legacy/CSM"
    HW_INTERFACES="$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}')"
}

hardware_warnings() {
    local warnings=""
    local min_ram
    min_ram="$(yaml_get "$PAYLOAD/build.yaml" installer.min_ram_mb 2048)"
    if [ "$HW_RAM_MB" -lt "$min_ram" ]; then
        warnings="${warnings}ОЗУ ${HW_RAM_MB} МБ меньше рекомендуемых ${min_ram} МБ (MikoPBX может работать нестабильно)\n"
    fi
    [ "$HW_BOOT_MODE" = "UEFI" ] || warnings="${warnings}Загрузка не в UEFI-режиме: установка невозможна (требуется UEFI)\n"
    echo -e "${warnings:-}"
}

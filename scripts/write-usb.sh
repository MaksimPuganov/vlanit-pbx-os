#!/usr/bin/env bash
# scripts/write-usb.sh — запись ISO на USB-накопитель.
#
# Использование:
#   bash scripts/write-usb.sh <iso> <диск, например /dev/sdX>
#
# СКРИПТ ТРЕБУЕТ ПОДТВЕРЖДЕНИЯ И root. Все данные на целевом диске
# будут безвозвратно удалены.
set -Eeuo pipefail

ISO="${1:-}"
DISK="${2:-}"

[ -n "$ISO" ] && [ -n "$DISK" ] || { echo "Использование: $0 <iso> <диск>"; exit 2; }
[ -f "$ISO" ] || { echo "ISO не найден: $ISO"; exit 1; }
[[ "$DISK" =~ ^/dev/(sd[a-z]|nvme[0-9]n[0-9]|mmcblk[0-9])$ ]] || {
    echo "Диск должен выглядеть как /dev/sdX, /dev/nvmeXnY или /dev/mmcblkN (получено: $DISK)"; exit 1;
}
[ -b "$DISK" ] || { echo "Не блочное устройство: $DISK"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "Требуется root (sudo $0 $ISO $DISK)"; exit 1; }

lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT "$DISK"
if lsblk -n -o MOUNTPOINT "$DISK" | grep -q '[^[:space:]]'; then
    echo "ОШИБКА: на диске есть смонтированные разделы. Размонтируйте их."; exit 1
fi

echo ""
echo "ВНИМАНИЕ: ВСЕ ДАННЫЕ НА $DISK БУДУТ БЕЗВОЗВРАТНО УДАЛЕНЫ."
read -r -p "Введите ДА для продолжения: " confirm
[ "$confirm" = "ДА" ] || { echo "Отменено."; exit 1; }

echo "Запись $ISO на $DISK ..."
dd if="$ISO" of="$DISK" bs=4M status=progress oflag=sync
sync
echo "Готово. Можно извлечь носитель и загрузиться с него (UEFI)."

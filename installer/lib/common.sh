# Общие функции VLANit Installer (источникится из vlanit-installer)
: "${DIALOG_OK:=0}" "${DIALOG_CANCEL:=1}" "${DIALOG_ESC:=255}"

ISO_MOUNT="/media/vlanit"
PAYLOAD="$ISO_MOUNT/payload"
LOG_FILE="/var/log/vlanit-install.log"

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo "$msg"
    # дублирование на serial-консоль для диагностики и тестов
    [ -w /dev/ttyS0 ] && echo "$msg" > /dev/ttyS0 2>/dev/null || true
}

die() {
    log "ОШИБКА: $*"
    if [ -n "${AUTOMODE:-}" ]; then
        echo "VLANIT_INSTALL_FAILED: $*" > /dev/console 2>/dev/null || true
        exit 1
    fi
    dialog --title "Ошибка установки" --msgbox "$*\n\nЖурнал: $LOG_FILE" 12 70 || true
    exit 1
}

# чтение простого значения из YAML через python3+yaml
yaml_get() {
    # yaml_get <file> <dotted.path> [default]
    python3 - "$1" "$2" "${3:-}" <<'PYEOF'
import sys, yaml
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = yaml.safe_load(open(path))
except Exception as e:
    print(default); sys.exit(0)
cur = data
for part in key.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print(default); sys.exit(0)
print("" if cur is None else cur)
PYEOF
}

# список/словарь целиком в JSON (для разбора ответов autoinstall)
yaml_to_json() {
    python3 - "$1" <<'PYEOF'
import sys, json, yaml
try:
    print(json.dumps(yaml.safe_load(open(sys.argv[1])) or {}))
except Exception:
    print("{}")
PYEOF
}

human_gb() {
    awk -v bytes="$1" 'BEGIN { printf "%.1f", bytes/1024/1024/1024 }'
}

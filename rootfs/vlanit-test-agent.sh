#!/usr/bin/env bash
# vlanit-test-agent — тестовый агент первой загрузки.
# Активируется ТОЛЬКО при kernel cmdline VLANIT_TEST=1 (сценарии QEMU).
# Публикует результаты проверок на последовательный порт для test-qemu.sh.
set -u

out() { echo "VLANIT_TEST: $*" > /dev/ttyS0 2>/dev/null || true; echo "VLANIT_TEST: $*"; }
pass=0; fail=0
AGENT_LOG=/var/log/vlanit-test-agent.log
: > "$AGENT_LOG"

check() {
    local name="$1"; shift
    if "$@" >>"$AGENT_LOG" 2>&1; then
        out "PASS $name"; pass=$((pass+1))
    else
        out "FAIL $name (детали: $AGENT_LOG)"; fail=$((fail+1))
    fi
}

out "agent start"

# --- Т3: система ---
check "hostname" sh -c "hostname | grep -q vlanit"
check "podman" podman --version
check "networkd-active" systemctl is-active --quiet systemd-networkd
check "fstab-uuid" sh -c "grep -q 'UUID=.*btrfs' /etc/fstab"

# --- T6: Btrfs ---
check "btrfs-root" sh -c "findmnt -n / | grep -q btrfs"
check "btrfs-subvol-mikopbx-cf" sh -c "findmnt -n /var/spool/mikopbx/cf | grep -q btrfs"
check "btrfs-snapshot-create" /opt/vlanit/vlanit-snapshot create testagent
check "btrfs-snapshot-list" sh -c "/opt/vlanit/vlanit-snapshot list | grep -q testagent"

# --- Т4: MikoPBX ---
check "quadlet-service" systemctl is-enabled --quiet mikopbx.service
systemctl start mikopbx.service 2>/dev/null || true

# ожидание готовности приложения (до 6 минут)
ready=0
for i in $(seq 1 72); do
    if podman logs mikopbx 2>/dev/null | grep -q "All services are fully loaded welcome"; then
        ready=1; break
    fi
    sleep 5
done
[ "$ready" -eq 1 ] && { out "PASS mikopbx-ready-banner"; pass=$((pass+1)); } \
                   || { out "FAIL mikopbx-ready-banner"; fail=$((fail+1)); }

check "mikopbx-service-active" systemctl is-active --quiet mikopbx.service

# веб-интерфейс (HTTPS, self-signed)
web=0
for i in $(seq 1 24); do
    if curl -sk --max-time 5 https://127.0.0.1/ -o /dev/null -w '%{http_code}' | grep -qE '200|301|302'; then
        web=1; break
    fi
    sleep 5
done
[ "$web" -eq 1 ] && { out "PASS mikopbx-webui"; pass=$((pass+1)); } \
                 || { out "FAIL mikopbx-webui"; fail=$((fail+1)); }

# REST API login с localhost (v3, localhost bypass)
if curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
        -H 'Content-Type: application/json' \
        -d '{"login":"admin","password":"admin12345"}' 2>/dev/null | \
        grep -qE 'accessToken|result'; then
    out "PASS mikopbx-api-login"; pass=$((pass+1))
else
    out "FAIL mikopbx-api-login"; fail=$((fail+1))
fi

# persistence конфигурации MikoPBX (env provisioning применён в БД)
check "mikopbx-cf-nonempty" sh -c "test -n \"\$(ls -A /var/spool/mikopbx/cf 2>/dev/null)\""

# --- WireGuard (если включён установщиком) ---
if systemctl is-enabled --quiet wg-quick@wg0.service 2>/dev/null; then
    check "wireguard-service-enabled" systemctl is-enabled --quiet wg-quick@wg0.service
    systemctl start wg-quick@wg0.service 2>/dev/null || true
    check "wireguard-interface-up" sh -c "wg show wg0 | grep -q interface"
    check "wireguard-address" sh -c "ip -4 -o addr show dev wg0 | grep -q '10\.66\.66\.'"
fi

# --- перезагрузка и проверка сохранения (Т4: автозапуск после reboot) ---
if [ "$fail" -eq 0 ] && [ ! -f /var/spool/mikopbx/storage/.vlanit-reboot-marker ]; then
    date -Is > /var/spool/mikopbx/storage/.vlanit-reboot-marker
    sync
    out "PHASE1_DONE rebooting (проверка сохранения после перезагрузки)"
    sleep 3
    reboot -f
    exit 0
fi
if [ -f /var/spool/mikopbx/storage/.vlanit-reboot-marker ]; then
    check "reboot-data-persisted" sh -c "test -s /var/spool/mikopbx/storage/.vlanit-reboot-marker"
    check "reboot-mikopbx-active" systemctl is-active --quiet mikopbx.service
    out "REBOOT_TEST_PASS"
fi

if [ "$fail" -eq 0 ]; then
    out "RESULT PASS ($pass checks)"
    out "VLANIT_TEST_PASS"
else
    out "AGENT_LOG (последние строки):"
    tail -20 "$AGENT_LOG" | while read -r line; do out "  $line"; done
    out "RESULT FAIL ($fail из $((pass+fail)))"
    out "VLANIT_TEST_FAIL"
fi

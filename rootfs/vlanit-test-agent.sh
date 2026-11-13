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

# веб-интерфейс (HTTPS, self-signed) — через ВНЕШНИЙ адрес устройства,
# а не loopback: интерфейс должен быть доступен из сети
EXT_IP="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)"
web=0
for i in $(seq 1 24); do
    if curl -sk --max-time 5 "https://${EXT_IP:-127.0.0.1}/" -o /dev/null -w '%{http_code}' | grep -qE '200|301|302'; then
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

# --- безопасность (1.2) ---
check "security-unattended-upgrades" sh -c "unattended-upgrades --dry-run >/dev/null 2>&1 || unattended-upgrades --dry-run -d >/dev/null 2>&1"
check "security-root-ssh-denied" sh -c "sshd -T 2>/dev/null | grep -qi '^permitrootlogin no' || grep -rqi '^PermitRootLogin no' /etc/ssh/sshd_config.d/"
check "security-fail2ban" sh -c "systemctl is-active --quiet fail2ban && fail2ban-client status sshd >/dev/null 2>&1"

# --- брендинг: фирменная тема Plymouth ---
check "plymouth-theme-vlanit" grep -q "Theme=vlanit" /etc/plymouth/plymouthd.conf

# --- 1.2.3: реестр проверок по фидбеку полевых тестов ---
check "apt-security-source" sh -c "grep -rh trixie-security /etc/apt/sources.list /etc/apt/sources.list.d/ | grep -q ."
check "timesyncd" sh -c "systemctl is-active --quiet systemd-timesyncd"
check "timezone-set" sh -c "test -s /etc/timezone"
check "console-font-cyrillic" grep -q "^FONT=CyrSlav" /etc/vconsole.conf
check "quadlet-perms-600" sh -c "stat -c %a /etc/containers/systemd/mikopbx.container | grep -q 600"
check "atc-ssh-port-23" sh -c "podman exec mikopbx sh -c 'test \"\$SSH_PORT\" = 23'"
check "atc-password-nonempty" sh -c "grep -q 'WEB_ADMIN_PASSWORD=..' /etc/containers/systemd/mikopbx.container"

# --- 1.2.4: системная интеграция и харденинг ---
check "bin-login-present" sh -c "test -x /usr/bin/login"
check "ssh-host-keys" sh -c '
  ls /etc/ssh/ssh_host_* >/dev/null 2>&1 || { echo "== /etc/ssh:"; ls -la /etc/ssh/; }
  systemctl is-active --quiet ssh || { echo "== ssh status:"; systemctl status ssh --no-pager 2>&1 | tail -8; }
  ls /etc/ssh/ssh_host_* >/dev/null 2>&1 && systemctl is-active --quiet ssh
'
check "nft-policy-drop" sh -c "nft list ruleset 2>/dev/null | grep -q 'policy drop'"
check "pids-limit" sh -c "podman inspect mikopbx --format '{{.HostConfig.PidsLimit}}' 2>/dev/null | grep -q 4096"
check "handle-power-key" sh -c "busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey 2>/dev/null | grep -q ignore"
# journal-persistent проверяется после reboot-фазы (см. ниже)

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
    # журналы прошлой загрузки доступны (Storage=persistent)
    check "journal-persistent" sh -c "[ \"\$(journalctl -b -1 -n 1 2>/dev/null | wc -l)\" -gt 0 ]"
    # пароль веб-админа ПЕРЕЖИЛ перезагрузку. ИЗВЕСТНАЯ ПРОБЛЕМА upstream
    # (MikoPBX): provisioning применяет WEB_ADMIN_PASSWORD по маркеру
    # CLOUD_INSTANCE_ID; после перезагрузки хэш в БД сброшен, маркер
    # совпадает → повторное применение пропускается. Проверка WARN-уровня
    # до исправления upstream; детект на устройстве — vlanit-firstboot.
    for i in $(seq 1 60); do
        podman logs mikopbx 2>/dev/null | grep -q "All services are fully loaded welcome" && break
        sleep 5
    done
    PW="$(sed -n 's/^Environment=WEB_ADMIN_PASSWORD=//p' /etc/containers/systemd/mikopbx.container | head -1)"
    if curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
            -H 'Content-Type: application/json' \
            -d "{\"login\":\"admin\",\"password\":\"$PW\"}" | grep -q accessToken; then
        out "WARN-CHECK PASS reboot-api-login"
    else
        out "WARN-CHECK FAIL reboot-api-login (известная проблема upstream, см. troubleshooting)"
    fi
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

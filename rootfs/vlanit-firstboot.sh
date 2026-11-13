#!/usr/bin/env bash
# /opt/vlanit/vlanit-firstboot.sh — идемпотентная первая загрузка.
# Все операции безопасны при повторном запуске (прерывание/сбой).
set -Eeuo pipefail

LOG_TAG="vlanit-firstboot"
log() { logger -t "$LOG_TAG" -- "$*"; echo "[vlanit-firstboot] $*"; }

log "старт первичной настройки"

# machine-id
if [ ! -s /etc/machine-id ]; then
    systemd-machine-id-setup || log "WARN: machine-id setup failed"
fi

# SSH host keys: sshd-keygen.service не срабатывает (ConditionFirstBoot
# перекрыт нашим firstboot) — генерируем сами, идемпотентно.
# ssh.service к этому моменту уже мог стартовать и упасть без ключей —
# после генерации перезапускаем.
if ! ls /etc/ssh/ssh_host_* >/dev/null 2>&1; then
    ssh-keygen -A || log "WARN: генерация SSH host keys не удалась"
    # ssh.service упал на старте без ключей и ушёл в rate limit:
    # сбрасываем состояние, затем безусловный restart
    systemctl reset-failed ssh.service 2>/dev/null || true
    systemctl restart ssh.service 2>/dev/null || systemctl start ssh.service || true
fi

# пользователь владения данными MikoPBX
if ! id vlanit-www >/dev/null 2>&1; then
    useradd --system --uid 1001 --user-group --home-dir /var/spool/mikopbx \
        --shell /usr/sbin/nologin vlanit-www
fi
mkdir -p /var/spool/mikopbx/cf /var/spool/mikopbx/storage
chown -R 1001:1001 /var/spool/mikopbx

# идемпорт payload-образа MikoPBX (если установщик его не импортировал)
IMAGE_REF="localhost/vlanit/mikopbx:2026.6.99-amd64"
if ! podman image exists "$IMAGE_REF" 2>/dev/null; then
    PAYLOAD="$(find /var/lib/vlanit/payload /opt/vlanit/payload -maxdepth 1 -name 'mikopbx-*.tar.zst' 2>/dev/null | head -1)"
    if [ -n "$PAYLOAD" ]; then
        log "импорт образа MikoPBX из $PAYLOAD"
        zcat "$PAYLOAD" | podman load
        podman tag "$(podman images --format '{{.Repository}}:{{.Tag}}' | grep mikopbx | head -1)" "$IMAGE_REF" 2>/dev/null || true
    else
        log "WARN: payload образа не найден, предполагается предварительный импорт"
    fi
else
    log "образ $IMAGE_REF уже присутствует"
fi

# активация quadlet-службы MikoPBX
systemctl daemon-reload
if systemctl cat mikopbx.service >/dev/null 2>&1; then
    systemctl enable mikopbx.service 2>/dev/null || true
    # --no-block: не блокировать firstboot (медленный старт контейнера)
    systemctl start --no-block mikopbx.service || log "WARN: не удалось запустить mikopbx.service"
else
    log "ERROR: quadlet mikopbx.service не создан systemd-генератором"
    exit 1
fi

mkdir -p /var/lib/vlanit
date -Is > /var/lib/vlanit/firstboot-done

# контроль стандартного пароля веб-админа MikoPBX + детект сброса
# пароля provisioning'ом (известная проблема upstream: маркер
# CLOUD_INSTANCE_ID не даёт повторно применить WEB_ADMIN_PASSWORD)
QUADLET_PW=""
grep -q "WEB_ADMIN_PASSWORD=" /etc/containers/systemd/mikopbx.container && \
    QUADLET_PW="$(sed -n 's/^Environment=WEB_ADMIN_PASSWORD=//p' /etc/containers/systemd/mikopbx.container | head -1)"
# снять окаймляющие кавычки (systemd-формат, добавляет configure_target_mikopbx)
QUADLET_PW="${QUADLET_PW%\"}"; QUADLET_PW="${QUADLET_PW#\"}"
if [ -n "$QUADLET_PW" ]; then
    log "проверка пароля веб-админа MikoPBX"
    sleep 20   # дать контейнеру поднять веб
    if curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
            -H 'Content-Type: application/json' \
            -d "{\"login\":\"admin\",\"password\":\"$QUADLET_PW\"}" | grep -q accessToken; then
        log "пароль веб-админа в порядке"
        rm -f /var/lib/vlanit/atc-password-broken
    else
        log "ВНИМАНИЕ: пароль веб-админа не соответствует quadlet (сброс provisioning'ом MikoPBX)"
        touch /var/lib/vlanit/atc-password-broken
    fi
fi
log "первичная настройка завершена"

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

# контроль стандартного пароля веб-админа MikoPBX
if ! grep -q "WEB_ADMIN_PASSWORD=" /etc/containers/systemd/mikopbx.container; then
    log "проверка стандартного пароля веб-админа MikoPBX"
    sleep 20   # дать контейнеру поднять веб
    if curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
            -H 'Content-Type: application/json' \
            -d '{"login":"admin","password":"admin"}' 2>/dev/null | grep -q accessToken; then
        log "ВНИМАНИЕ: веб-админ MikoPBX использует стандартный пароль admin/admin — смените: https://<IP-адрес>"
        echo "VLANit: веб-админ MikoPBX использует стандартный пароль — смените через веб-интерфейс." >> /etc/motd
    fi
fi
log "первичная настройка завершена"

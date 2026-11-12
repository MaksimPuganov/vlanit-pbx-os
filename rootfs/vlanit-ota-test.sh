#!/usr/bin/env bash
# vlanit-ota-test — сценарий Т8 (обновление и откат). Только при VLANIT_TEST=ota.
set -u
out() { echo "VLANIT_OTA: $*" > /dev/ttyS0 2>/dev/null || true; echo "VLANIT_OTA: $*"; }
pass=0; fail=0
ok()  { out "PASS $1"; pass=$((pass+1)); }
bad() { out "FAIL $1"; fail=$((fail+1)); }

USB_MNT=/mnt/vlanit-usb
PHASE_FILE=/var/spool/mikopbx/storage/.vlanit-ota-phase

# --- подготовка USB (идемпотентно) ---
if ! mountpoint -q "$USB_MNT"; then
    mkdir -p "$USB_MNT"
    for dev in /dev/sda /dev/sdb /dev/sda1 /dev/sdb1; do
        [ -b "$dev" ] || continue
        mount "$dev" "$USB_MNT" 2>/dev/null && break
    done
fi
mountpoint -q "$USB_MNT" || { bad "usb-mount"; out "RESULT FAIL"; exit 1; }
PKG="$(ls "$USB_MNT"/vlanit-update-*.tar 2>/dev/null | head -1)"
[ -n "$PKG" ] || { bad "package-not-found"; out "RESULT FAIL"; exit 1; }

PHASE="$(cat "$PHASE_FILE" 2>/dev/null || echo 1)"

case "$PHASE" in
    1)
        # негатив: испорченный пакет отклонён
        cp "$PKG" /tmp/bad.tar; printf 'X' | dd of=/tmp/bad.tar bs=1 seek=100000 conv=notrunc 2>/dev/null
        cp "$PKG.asc" /tmp/bad.tar.asc 2>/dev/null || cp "${PKG}.asc" /tmp/bad.tar.asc
        if VLANIT_ASSUME_YES=1 vlanit-update /tmp/bad.tar >/dev/null 2>&1; then
            bad "corrupt-package-accepted"
        else
            ok "corrupt-package-rejected"
        fi
        # позитив: обновление применено
        if VLANIT_ASSUME_YES=1 vlanit-update "$PKG" >/dev/null 2>&1; then
            ok "update-applied"
        else
            bad "update-applied"
        fi
        grep -q "mikopbx:.*test1\|test1" /etc/containers/systemd/mikopbx.container \
            && ok "quadlet-new-tag" || bad "quadlet-new-tag"
        systemctl is-active --quiet mikopbx.service && ok "mikopbx-active-after-update" \
            || bad "mikopbx-active-after-update"
        /opt/vlanit/vlanit-snapshot list 2>/dev/null | grep -q pre-update \
            && ok "pre-update-snapshot" || bad "pre-update-snapshot"
        echo 2 > "$PHASE_FILE"; sync; sleep 2; reboot -f
        ;;
    2)
        # откат, затем reboot для проверки чистого состояния
        out "PHASE2: откат"
        if VLANIT_ASSUME_YES=1 vlanit-rollback "$(ls /.snapshots/ | grep pre-update | head -1 | sed 's/-@$//')" >/dev/null 2>&1; then
            ok "rollback-executed"
        else
            bad "rollback-executed"
        fi
        # vlanit-rollback сам перезагружает; до неё не дойдёт при успехе
        echo 3 > "$PHASE_FILE" 2>/dev/null || true
        sleep 5; reboot -f
        ;;
    *)
        # фаза 3: после отката — проверка возврата версии
        sleep 90   # дать контейнеру подняться
        if grep -q "2026.6.99-amd64" /etc/containers/systemd/mikopbx.container \
           && ! grep -q "test1" /etc/containers/systemd/mikopbx.container; then
            ok "version-reverted"
        else
            bad "version-reverted"
        fi
        systemctl is-active --quiet mikopbx.service && ok "mikopbx-active-after-rollback" \
            || bad "mikopbx-active-after-rollback"
        if [ "$fail" -eq 0 ]; then
            out "OTA_TEST_PASS ($pass checks)"
        else
            out "OTA_TEST_FAIL ($fail из $((pass+fail)))"
        fi
        ;;
esac

#!/usr/bin/env bash
# vlanit-backup-test — сценарий Т9 (бэкап на USB и восстановление). Только при VLANIT_TEST=backup.
set -u
out() { echo "VLANIT_BAK: $*" > /dev/ttyS0 2>/dev/null || true; echo "VLANIT_BAK: $*"; }
pass=0; fail=0
ok()  { out "PASS $1"; pass=$((pass+1)); }
bad() { out "FAIL $1"; fail=$((fail+1)); }

USB_MNT=/mnt/vlanit-usb
PHASE_FILE=/var/spool/mikopbx/storage/.vlanit-bak-phase

if ! mountpoint -q "$USB_MNT"; then
    mkdir -p "$USB_MNT"
    for dev in /dev/sda /dev/sdb /dev/sda1 /dev/sdb1; do
        [ -b "$dev" ] || continue
        mount "$dev" "$USB_MNT" 2>/dev/null && break
    done
fi
mountpoint -q "$USB_MNT" || { bad "usb-mount"; out "RESULT FAIL"; exit 1; }

PHASE="$(cat "$PHASE_FILE" 2>/dev/null || echo 1)"

case "$PHASE" in
    1)
        echo "marker-original-$(date +%s)" > /var/spool/mikopbx/storage/.vlanit-bak-marker
        MARKER_ORIG="$(cat /var/spool/mikopbx/storage/.vlanit-bak-marker)"
        echo "$MARKER_ORIG" > /root/.vlanit-bak-expected
        if vlanit-backup "$USB_MNT" >/tmp/vlanit-bak.log 2>&1; then
            ok "backup-created"
        else
            bad "backup-created"
            head -10 /tmp/vlanit-bak.log | while read -r l; do out "  $l"; done
        fi
        ls -d "$USB_MNT"/vlanit-backup-*/data.tar.zst >/dev/null 2>&1 && ok "backup-files" || bad "backup-files"
        systemctl is-active --quiet mikopbx.service && ok "mikopbx-active-after-backup" \
            || bad "mikopbx-active-after-backup"
        echo "marker-MODIFIED" > /var/spool/mikopbx/storage/.vlanit-bak-marker
        echo 2 > "$PHASE_FILE"; sync
        # восстановление данных из бэкапа (вручную, по инструкции troubleshooting)
        systemctl stop mikopbx.service 2>/dev/null || true
        BAKDIR="$(ls -d "$USB_MNT"/vlanit-backup-* | head -1)"
        out "  backup-dir: $BAKDIR"
        out "  marker-in-archive: $(tar -tf "$BAKDIR/data.tar.zst" 2>/dev/null | grep -c 'vlanit-bak-marker')"
        tar -C / --zstd -xf "$BAKDIR/data.tar.zst" 2>/tmp/vlanit-restore.err || { bad "restore-extract"; head -5 /tmp/vlanit-restore.err | while read -r l; do out "  $l"; done; }
        RESTORED="$(cat /var/spool/mikopbx/storage/.vlanit-bak-marker 2>/dev/null)"
        EXPECTED="$(cat /root/.vlanit-bak-expected)"
        out "  restored='$RESTORED' expected='$EXPECTED'"
        [ "$RESTORED" = "$EXPECTED" ] && ok "data-restored" || bad "data-restored"
        systemctl start mikopbx.service
        echo 3 > "$PHASE_FILE"; sync; sleep 3; reboot -f
        ;;
    *)
        sleep 90
        RESTORED="$(cat /var/spool/mikopbx/storage/.vlanit-bak-marker 2>/dev/null)"
        EXPECTED="$(cat /root/.vlanit-bak-expected 2>/dev/null)"
        out "  final: restored='$RESTORED' expected='$EXPECTED'"
        [ "$RESTORED" = "$EXPECTED" ] && ok "data-persisted" || bad "data-persisted"
        systemctl is-active --quiet mikopbx.service && ok "mikopbx-active-final" || bad "mikopbx-active-final"
        if [ "$fail" -eq 0 ]; then
            out "BACKUP_TEST_PASS ($pass checks)"
        else
            out "BACKUP_TEST_FAIL ($fail из $((pass+fail)))"
        fi
        ;;
esac

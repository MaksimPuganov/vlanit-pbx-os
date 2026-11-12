#!/usr/bin/env bash
# scripts/test-qemu.sh — автоматизированные тесты VLANit PBX OS в QEMU/KVM.
#
# Сценарии:
#   bash scripts/test-qemu.sh boot     — Т1: загрузка ISO (UEFI), запуск установщика
#   bash scripts/test-qemu.sh install  — Т2+Т3+Т4+Т6: установка, первая загрузка, MikoPBX, Btrfs
#   bash scripts/test-qemu.sh offline  — Т5: установка и работа без сети
#   bash scripts/test-qemu.sh errors   — Т7: ошибочные сценарии
#   bash scripts/test-qemu.sh ota      — Т8: обновление и откат (vlanit-update/rollback)
#   bash scripts/test-qemu.sh backup   — Т9: бэкап на USB и восстановление
#   bash scripts/test-qemu.sh all      — всё вышеперечисленное
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

ISO="dist/VLANit-PBX-1.2-amd64.iso"
STAGING="build/iso-staging"
EFI_IMG="build/grub/efi.img"
# изолированный каталог на каждый запуск (защита от параллельных/старых прогонов)
TESTDIR="build/qemu/$(date +%Y%m%d_%H%M%S)_$$"
OVMF_DIR="tools/root/usr/share/OVMF"
OVMF_CODE="$OVMF_DIR/OVMF_CODE_4M.fd"
OVMF_VARS_SRC="$OVMF_DIR/OVMF_VARS_4M.fd"
XORRISO="tools/root/usr/bin/xorriso"
export LD_LIBRARY_PATH="$PROJECT_ROOT/tools/root/usr/lib/x86_64-linux-gnu"

QEMU_MEM="${QEMU_MEM:-4096}"
QEMU_SMP="${QEMU_SMP:-2}"
DISK_SIZE_GB="${DISK_SIZE_GB:-64}"

[ -f "$ISO" ] || { echo "Нет $ISO — выполните make iso"; exit 1; }
[ -f "$OVMF_CODE" ] || { echo "Нет OVMF — скачайте пакет ovmf в tools/"; exit 1; }
[ -f "$EFI_IMG" ] || { echo "Нет $EFI_IMG — сборка ISO не завершена корректно"; exit 1; }
mkdir -p "$TESTDIR"

FAILED=0
say()  { printf '\n=== %s ===\n' "$*"; }
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; FAILED=1; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 2; }

# очистка зависших ВМ прошлых прогонов (только наши, по -name vlanit-)
for pid in $(pgrep -f "qemu-system.*-name vlanit-" 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
done

# Сборка тестового ISO из staging (+ опциональная подмена/добавление файлов)
# make_test_iso <out.iso> <iso9660_path=hostfile> [...]
make_test_iso() {
    local out="$1"; shift
    local -a maps=()
    while [ $# -gt 0 ]; do maps+=( "${1%%=*}=${1#*=}" ); shift; done
    # graft-points: iso_path=host_path
    "$XORRISO" -as mkisofs \
        -V VLANIT_PBX_OS -A "VLANit PBX OS 1.2 test" \
        -graft-points \
        -o "$out" \
        -e boot/grub/efi.img -no-emul-boot \
        -append_partition 2 0xef "$EFI_IMG" \
        -partition_cyl_align all \
        "$STAGING" "${maps[@]}"
}

make_disk() { qemu-img create -f qcow2 "$1" "${DISK_SIZE_GB}G" >/dev/null; }

# Скриншот экрана ВМ через monitor (screendump PPM -> PNG).
# shot <имя> <vm-name>
shot() {
    local name="$1" vm="$2"
    local mon="$TESTDIR/${vm}.monitor"
    local dir
    dir="$(mkdir -p "$TESTDIR/${vm}_shots" && realpath "$TESTDIR/${vm}_shots")"
    [ -S "$mon" ] || return 0
    MON_ABS="$(realpath "$mon")"
    printf 'screendump %s/%s.ppm\n' "$dir" "$name" | \
        python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.sendall(sys.stdin.buffer.read()); time.sleep(0.5)' "$MON_ABS" 2>/dev/null || return 0
    sleep 2
    [ -f "$dir/$name.ppm" ] && python3 "$PROJECT_ROOT/scripts/ppm2png.py" \
        "$dir/$name.ppm" "$dir/$name.png" >/dev/null 2>&1 && rm -f "$dir/$name.ppm"
}

# Чистка старых прогонов: оставляем KEEP_RUNS последних каталогов
cleanup_runs() {
    local keep="${KEEP_RUNS:-3}"
    ls -1dt "$PROJECT_ROOT"/build/qemu/2* 2>/dev/null | tail -n +$((keep + 1)) | \
        while read -r d; do echo "cleanup: $d"; rm -rf "$d"; done
    rm -f /tmp/vlanit-*-usb-*.raw /tmp/vlanit-*-pkg-*
}

run_qemu() {
    # run_qemu <name> <iso|-> <disk|-> [extra args...]
    local name="$1" iso="$2" disk="$3"; shift 3
    # NVRAM общий для фаз одного сценария (t2_p1/t2_p2 → t2)
    local vbase="${name%_p1}"; vbase="${vbase%_p2}"
    local vars="$TESTDIR/${vbase}_OVMF_VARS.fd"
    cp -n "$OVMF_VARS_SRC" "$vars" 2>/dev/null || true
    local -a args=(
        -name "vlanit-$name"
        -machine q35 -enable-kvm -m "$QEMU_MEM" -smp "$QEMU_SMP"
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
        -drive "if=pflash,format=raw,file=$vars"
        -serial "file:$TESTDIR/${name}_serial.log"
        -monitor "unix:$TESTDIR/${name}.monitor,server,nowait"
        -display none -pidfile "$TESTDIR/${name}.pid" -daemonize
    )
    [ "$disk" != "-" ] && args+=( -drive "file=$disk,if=virtio,format=qcow2" )
    if [ "$iso" != "-" ]; then
        if [ "${MEDIA:-usb}" = "usb" ]; then
            # реалистичный путь железа: ISO записан на флешку (dd) и
            # подключён как USB-накопитель; UEFI грузит ESP-раздел (FAT)
            args+=( -device qemu-xhci,id=xhci
                    -drive "file=$iso,if=none,id=instiso,format=raw"
                    -device "usb-storage,drive=instiso" )
        else
            args+=( -cdrom "$iso" )
        fi
    fi
    qemu-system-x86_64 "${args[@]}" "$@"
}

kill_qemu() {
    local pidfile="$TESTDIR/$1.pid"
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true
    sleep 1
    rm -f "$pidfile"
}

wait_serial() {
    local log="$1" pat="$2" timeout="$3" i=0
    while [ "$i" -lt "$timeout" ]; do
        grep -q "$pat" "$log" 2>/dev/null && return 0
        sleep 5; i=$((i+5))
    done
    return 1
}

report_failures() {
    local log="$1"
    grep "VLANIT_TEST: FAIL" "$log" 2>/dev/null | sort -u | while read -r l; do
        fail "$l"
    done
    grep -E "VLANIT_INSTALL_FAILED" "$log" 2>/dev/null | head -1 | while read -r l; do
        fail "$l"
    done
}

# ------------------------------------------------------------------
test_boot() {
    say "Т1: загрузка ISO (UEFI) и запуск установщика"
    local name="t1boot"
    make_test_iso "$TESTDIR/t1.iso" /autoinstall.yaml=tests/integration/autoinstall.yaml
    rm -f "$TESTDIR/${name}_serial.log"
    run_qemu "$name" "$TESTDIR/t1.iso" "-"
    # серия кадров: меню GRUB показывается ~5 с с момента старта ВМ
    for t in 3 4 5 6 7 8; do sleep 1; shot "00-grub-t${t}s" "$name"; done
    if wait_serial "$TESTDIR/${name}_serial.log" "обнаружен autoinstall" 300; then
        sleep 10; shot "01-installer-running" "$name"
        pass "T1: UEFI-загрузка live-среды и запуск VLANit Installer"
    else
        fail "T1: установщик не запустился (см. $TESTDIR/${name}_serial.log)"
    fi
    kill_qemu "$name"
}

# Фаза 1: установка (ISO). Фаза 2: первая загрузка с диска (без ISO).
install_two_phases() {
    local tag="$1" net="${2:-user}" yaml="${3:-tests/integration/autoinstall.yaml}"
    local p1="${tag}_p1" p2="${tag}_p2"
    local disk="$TESTDIR/${tag}_disk.qcow2"
    local iso="$TESTDIR/${tag}.iso"

    make_test_iso "$iso" /autoinstall.yaml="$yaml"
    rm -f "$disk" "$TESTDIR/${p1}_serial.log" "$TESTDIR/${p2}_serial.log"
    make_disk "$disk"

    # --- фаза 1: установка ---
    local -a netargs1=()
    if [ "$net" = "user" ]; then
        netargs1=( -netdev "user,id=n0" -device virtio-net-pci,netdev=n0 )
    fi
    run_qemu "$p1" "$iso" "$disk" "${netargs1[@]}"
    sleep 35; shot "01-install-progress" "$p1"   # этап разметки/развёртывания
    if ! wait_serial "$TESTDIR/${p1}_serial.log" "VLANIT_INSTALL_DONE" 1800; then
        report_failures "$TESTDIR/${p1}_serial.log"
        shot "01-install-failed" "$p1"
        fail "$tag: установка не завершена (фаза 1)"
        kill_qemu "$p1"
        return 1
    fi
    shot "02-install-finished" "$p1"
    grep -q "VLANIT_EFI" "$TESTDIR/${p1}_serial.log" \
        && pass "$tag: GPT-разметка выполнена" || fail "$tag: нет подтверждения разметки"
    kill_qemu "$p1"

    # --- фаза 2: загрузка установленной системы, тест-агент ---
    local -a netargs2=()
    if [ "$net" = "user" ]; then
        netargs2=( -netdev "user,id=n0,hostfwd=tcp::8443-:443" -device virtio-net-pci,netdev=n0 )
    fi
    run_qemu "$p2" "-" "$disk" "${netargs2[@]}"
    if wait_serial "$TESTDIR/${p2}_serial.log" "VLANIT_TEST_PASS" 1800; then
        sleep 5; shot "03-installed-system" "$p2"   # консоль установленной системы
        pass "$tag: первая загрузка с диска, все проверки агента пройдены"
    elif wait_serial "$TESTDIR/${p2}_serial.log" "VLANIT_TEST_FAIL" 1800; then
        report_failures "$TESTDIR/${p2}_serial.log"
        fail "$tag: проверки агента не пройдены"
    else
        fail "$tag: таймаут фазы 2 (см. $TESTDIR/${p2}_serial.log)"
    fi
    return 0
}

test_install() {
    say "Т2/Т3/Т4/Т6: установка, первая загрузка, MikoPBX, сохранение, Btrfs"
    install_two_phases t2 user || { return; }

    # внешняя проверка веб-интерфейса через hostfwd (ВМ t2_p2 ещё жива)
    sleep 5
    if curl -sk --max-time 15 https://127.0.0.1:8443/ -o /dev/null; then
        pass "T4: веб-интерфейс MikoPBX доступен с хоста (https://127.0.0.1:8443)"
    else
        fail "T4: веб-интерфейс недоступен с хоста"
    fi
    kill_qemu t2_p2
}

# USB-образ для Т8/Т9: vfat с пакетом обновления
make_usb_update() {
    local out="$1" pkgdir="$2"
    rm -f "$out"
    dd if=/dev/zero of="$out" bs=1M count=1024 status=none
    OUT_ABS="$(realpath "$out")"; PKG_ABS="$(realpath "$pkgdir")"
    docker run --rm --privileged \
        -v "$OUT_ABS:/b/usb.raw" -v "$PKG_ABS:/pkg:ro" \
        vlanit-build:1.0 sh -c "
        # явная геометрия: mtools не определяет размер bind-mounted файла;
        # 1024 МБ = 2097152 секторов = 8322 трека при h=4, s=63
        mformat -i /b/usb.raw -C -t 8322 -h 4 -s 63 -v VLANIT_UPD ::
        mcopy -i /b/usb.raw /pkg/vlanit-update-*.tar /pkg/vlanit-update-*.tar.asc ::
    " 2>/dev/null || die "не удалось создать USB-образ"
}

# Подготовка тестового пакета обновления (тот же образ, новый тег test1)
build_test_package() {
    local outdir="$1"
    mkdir -p "$outdir"
    cp build/payload/mikopbx-2026.6.99-amd64.tar.zst \
        "$outdir/mikopbx-2026.6.99-test1-amd64.tar.zst"
    GNUPGHOME="$HOME/.vlanit-release-gnupg" bash scripts/build-update-package.sh \
        "$outdir/mikopbx-2026.6.99-test1-amd64.tar.zst" "$outdir" "1.2.0" >/dev/null \
        || die "не удалось собрать пакет обновления"
    ls "$outdir"/vlanit-update-*.tar
}

# Двухфазный сценарий с USB-носителем и тестовым профилем.
# Носитель готовится в /tmp ПОСЛЕ фазы 1 (каталоги прогонов подвержены
# внешней чистке). mode=update: пакет из $TESTDIR/${tag}_pkg; mode=blank:
# чистый vfat.
run_usb_scenario() {
    local tag="$1" marker="$2" yaml="$3" mode="${4:-blank}"
    local p1="${tag}_p1" p2="${tag}_p2"
    local disk="$TESTDIR/${tag}_disk.qcow2"
    local usb="/tmp/vlanit-${tag}-usb-$$.raw"
    local iso="$TESTDIR/${tag}.iso"
    make_test_iso "$iso" /autoinstall.yaml="$yaml"
    rm -f "$disk" "$TESTDIR/${p1}_serial.log" "$TESTDIR/${p2}_serial.log"
    make_disk "$disk"
    run_qemu "$p1" "$iso" "$disk" \
        -netdev "user,id=n0" -device virtio-net-pci,netdev=n0
    if ! wait_serial "$TESTDIR/${p1}_serial.log" "VLANIT_INSTALL_DONE" 1800; then
        report_failures "$TESTDIR/${p1}_serial.log"
        fail "$tag: установка не завершена"
        kill_qemu "$p1"; return 1
    fi
    kill_qemu "$p1"
    if [ "$mode" = "update" ]; then
        # пакет собираем в /tmp ПОСЛЕ фазы 1
        local pkgdir="/tmp/vlanit-${tag}-pkg-$$"
        build_test_package "$pkgdir" >/dev/null
        make_usb_update "$usb" "$pkgdir"
        rm -rf "$pkgdir"
    else
        rm -f "$usb"
        dd if=/dev/zero of="$usb" bs=1M count=2048 status=none
        USB_ABS="$(realpath "$usb")"
        docker run --rm --privileged -v "$USB_ABS:/b/usb.raw" vlanit-build:1.0 \
            mformat -i /b/usb.raw -C -t 16644 -h 4 -s 63 -v VLANIT_BAK :: 2>/dev/null \
            || die "не удалось отформатировать USB ($tag)"
    fi
    run_qemu "$p2" "-" "$disk" \
        -netdev "user,id=n0" -device virtio-net-pci,netdev=n0 \
        -device qemu-xhci,id=xhci \
        -drive "file=$usb,if=none,id=usbstick,format=raw" \
        -device usb-storage,drive=usbstick
    if wait_serial "$TESTDIR/${p2}_serial.log" "$marker" 2400; then
        pass "$tag: сценарий завершён ($marker)"
    elif grep -q "_TEST_FAIL" "$TESTDIR/${p2}_serial.log"; then
        grep "VLANIT_\(OTA\|BAK\): FAIL" "$TESTDIR/${p2}_serial.log" | sort -u | while read -r l; do fail "$tag: $l"; done
    else
        fail "$tag: таймаут сценария (см. $TESTDIR/${p2}_serial.log)"
    fi
    rm -f "$usb"
    return 0
}

test_ota() {
    say "Т8: обновление (vlanit-update) и откат (vlanit-rollback)"
    run_usb_scenario t8 "VLANIT_OTA: OTA_TEST_PASS" tests/integration/autoinstall-ota.yaml update \
        && pass "Т8: негатив (битый пакет), обновление, снапшот, откат, возврат версии"
    kill_qemu t8_p2
}

test_backup() {
    say "Т9: бэкап на USB (vlanit-backup) и восстановление"
    run_usb_scenario t9 "VLANIT_BAK: BACKUP_TEST_PASS" tests/integration/autoinstall-backup.yaml blank \
        && pass "Т9: бэкап, модификация, восстановление, сохранение после reboot"
    kill_qemu t9_p2
}

test_errors() {
    say "Т7: обработка ошибочных сценариев"

    # 7a: несуществующий диск
    local name="t7a"
    sed 's|^disk:.*|disk: /dev/vdz|' tests/integration/autoinstall.yaml > "$TESTDIR/t7_nodisk.yaml"
    make_test_iso "$TESTDIR/t7a.iso" /autoinstall.yaml="$TESTDIR/t7_nodisk.yaml"
    rm -f "$TESTDIR/${name}_serial.log"
    run_qemu "$name" "$TESTDIR/t7a.iso" "-"
    if wait_serial "$TESTDIR/${name}_serial.log" "VLANIT_INSTALL_FAILED" 300; then
        pass "T7a: несуществующий диск отклонён установщиком"
    else fail "T7a: нет отказа на несуществующий диск"; fi
    kill_qemu "$name"

    # 7b: слишком мелкий диск (20G < 50G минимума)
    local name="t7b"
    make_test_iso "$TESTDIR/t7b.iso" /autoinstall.yaml=tests/integration/autoinstall.yaml
    rm -f "$TESTDIR/t7b_disk.qcow2" "$TESTDIR/${name}_serial.log"
    qemu-img create -f qcow2 "$TESTDIR/t7b_disk.qcow2" 20G >/dev/null
    run_qemu "$name" "$TESTDIR/t7b.iso" "$TESTDIR/t7b_disk.qcow2"
    if wait_serial "$TESTDIR/${name}_serial.log" "VLANIT_INSTALL_FAILED" 300; then
        pass "T7b: мелкий диск отклонён установщиком"
    else fail "T7b: нет отказа на мелкий диск"; fi
    kill_qemu "$name"

    # 7c: повреждённый payload (несоответствие SHA256)
    local name="t7c"
    echo "0000000000000000000000000000000000000000000000000000000000000000  mikopbx-2026.6.99-amd64.tar.zst" \
        > "$TESTDIR/t7_bad.sha256"
    make_test_iso "$TESTDIR/t7c.iso" \
        /autoinstall.yaml=tests/integration/autoinstall.yaml \
        /payload/mikopbx-2026.6.99-amd64.tar.zst.sha256="$TESTDIR/t7_bad.sha256"
    rm -f "$TESTDIR/${name}_serial.log"
    run_qemu "$name" "$TESTDIR/t7c.iso" "-"
    if wait_serial "$TESTDIR/${name}_serial.log" "VLANIT_INSTALL_FAILED" 600; then
        pass "T7c: повреждённый payload отклонён (checksum)"
    else fail "T7c: нет отказа на повреждённый payload"; fi
    kill_qemu "$name"

    # 7d: установка без сетевого интерфейса
    local name="t7d"
    make_test_iso "$TESTDIR/t7d.iso" /autoinstall.yaml=tests/integration/autoinstall.yaml
    rm -f "$TESTDIR/t7d_disk.qcow2" "$TESTDIR/${name}_serial.log"
    make_disk "$TESTDIR/t7d_disk.qcow2"
    run_qemu "$name" "$TESTDIR/t7d.iso" "$TESTDIR/t7d_disk.qcow2"
    if wait_serial "$TESTDIR/${name}_serial.log" "VLANIT_INSTALL_DONE" 1800; then
        pass "T7d: установка прошла без сетевого интерфейса"
    else
        report_failures "$TESTDIR/${name}_serial.log"
        fail "T7d: установка зависла без NIC"
    fi
    kill_qemu "$name"
}

test_offline() {
    say "Т5: полностью автономная установка (без сетевых устройств)"
    install_two_phases t5 none && pass "T5: офлайн-установка и работа MikoPBX"
    kill_qemu t5_p2
}

cleanup_runs

case "${1:-all}" in
    boot)    test_boot ;;
    install) test_install ;;
    offline) test_offline ;;
    errors)  test_errors ;;
    ota)     test_ota ;;
    backup)  test_backup ;;
    all)     test_boot; test_install; test_offline; test_errors; test_ota; test_backup ;;
    *) echo "Неизвестный сценарий: $1"; exit 2 ;;
esac

say "ИТОГ"
cleanup_runs
if [ "$FAILED" -eq 0 ]; then echo "ВСЕ ЗАПУЩЕННЫЕ ТЕСТЫ ПРОЙДЕНЫ"; else echo "ЕСТЬ ПРОВАЛЕННЫЕ ТЕСТЫ"; exit 1; fi

# Архитектура VLANit PBX OS

## Общая схема

```
Сборочная машина (docker)
  Dockerfile.build (Debian 13 + mmdebstrap/xorriso/grub)
    10-golden-rootfs.sh   Golden Image: Debian 13 + podman + VLANit-службы
    20-live-rootfs.sh     Live-среда: ядро + установщик (dialog) -> squashfs
    30-initramfs.sh       initramfs с кастомным vlanit-init
    40-staging.sh         payload + release-manifest
    50-iso.sh             GRUB UEFI + xorriso -> dist/*.iso

Целевое устройство (UEFI)
  ISO (VLANIT_PBX_OS)
    -> GRUB -> vmlinuz + initrd (vlanit-init)
       -> монтирование /dev/sr0 по метке, squashfs + overlayfs (tmpfs)
       -> switch_root -> systemd -> VLANit Installer (TUI, tty1)
            -> разметка GPT: EFI 1GiB / System 40GiB / Data (остаток), Btrfs
            -> subvolumes: @, @var_log, @snapshots | mikopbx-cf, mikopbx-storage
            -> развёртывание Golden Image, fstab по UUID
            -> grub-install (x86_64-efi) в chroot, update-initramfs
            -> импорт образа MikoPBX в rootful Podman (offline, из payload)
            -> первая загрузка: vlanit-firstboot -> systemd Quadlet
               -> mikopbx.service (podman, network=host, NET_ADMIN)
                  -> MikoPBX: env provisioning (PBX_NAME, пароль и т.д.)
```

## Golden Image

Переносимый образ файловой системы (tar.zst), а не поблочный образ диска —
поэтому установка возможна на накопители любого размера (≥ 50 GiB).

Из Golden Image удаляются все уникальные идентификаторы: machine-id
(пустой файл → systemd генерирует при первой загрузке), SSH host keys,
hostname, журналы. Секретов в образе нет: пароли администратора и веб-админа
задаются установщиком на устройстве.

## Загрузка Live

initramfs собирается initramfs-tools с hook `vlanit-live`, который копирует
busybox, скрипт `/vlanit-init` и модули (squashfs, isofs, loop, overlay,
virtio/sata/nvme, cdrom). `vlanit-init`:

1. монтирует devtmpfs/proc/sysfs;
2. ищет блочное устройство с меткой `VLANIT_PBX_OS` (без фиксированных имён);
3. монтирует ISO и squashfs rootfs;
4. поднимает overlayfs с tmpfs upper (Live-среда не пишет на носитель);
5. `switch_root` в систему; ISO остаётся смонтирован в `/media/vlanit`
   (оттуда установщик берёт payload).

Диагностика: пункт меню GRUB «режим отладки» (`VLANIT_DEBUG=1`) открывает
shell в initramfs.

## Дисковая схема (Btrfs)

| Раздел | Размер | ФС | Назначение |
|---|---|---|---|
| 1 | 1 GiB | FAT32 (EF00) | ESP: GRUB |
| 2 | 40 GiB | Btrfs | `@` (root), `@var_log`, `@snapshots` |
| 3 | остаток | Btrfs | `mikopbx-cf` (конфигурация АТС), `mikopbx-storage` (записи), `.snapshots` |

fstab генерируется по UUID. Монтирование: `compress=zstd,noatime` для
данных. Снапшоты — команда `vlanit-snapshot` (read-only, `/.snapshots`).

Ограничение v1: rollback работающей БД MikoPBX автоматически не выполняется
(нет подтверждённого механизма согласованного восстановления); снапшоты
создаются перед обновлениями вручную/скриптово.

## Podman и MikoPBX

- Rootful Podman (обоснование: host-network + NET_ADMIN + владение данными,
  максимальная совместимость с docker-run параметрами MikoPBX).
- Автозапуск — **systemd Quadlet** `/etc/containers/systemd/mikopbx.container`
  (Podman 5.4 в trixie, генератор в комплекте). `Restart=always`,
  `TimeoutStopSec=90` (entrypoint MikoPBX корректно обрабатывает SIGTERM).
- `Network=host` (требование MikoPBX для SIP/RTP/fail2ban),
  `AddCapability=NET_ADMIN`.
- Volumes: `/var/spool/mikopbx/cf:/cf`, `/var/spool/mikopbx/storage:/storage`
  (Btrfs subvolumes, владелец `vlanit-www` uid 1001 → `ID_WWW_USER/GROUP`).
- Внешние registry отключены (`unqualified-search-registries = []`) —
  образ импортируется из локального payload, интернет не нужен.

## Provisioning

Декларативная схема VLANit (YAML, `schema_version: 1`), валидация —
`provisioning/vlanit-provision` (python3-yaml):

- **System**: hostname, network (DHCP/static), ssh, storage, container,
  wireguard (enabled, address, listen_port, peers).
- **PBX**: только подтверждённые переменные окружения MikoPBX
  (PBX_NAME, WEB_ADMIN_*, порты и др., см. docs/mikopbx-research.md §3).
  Они применяются механизмом DockerCloud при каждом старте контейнера
  и сохраняются в БД → конфигурация переживает обновление образа.
- Профили расширений (SIP extensions, trunks, routes, IVR и т.д.) заложены
  схемой, но не реализуются до подтверждения соответствующих API-ресурсов.

Идемпотентность: повторный запуск перезаписывает только изменившиеся блоки;
службы применяются через systemd (daemon-reload + restart).

## Systemd-службы (установленная система)

| Юнит | Назначение |
|---|---|
| `vlanit-firstboot.service` | одноразовая первичная настройка (маркер `/var/lib/vlanit/firstboot-done`) |
| `mikopbx.service` | quadlet-служба контейнера MikoPBX |
| `vlanit-test-agent.service` | только при `VLANIT_TEST=1` в cmdline (QUI-тесты) |
| `systemd-timesyncd.service` | NTP-синхронизация (1.2.3; FallbackNTP pool.ntp.org) |
| `nftables.service` | firewall: input policy drop, явные разрешения (1.2.4, ADR-0003) |
| `sshd-keygen` + `ssh-keygen -A` в firstboot | host-ключи SSH (1.2.4: обход ConditionFirstBoot=yes) |

## Журналы и аудит

- systemd-journald: `Storage=persistent`, каталог `/var/log/journal`
  (Btrfs subvolume `@var_log`), `SystemMaxUse=200M` — журналы переживают
  перезагрузку (1.2.4).
- Аудит безопасности: `/cso` (daily). Отчёт 1.2.2: `.gstack/security-reports/2026-11-13-014500.json`
  (HIGH #1 — пароль в quadlet 0644 — исправлено в 1.2.3 правами 0600).

## Кнопка питания

logind (`/etc/systemd/logind.conf.d/01-vlanit.conf`, 1.2.4):
короткое нажатие — игнор, длинное (>5 с) — штатное выключение.
Апплаенс: случайное нажатие не должно ронять телефонию.

## Контейнер MikoPBX (лимиты, 1.2.4)

`PidsLimit=4096`, `TimeoutStopSec=120` в quadlet (по умолчанию podman:
2048 pids, стоп 10 с — недостаточно для корректного завершения АТС).
`MemoryMax` — осознанно не задан (жёсткий лимит рискован для длинных звонков).

## Безопасность установщика

- Диски обнаруживаются динамически (`lsblk`), исключаются removable-носители,
  установочный USB и диски с смонтированными разделами.
- Нет фиксированных `/dev/sda|nvme0n1`.
- Деструктивные операции — только после явного подтверждения (интерактив)
  или `confirm: yes` (только автоустановка в тестах).
- Контрольные суммы payload проверяются перед разметкой.

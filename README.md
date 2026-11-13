# VLANit PBX OS

Собственный установочный ISO для автоматического развёртывания MikoPBX
на физических x86-64 устройствах: Debian 13 (trixie) Minimal + Podman +
MikoPBX в контейнере + Btrfs со снапшотами + преднастроенный WireGuard.
Установка полностью автономна (интернет на целевом устройстве не требуется).

Это самостоятельный продукт: VLANit Portal и его зависимости в состав не входят.

**Документация:** пользовательская и полевая — в [Wiki проекта](https://github.com/vlanit-com/vlanit-pbx-os/wiki)
(быстрый старт, FAQ, runbooks, совместимое железо, release notes); техническая — в `docs/` репозитория.

**Автор и мейнтейнер:** Максим Пуганов (MaksimPuganov).
**Лицензия:** Apache-2.0 (см. LICENSE).

## Возможности 1.2

- **OTA-обновления**: `vlanit-update` — подписанные GPG пакеты (USB или
  `--online`), снапшот перед применением, health-check MikoPBX;
  `vlanit-rollback` — откат системы из Btrfs-снапшота с перезагрузкой.
- **Безопасность**: unattended-upgrades (security-источники с 1.2.3),
  запрет root по SSH, host fail2ban (journald), контроль стандартного
  пароля веб-админа, quadlet с правами 0600, firewall default-deny (1.2.4).
- **Бэкап**: `vlanit-backup` — tar (`/cf` + `/storage` + `/etc`) на USB.
- **WireGuard VPN**: своя пара ключей при установке, wg0 с автозапуском,
  форвардинг, публичный ключ показывается на экране завершения.
- **Брендинг ОС**: фон и цвета GRUB (логотип), Plymouth-заставка,
  os-release, консольные баннеры, шрифт консоли с кириллицей (1.2.3).

## Системные настройки по умолчанию (1.2.4)

**Сеть (nftables, ADR-0003).** Политика `input: default drop`; открыто только
необходимое (файл `/etc/nftables.conf` на устройстве):

| Направление | Порты | Назначение |
|---|---|---|
| tcp | 22 | SSH устройства (root отключён, fail2ban) |
| udp | 51820 | WireGuard |
| tcp | 80, 443 | веб-интерфейс MikoPBX |
| tcp | 5060, 5061 | SIP / SIP-TLS |
| udp | 5060, 10000–10800 | SIP / RTP |

Ограничение управления подсетями админа: заменить `accept` на
`ip saddr { 10.x.0.0/16 } accept` для tcp/22 и udp/51820 в `/etc/nftables.conf`.
Форвардинг разрешён только для WireGuard (road-warrior доступ к АТС).

**SSH и вход.** Host-ключи генерируются при первой загрузке (`vlanit-firstboot`,
обход `ConditionFirstBoot` + `reset-failed` rate limit). root по SSH запрещён,
`MaxAuthTries 5`. Консоль — программа `login`, пароль локального администратора
из мастера.

**Журналы.** systemd-journald: `Storage=persistent`, `/var/log/journal`
(subvolume `@var_log`), лимит `SystemMaxUse=200M` — журналы переживают перезагрузку.
Журналы OTA/бэкапа: `/var/log/vlanit-update.log`, `/var/log/vlanit-backup.log`.

**Контейнер АТС (quadlet).** `PidsLimit=4096`, `TimeoutStopSec=120`,
`Restart=always`; сеть host + `NET_ADMIN`; конфигурационный файл — права `0600`
(пароль веб-админа). `MemoryMax` осознанно не задан (риск для длинных звонков).

**Кнопка питания (logind).** Короткое нажатие — игнор; длинное (>5 с) —
штатное выключение. Случайное нажатие не роняет телефонию.

**Время.** `systemd-timesyncd` (FallbackNTP: debian pool), часовой пояс —
из мастера установки (`/etc/timezone`).

## Плановые доработки

- **`vlanit-doctor`** (1.3.0) — диагностический скрипт установленной ОС:
  одна команда сводного контроля здоровья (33 группы проверок от тест-агента),
  вывод OK/FAIL/SKIP, код возврата, `--fix-hints`, `--json`. Спека:
  `docs/specs/planned-vlanit-doctor.md`.

## Требования к сборочной машине

- Debian 13 (trixie) amd64 (проверено), или иной Linux с Docker.
- Docker с доступом пользователя (сборка выполняется в привилегированном
  build-контейнере `scripts/Dockerfile.build`; root на сборочной машине
  не требуется).
  **Docker — только инструмент сборочной машины. В самом продукте
  (VLANit PBX OS) Docker отсутствует: контейнерный рантайм — Podman
  (rootful, systemd Quadlet).** Rootless Podman как build-рантайм на
  сборочной машине не используется: в ряде окружений блокируется
  (newuidmap EPERM), rootful требует sudo.
- RAM ≥ 8 ГБ, диск ≥ 30 ГБ свободно (ISO ~1.3 ГБ + сборочные каталоги).
- KVM для тестов (для скорости; без KVM тесты работают в эмуляции — медленно).

## Команды

```bash
# подготовка payload (один раз, нужен docker)
bash scripts/pull-mikopbx.sh

# сборка ISO
make iso            # == bash scripts/build.sh в build-контейнере

# тесты в QEMU/KVM (нужен пакет ovmf: apt-get download ovmf + dpkg -x)
bash scripts/test-qemu.sh all        # все сценарии
bash scripts/test-qemu.sh install    # только установка/загрузка/MikoPBX

# запись на USB (требует root, ДЕСТРУКТИВНО)
sudo bash scripts/write-usb.sh dist/VLANit-PBX-1.2.4-amd64.iso /dev/sdX
# другие способы (dd, GNOME Disks, KDE ISO Image Writer, Rufus, balenaEtcher,
# macOS dd, Ventoy) — docs/installation.md, раздел «Создание загрузочной флэшки»

make clean          # очистка build/{rootfs,live,iso-staging}, dist
```

## Артефакты

| Путь | Назначение |
|---|---|
| `dist/VLANit-PBX-1.2.4-amd64.iso` | итоговый загрузочный ISO (UEFI) |
| `dist/VLANit-PBX-1.2.4-amd64.iso.sha256` | контрольная сумма |
| `build/payload/mikopbx-*.tar.zst` | экспортированный образ MikoPBX (+sha256) |
| `build/payload/golden.tar.zst` | Golden Image устанавливаемой системы |
| `build/logs/` | журналы шагов сборки |

## Состав ISO

- `live/` — ядро Debian, initramfs со скриптом `vlanit-init` (монтирует ISO
  по метке `VLANIT_PBX_OS`, squashfs rootfs + overlayfs) и rootfs Live-среды.
- `payload/` — Golden Image (tar.zst), образ MikoPBX (tar.zst), манифест
  версий, контрольные суммы, дефолты установщика.
- `boot/grub/` — GRUB UEFI (`grub.cfg`, `efi.img`).

## Важно

- Установка только UEFI (Legacy BIOS — не в v1, архитектура это допускает).
- Установщик и его автономный режим описаны в `docs/installation.md`.
- Исследование MikoPBX: `docs/mikopbx-research.md`.
- Результаты тестов: `docs/testing.md`.

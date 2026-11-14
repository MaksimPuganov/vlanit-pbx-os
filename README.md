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

- **Полное обновление при сборке (1.2.5)**: все пакеты golden/live
  rootfs — последних версий (trixie + updates + security), в образ всегда
  попадает последнее ядро (`linux-image-amd64` == Candidate), старые ядра
  вычищаются. Guard в сборке: несовпадение версии ядра = ошибка шага.

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

**SSH и вход.** Host-ключи генерируются drop-in'ом `ssh.service.d/00-keygen.conf`
(`ssh-keygen -A` до старта sshd; с 1.2.6 — ssh.service стартует без падений,
firstboot-логика осталась идемпотентной подстраховкой). root по SSH запрещён,
`MaxAuthTries 5`. Консоль — программа `login`, пароль локального администратора
из мастера.

**Владение файлами (1.2.6).** Вся система — root:root (guard сборки:
файлы uid/gid ≥ 1000 обрывают сборку; сборка только в build-контейнере,
`make iso`). sudo: root-owned + setuid, с паролем администратора.

**Контейнер АТС (quadlet).** Секция `[Container]`: `PidsLimit` и
`StopTimeout` задаются установщиком из `/etc/vlanit/mikopbx-container.conf`
(по умолчанию 8192 и 120 с; issue #16 — раньше контейнер убивался через
10 с, лимит был жёстко 4096), env-параметры VLANit (в т.ч.
`WEB_ADMIN_PASSWORD`) — блок `VLANIT-ENV` строго в `[Container]` (Quadlet
передаёт `Environment=` в контейнер только оттуда; кавычкование значений
с пробелами). Файл quadlet: 0600.

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

## Трекер задач

Плановая работа ведётся в [GitHub Issues](https://github.com/vlanit-com/vlanit-pbx-os/issues):
майлстоун **1.3.0** — тестовая инфраструктура Т10–Т17 + vlanit-doctor.
Метки: `test` (автотесты), `planned` (спека готова), `upstream`
(зависит от MikoPBX), `field` (полевой фидбек), `security`.

## Плановые доработки

- **Тестирование Т10–Т17** — дорожная карта: power-cut resilience,
  performance baseline, регрессионный веб-QA MikoPBX, WireGuard e2e,
  глубокие проверки apt, интерактивный TUI-прогон, SIP-стресс, soak.
  Спека: `docs/specs/testing-roadmap-t10-t17.md`.
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

# подпись контрольных сумм релиза (GPG, ключ релиза)
bash scripts/sign-release.sh   # dist/*.iso.sha256 -> .asc

# релиз через CI: git tag vX.Y.Z && git push origin vX.Y.Z
# workflow build-iso собирает ISO из исходников тега и публикует релиз
# с подписанными контрольными суммами (идея #11, см. ниже «Правило релизов»)

# запись на USB (требует root, ДЕСТРУКТИВНО)
sudo bash scripts/write-usb.sh dist/VLANit-PBX-1.2.6-amd64.iso /dev/sdX
# другие способы (dd, GNOME Disks, KDE ISO Image Writer, Rufus, balenaEtcher,
# macOS dd, Ventoy) — docs/installation.md, раздел «Создание загрузочной флэшки»

make clean          # очистка build/{rootfs,live,iso-staging}, dist
```

## Артефакты

| Путь | Назначение |
|---|---|
| `dist/VLANit-PBX-1.2.6-amd64.iso` | итоговый загрузочный ISO (UEFI) |
| `dist/VLANit-PBX-1.2.6-amd64.iso.sha256` | контрольная сумма |
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

## Правило релизов (CI)

1. Тег и файлы релиза после публикации не меняются.
2. Каждый релиз собирает CI из запушенных исходников: `git tag vX.Y.Z &&
   git push origin vX.Y.Z` запускает workflow `build-iso`, который публикует
   релиз с этим тегом (`--verify-tag`). Ручной запуск — `workflow_dispatch`.
3. Контрольные суммы ISO подписаны GPG-ключом релиза (публичный ключ —
   `rootfs/etc-vlanit-release.pub`, приватный — GitHub Secret
   `RELEASE_GPG_PRIVATE_KEY`). Проверка перед записью на USB:

   ```bash
   gpg --no-default-keyring --keyring rootfs/etc-vlanit-release.pub \
       --verify dist/VLANit-PBX-X.Y.Z-amd64.iso.sha256.asc
   sha256sum -c dist/VLANit-PBX-X.Y.Z-amd64.iso.sha256
   ```

   Спека пайплайна: `docs/specs/1.2.6-ci-release.md`.

# Changelog VLANit PBX OS

Формат: секция `## X.Y.Z (дата)` на релиз. Workflow build-iso при публикации
релиза по тегу `vX.Y.Z` берёт текст секции из этого файла как описание релиза
(идея #11: тег не меняется, описание — часть исходников на коммите тега).

## 1.2.7 (2026-11-14)

- **Первый релиз, собранный полностью через CI** по правилу релизов: тег →
  сборка из исходников тега → GPG-подпись контрольных сумм → публикация.
- Экран 1 «Проверка оборудования» в мастере установки: CPU, ОЗУ, сетевые
  интерфейсы, режим загрузки, предупреждения (ОЗУ < 2 ГБ и т.п.).
- Рефакторинг по аудиту на овер-инжиниринг (issue #21–#28): удалён фантомный
  config/defaults.yaml (дефолты — в build.yaml), мёртвый код, артефакты
  (__pycache__, .gstack) вычищены из git; общие модули vlanit_quadlet и
  gpg-release-common вместо дублированной логики (−~120 строк).
- Ядро 6.12.117+deb13-amd64 (trixie-security).

Тестирование (QEMU/KVM, UEFI): 42 проверки агента PASS + WARN-CHECK
reboot-api-login (известный upstream-баг MikoPBX, #10).

## 1.2.6 (2026-11-13)

Полевые исправления по тесту 1.2.4 (issue #15–#19):

- sudo и владение файлами: вся система root:root; guard сборки от uid/gid ≥
  1000, сборка только в build-контейнере.
- Firewall: убрано тестовое правило 10.0.2.0/24 accept.
- Пароль веб-админа из мастера реально доходит до MikoPBX (VLANIT-ENV в
  секции [Container] quadlet; Environment= из [Service] контейнеру не
  передаётся).
- Остановка контейнера 120 с (было 10); PidsLimit 8192 — оба параметра в
  настройке /etc/vlanit/mikopbx-container.conf.
- ssh.service стартует без падений: drop-in генерирует host keys до старта sshd.
- Часовой пояс спрашивается в мастере (дефолт Europe/Moscow).

Тестирование: 42 проверки агента PASS + WARN-CHECK #10.
Спека: docs/specs/1.2.6-field-fixes.md.

## 1.2.5 (2026-11-13)

- Гарантия последнего ядра в образе: guard сборки Installed==Candidate,
  источники security/updates до full-upgrade, resolv.conf в chroot,
  явный purge старых ядер (issue #11).

## 1.2.4 (2026-11-13)

- Харденинг: вход в систему (login + SSH host keys), nftables default-deny
  (ADR-0003), persistent journal (200 МБ), лимиты контейнера, кнопка питания
  (короткое нажатие — игнор).

## 1.2.3 (2026-11-13)

- apt security/updates-источники, NTP (timesyncd), консольный шрифт с
  кириллицей, автогенерация пароля АТС при пустом, quadlet 0600.

## 1.2.2 (2026-11-13)

- Логотип VLANit в меню GRUB, фирменная тема Plymouth, фирменные цвета GRUB
  установленной системы.

## 1.2.1 (2026-11-13)

- **Важно для железа:** загрузка с USB-флешки (GRUB fat-модуль, usb-модули,
  поиск носителя в initramfs). Брендинг vlanit.com, репозиторий очищен от
  бинарников.

## 1.2.0 (2026-11-12)

- OTA-обновления (vlanit-update/vlanit-rollback, GPG-подпись пакетов),
  безопасность (unattended-upgrades, запрет root по SSH, fail2ban),
  vlanit-backup на USB, WireGuard VPN, CI workflow build-iso.

Релизы 1.0–1.1.x: начальная версия — установщик, Golden Image, Podman +
MikoPBX, Btrfs-снапшоты, автономная установка, QEMU-тесты (см. git log).

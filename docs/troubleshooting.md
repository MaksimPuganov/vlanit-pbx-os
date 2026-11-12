# Диагностика проблем (troubleshooting)

## Не загружается с USB

- Проверьте, что загрузка именно **UEFI** (в Boot Menu пункт с пометкой UEFI).
- Перезапишите USB: `sudo bash scripts/write-usb.sh dist/...iso /dev/sdX`.
- Пункт GRUB «режим отладки» (`VLANIT_DEBUG=1`) даёт shell в initramfs:
  `blkid` — виден ли носитель с меткой `VLANIT_PBX_OS`.

## Live-среда не находит установочный носитель

- `vlanit-init` ищет метку `VLANIT_PBX_OS` на /dev/sr*, затем сканирует
  блочные устройства. На нестандартных контроллерах добавьте модуль ядра
  в `live/initramfs-hook-vlanit-live` и пересоберите (`make iso`).

## Установщик: нет подходящих дисков

- Исключаются removable-носители и диски с смонтированными разделами.
- `lsblk -d -o NAME,TYPE,RM,SIZE,MODEL` — проверьте, что диск TYPE=disk, RM=0.

## Проблемы сети после установки

- Настройки привязаны к MAC-адресу (`/etc/systemd/network/10-vlanit.network`).
- Проверка: `networkctl status`, `journalctl -u systemd-networkd`.
- DNS: `resolvectl status` (systemd-resolved).

## Podman / MikoPBX

- `systemctl status mikopbx` — служба Quadlet; генератор:
  `systemctl cat mikopbx.service`.
- Образ отсутствует: `zcat /var/lib/vlanit/payload/mikopbx-*.tar.zst | podman load`.
- Веб не поднимается: `podman logs mikopbx | tail -50`; занятые порты
  (host network!): `ss -tlnp`.
- NET_ADMIN: без capability не работают fail2ban/iptables внутри контейнера,
  базовая телефония работает.
- Только rootful: rootless-режим с host-сетью и NET_ADMIN не поддерживается v1.

## Btrfs / снапшоты

- `findmnt /` — btrfs; `btrfs subvolume list /`.
- `vlanit-snapshot create before-update`, `vlanit-snapshot list`.
- Rollback: корневой subvolume переносится (mv), из снапшота создаётся
  новый — перезагрузка обязательна.

## OTA-обновления и откат

- `vlanit-update [пакет]` — сканирует USB (или `--online`), проверяет
  GPG-подпись, совместимость версий и SHA256, делает снапшот `pre-update`,
  применяет обновление, проверяет готовность MikoPBX.
- `vlanit-rollback [снапшот]` — возвращает систему (включая данные АТС)
  к состоянию снапшота, перезагружает устройство.
- Пакет обновления собирается `scripts/build-update-package.sh`
  (нужен приватный ключ релиза, хранится вне репозитория).
- Журналы: `/var/log/vlanit-update.log`, `/var/log/vlanit-backup.log`.

## Бэкап на USB

- `vlanit-backup` — останавливает MikoPBX, пишет tar.zst (cf + storage +
  /etc) на USB, запускает контейнер обратно, проверяет health.
- Восстановление: остановить контейнер, распаковать `data.tar.zst`
  с корня (`tar -C / --zstd -xf`), запустить контейнер.

## systemd

- `journalctl -b -p err` — ошибки текущей загрузки.
- `systemctl --failed` — упавшие юниты.
- Первичная настройка: `journalctl -u vlanit-firstboot -b`.

## Сборка

- Журналы шагов: `build/logs/*.log`.
- `make clean` затрагивает только `build/rootfs|live|iso-staging` и `dist`.
- Обновление MikoPBX: `scripts/pull-mikopbx.sh` (проверит digest),
  затем `make iso`.

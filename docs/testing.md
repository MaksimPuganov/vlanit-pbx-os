# Тестирование VLANit PBX OS

## Запуск

```bash
# unit-тесты (валидация схемы provisioning)
bash tests/unit/test-provision-validation.sh

# интеграционные тесты в QEMU/KVM (UEFI, OVMF)
bash scripts/test-qemu.sh boot      # Т1
bash scripts/test-qemu.sh install   # Т2, Т3, Т4, Т6
bash scripts/test-qemu.sh offline   # Т5
bash scripts/test-qemu.sh errors    # Т7
bash scripts/test-qemu.sh all
```

Требования: `qemu-system-x86_64`, KVM (`/dev/kvm`), OVMF
(`apt-get download ovmf && dpkg -x ovmf_*.deb tools/root`), образ
`dist/VLANit-PBX-1.0-amd64.iso`.

Сценарии используют профиль `tests/integration/autoinstall.yaml`
(автоустановка на /dev/vda, 64 GiB, DHCP, тест-агент `VLANIT_TEST=1`).
Каждый прогон изолируется в `build/qemu/<timestamp>_<pid>/`.

Механика: тестовый ISO собирается из `build/iso-staging` с подложенным
`/autoinstall.yaml`; установка (фаза 1, с ISO) и первая загрузка
(фаза 2, без ISO, общий NVRAM OVMF) — отдельные запуски QEMU. Тест-агент
(`rootfs/vlanit-test-agent.sh`, активен только при `VLANIT_TEST=1` в cmdline)
выполняет 16 проверок на устройстве и публикует `VLANIT_TEST: PASS/FAIL …`,
`VLANIT_TEST_PASS` / `VLANIT_TEST_FAIL` на ttyS0. После успешных проверок
агент перезагружает устройство и проверяет сохранение данных и автозапуск
MikoPBX (REBOOT_TEST_PASS).

## Фактические результаты

### Прогон 2026-11-13, ISO VLANit-PBX-1.2.3-amd64.iso (field fixes)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: 27 проверок, включая apt-security, timesyncd, quadlet 600, SSH_PORT=23) |

### Прогон 2026-11-13, ISO VLANit-PBX-1.2.1-amd64.iso (USB-boot, брендинг, чистка)

| Тест | Результат |
|---|---|
| Т1 Загрузка (USB-носитель, эмуляция флешки) | PASS |
| Т2–Т4, Т6 (установка, MikoPBX, Btrfs) | PASS (22 проверки агента; REBOOT_TEST_PASS) |
| Т5 Offline | PASS |
| Т7a–d Ошибки | PASS |
| Т8 Обновление и откат | PASS |
| Т9 Бэкап на USB (носитель 3 ГБ) | PASS |

### Прогон 2026-11-12, ISO VLANit-PBX-1.2-amd64.iso (OTA, безопасность, бэкап)

| Тест | Результат |
|---|---|
| Т1 Загрузка ISO (UEFI) | PASS |
| Т2–Т4, Т6 (установка, MikoPBX, Btrfs) | PASS (22 проверки агента: 16 базовых + WireGuard×3 + безопасность×3; REBOOT_TEST_PASS) |
| Т5 Offline | PASS |
| Т7a–d Ошибки | PASS |
| Т8 Обновление и откат | PASS (негатив: битый пакет отклонён по GPG; снапшот pre-update; обновление; откат; версия возвращена) |
| Т9 Бэкап на USB | PASS (бэкап; модификация данных; восстановление; сохранение после reboot) |

### Прогон 2026-11-12, ISO VLANit-PBX-1.1-amd64.iso (WireGuard + брендинг)

| Тест | Результат |
|---|---|
| Т1 Загрузка ISO (UEFI) | PASS |
| Т2 Установка системы | PASS |
| Т3 Первая загрузка | PASS |
| Т4 MikoPBX | PASS (19 проверок агента: 16 базовых + wireguard-service-enabled, wireguard-interface-up, wireguard-address; REBOOT_TEST_PASS) |
| Т5 Offline | PASS |
| Т6 Btrfs | PASS |
| Т7a–d Ошибки | PASS |

### Прогон 2026-11-12, ISO VLANit-PBX-1.0-amd64.iso (базовый)

| Тест | Результат | Подтверждение |
|---|---|---|
| Т1 Загрузка ISO (UEFI) | PASS | live-среда загружена, установщик запущен |
| Т2 Установка системы | PASS | GPT (EFI 1G/System 40G/Data rest), Btrfs, Golden Image, fstab по UUID, GRUB x86_64-efi |
| Т3 Первая загрузка | PASS | загрузка с диска, hostname, networkd, podman, fstab-uuid |
| Т4 MikoPBX | PASS | quadlet-служба, баннер готовности, веб-интерфейс (из ВМ и с хоста через hostfwd 8443→443), API login v3, автозапуск и данные после reboot |
| Т5 Offline | PASS | полная установка и работа без сетевых устройств |
| Т6 Btrfs | PASS | subvolumes смонтированы, read-only snapshot создан и отображён |
| Т7a несуществующий диск | PASS | отказ установщика (диск не в списке кандидатов) |
| Т7b диск 20 GiB | PASS | отказ (минимум 50 GiB) |
| Т7c повреждённый payload | PASS | отказ по SHA256 до разметки |
| Т7d установка без NIC | PASS | установка завершена успешно |

Итог агента (1.0): `RESULT PASS (16 checks)`, `VLANIT_TEST_PASS`, `REBOOT_TEST_PASS`.
Логи прогонов: `build/qemu/<run>/`, сводки `build/qemu*_t*.log`.

## Состав проверок агента (16)

hostname, podman, networkd-active, fstab-uuid, btrfs-root,
btrfs-subvol-mikopbx-cf, btrfs-snapshot-create, btrfs-snapshot-list,
quadlet-service, mikopbx-ready-banner, mikopbx-service-active,
mikopbx-webui, mikopbx-api-login, mikopbx-cf-nonempty,
reboot-data-persisted, reboot-mikopbx-active.

## Не автоматизируется в v1 (ручные сценарии)

- Интерактивный TUI-мастер (прохождение экранов вручную на железе/ВМ).
- Установка на реальный SATA/NVMe диск (прогон на физическом устройстве).
- Проверка SIP-регистрации/звонка (требуется SIP-клиент/транк).
- Загрузка Legacy BIOS (не поддерживается в v1; fallback `EFI/BOOT/BOOTX64.EFI` на целевом ESP добавлен).
- Secure Boot (не входит в v1).

## Воспроизводимость сборки

`make clean && make iso` пересобирает ISO полностью из исходников
(проверено: повторная сборка успешна). Побайтовая идентичность не
гарантируется (в манифесте — дата сборки, в rootfs — метки времени пакетов);
контроль целостности — SHA256 артефактов в `config/release-manifest.yaml`
и `dist/*.iso.sha256`.

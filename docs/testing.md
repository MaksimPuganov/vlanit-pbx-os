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
Серийные логи: `build/qemu/*_serial.log`.

Механика: тестовый ISO собирается из `build/iso-staging` с подложенным
`/autoinstall.yaml`; установка (фаза 1, с ISO) и первая загрузка
(фаза 2, без ISO) — отдельные запуски QEMU. Тест-агент
(`rootfs/vlanit-test-agent.sh`, активен только при `VLANIT_TEST=1` в cmdline)
выполняет проверки на устройстве и публикует `VLANIT_TEST: PASS/FAIL …`,
`VLANIT_TEST_PASS` / `VLANIT_TEST_FAIL` на ttyS0.

## Сценарии и фактические результаты

### Т1 — Загрузка ISO (UEFI)
Проверяется: запуск Debian Live, запуск VLANit Installer.
- Ожидание: в serial-логе признаки autoinstall и старта разметки.
- Статус: ЗАПЛАНИРОВАН → (заполняется прогоном)

### Т2 — Установка системы
Проверяется: обнаружение диска, GPT, EFI, Btrfs, развёртывание rootfs,
загрузчик, fstab. Маркер `VLANIT_INSTALL_DONE`.
- Статус: ЗАПЛАНИРОВАН

### Т3 — Первая загрузка
Проверяется: загрузка Debian с диска, hostname, networkd, podman.
- Статус: ЗАПЛАНИРОВАН

### Т4 — MikoPBX
Проверяется: импорт образа, запуск контейнера, служба, баннер готовности,
веб-интерфейс (с агента и с хоста через hostfwd), REST API login (v3,
localhost bypass), автозапуск и сохранение данных после reboot.
- Статус: ЗАПЛАНИРОВАН

### Т5 — Offline
Проверяется: установка и работа без сетевых устройств (`-nic` отсутствует).
- Статус: ЗАПЛАНИРОВАН

### Т6 — Btrfs
Проверяется: subvolumes, монтирование, создание и список снапшотов.
- Статус: ЗАПЛАНИРОВАН

### Т7 — Ошибки
- Т7a несуществующий диск → отказ установщика.
- Т7b диск 20 GiB (< 50 GiB) → отказ.
- Т7c несоответствие SHA256 payload → отказ до разметки.
- Т7d установка без сетевого интерфейса → успех.
- Статус: ЗАПЛАНИРОВАН

## Не автоматизируется в v1 (ручные сценарии)

- Интерактивный TUI-мастер (прохождение экранов вручную на железе/ВМ).
- Установка на реальный SATA/NVMe диск (прогон на физическом устройстве).
- Проверка SIP-регистрации/звонка (требуется SIP-клиент/транк).
- Загрузка Legacy BIOS (не поддерживается в v1).
- Secure Boot (не входит в v1).

## Последний прогон

(заполняется после выполнения `bash scripts/test-qemu.sh all`: дата, ISO,
итог по каждому тесту, ссылки на логи)

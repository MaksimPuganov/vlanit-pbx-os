# tools/ — инструменты сборочной машины

Бинарники в git **не хранятся**. Этот каталог заполняется локально:

```bash
bash tools/fetch-tools.sh   # скачать .deb и распаковать в tools/root (без root)
```

Список пакетов (Debian 13 trixie, amd64) — в `fetch-tools.sh`:

| Пакет | Назначение |
|---|---|
| mmdebstrap | сборка Golden/Live rootfs |
| xorriso + libisoburn1t64 | создание ISO |
| squashfs-tools | squashfs Live-окружения |
| ovmf | UEFI-прошивка (OVMF_CODE/VARS) для QEMU-тестов |

`tools/debs/` и `tools/root/` — в `.gitignore`.

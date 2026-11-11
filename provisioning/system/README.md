# System Provisioning

Отвечает за hostname, network, административные учётные записи, SSH,
системные параметры, каталоги хранения, Btrfs и диагностику.

Реализация: часть `system:` схемы в `provisioning/vlanit-provision`
(валидация + применение hostname/network), сетевая конфигурация —
systemd-networkd-файлы, генерируемые установщиком (`installer/lib/network.sh`).

Запуск вручную на установленной системе:
    python3 /opt/vlanit/provisioning/vlanit-provision /path/config.yaml

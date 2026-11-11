# Podman Provisioning

Контейнерный runtime: rootful Podman, systemd Quadlet.

- Юнит: `quadlet/mikopbx.container` → `/etc/containers/systemd/mikopbx.container`
- Внешние registry отключены: `rootfs/etc-containers-registries.conf`
- Идемпорт payload: `rootfs/vlanit-firstboot.sh`, `installer/lib/deploy.sh`

Запуск вручную: `systemctl restart mikopbx`, `podman logs mikopbx`.

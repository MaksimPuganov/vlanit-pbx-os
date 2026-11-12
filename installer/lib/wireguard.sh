# WireGuard: преднастройка при установке.
# Генерирует уникальную пару ключей устройства, wg0.conf,
# включает wg-quick@wg0 и форвардинг IPv4.
WG_CONF_DIR="etc/wireguard"

configure_target_wireguard() {
    local address="$1" listen_port="$2"
    shift 2
    local peers_file="${1:-}"   # опциональный файл с [Peer]-блоками (autoinstall)

    log "WireGuard: генерация ключей и wg0.conf"
    chroot "$SYS_MNT" /bin/sh -c "
        mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
        umask 077
        wg genkey > /etc/wireguard/privatekey
        wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey
    " || die "WireGuard: генерация ключей не удалась"

    local priv
    priv="$(cat "$SYS_MNT/$WG_CONF_DIR/privatekey")"
    cat > "$SYS_MNT/$WG_CONF_DIR/wg0.conf" <<EOF
# VLANit PBX OS — WireGuard (создано установщиком)
[Interface]
PrivateKey = $priv
Address = $address
ListenPort = $listen_port

# Peers добавляйте вручную или через provisioning, например:
# [Peer]
# PublicKey = <публичный ключ пира>
# AllowedIPs = 10.66.66.2/32
EOF
    if [ -n "$peers_file" ] && [ -s "$peers_file" ]; then
        cat "$peers_file" >> "$SYS_MNT/$WG_CONF_DIR/wg0.conf"
    fi
    chmod 600 "$SYS_MNT/$WG_CONF_DIR/wg0.conf"
    rm -f "$SYS_MNT/$WG_CONF_DIR/privatekey"

    # форвардинг (нужен для маршрутизации трафика пиров)
    cat > "$SYS_MNT/etc/sysctl.d/99-vlanit-wireguard.conf" <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    chroot "$SYS_MNT" systemctl enable wg-quick@wg0.service || \
        die "WireGuard: не удалось включить wg-quick@wg0"
    log "WireGuard: wg0 ($address, порт $listen_port) настроен"
}

wireguard_pubkey() {
    cat "$SYS_MNT/$WG_CONF_DIR/publickey" 2>/dev/null || true
}

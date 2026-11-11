# Настройка сети: выбор интерфейса, DHCP/static; конфиг для установленной системы.
list_interfaces() {
    ip -o link show | awk -F': ' '$2 != "lo" && $2 !~ /^docker|^veth/ {print $2}'
}

iface_mac() {
    cat "/sys/class/net/$1/address" 2>/dev/null
}

# Применить конфиг к живой среде (чтобы post-install проверки работали)
apply_live_network() {
    local ifname="$1" mode="$2" address="$3" gateway="$4" dns="$5"
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/10-vlanit-installer.network <<EOF
[Match]
Name=$ifname

[Network]
EOF
    if [ "$mode" = "dhcp" ]; then
        echo "DHCP=yes" >> /etc/systemd/network/10-vlanit-installer.network
    else
        {
            echo "Address=$address"
            echo "Gateway=$gateway"
            for d in $dns; do echo "DNS=$d"; done
        } >> /etc/systemd/network/10-vlanit-installer.network
    fi
    systemctl restart systemd-networkd 2>/dev/null || true
}

# Записать конфиг в установленную систему (привязка по MAC — защита от переименования)
write_target_network() {
    local target="$1" ifname="$2" mode="$3" address="$4" gateway="$5" dns="$6"
    local mac
    mac="$(iface_mac "$ifname")"
    [ -n "$mac" ] || die "не найден MAC адрес интерфейса $ifname"
    mkdir -p "$target/etc/systemd/network"
    {
        echo "[Match]"
        echo "MACAddress=$mac"
        echo
        echo "[Network]"
        if [ "$mode" = "dhcp" ]; then
            echo "DHCP=yes"
        else
            echo "Address=$address"
            echo "Gateway=$gateway"
            for d in $dns; do echo "DNS=$d"; done
        fi
    } > "$target/etc/systemd/network/10-vlanit.network"
}

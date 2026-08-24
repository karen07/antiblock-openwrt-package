#!/bin/ash
set -eu

: "${E2E_IP:?}"
: "${E2E_GATEWAY:?}"

# procd must never open the host's hardware watchdog from an E2E container.
if [ -e /dev/watchdog ] || [ -e /dev/watchdog0 ]; then
    echo "E2E refused: hardware watchdog is visible in container" >&2
    exit 1
fi

cat > /etc/config/network <<EONET
config interface 'loopback'
        option device 'lo'
        option proto 'static'
        option ipaddr '127.0.0.1'
        option netmask '255.0.0.0'

config interface 'lan'
        option device 'eth0'
        option proto 'static'
        option ipaddr '$E2E_IP'
        option netmask '255.255.255.0'
        option gateway '$E2E_GATEWAY'
        list dns '1.1.1.1'
EONET

# The E2E network has no DHCP clients; keep dnsmasq DNS service only.
# Avoid dnsmasq probing for another DHCP server with udhcpc.
uci -q set dhcp.lan.ignore='1'
uci -q commit dhcp

exec /sbin/init

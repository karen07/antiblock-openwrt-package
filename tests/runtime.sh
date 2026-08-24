#!/bin/sh
set -u

: "${OPENWRT_CONTAINER:?}"
: "${DNS_CONTAINER:?}"
: "${OPENWRT_IP:?}"
: "${DNS_IP:?}"
: "${NETWORK_GATEWAY:?}"
: "${PKG_VERSION:?}"

PASS=0

ow() {
    docker exec "$OPENWRT_CONTAINER" /bin/ash -ec "$1"
}

pass() {
    PASS=$((PASS + 1))
    printf '[PASS] %02d %s\n' "$PASS" "$1"
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    printf '\n--- OpenWrt log ---\n' >&2
    docker exec "$OPENWRT_CONTAINER" logread 2>/dev/null | tail -n 150 >&2 || true
    printf '\n--- routes ---\n' >&2
    docker exec "$OPENWRT_CONTAINER" ip route show >&2 || true
    printf '\n--- AntiBlock service ---\n' >&2
    docker exec "$OPENWRT_CONTAINER" \
        ubus call service list '{"name":"antiblock"}' >&2 || true
    exit 1
}

wait_process() {
    wp_attempt=0
    while [ "$wp_attempt" -lt 30 ]; do
        if ow 'pidof antiblock >/dev/null 2>&1'; then
            return 0
        fi
        wp_attempt=$((wp_attempt + 1))
        sleep 0.25
    done
    return 1
}

wait_new_pid() {
    wnp_old=$1
    wnp_name=${2:-antiblock}
    wnp_attempt=0
    while [ "$wnp_attempt" -lt 80 ]; do
        wnp_new=$(ow "pidof $wnp_name 2>/dev/null || true" | tr -d '\r\n')
        if [ -n "$wnp_new" ] && [ "$wnp_new" != "$wnp_old" ]; then
            printf '%s\n' "$wnp_new"
            return 0
        fi
        wnp_attempt=$((wnp_attempt + 1))
        sleep 0.25
    done
    return 1
}

wait_route_contains() {
    wrc_ip=$1
    shift
    wrc_attempt=0
    wrc_out=

    while [ "$wrc_attempt" -lt 40 ]; do
        wrc_out=$(ow "ip route show $wrc_ip 2>/dev/null || true")
        wrc_ok=1
        for wrc_needle in "$@"; do
            case "$wrc_out" in
                *"$wrc_needle"*) ;;
                *) wrc_ok=0 ;;
            esac
        done
        [ "$wrc_ok" -eq 1 ] && return 0
        wrc_attempt=$((wrc_attempt + 1))
        sleep 0.25
    done

    printf 'route for %s: %s\n' "$wrc_ip" "$wrc_out" >&2
    return 1
}

wait_no_route() {
    wnr_ip=$1
    wnr_attempt=0
    wnr_out=

    while [ "$wnr_attempt" -lt 40 ]; do
        wnr_out=$(ow "ip route show $wnr_ip 2>/dev/null || true")
        [ -z "$wnr_out" ] && return 0
        wnr_attempt=$((wnr_attempt + 1))
        sleep 0.25
    done

    printf 'route still exists for %s: %s\n' "$wnr_ip" "$wnr_out" >&2
    return 1
}

send_dns() {
    docker exec "$DNS_CONTAINER" \
        python /tests/dns-send.py "$1" "$2" "$OPENWRT_IP" 53000 || return 1
    sleep 0.15
}

write_file() {
    wf_path=$1
    wf_data=$2
    printf '%s\n' "$wf_data" | docker exec -i "$OPENWRT_CONTAINER" \
        /bin/ash -c "mkdir -p \"\$(dirname '$wf_path')\"; cat > '$wf_path'"
}

write_config() {
    docker exec -i "$OPENWRT_CONTAINER" \
        /bin/ash -c 'cat > /etc/config/antiblock' || fail 'cannot write UCI config'
}

stop_ab() {
    ow '/etc/init.d/antiblock stop >/dev/null 2>&1 || true'
    sleep 0.3
}

ow "antiblock --help | grep -F 'AntiBlock $PKG_VERSION' >/dev/null" \
    || fail 'binary version/help check'
pass "binary is AntiBlock $PKG_VERSION"

ow 'test -x /etc/init.d/antiblock && test -f /etc/config/antiblock' \
    || fail 'package files missing'
pass 'package installed init script and UCI config'

stop_ab
write_config <<EOF_CFG
config main 'config'
        option enabled '0'
        option listen '$DNS_IP:53'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'disabled service start command failed'
sleep 0.5
if ow 'pidof antiblock >/dev/null 2>&1'; then
    fail 'disabled service started a process'
fi
pass 'disabled UCI config does not start AntiBlock'

# Preflight rejects enabled services without a usable routing rule. The
# rc.common/procd wrapper can mask start_service()'s return status, so verify
# the daemon was not started and the error was sent to the system log.
expect_rejected_route_config() {
    err_label=$1
    err_message='No enabled route with both interface (or gateway) and domains_path'
    err_before=$(ow "logread | grep -Fc '$err_message' || true" | tr -d '\r\n')
    ow '/etc/init.d/antiblock start >/dev/null 2>&1 || true' \
        || fail "$err_label: init script could not be invoked"
    sleep 0.2
    if ow 'pidof antiblock >/dev/null 2>&1'; then
        fail "$err_label: invalid configuration started AntiBlock"
    fi
    err_after=$(ow "logread | grep -Fc '$err_message' || true" | tr -d '\r\n')
    [ "$err_after" -gt "$err_before" ] \
        || fail "$err_label: missing daemon.err log entry"
    pass "$err_label"
}

write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'
EOF_CFG
expect_rejected_route_config 'enabled service without route sections is rejected'

write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'lo'
EOF_CFG
expect_rejected_route_config 'route without domains_path is rejected'

write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option domains_path '/etc/antiblock/l2.txt'
EOF_CFG
expect_rejected_route_config 'route without interface or gateway is rejected'

write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option enabled '0'
        option interface 'lo'
        option domains_path '/etc/antiblock/l2.txt'
EOF_CFG
expect_rejected_route_config 'all-disabled route sections are rejected'

# An incomplete section must not prevent another usable rule from starting.
write_file /etc/antiblock/preflight.txt 'preflight.test' \
    || fail 'cannot create preflight domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'lo'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/preflight.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start with one usable route'
wait_process || fail 'usable route did not start AntiBlock'
send_dns preflight.test 11.22.33.55 || fail 'cannot send preflight DNS response'
wait_route_contains 11.22.33.55 'dev lo' 'metric 23117' \
    || fail 'usable route did not install host route'
pass 'usable route starts despite another incomplete route section'
stop_ab

write_file /etc/antiblock/l2.txt 'l2.test' || fail 'cannot create L2 domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'eth0'
        option domains_path '/etc/antiblock/l2.txt'
EOF_CFG
ow '/etc/init.d/antiblock restart' || fail 'cannot restart L2 service'
wait_process || fail 'L2 service did not start'
send_dns l2.test 11.22.33.10 || fail 'cannot send L2 DNS response'
wait_route_contains 11.22.33.10 \
    "via $NETWORK_GATEWAY" 'dev eth0' 'metric 23117' \
    || fail 'L2 route not installed'
pass 'L2 rule installs /32 through eth0 default gateway'

ow '/etc/init.d/antiblock stop' || fail 'cannot stop L2 service'
wait_no_route 11.22.33.10 || fail 'route cleanup after stop'
pass 'stop removes AntiBlock route'

write_file /etc/antiblock/l3.txt 'l3.test' || fail 'cannot create L3 domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/l3.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start L3 service'
wait_process || fail 'L3 service did not start'
send_dns l3.test 11.22.33.11 || fail 'cannot send L3 DNS response'
wait_route_contains 11.22.33.11 'dev lo' 'metric 23117' \
    || fail 'L3 route not installed'
pass 'L3 rule installs /32 directly on non-Ethernet interface'
stop_ab

write_file /etc/antiblock/legacy.txt 'legacy.test' \
    || fail 'cannot create legacy domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option gateway 'lo'
        option domains_path '/etc/antiblock/legacy.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start legacy service'
wait_process || fail 'legacy gateway service did not start'
send_dns legacy.test 11.22.33.12 || fail 'cannot send legacy DNS response'
wait_route_contains 11.22.33.12 'dev lo' 'metric 23117' \
    || fail 'legacy gateway compatibility failed'
pass 'legacy gateway UCI key remains compatible'
stop_ab

write_file /etc/antiblock/move-l2.txt 'move-a.test' \
    || fail 'cannot create move L2 domain file'
write_file /etc/antiblock/move-l3.txt 'move-b.test' \
    || fail 'cannot create move L3 domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'eth0'
        option domains_path '/etc/antiblock/move-l2.txt'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/move-l3.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start move service'
wait_process || fail 'move service did not start'
send_dns move-a.test 11.22.33.13 || fail 'cannot send first move DNS response'
wait_route_contains 11.22.33.13 "via $NETWORK_GATEWAY" 'dev eth0' \
    || fail 'initial move route missing'
send_dns move-b.test 11.22.33.13 || fail 'cannot send second move DNS response'
wait_route_contains 11.22.33.13 'dev lo' 'metric 23117' \
    || fail 'route did not move to second rule'
if ow "ip route show 11.22.33.13 | grep -F 'via $NETWORK_GATEWAY' >/dev/null"; then
    fail 'old route remained after move'
fi
pass 'same destination moves between UCI route rules'
stop_ab

write_file /etc/antiblock/blacklist.txt 'blacklist.test' \
    || fail 'cannot create blacklist domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'
        list blacklist '11.22.34.0/24'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/blacklist.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start blacklist service'
wait_process || fail 'blacklist service did not start'
send_dns blacklist.test 11.22.34.20 || fail 'cannot send blacklist DNS response'
sleep 0.3
wait_no_route 11.22.34.20 || fail 'custom UCI blacklist did not block route'
pass 'UCI blacklist is materialized and enforced'

# Changing only blacklist content keeps the AntiBlock command unchanged.
# procd must use the UCI file checksum to restart the service on reload.
OLD_PID=$(ow 'pidof antiblock' | tr -d '\r\n')
[ -n "$OLD_PID" ] || fail 'AntiBlock PID missing before blacklist reload'
ow "uci -q delete antiblock.config.blacklist; \
    uci add_list antiblock.config.blacklist='11.22.35.0/24'; \
    uci commit antiblock" || fail 'cannot update UCI blacklist for reload'
ow '/etc/init.d/antiblock reload' || fail 'cannot reload after blacklist update'
NEW_PID=$(wait_new_pid "$OLD_PID") || fail 'blacklist-only reload did not restart AntiBlock'
send_dns blacklist.test 11.22.35.20 || fail 'cannot send newly blacklisted DNS response'
wait_no_route 11.22.35.20 || fail 'new blacklist was not applied after reload'
send_dns blacklist.test 11.22.34.20 || fail 'cannot send formerly blacklisted DNS response'
wait_route_contains 11.22.34.20 'dev lo' 'metric 23117' \
    || fail 'old blacklist remains active after reload'
pass 'blacklist-only UCI change applies through procd reload'
stop_ab

write_file /etc/antiblock/test-mode.txt 'test-mode.test' \
    || fail 'cannot create test-mode domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'
        option test '1'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/test-mode.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start test-mode service'
wait_process || fail 'test-mode service did not start'
send_dns test-mode.test 11.22.33.14 || fail 'cannot send test-mode DNS response'
sleep 0.3
wait_no_route 11.22.33.14 || fail '--test modified kernel routes'
pass 'UCI test=1 maps to --test and leaves kernel routes untouched'
stop_ab

write_file /etc/antiblock/telemetry.txt 'telemetry.test' \
    || fail 'cannot create telemetry domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'
        option log '1'
        option stat '1'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/telemetry.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start telemetry service'
wait_process || fail 'telemetry service did not start'
send_dns telemetry.test 11.22.33.15 || fail 'cannot send telemetry DNS response'
wait_route_contains 11.22.33.15 'dev lo' || fail 'telemetry route not installed'
ow '/etc/init.d/antiblock stop' || fail 'cannot stop telemetry service'
ow 'test -s /tmp/antiblock/log.txt && test -s /tmp/antiblock/stat.txt' \
    || fail 'log/stat files missing or empty'
pass 'UCI log/stat options create telemetry files'

write_file /etc/antiblock/respawn.txt 'respawn.test' \
    || fail 'cannot create respawn domain file'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/respawn.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start respawn service'
wait_process || fail 'respawn service did not start'
OLD_PID=$(ow 'pidof antiblock' | tr -d '\r\n')
[ -n "$OLD_PID" ] || fail 'AntiBlock PID is empty'
ow "kill -9 $OLD_PID" || fail 'cannot kill AntiBlock process'
NEW_PID=$(wait_new_pid "$OLD_PID") || fail 'procd did not respawn AntiBlock'
[ "$NEW_PID" != "$OLD_PID" ] || fail 'respawn PID did not change'
pass 'procd respawns AntiBlock after SIGKILL'
stop_ab

ow '/etc/init.d/dnsmasq stop >/dev/null 2>&1 || true'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/respawn.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start with dnsmasq stopped'
wait_process || fail 'service did not start with dnsmasq stopped'
sleep 0.5
if ow 'pidof dnsmasq >/dev/null 2>&1'; then
    fail 'AntiBlock unexpectedly started stopped dnsmasq'
fi
pass 'starting AntiBlock does not start a stopped dnsmasq'
stop_ab

ow '/etc/init.d/dnsmasq start' || fail 'cannot start dnsmasq'
dnsmasq_started=0
attempt=0
while [ "$attempt" -lt 30 ]; do
    if ow 'pidof dnsmasq >/dev/null 2>&1'; then
        dnsmasq_started=1
        break
    fi
    attempt=$((attempt + 1))
    sleep 0.2
done
[ "$dnsmasq_started" -eq 1 ] || fail 'dnsmasq did not start'

DNSMASQ_OLD=$(ow 'pidof dnsmasq 2>/dev/null || true' | tr -d '\r\n')
[ -n "$DNSMASQ_OLD" ] || fail 'dnsmasq PID is empty'
ow '/etc/init.d/antiblock start' || fail 'cannot start with dnsmasq running'
wait_process || fail 'service did not start with dnsmasq running'
wait_new_pid "$DNSMASQ_OLD" dnsmasq >/dev/null \
    || fail 'AntiBlock did not restart running dnsmasq'
pass 'starting AntiBlock restarts running dnsmasq to clear its cache'
stop_ab

# Disabled UCI route entries must not be passed to the daemon.
write_file /etc/antiblock/route-on.txt 'route-on.test' || fail 'cannot create active domain file'
if ! write_file /etc/antiblock/route-off.txt 'route-off.test'; then
    fail 'cannot create disabled domain file'
fi
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$DNS_IP:53'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/route-on.txt'

config route
        option enabled '0'
        option interface 'lo'
        option domains_path '/etc/antiblock/route-off.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start with disabled UCI route'
wait_process || fail 'service did not start with disabled UCI route'
send_dns route-on.test 11.22.33.16 || fail 'cannot send active route DNS response'
wait_route_contains 11.22.33.16 'dev lo' || fail 'enabled UCI route did not install route'
send_dns route-off.test 11.22.33.17 || fail 'cannot send disabled route DNS response'
wait_no_route 11.22.33.17 || fail 'disabled UCI route installed kernel route'
pass 'disabled UCI route is ignored while enabled route works'

# Keep AntiBlock running to test restarting an active procd instance.
# A committed change of domain source must take effect after service restart.
if ! write_file /etc/antiblock/route-new.txt 'route-new.test'; then
    fail 'cannot create replacement domain file'
fi
ow "uci set antiblock.@route[0].domains_path='/etc/antiblock/route-new.txt'; uci commit antiblock" \
    || fail 'cannot update UCI route source'
ow '/etc/init.d/antiblock restart' || fail 'cannot restart after UCI update'
wait_process || fail 'service did not restart after UCI update'
send_dns route-new.test 11.22.33.18 || fail 'cannot send updated route DNS response'
wait_route_contains 11.22.33.18 'dev lo' || fail 'updated UCI route source was not loaded'
send_dns route-on.test 11.22.33.19 || fail 'cannot send obsolete source DNS response'
wait_no_route 11.22.33.19 || fail 'obsolete UCI source is still active'
pass 'committed UCI source update applies after service restart'

# A committed UCI source change must also apply through procd reload.
write_file /etc/antiblock/route-reload.txt 'route-reload.test' \
    || fail 'cannot create reload domain file'
OLD_PID=$(ow 'pidof antiblock' | tr -d '\r\n')
[ -n "$OLD_PID" ] || fail 'AntiBlock PID missing before reload'
ow "uci set antiblock.@route[0].domains_path='/etc/antiblock/route-reload.txt'" \
    || fail 'cannot update UCI route source for reload'
ow 'uci commit antiblock' || fail 'cannot commit UCI route source for reload'
ow '/etc/init.d/antiblock reload' || fail 'cannot reload after UCI update'
NEW_PID=$(wait_new_pid "$OLD_PID") || fail 'procd did not restart AntiBlock on reload'
wait_no_route 11.22.33.18 || fail 'old route was not removed after reload'
send_dns route-reload.test 11.22.33.20 || fail 'cannot send reloaded DNS response'
wait_route_contains 11.22.33.20 'dev lo' || fail 'reloaded UCI source was not applied'
send_dns route-new.test 11.22.33.21 || fail 'cannot send old DNS response after reload'
wait_no_route 11.22.33.21 || fail 'previous UCI source is still active after reload'
pass 'committed UCI source update applies after service reload'
stop_ab

# The UCI limit must match AB_MAX_RULES (32): 32 active routes may start.
write_file /etc/antiblock/max-routes.txt 'max-routes.test' \
    || fail 'cannot create max route domain file'
{
    printf "config main 'config'\n"
    printf "        option enabled '1'\n"
    printf "        option listen '%s:53'\n" "$DNS_IP"
    max_index=0
    while [ "$max_index" -lt 32 ]; do
        printf '\nconfig route\n'
        printf "        option interface 'lo'\n"
        printf "        option domains_path '/etc/antiblock/max-routes.txt'\n"
        max_index=$((max_index + 1))
    done
} | write_config
ow '/etc/init.d/antiblock start' || fail '32-route service start failed'
wait_process || fail '32 valid UCI routes did not start AntiBlock'
pass '32 enabled UCI routes are accepted'
stop_ab

# Use a forwarded domain: dnsmasq handles the .test zone locally.
# Starting AntiBlock must flush an already warm dnsmasq cache via restart.
CACHE_DOMAIN='cached.antiblock-e2e.example.org'
stop_ab
ow "uci -q set dhcp.@dnsmasq[0].noresolv='1'" \
    || fail 'cannot set dnsmasq noresolv'
ow "uci -q add_list dhcp.@dnsmasq[0].server='$DNS_IP#5300'" \
    || fail 'cannot set dnsmasq test upstream'
ow 'uci commit dhcp; /etc/init.d/dnsmasq restart' \
    || fail 'cannot configure dnsmasq upstream'
DNSMASQ_OLD=$(ow 'pidof dnsmasq 2>/dev/null || true' | tr -d '\r\n')
[ -n "$DNSMASQ_OLD" ] || fail 'dnsmasq not running before cache test'
docker exec -d "$DNS_CONTAINER" \
    python -u /tests/dns-cache.py serve "$CACHE_DOMAIN" 11.22.33.51 /tmp/cache-query-count \
    || fail 'cannot start upstream DNS responder'
sleep 0.3
docker exec "$DNS_CONTAINER" \
    python /tests/dns-cache.py query "$OPENWRT_IP" "$CACHE_DOMAIN" 11.22.33.51 \
    || fail 'cannot warm dnsmasq cache'
CACHE_COUNT_OLD=$(docker exec "$DNS_CONTAINER" \
    /bin/sh -c 'wc -l </tmp/cache-query-count' | tr -d '[:space:]')
[ "$CACHE_COUNT_OLD" -gt 0 ] || fail 'dnsmasq did not use test upstream'
docker exec "$DNS_CONTAINER" \
    python /tests/dns-cache.py query "$OPENWRT_IP" "$CACHE_DOMAIN" 11.22.33.51 \
    || fail 'cannot query warm dnsmasq cache'
CACHE_COUNT_WARM=$(docker exec "$DNS_CONTAINER" \
    /bin/sh -c 'wc -l </tmp/cache-query-count' | tr -d '[:space:]')
[ "$CACHE_COUNT_WARM" = "$CACHE_COUNT_OLD" ] \
    || fail 'dnsmasq cache was not warm before AntiBlock startup'
write_file /etc/antiblock/cached.txt "$CACHE_DOMAIN" \
    || fail 'cannot create cached domain source'
write_config <<EOF_CFG
config main 'config'
        option enabled '1'
        option listen '$OPENWRT_IP:53'

config route
        option interface 'lo'
        option domains_path '/etc/antiblock/cached.txt'
EOF_CFG
ow '/etc/init.d/antiblock start' || fail 'cannot start cache test service'
wait_process || fail 'cache test service did not start'
wait_new_pid "$DNSMASQ_OLD" dnsmasq >/dev/null \
    || fail 'AntiBlock did not restart dnsmasq for cache reset'
docker exec "$DNS_CONTAINER" \
    python /tests/dns-cache.py query "$OPENWRT_IP" "$CACHE_DOMAIN" 11.22.33.51 \
    || fail 'cannot query dnsmasq after cache reset'
wait_route_contains 11.22.33.51 'dev lo' 'metric 23117' \
    || fail 'DNS answer after cache reset did not create a route'
CACHE_COUNT_NEW=$(docker exec "$DNS_CONTAINER" \
    /bin/sh -c 'wc -l </tmp/cache-query-count' | tr -d '[:space:]')
[ "$CACHE_COUNT_NEW" -gt "$CACHE_COUNT_WARM" ] \
    || fail 'dnsmasq cache was not cleared by AntiBlock startup'
pass 'starting AntiBlock flushes warm dnsmasq cache and routes fresh DNS replies'
stop_ab

printf '\n%d runtime tests passed\n' "$PASS"

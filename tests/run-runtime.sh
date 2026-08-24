#!/bin/sh
set -u

ROOT_DIR=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
TEST_DIR="$ROOT_DIR/tests"
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"
ROOTFS_IMAGE="${OPENWRT_ROOTFS_IMAGE:-ghcr.io/openwrt/rootfs:x86_64-$OPENWRT_VERSION}"
RUNTIME_IMAGE="antiblock-openwrt-runtime:$OPENWRT_VERSION-$$"
OPENWRT_FILE_HOST="${OPENWRT_FILE_HOST:-https://downloads.openwrt.org}"
INDEX_URL="$OPENWRT_FILE_HOST/releases/$OPENWRT_VERSION/targets/x86/64/packages/packages.adb"

NETWORK_NAME="antiblock-e2e-$$"
NETWORK_SUBNET="172.31.77.0/24"
NETWORK_GATEWAY="172.31.77.1"
OPENWRT_IP="172.31.77.2"
DNS_IP="172.31.77.53"
STAGE_CONTAINER="antiblock-openwrt-stage-$$"
OPENWRT_CONTAINER="antiblock-openwrt-e2e-$$"
DNS_CONTAINER="antiblock-dns-e2e-$$"

cleanup() {
    docker rm -f "$DNS_CONTAINER" "$OPENWRT_CONTAINER" >/dev/null 2>&1 || true
    docker rm -f "$STAGE_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
    docker image rm "$RUNTIME_IMAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

fail() {
    printf '\n[FAIL] %s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

stage_debug() {
    printf '\n--- staging network ---\n' >&2
    docker exec "$STAGE_CONTAINER" ip addr show >&2 || true
    docker exec "$STAGE_CONTAINER" ip route show >&2 || true
    printf '\n--- staging resolv.conf ---\n' >&2
    docker exec "$STAGE_CONTAINER" cat /etc/resolv.conf >&2 || true
}

APK=
IFS= read -r APK || true
[ -n "$APK" ] || fail "APK path was not received on stdin"
[ -f "$APK" ] || fail "APK not found: $APK"

EXTRA=
if IFS= read -r EXTRA; then
    fail "more than one APK path received on stdin: $EXTRA"
fi

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$ROOT_DIR/antiblock/Makefile" | head -n 1)
[ -n "$PKG_VERSION" ] || fail "cannot read PKG_VERSION"

need docker
docker info >/dev/null 2>&1 || fail "Docker daemon is not available"

printf '\n[PASS] package build produced: %s\n' "$APK"
printf '\n========================================\n'
printf 'PREPARE OPENWRT DOCKER ROOTFS\n'
printf 'OpenWrt: %s x86/64\n' "$OPENWRT_VERSION"
printf '========================================\n\n'

if ! docker image inspect "$ROOTFS_IMAGE" >/dev/null 2>&1; then
    printf '[INFO] Pulling official OpenWrt Docker rootfs\n'
    printf '       Image: %s\n' "$ROOTFS_IMAGE"

    docker pull --platform linux/amd64 "$ROOTFS_IMAGE" \
        || fail "cannot pull official OpenWrt rootfs"
else
    printf '[PASS] cached official OpenWrt Docker rootfs found\n'
fi

# Install packages before starting procd. The official Docker rootfs removes its
# static resolv.conf so Docker can inject working DNS into this staging phase.
docker run -d \
    --name "$STAGE_CONTAINER" \
    "$ROOTFS_IMAGE" \
    /bin/ash -c 'while :; do sleep 3600; done' >/dev/null \
    || fail "cannot start OpenWrt staging container"

stage_running=0
attempt=0
while [ "$attempt" -lt 20 ]; do
    if docker exec "$STAGE_CONTAINER" true >/dev/null 2>&1; then
        stage_running=1
        break
    fi
    attempt=$((attempt + 1))
    sleep 0.25
done
[ "$stage_running" -eq 1 ] || fail "OpenWrt staging container did not start"

if ! docker exec "$STAGE_CONTAINER" /bin/ash -ec "
    test -s /etc/resolv.conf
    wget -q -O /tmp/openwrt-index '$INDEX_URL'
    test -s /tmp/openwrt-index
    rm -f /tmp/openwrt-index
"; then
    stage_debug
    fail "official OpenWrt Docker rootfs has no repository access"
fi
printf '[PASS] official OpenWrt Docker rootfs has Internet access\n'

docker cp "$APK" "$STAGE_CONTAINER:/tmp/antiblock.apk" \
    || fail "cannot copy APK into OpenWrt staging container"

if ! docker exec "$STAGE_CONTAINER" /bin/ash -ec '
    mkdir -p /var/lock
    apk update
    apk add dnsmasq
    apk add --allow-untrusted /tmp/antiblock.apk
    antiblock --help >/dev/null

    # OpenWrt dnsmasq uses procd/ujail by default. An unprivileged Docker
    # container cannot create the namespaces required by ujail, causing
    # "jail: failed to clone/fork: Operation not permitted". Disable only
    # the dnsmasq jail setup in this disposable E2E image; keep the package
    # init script and the real procd service lifecycle untouched.
    if ! grep -q "procd_add_jail dnsmasq" /etc/init.d/dnsmasq; then
        echo "missing expected dnsmasq procd jail configuration" >&2
        exit 1
    fi
    sed -i "s/procd_add_jail/: &/g" /etc/init.d/dnsmasq

    rm -f /tmp/antiblock.apk
'; then
    stage_debug
    fail "cannot install APK and dependencies in staging container"
fi
printf '[PASS] APK installed with dependencies before OpenWrt boot\n'
printf '[PASS] dnsmasq ujail disabled in disposable Docker runtime only\n'

docker commit "$STAGE_CONTAINER" "$RUNTIME_IMAGE" >/dev/null \
    || fail "cannot create prepared OpenWrt runtime image"
docker rm -f "$STAGE_CONTAINER" >/dev/null \
    || fail "cannot remove OpenWrt staging container"
printf '[PASS] prepared OpenWrt runtime image created\n'

docker network create \
    --internal \
    --subnet "$NETWORK_SUBNET" \
    --gateway "$NETWORK_GATEWAY" \
    "$NETWORK_NAME" >/dev/null || fail "cannot create Docker network"

docker run -d \
    --name "$OPENWRT_CONTAINER" \
    --hostname openwrt-antiblock-e2e \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --cap-drop MKNOD \
    --network "$NETWORK_NAME" \
    --ip "$OPENWRT_IP" \
    --volume "$TEST_DIR:/tests:ro" \
    -e E2E_IP="$OPENWRT_IP" \
    -e E2E_GATEWAY="$NETWORK_GATEWAY" \
    "$RUNTIME_IMAGE" \
    /bin/ash /tests/openwrt-init.sh >/dev/null || fail "cannot start OpenWrt"

booted=0
attempt=0
while [ "$attempt" -lt 60 ]; do
    if docker exec "$OPENWRT_CONTAINER" \
        ubus call system board >/dev/null 2>&1; then
        booted=1
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done

if [ "$booted" -ne 1 ]; then
    docker logs "$OPENWRT_CONTAINER" >&2 || true
    fail "OpenWrt did not finish booting"
fi
printf '[PASS] OpenWrt booted with procd/ubus\n'

docker exec "$OPENWRT_CONTAINER" /bin/ash -ec '
    command -v antiblock >/dev/null
    command -v dnsmasq >/dev/null
    test -x /etc/init.d/antiblock
' || fail "prepared packages are missing after OpenWrt boot"
printf '[PASS] prepared packages are present after boot\n'

docker run -d \
    --name "$DNS_CONTAINER" \
    --network "$NETWORK_NAME" \
    --ip "$DNS_IP" \
    --volume "$TEST_DIR:/tests:ro" \
    python:3.12-alpine \
    sleep infinity >/dev/null || fail "cannot start DNS test container"

export OPENWRT_CONTAINER DNS_CONTAINER OPENWRT_IP DNS_IP NETWORK_GATEWAY PKG_VERSION
"$TEST_DIR/runtime.sh" || fail "OpenWrt runtime tests failed"

printf '\n========================================\n'
printf 'ALL OPENWRT PACKAGE E2E TESTS PASSED\n'
printf 'APK: %s\n' "$APK"
printf '========================================\n'

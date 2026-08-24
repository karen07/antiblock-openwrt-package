#!/bin/sh
set -u

ROOT_DIR=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
TEST_DIR="$ROOT_DIR/tests"
ARTIFACT_DIR="$TEST_DIR/.artifacts"
PARENT_DIR=$(dirname "$ROOT_DIR")
DEFAULT_BUILD_SH="$PARENT_DIR/openwrt-package-ci/openwrt-build.sh"
BUILD_SH="${OPENWRT_BUILD_SH:-$DEFAULT_BUILD_SH}"
LOCAL_BUILD_SH="$ROOT_DIR/.openwrt-build-e2e.sh"
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"

cleanup() {
    rm -f "$LOCAL_BUILD_SH"
}
trap cleanup EXIT INT TERM

fail() {
    printf '\n[FAIL] %s\n' "$*" >&2
    exit 1
}

[ -f "$ROOT_DIR/antiblock/Makefile" ] \
    || fail "run this test from the antiblock-openwrt-package repository"
[ -f "$ROOT_DIR/openwrt-build.env" ] || fail "openwrt-build.env not found"
[ -f "$BUILD_SH" ] || fail "openwrt-build.sh not found: $BUILD_SH"

mkdir -p "$ARTIFACT_DIR" || fail "cannot create artifact directory"
rm -f "$ARTIFACT_DIR"/antiblock_*.apk "$ARTIFACT_DIR"/antiblock-*.apk

printf '\n========================================\n'
printf 'BUILD OPENWRT PACKAGE\n'
printf 'OpenWrt: %s x86/64\n' "$OPENWRT_VERSION"
printf 'Builder: %s\n' "$BUILD_SH"
printf '========================================\n\n'

# The shared builder resolves openwrt-build.env and package directories next
# to $0. The real CI copies it into the package repository before execution;
# do the same locally so the exact same build path is exercised.
cp "$BUILD_SH" "$LOCAL_BUILD_SH" || fail "cannot copy openwrt-build.sh"
chmod +x "$LOCAL_BUILD_SH" || fail "cannot make openwrt-build.sh executable"

"$LOCAL_BUILD_SH" \
    build-target \
    antiblock \
    "$OPENWRT_VERSION" \
    x86 \
    64 \
    x86_64 \
    "$ARTIFACT_DIR" || fail "OpenWrt package build failed"

rm -f "$LOCAL_BUILD_SH"

find "$ARTIFACT_DIR" -type f -name 'antiblock_v*.apk' -print \
    | "$TEST_DIR/run-runtime.sh"

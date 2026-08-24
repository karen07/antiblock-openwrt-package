# OpenWrt package E2E tests

These tests belong to the OpenWrt package repository, not to the AntiBlock core.
They build the package with the same shared `openwrt-build.sh` used by CI and
then validate the resulting APK in an OpenWrt x86/64 Docker runtime.

Expected local layout:

```text
work/
|-- openwrt-package-ci/
|   `-- openwrt-build.sh
`-- antiblock-openwrt-package/
    |-- antiblock/
    |-- openwrt-build.env
    `-- tests/
```

Run everything from `antiblock-openwrt-package`:

```sh
./tests/run.sh
```

The default builder path is:

```text
../openwrt-package-ci/openwrt-build.sh
```

The shared builder expects `openwrt-build.env` and package directories relative
to its own `$0`. GitHub Actions solves this by copying `openwrt-build.sh` into
the package repository before running it. `tests/run.sh` does the same with a
temporary file and removes it afterwards.

The build command is equivalent to:

```sh
./openwrt-build.sh \
    build-target \
    antiblock \
    25.12.5 \
    x86 \
    64 \
    x86_64 \
    tests/.artifacts
```

The resulting APK path is piped into `tests/run-runtime.sh`.

The runtime test pulls the official OpenWrt 25.12.5 x86/64 Docker rootfs from
`ghcr.io/openwrt/rootfs:x86_64-25.12.5`. It installs dnsmasq and the just-built
AntiBlock APK, prepares a temporary image, and boots it with procd and ubus on an
internal Docker network. The booted runtime does not need external Internet access.

During image preparation, the harness disables `procd_add_jail*` calls in the
**container copy** of `/etc/init.d/dnsmasq`. OpenWrt's default dnsmasq `ujail`
requires namespace operations unavailable in this unprivileged Docker runtime;
without this workaround dnsmasq fails with `jail: failed to clone/fork: Operation not permitted`. Only dnsmasq jail setup is bypassed: dnsmasq still runs under
`procd`, so stopped/running/cache integration tests remain active. No package
files or AntiBlock production init scripts are modified. A real OpenWrt device
or VM should still be used to validate dnsmasq with the normal jail enabled.
The boot configuration also disables the LAN DHCP pool for this DNS-only E2E
network, so dnsmasq does not probe for DHCP servers via `udhcpc`.

The runtime scenarios verify real kernel routes for L2 and L3 rules, legacy
`gateway`, route moves, blacklist, `--test`, log/stat, route cleanup, procd
respawn, that a stopped dnsmasq stays stopped, and that starting AntiBlock
restarts a running dnsmasq and clears its warm DNS cache. It also verifies
disabled per-route UCI sections, source changes
after UCI commit/service restart, service reload (including replacement of
active routes and blacklist-only updates), and acceptance of 32 enabled routing rules.
The init script requires at least one enabled rule with `interface` (or legacy
`gateway`) and `domains_path`; the AntiBlock binary validates the maximum rule
count and remaining argument constraints. The runtime suite contains 25 checks, including five start-up route
validation regressions: no routes, missing interface/gateway, missing
domains_path, all routes disabled, and one usable rule alongside an
incomplete rule.

To use another OpenWrt release:

```sh
OPENWRT_VERSION=25.12.5 ./tests/run.sh
```

To use a builder from another location:

```sh
OPENWRT_BUILD_SH=/path/to/openwrt-build.sh ./tests/run.sh
```

Requirements: the sibling `openwrt-package-ci` checkout, Docker with a running
daemon, standard OpenWrt build host tools and Internet access during build and
staging. On the first run, Docker also needs access to `ghcr.io` to pull the
OpenWrt rootfs image.

The runtime uses `NET_ADMIN` and `NET_RAW` for routing and packet capture,
without `--privileged`. Host hardware watchdog devices must not be exposed.

The shared builder caches its SDK under `.openwrt-build/`. Docker caches the
official OpenWrt rootfs image locally. The latest x86/64 APK used by the E2E test
is stored under `tests/.artifacts/`.

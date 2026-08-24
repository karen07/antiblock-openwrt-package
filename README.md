# AntiBlock OpenWrt package

This repository contains the OpenWrt package definition for [AntiBlock](https://github.com/karen07/antiblock).

It packages the AntiBlock binary together with an OpenWrt init script and UCI configuration, so the service can be installed and managed in the usual OpenWrt way. The package depends on `libcurl` and `libpcap`. AntiBlock 3.x route rules use network interface names; the init script still accepts the legacy `gateway` UCI key from 2.x configurations.

When used inside an OpenWrt buildroot, the Makefile can build from `../antiblock` relative to the package directory (normally `package/antiblock`). Otherwise OpenWrt fetches the upstream tag `v$(PKG_VERSION)`.

## Описание

Этот репозиторий содержит описание пакета OpenWrt для [AntiBlock](https://github.com/karen07/antiblock).

Пакет устанавливает бинарный файл AntiBlock вместе со скриптом запуска OpenWrt и конфигурацией UCI, поэтому сервисом можно управлять стандартными средствами OpenWrt. Пакет зависит от `libcurl` и `libpcap`. В AntiBlock 3.x первый параметр правила `-r` - имя сетевого интерфейса. Init script использует новый UCI-параметр `interface`, но сохраняет fallback на старый `gateway`, поэтому существующий `/etc/config/antiblock` можно не переписывать сразу.

При использовании внутри OpenWrt buildroot Makefile может брать исходники из `../antiblock` относительно каталога пакета (обычно `package/antiblock`). В обычной сборке OpenWrt загружает upstream tag `v$(PKG_VERSION)`.

## Что находится в репозитории

- `antiblock/Makefile` - описание OpenWrt package;
- `antiblock/files/etc/init.d/antiblock` - init script;
- `antiblock/files/etc/config/antiblock` - UCI configuration with `interface` and legacy `gateway` compatibility;
- `openwrt-build.env` - параметры пакета для общего CI;
- `.github/workflows/openwrt-build.yml` - вызов общего reusable workflow;
- `antiblock/test-version.sh` - вспомогательный тестовый скрипт;
- `tests/` - локальные Docker E2E тесты OpenWrt package.

## Совместимость с AntiBlock 3.x

Пакет синхронизирован с AntiBlock 3.0.0. `PKG_RELEASE` сброшен на `1`. Проверочный `antiblock/test-version.sh` вызывает `antiblock --help`, поэтому не зависит от поведения запуска демона без обязательных аргументов.

## Сборка

Сборка выполняется через GitHub Actions. Workflow этого репозитория вызывает общий reusable workflow из [openwrt-package-ci](https://github.com/karen07/openwrt-package-ci).

CI можно запустить:

- push тега OpenWrt release, например `v25.12.5` - значение тега используется как версия OpenWrt;
- вручную через `workflow_dispatch`, указав версию OpenWrt и при необходимости фильтры target/subtarget.

Этот тег задает версию OpenWrt для сборки, а не `PKG_VERSION` AntiBlock. Версия AntiBlock задается в `antiblock/Makefile`.

Параметры этого пакета хранятся в `openwrt-build.env`. Общие `openwrt-build.sh`, `openwrt-matrix.py` и логика сборки через OpenWrt SDK находятся в `openwrt-package-ci`.

Для ручной сборки каталог `antiblock/` можно использовать как обычный package directory внутри OpenWrt buildroot/SDK.

## Журнал и статистика

При включении `option log '1'` AntiBlock записывает DNS-операции в
`/tmp/antiblock/log.txt`. В OpenWrt каталог `/tmp` обычно расположен в RAM (tmpfs),
поэтому при длительной работе лог может расходовать оперативную память.
Для постоянной работы рекомендуем оставлять `log '0'` (по умолчанию), а логирование
включать только на время диагностики. Файл `stat.txt` также находится в `/tmp`,
если включён `option stat '1'`.

## Связанные проекты

- [antiblock](https://github.com/karen07/antiblock) - основной DNS-based routing daemon;
- [luci-app-antiblock-openwrt-package](https://github.com/karen07/luci-app-antiblock-openwrt-package) - LuCI web interface.

## Локальный OpenWrt E2E

Тесты OpenWrt-пакета находятся в `tests/`, потому что они проверяют именно упаковку и
интеграцию с OpenWrt, а не core AntiBlock.

Для локального запуска репозитории должны лежать рядом:

```text
work/
|-- openwrt-package-ci/
`-- antiblock-openwrt-package/
```

Запуск:

```sh
./tests/run.sh
```

`tests/run.sh` берет общий builder из:

```text
../openwrt-package-ci/openwrt-build.sh
```

и, как обычный CI, временно копирует его в корень package-репозитория. После этого
вызывается `build-target antiblock 25.12.5 x86 64 x86_64`, а путь к полученному APK
через pipe передается в Docker runtime test.

Runtime test использует официальный OpenWrt 25.12.5 x86/64 Docker rootfs
`ghcr.io/openwrt/rootfs:x86_64-25.12.5`, устанавливает зависимости и только что
собранный AntiBlock APK, а затем запускает подготовленный OpenWrt с procd/ubus во
внутренней Docker-сети без внешнего доступа.

Только для Docker E2E при подготовке образа отключается `procd` jail у `dnsmasq`:
контейнеру недоступны необходимые операции создания namespaces. На настоящий
OpenWrt, установочный APK и init script AntiBlock это изменение не влияет.
Для тестовой сети также отключается выдача DHCP на LAN, но DNS-служба
`dnsmasq` продолжает работать под управлением `procd`.

E2E проверяет установку APK, UCI, `rc.common`/procd, реальные L2/L3 маршруты,
legacy `gateway`, перенос маршрута между правилами, blacklist, `--test`, log/stat,
cleanup, procd respawn и применение UCI через restart/reload, в том числе
изменения одного только blacklist без изменения аргументов запуска.
При запуске AntiBlock перезапускает работающий `dnsmasq`, чтобы сбросить его DNS-кеш,
но не запускает остановленный `dnsmasq`. Отдельный тест проверяет сброс прогретого
кеша и создание маршрута по новому DNS-ответу.
Всего 25 runtime-тестов, включая 5 проверок валидации route-секций при запуске. Init script проверяет наличие хотя бы одного
включённого правила с `interface` (или `gateway`) и `domains_path`;
ограничение в 32 правила и дополнительные проверки выполняет AntiBlock.

# AntiBlock OpenWrt package

This repository contains the OpenWrt package definition for [AntiBlock](https://github.com/karen07/antiblock).

It packages the AntiBlock binary together with an OpenWrt init script and UCI configuration, so the service can be installed and managed in the usual OpenWrt way. The package depends on `libcurl` and `libpcap`.

For development, the Makefile can build from a sibling `../antiblock` checkout. Otherwise OpenWrt fetches the tagged upstream source specified by `PKG_VERSION`.

## Описание

Этот репозиторий содержит описание пакета OpenWrt для [AntiBlock](https://github.com/karen07/antiblock).

Пакет устанавливает бинарный файл AntiBlock вместе со скриптом запуска OpenWrt и конфигурацией UCI, поэтому сервисом можно управлять стандартными средствами OpenWrt. Пакет зависит от `libcurl` и `libpcap`.

При разработке Makefile может собирать исходники из соседнего каталога `../antiblock`. Если такого каталога нет, OpenWrt загружает версию исходников по тегу, заданному в `PKG_VERSION`.

## Что находится в репозитории

- `antiblock/Makefile` - описание OpenWrt package;
- `antiblock/files/etc/init.d/antiblock` - init script;
- `antiblock/files/etc/config/antiblock` - UCI configuration;
- `openwrt-build.env` - параметры пакета для общего CI;
- `.github/workflows/openwrt-build.yml` - вызов общего reusable workflow;
- `test.sh` - вспомогательный тестовый скрипт.

## Сборка

Сборка выполняется через GitHub Actions. Workflow этого репозитория вызывает общий reusable workflow из [openwrt-package-ci](https://github.com/karen07/openwrt-package-ci).

CI можно запустить:

- push тега вида `vX.Y.Z` - значение тега используется как версия OpenWrt;
- вручную через `workflow_dispatch`, указав версию OpenWrt и при необходимости фильтры target/subtarget.

Параметры этого пакета хранятся в `openwrt-build.env`. Общие `openwrt-build.sh`, `openwrt-matrix.py` и логика сборки через OpenWrt SDK находятся в `openwrt-package-ci`.

Для ручной сборки каталог `antiblock/` можно использовать как обычный package directory внутри OpenWrt buildroot/SDK.

## Связанные проекты

- [antiblock](https://github.com/karen07/antiblock) - основной DNS-based routing daemon;
- [luci-app-antiblock-openwrt-package](https://github.com/karen07/luci-app-antiblock-openwrt-package) - LuCI web interface.

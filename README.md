# AntiBlock OpenWrt Package

OpenWrt packaging for [AntiBlock](https://github.com/karen07/antiblock), a DNS-based
dynamic routing tool. It provides the application, an init script, and UCI configuration
for managing the service on OpenWrt.

Пакет OpenWrt для [AntiBlock](https://github.com/karen07/antiblock) - инструмента
динамической маршрутизации на основе DNS. Он устанавливает приложение, init-скрипт и
UCI-конфигурацию для управления сервисом на OpenWrt.

## Описание

Зависимости пакета - `libcurl` и `libpcap`. В AntiBlock 3.x первый параметр правила `-r`
означает имя сетевого интерфейса. Init-скрипт использует новый UCI-параметр `interface`, но
по-прежнему принимает прежний `gateway`, поэтому существующий `/etc/config/antiblock`
необязательно менять сразу.

При использовании внутри OpenWrt buildroot Makefile может брать исходники из `../antiblock` относительно каталога пакета (обычно `package/antiblock`). В обычной сборке OpenWrt загружает upstream tag `v$(PKG_VERSION)`.

## Содержание

- [Разработка и проверка изменений](#%D1%80%D0%B0%D0%B7%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D0%BA%D0%B0-%D0%B8-%D0%BF%D1%80%D0%BE%D0%B2%D0%B5%D1%80%D0%BA%D0%B0-%D0%B8%D0%B7%D0%BC%D0%B5%D0%BD%D0%B5%D0%BD%D0%B8%D0%B9)
- [Совместимость с AntiBlock 3.x](#%D1%81%D0%BE%D0%B2%D0%BC%D0%B5%D1%81%D1%82%D0%B8%D0%BC%D0%BE%D1%81%D1%82%D1%8C-%D1%81-antiblock-3x)
- [Сборка](#%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B0)
- [Журнал и статистика](#%D0%B6%D1%83%D1%80%D0%BD%D0%B0%D0%BB-%D0%B8-%D1%81%D1%82%D0%B0%D1%82%D0%B8%D1%81%D1%82%D0%B8%D0%BA%D0%B0)
- [Тестирование](#%D1%82%D0%B5%D1%81%D1%82%D0%B8%D1%80%D0%BE%D0%B2%D0%B0%D0%BD%D0%B8%D0%B5)
- [Структура проекта](#%D1%81%D1%82%D1%80%D1%83%D0%BA%D1%82%D1%83%D1%80%D0%B0-%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82%D0%B0)
- [Связанные проекты](#%D1%81%D0%B2%D1%8F%D0%B7%D0%B0%D0%BD%D0%BD%D1%8B%D0%B5-%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82%D1%8B)
- [Лицензия](#%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%8F)

## Разработка и проверка изменений

**Основные точки изменения:**

- `antiblock/Makefile` - зависимости, версия и правила установки пакета;
- `antiblock/files/etc/init.d/antiblock` - управление сервисом OpenWrt;
- `antiblock/files/etc/config/antiblock` - значения и имена UCI-опций;
- `tests/run.sh` - E2E-проверки пакета;
- `openwrt-build.env` - параметры общей CI-сборки.

**Проверка изменений:** Функциональность демона изменяется в отдельном проекте `antiblock`; здесь изменяются упаковка и интеграция OpenWrt. При изменении UCI-опций согласовывайте конфиг и init-скрипт, затем запускайте тесты из `tests/` и сборку через общий `openwrt-package-ci`.

**Контракт конфигурации:** для секции маршрута init-скрипт сначала читает
`interface`, а при пустом значении использует старый ключ `gateway`.
Удаление этого fallback нарушит совместимость конфигураций AntiBlock 2.x.
Параметры `enabled`, `listen`, `log`, `stat`, `test` и `blacklist` следует
сверять с полями LuCI и аргументами демона при изменении их семантики.

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

## Тестирование

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

## Структура проекта

- `antiblock/Makefile` - описание OpenWrt package;
- `antiblock/files/etc/init.d/antiblock` - init script;
- `antiblock/files/etc/config/antiblock` - UCI configuration with `interface` and legacy `gateway` compatibility;
- `openwrt-build.env` - параметры пакета для общего CI;
- `.github/workflows/openwrt-build.yml` - вызов общего reusable workflow;
- `antiblock/test-version.sh` - вспомогательный тестовый скрипт;
- `tests/` - локальные Docker E2E тесты OpenWrt package.

## Связанные проекты

- [antiblock](https://github.com/karen07/antiblock) - основной DNS-based routing daemon;
- [luci-app-antiblock-openwrt-package](https://github.com/karen07/luci-app-antiblock-openwrt-package) - LuCI web interface.

## Лицензия

Проект распространяется под лицензией GNU Affero General Public License v3.0. Подробности см. в файле [LICENSE](LICENSE).

# AntiBlock OpenWrt Package E2E Tests

Docker-based end-to-end tests that build the AntiBlock OpenWrt package using the shared CI builder and verify its APK, init scripts, DNS integration, and kernel routes in an OpenWrt runtime.

## Описание

End-to-end тесты пакета AntiBlock для OpenWrt. Они собирают пакет тем же общим скриптом, что используется в CI, затем проверяют APK, init-скрипты, DNS-интеграцию и маршруты ядра в контейнерном окружении OpenWrt.

Эти тесты относятся к репозиторию OpenWrt-пакета, а не к основному исходному коду AntiBlock.

## Требования

- Соседний репозиторий `openwrt-package-ci` со скриптом `openwrt-build.sh`.
- Docker с запущенным демоном, стандартные инструменты сборки OpenWrt и доступ к Интернету на этапах сборки/подготовки окружения.
- При первом запуске доступ к `ghcr.io` для загрузки образа rootfs OpenWrt.
- В контейнере используются только `NET_ADMIN` и `NET_RAW`, без `--privileged` и без доступа к аппаратным watchdog хоста.

Ожидаемое размещение исходников:

```text
work/
|-- openwrt-package-ci/
|   `-- openwrt-build.sh
`-- antiblock-openwrt-package/
    |-- antiblock/
    |-- openwrt-build.env
    `-- tests/
```

## Быстрый старт

Из корня `antiblock-openwrt-package`:

```sh
./tests/run.sh
```

Для выбора другой версии OpenWrt:

```sh
OPENWRT_VERSION=25.12.5 ./tests/run.sh
```

Для указания другого пути к общему сборщику:

```sh
OPENWRT_BUILD_SH=/path/to/openwrt-build.sh ./tests/run.sh
```

## Сборка и установка

По умолчанию используется общий сборщик:

```text
../openwrt-package-ci/openwrt-build.sh
```

Общий сборщик ожидает `openwrt-build.env` и каталоги пакетов относительно собственного `$0`. В GitHub Actions он копируется в репозиторий пакета; `tests/run.sh` делает то же самое во временный файл, который затем удаляется.

Эквивалентная команда сборки:

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

Полученный путь к APK передаётся в `tests/run-runtime.sh`.

## Архитектура и реализация

### Тестовое окружение

Тесты используют официальный OpenWrt 25.12.5 x86/64 Docker rootfs `ghcr.io/openwrt/rootfs:x86_64-25.12.5`: добавляют `dnsmasq`, собранный APK, загружают окружение с `procd` и `ubus` во внутренней сети Docker. После подготовки окружения доступ к внешнему Интернету ему не нужен.

В копии `/etc/init.d/dnsmasq` **внутри тестового контейнера** выключаются вызовы `procd_add_jail*`: стандартный OpenWrt `ujail` требует namespace-операций, недоступных в этом непривилегированном Docker-окружении. Без обхода dnsmasq выдаёт `jail: failed to clone/fork: Operation not permitted`.

Меняется только настройка jail для dnsmasq в тестовой копии: dnsmasq по-прежнему работает под `procd`, а production-скрипты AntiBlock и файлы пакета не изменяются. На реальном OpenWrt-устройстве или VM нужно дополнительно проверять штатную работу `ujail`. Пул LAN DHCP отключён, чтобы dnsmasq не проверял наличие DHCP-серверов через `udhcpc` в тестовой DNS-сети.

## Тестирование

Тестовый набор включает **25 проверок**:

- реальные маршруты ядра для правил L2 и L3, устаревший параметр `gateway`, перенос маршрутов и blacklist;
- режим `--test`, журнал `--log`, статистику `--stat` и очистку маршрутов;
- перезапуск процесса через `procd`;
- сохранение остановленного `dnsmasq` в остановленном состоянии;
- перезапуск работающего dnsmasq при запуске AntiBlock и очистку тёплого DNS-кеша;
- отключённые UCI-секции маршрутов, изменение источников после UCI commit/restart;
- `reload` сервиса с заменой активных маршрутов и обновлением только blacklist;
- принятие конфигурации с 32 включёнными правилами;
- пять регрессий валидации старта: нет правил; отсутствует interface/gateway; отсутствует `domains_path`; все правила выключены; одно рабочее и одно неполное правило.

Init-скрипт требует хотя бы одного включённого правила с `interface` (или устаревшим `gateway`) и `domains_path`. Максимальное количество правил и прочие аргументы дополнительно валидирует бинарный файл AntiBlock.

## Структура проекта

Общий SDK кешируется в `.openwrt-build/`, образ OpenWrt - в локальном кеше Docker. Последний собранный x86/64 APK для E2E хранится в `tests/.artifacts/`.

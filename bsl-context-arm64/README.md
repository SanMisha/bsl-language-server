# PlatformFinder на Linux ARM64

Проба печатает, какие установки платформы 1С находит `PlatformFinder` из bsl-context. На Linux ARM64 пакеты 1С ставят платформу в `/opt/1cv8/arm64/<версия>/`, и автопоиск её не видит.

## Что нужно

- Java 21+ и bash.
- `bsl-context-0.10.2.jar` с Maven Central: https://repo1.maven.org/maven2/io/github/1c-syntax/bsl-context/0.10.2/bsl-context-0.10.2.jar. Тот же файл лежит в `bsl-language-server-1.1.0-rc.9-exec.jar` как `BOOT-INF/lib/bsl-context-0.10.2.jar`.
- Для воспроизведения — Linux на ARM64 с платформой 1С из пакетов `1c-enterprise-<версия>-client` для arm64.

## Запуск

    ./run.sh <путь к bsl-context-0.10.2.jar>

Без bash: `java -cp <путь к jar> PlatformFinderProbe.java`.

## Что ожидается

`findAllInstalls` перечисляет установки из `/opt/1cv8/arm64/`, `findLatest` возвращает самую свежую.

## Что получается на Ubuntu 24.04 (aarch64), OpenJDK 21

    == Система: Linux aarch64
    == Архитектура пакетов: arm64
    == Справка платформы на диске (/opt/1cv8):
    /opt/1cv8/arm64/8.3.27.1688/shcntx_ru.hbk
    /opt/1cv8/arm64/8.5.1.1343/shcntx_ru.hbk
    == PlatformFinder:
    os.name=Linux os.arch=aarch64
    findAllInstalls=[]
    findLatest=Optional.empty

Сама справка на месте и разбирается. BSL LS 1.1.0-rc.9 с `v8platform.binPath` = `/opt/1cv8/arm64/8.5.1.1343` пишет в лог `Loaded 2542 platform contexts from 1C syntax helper`, а без `binPath` — `Failed to load platform contexts from 1C syntax helper: No 1C platform installations found on this machine.`

## Для сравнения: macOS на Apple Silicon

    == Система: Darwin arm64
    == Справка платформы на диске (/opt/1cv8):
    /opt/1cv8/8.3.27.1688/shcntx_ru.hbk
    /opt/1cv8/8.3.27.2074/shcntx_ru.hbk
    /opt/1cv8/8.5.1.1343/shcntx_ru.hbk
    == PlatformFinder:
    os.name=Mac OS X os.arch=aarch64
    findAllInstalls=[PlatformInstall[version=8.5.1.1343, binDir=/opt/1cv8/8.5.1.1343], PlatformInstall[version=8.3.27.2074, binDir=/opt/1cv8/8.3.27.2074], PlatformInstall[version=8.3.27.1688, binDir=/opt/1cv8/8.3.27.1688]]
    findLatest=Optional[PlatformInstall[version=8.5.1.1343, binDir=/opt/1cv8/8.5.1.1343]]

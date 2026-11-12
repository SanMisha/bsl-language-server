# Решение из одного расширения теряет «Назначение использования»

Если в каталоге только расширение, `MDClasses.createSolution` отдаёт решение с пустым `getUsePurposes()`, хотя у самого расширения назначение задано. Здесь минимальный пример и скрипт, который это показывает: прямым вызовом API mdclasses и прогоном BSL Language Server.

## Что внутри

- `ext/` — выгрузка конфигуратора: расширение `РепроРасширение`, назначение использования — только «Приложение для платформы» (`UsePurposes = PlatformApplication`), основной режим запуска — управляемое приложение. Из объектов в нём только серверный общий модуль `Р_Сервер`.
- `cf/` — тот же модуль и те же `UsePurposes`/`DefaultRunMode`, корень — конфигурация.
- `UsePurposesProbe.java` — читает каталог через `MDClasses.createSolution` с теми же настройками, что BSL LS, и печатает `getUsePurposes()`, `getDefaultRunMode()` и `getCompatibilityMode()` у основы, расширения и решения.
- `bsl-ls.json` — включает только диагностику `MemberAccessUnavailable`, все режимы `auto`.
- `run.sh` — компилирует и запускает пробник, затем `analyze` на `ext/` и `cf/`, печатает итог.

В модуле `Р_Сервер` три обращения: `ЗаписьЖурналаРегистрации`, `УровеньЖурналаРегистрации`, `ОбходРезультатаЗапроса`. По синтакс-помощнику 8.5.1 они доступны на сервере, в толстом клиенте и во внешнем соединении. Мобильного приложения в этом списке нет.

## Запуск

Нужны JDK 21+ (`java`, `javac`, `jar`), jq и bash (Linux или macOS). mdclasses и её зависимости скрипт берёт из jar-а BSL LS.

    ./run.sh <путь к bsl-language-server-1.1.0-rc.9-exec.jar>

`MemberAccessUnavailable` берёт доступность членов из синтакс-помощника платформы. BSL LS ищет установленную платформу сам; если не находит, замечаний не будет ни в одном прогоне. Тогда передайте каталог с `shcntx_ru.hbk` вторым аргументом:

    ./run.sh <путь к jar> /opt/1cv8/8.5.1.1343

Пробнику mdclasses платформа не нужна. Логи и отчёты — в `out/<дата-время>/`. Код выхода: 1 — ошибка воспроизводится, 0 — нет, 2 — сбой.

Исправленную mdclasses можно проверить без пересборки BSL LS. Скрипт ставит jar из переменной `MDCLASSES_JAR` первым в `-Dloader.path`, и этот jar перекрывает mdclasses из `BOOT-INF/lib` и в пробнике, и в `analyze`:

    MDCLASSES_JAR=<jar mdclasses> ./run.sh <путь к jar BSL LS>

## Что ожидается

С исправленной mdclasses (`MDCLASSES_JAR=<jar mdclasses> ./run.sh <jar BSL LS>`) у решения из `ext/` `usePurposes=[PLATFORM_APPLICATION]`, как у расширения. В обоих прогонах `analyze` замечаний нет: с таким назначением режимы мобильного приложения не проверяются.

## Что получается на mdclasses 0.21.0 (BSL LS 1.1.0-rc.9)

    == mdclasses: MDClasses.createSolution
      Каталог ext
        основа:     нет (Configuration.EMPTY)
        расширение: РепроРасширение: usePurposes=[PLATFORM_APPLICATION], defaultRunMode=MANAGED_APPLICATION, compatibilityMode=8.5.1
        Solution:   solution: usePurposes=[], defaultRunMode=MANAGED_APPLICATION, compatibilityMode=8.5.1
        Итог: у расширения назначение задано, у решения список пуст
      Каталог cf
        основа:     РепроКонфигурация: usePurposes=[PLATFORM_APPLICATION], defaultRunMode=MANAGED_APPLICATION, compatibilityMode=8.5.1
        Solution:   РепроКонфигурация: usePurposes=[PLATFORM_APPLICATION], defaultRunMode=MANAGED_APPLICATION, compatibilityMode=8.5.1
        Итог: назначение у решения совпадает с исходным

    == BSL LS analyze --srcDir ext (корень — расширение)
      Loaded 2542 platform contexts from 1C syntax helper
      строка 7: Метод "ЗаписьЖурналаРегистрации" недоступен в контексте вызывающего метода (Мобильное приложение (сервер))
      строка 7: Свойство "УровеньЖурналаРегистрации" недоступно в контексте обращения (Мобильное приложение (сервер))
      строка 12: Свойство "ОбходРезультатаЗапроса" недоступно в контексте обращения (Мобильное приложение (сервер))

    == BSL LS analyze --srcDir cf (корень — конфигурация, тот же модуль)
      Loaded 2542 platform contexts from 1C syntax helper
      замечаний нет

    Замечаний про мобильное приложение: ext — 3, cf — 0
    Итог: ошибка воспроизводится — у расширения getUsePurposes() не пуст, у решения пуст

`defaultRunMode` и `compatibilityMode` решение получает от расширения, `usePurposes` остаётся пустым. Проверено на macOS (Apple Silicon), OpenJDK 21, синтакс-помощник 8.5.1.1343 и 8.3.27.2074: со справкой 8.3.27 строка про загрузку — `Loaded 2495 platform contexts`, остальной вывод тот же.

## С исправлением

В `MDMerger.merge` после `.defaultRunMode(extension.getDefaultRunMode())` добавлена строка `.usePurposes(extension.getUsePurposes())`, класс подменён в копии `mdclasses-0.21.0.jar`:

    mdclasses: mdclasses-0.21.0-usepurposes.jar из MDCLASSES_JAR (перекрывает BOOT-INF/lib)
      Каталог ext
        Solution:   solution: usePurposes=[PLATFORM_APPLICATION], defaultRunMode=MANAGED_APPLICATION, compatibilityMode=8.5.1
        Итог: назначение у решения совпадает с исходным
    == BSL LS analyze --srcDir ext (корень — расширение)
      замечаний нет
    == BSL LS analyze --srcDir cf (корень — конфигурация, тот же модуль)
      замечаний нет
    Итог: ошибка не воспроизводится

Вывод сокращён. С исходным `mdclasses-0.21.0.jar` в `MDCLASSES_JAR` результат тот же, что без переменной: три замечания и код выхода 1.

# Примеры для воспроизведения

Примеры к issue в `1c-syntax/bsl-language-server`, `1c-syntax/mdclasses` и `1c-syntax/bsl-context`. В каждом каталоге есть README с командой запуска и ожидаемым выводом, а рядом лежит тот же пример архивом `repro.zip`.

| Каталог | Что воспроизводит |
|---|---|
| [bsl-ls-config-from-launch-dir](bsl-ls-config-from-launch-dir) | Рабочая папка получает настройки из `.bsl-language-server.json` в каталоге запуска сервера вместо своего файла |
| [bsl-context-arm64](bsl-context-arm64) | На Linux ARM64 автопоиск не находит установленную платформу 1С |
| [bsl-ls-fp-event-handler-without-helper](bsl-ls-fp-event-handler-without-helper) | Без синтакс-помощника `EventHandlerInvalidSignature` помечает правильный обработчик события элемента формы |
| [bsl-ls-analyze-deadlock-extension](bsl-ls-analyze-deadlock-extension) | `analyze` зависает, если модуль объекта документа есть и в основной конфигурации, и в расширении |
| [mdclasses-borrowed-common-module](mdclasses-borrowed-common-module) | `Solution` не находит по URI `Module.bsl` заимствованного общего модуля из расширения |

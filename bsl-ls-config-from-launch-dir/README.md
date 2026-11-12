# Настройки папки зависят от каталога, из которого запущен analyze

## Что внутри

- `multi/a/.bsl-language-server.json` выключает `EmptyCodeBlock`.
- `multi/b/.bsl-language-server.json` поднимает `LineLength.maxLineLength` до 200.
- `multi/b/Module.bsl` и `multi/a/src/Module.bsl` — одинаковые модули. В каждом есть пустой блок `Если`, строка длиной 139 символов и вызов `Сообщить` без точки с запятой. Без настроек в модуле четыре замечания: `EmptyCodeBlock`, `LineLength`, `SemicolonPresence`, `DeprecatedMessage`. По тому, какое из первых двух пропало, видно, чей файл применился.
- `run.sh` трижды запускает `analyze` и сравнивает результат с ожидаемым.

## Как запустить

```sh
./run.sh <путь к bsl-language-server-*-exec.jar>
```

Нужны Java 21 или новее и `jq`. Отчёты и логи складываются в `out/`. Код возврата: 0 — все запуски дали ожидаемые настройки, 1 — хотя бы один нет, 2 — сбой запуска.

## Что ожидается

1. `cd multi && analyze -s b`: в каталоге запуска файла настроек нет, папка `multi/b` получает свои настройки.
2. `cd multi/a && analyze -s ../b`: папка `multi/b` тоже получает свои настройки, хотя в каталоге запуска лежит файл папки `multi/a`.
3. `cd multi/a && analyze -s src`: у `multi/a/src` своего файла нет, поэтому применяется файл из каталога запуска. Так сейчас работает `analyze -s src/cf`, запущенный из корня репозитория.

## Что получается на 1.1.0-rc.9

```text
BSL Language Server 1.1.0-rc.9

1. cd multi && analyze -s b
   в каталоге запуска нет .bsl-language-server.json
   замечания: DeprecatedMessage, EmptyCodeBlock, SemicolonPresence
   настройки: папки multi/b (ожидается: папки multi/b)

2. cd multi/a && analyze -s ../b
   в каталоге запуска лежит файл папки multi/a
   замечания: DeprecatedMessage, LineLength, SemicolonPresence
   настройки: папки multi/a (ожидается: папки multi/b)

3. cd multi/a && analyze -s src
   у multi/a/src своего файла нет, как у src/cf при запуске из корня репозитория
   замечания: DeprecatedMessage, LineLength, SemicolonPresence
   настройки: папки multi/a (ожидается: папки multi/a)

Итог: не те настройки в запуске 2.
```

Во втором запуске папка `multi/b` получила файл папки `multi/a`: пропал `EmptyCodeBlock`, появился `LineLength`, а свой `maxLineLength: 200` не применился. Файлы не сливаются, работает только файл из каталога запуска.

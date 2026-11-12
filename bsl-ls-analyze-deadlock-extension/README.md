# analyze зависает: модуль объекта документа есть и в основе, и в расширении

Пример к issue в 1c-syntax/bsl-language-server. В `src/cf` — основная конфигурация, в `src/cfe` — расширение, обе в формате выгрузки конфигуратора. Расширение заимствует `Документ1`, и модуль объекта у документа есть в обеих:

```text
src/cf/Configuration.xml
src/cf/Documents/Документ1.xml
src/cf/Documents/Документ1/Ext/ObjectModule.bsl     Процедура ПередЗаписью(...)
src/cfe/Configuration.xml                           расширение, префикс Расш1_
src/cfe/Documents/Документ1.xml                     ObjectBelonging = Adopted
src/cfe/Documents/Документ1/Ext/ObjectModule.bsl    &После("ПередЗаписью") Процедура Расш1_ПередЗаписью(...)
```

## Как запустить

```bash
./run.sh /путь/к/bsl-language-server-1.1.0-rc.9-exec.jar
```

Если архив распаковался без признака исполняемого файла — `bash run.sh …`. Нужны JDK 21+ (`java`, а для дампа потоков `jstack` или `jcmd`) и `jq`. Скрипт трижды запускает `analyze --srcDir src` с настройками по умолчанию и ждёт каждый запуск до 60 секунд. Если запуск завис, скрипт снимает дамп потоков в `out/<дата-время>/<запуск>/threads.txt` и останавливает JVM. Последний запуск идёт с обходом `-Djava.util.concurrent.ForkJoinPool.common.parallelism=1`. Время ожидания и число запусков задают переменные `TIMEOUT` и `RUNS`.

## Что должно быть

Каждый запуск `analyze` завершается за несколько секунд, в отчёте два файла. Итоговая строка — «зависаний с настройками по умолчанию — 0 из 3», код выхода 0.

## Что получается

На BSL LS 1.1.0-rc.9 (macOS, OpenJDK 21) все три запуска зависают, запуск с обходом проходит:

```text
default-1: analyze не завершился за 60 с, дамп потоков — out/20261112-230038/default-1/threads.txt
default-2: analyze не завершился за 60 с, дамп потоков — out/20261112-230038/default-2/threads.txt
default-3: analyze не завершился за 60 с, дамп потоков — out/20261112-230038/default-3/threads.txt

parallelism-1: analyze завершился за 15 с, код выхода 0, файлов в отчёте: 2

Итог: зависаний с настройками по умолчанию — 3 из 3
```

После каждого зависшего запуска скрипт печатает секцию дампа, где JVM сообщает о взаимоблокировке, и стеки обоих потоков. Фрагмент первого запуска (адреса и номера потоков от запуска к запуску другие):

```text
Found one Java-level deadlock:
=============================
"cli-src-2":
  waiting for ownable synchronizer 0x0000000361009d00, (a java.util.concurrent.locks.ReentrantLock$NonfairSync),
  which is held by "cli-src-11"

"cli-src-11":
  waiting for ownable synchronizer 0x0000000361e2ac68, (a java.util.concurrent.locks.ReentrantLock$NonfairSync),
  which is held by "cli-src-2"

"cli-src-2":
	at com.github._1c_syntax.bsl.languageserver.context.DocumentContext.getSymbolTree(DocumentContext.java:193)
	at com.github._1c_syntax.bsl.languageserver.types.registry.ConfigurationModuleMembersProvider.collectModuleMembers(ConfigurationModuleMembersProvider.java:384)
	at com.github._1c_syntax.bsl.languageserver.types.registry.ConfigurationModuleMembersProvider.lambda$register$0(ConfigurationModuleMembersProvider.java:264)
	at com.github._1c_syntax.bsl.languageserver.types.registry.TypeRegistry.computeMembers(TypeRegistry.java:851)
	at com.github._1c_syntax.bsl.languageserver.types.registry.TypeRegistry.computeAndCacheMembers(TypeRegistry.java:612)
	at com.github._1c_syntax.bsl.languageserver.types.registry.TypeRegistry.getMembers(TypeRegistry.java:591)
	at com.github._1c_syntax.bsl.languageserver.types.registry.EventHandlerResolver.lambda$eventHandlersOf$1(EventHandlerResolver.java:219)
	at com.github._1c_syntax.bsl.languageserver.types.registry.EventHandlerResolver.eventHandlersOf(EventHandlerResolver.java:219)
	at com.github._1c_syntax.bsl.languageserver.context.computer.SymbolTreeComputer.isUpToDate(SymbolTreeComputer.java:121)
	at com.github._1c_syntax.bsl.languageserver.context.DocumentContext.isSymbolTreeUpToDate(DocumentContext.java:616)
	at com.github._1c_syntax.bsl.languageserver.context.DocumentContext.rebuild(DocumentContext.java:433)
	at com.github._1c_syntax.bsl.languageserver.context.DocumentContext.rebuildFromFileSystem(DocumentContext.java:497)
	at com.github._1c_syntax.bsl.languageserver.context.ServerContext.rebuildDocument(ServerContext.java:574)
	at com.github._1c_syntax.bsl.languageserver.cli.AnalyzeCommand.getFileInfoFromFile(AnalyzeCommand.java:267)
"cli-src-11":
	(тот же стек)
```

В полном дампе `threads.txt` у каждого из двух потоков в «Locked ownable synchronizers» по две `ReentrantLock`, а ждёт он первую из пары другого потока:

```text
"cli-src-2"   держит 0x0000000361e2ac68, 0x0000000361e2ac98   ждёт 0x0000000361009d00
"cli-src-11"  держит 0x0000000361009d00, 0x0000000361009d30   ждёт 0x0000000361e2ac68
```

На 1.1.0-rc.4, rc.7 и rc.8 пример зависает так же, только потоки стоят в построении дерева: `DocumentContext.computeSymbolTree` → `MethodSymbolComputer` → `EventHandlerResolver`. На 1.0.7 оба запуска проходят.

## Как обойти

Запустить анализ в один поток:

```bash
java -Djava.util.concurrent.ForkJoinPool.common.parallelism=1 \
  -jar bsl-language-server-1.1.0-rc.9-exec.jar analyze --srcDir src --outputDir out --reporter json
```

# mdclasses не находит по URI модуль заимствованного общего модуля из расширения

Пример к issue в 1c-syntax/mdclasses. Два варианта выгрузки конфигуратора:

```text
with-base-bsl/
  cf/    основа: серверный общий модуль ОбщийМодуль1 и документ Документ1, у обоих есть BSL
  cfe/   расширение Расширение1: заимствованы ОбщийМодуль1 и Документ1, у обоих свой BSL;
         собственный общий модуль Расш1_ОбщийМодуль2
without-base-bsl/   то же, но в cf/ только XML
SolutionProbe.java  прямой вызов API mdclasses
bsl-ls.json         настройки analyze: только CompilationDirectiveNeedLess и MissingCommonModuleMethod
```

В каждом BSL-модуле есть процедура с `&НаСервере`, поэтому `CompilationDirectiveNeedLess` срабатывает в любом модуле, тип которого BSL LS знает. Модуль объекта документа из расширения вызывает метод, который расширение добавило в заимствованный общий модуль: `ОбщийМодуль1.Расш1_Обработать()`.

## Как запустить

```bash
./run.sh /путь/к/bsl-language-server-1.1.0-rc.9-exec.jar
```

Если архив распаковался без признака исполняемого файла — `bash run.sh …`. Нужны JDK 21+ (`java`, `javac`, `jar`) и `jq`. mdclasses и её зависимости скрипт берёт из jar-а BSL LS (`BOOT-INF/lib`). Сначала он компилирует `SolutionProbe.java` и вызывает `MDClasses.createSolution` на обоих вариантах, затем запускает `analyze` BSL LS: основу вместе с расширением и, для сравнения, одно расширение. Другая сборка mdclasses подставляется в первый шаг через `MDCLASSES_JAR=/путь/к/mdclasses.jar`, на `analyze` эта переменная не влияет.

## Что должно быть

Решение находит `cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl`: `Solution.findChild(uri)` — `CommonModule.ОбщийМодуль1`, тип — `CommonModule`, а у слитого `CommonModule.ОбщийМодуль1` два модуля, как у документа. Итог — «ошибка не воспроизводится», код выхода 0.

## Что получается

BSL LS 1.1.0-rc.9 (внутри mdclasses 0.21.0), macOS, OpenJDK 21:

```text
BSL LS: bsl-language-server-1.1.0-rc.9-exec.jar
Java: openjdk version "21.0.11" 2026-04-21
mdclasses в jar-е BSL LS: 0.21.0

== mdclasses, with-base-bsl
  mdclasses: mdclasses-0.21.0.jar
  Основа: Конфигурация, расширение: Расширение1
  Файл                                                 Solution.findChild(uri)            getModuleTypeByURI   расширение.findChild(uri)
  cf/CommonModules/ОбщийМодуль1/Ext/Module.bsl         CommonModule.ОбщийМодуль1          CommonModule         —
  cf/Documents/Документ1/Ext/ObjectModule.bsl          Document.Документ1                 ObjectModule         —
  cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl        —                                  UNKNOWN              CommonModule.ОбщийМодуль1
  cfe/CommonModules/Расш1_ОбщийМодуль2/Ext/Module.bsl  CommonModule.Расш1_ОбщийМодуль2    CommonModule         CommonModule.Расш1_ОбщийМодуль2
  cfe/Documents/Документ1/Ext/ObjectModule.bsl         Document.Документ1                 ObjectModule         Document.Документ1
  Модули объектов в слитой конфигурации, getModules():
    CommonModule.ОбщийМодуль1: cf/CommonModules/ОбщийМодуль1/Ext/Module.bsl
    Document.Документ1: cf/Documents/Документ1/Ext/ObjectModule.bsl, cfe/Documents/Документ1/Ext/ObjectModule.bsl
  Итог: решение не знает cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl, а расширение знает — ошибка воспроизводится

== mdclasses, without-base-bsl
  mdclasses: mdclasses-0.21.0.jar
  Основа: Конфигурация, расширение: Расширение1
  Файл                                                 Solution.findChild(uri)            getModuleTypeByURI   расширение.findChild(uri)
  cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl        —                                  UNKNOWN              CommonModule.ОбщийМодуль1
  cfe/CommonModules/Расш1_ОбщийМодуль2/Ext/Module.bsl  CommonModule.Расш1_ОбщийМодуль2    CommonModule         CommonModule.Расш1_ОбщийМодуль2
  cfe/Documents/Документ1/Ext/ObjectModule.bsl         Document.Документ1                 ObjectModule         Document.Документ1
  Модули объектов в слитой конфигурации, getModules():
    CommonModule.ОбщийМодуль1: cf/CommonModules/ОбщийМодуль1/Ext/Module.bsl (файла нет)
    Document.Документ1: cfe/Documents/Документ1/Ext/ObjectModule.bsl
  Итог: решение не знает cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl, а расширение знает — ошибка воспроизводится

== BSL LS analyze --srcDir with-base-bsl (основа и расширение)
  cf/CommonModules/ОбщийМодуль1/Ext/Module.bsl         CommonModule.ОбщийМодуль1          CompilationDirectiveNeedLess
  cf/Documents/Документ1/Ext/ObjectModule.bsl          Document.Документ1                 CompilationDirectiveNeedLess
  cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl        mdoRef = URI файла                 —
  cfe/CommonModules/Расш1_ОбщийМодуль2/Ext/Module.bsl  CommonModule.Расш1_ОбщийМодуль2    CompilationDirectiveNeedLess
  cfe/Documents/Документ1/Ext/ObjectModule.bsl         Document.Документ1                 CompilationDirectiveNeedLess, MissingCommonModuleMethod

== BSL LS analyze --srcDir with-base-bsl/cfe (только расширение)
  CommonModules/ОбщийМодуль1/Ext/Module.bsl            CommonModule.ОбщийМодуль1          CompilationDirectiveNeedLess
  CommonModules/Расш1_ОбщийМодуль2/Ext/Module.bsl      CommonModule.Расш1_ОбщийМодуль2    CompilationDirectiveNeedLess
  Documents/Документ1/Ext/ObjectModule.bsl             Document.Документ1                 CompilationDirectiveNeedLess

Итог: ошибка воспроизводится — mdclasses не находит по URI cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl
```

В слитой конфигурации у документа оба модуля, а у общего модуля — только модуль основы. Без BSL основы это путь к файлу, которого нет.

В `analyze` по основе с расширением у файла заимствованного общего модуля нет ни типа, ни объекта метаданных: `mdoRef` равен URI файла, и `CompilationDirectiveNeedLess` на нём не срабатывает. На модуле документа из расширения появляется `MissingCommonModuleMethod` — «Метод Расш1_Обработать общего модуля ОбщийМодуль1 не существует». Если анализировать одно расширение, тот же файл привязан к `CommonModule.ОбщийМодуль1`.

С mdclasses 0.20.0, подставленной через `MDCLASSES_JAR`, первый шаг даёт тот же результат.

## Почему analyze в один поток

`analyze` здесь запускается с `-Djava.util.concurrent.ForkJoinPool.common.parallelism=1`. При параллельном разборе этот пример зависает из-за другой ошибки BSL LS: модули объекта `Документ1` из основы и из расширения ждут друг друга. Это отдельный issue в 1c-syntax/bsl-language-server.

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

Если архив распаковался без признака исполняемого файла — `bash run.sh …`. Нужны JDK 21+ (`java`, `javac`, `jar`) и `jq`. mdclasses и её зависимости скрипт берёт из jar-а BSL LS (`BOOT-INF/lib`). Сначала он компилирует `SolutionProbe.java` и вызывает `MDClasses.createSolution` на обоих вариантах, затем запускает `analyze` BSL LS: основу вместе с расширением и, для сравнения, одно расширение. Другая сборка mdclasses подставляется в первый шаг через `MDCLASSES_JAR=/путь/к/mdclasses.jar`. На `analyze` эта переменная не влияет: он всегда работает на mdclasses из jar-а BSL LS, поэтому после исправления его раздел вывода не изменится.

## Что должно быть

Для `cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl` в обоих вариантах выполнены три условия:

- `Solution.findChild(uri)` — `CommonModule.ОбщийМодуль1`;
- `getModuleTypeByURI(uri)` — `CommonModule`;
- среди `getModules()` слитого `CommonModule.ОбщийМодуль1` есть модуль расширения, а в `with-base-bsl` — и модуль основы. Путь основы без файла в `without-base-bsl` не проверяется.

Тогда зонд печатает «Итог: ошибка не воспроизводится — выполнены все условия», а скрипт завершается с кодом 0. Код 1 — ошибка воспроизводится, в строке «Итог» перечислены невыполненные условия. Код 2 — сбой: зонд не собрался, упал, напечатал «Итог: сбой» или не одну строку «Итог»; `analyze` упал, завис или не записал отчёт. Причину и конец лога скрипт выводит в stderr.

## Что получается

BSL LS 1.1.0-rc.9 (внутри mdclasses 0.21.0), macOS, OpenJDK 21, код выхода 1:

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
  Итог: ошибка воспроизводится — Solution.findChild(uri) = —, нужно CommonModule.ОбщийМодуль1; getModuleTypeByURI(uri) = UNKNOWN, нужно CommonModule; среди модулей слитого CommonModule.ОбщийМодуль1 нет cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl

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
  Итог: ошибка воспроизводится — Solution.findChild(uri) = —, нужно CommonModule.ОбщийМодуль1; getModuleTypeByURI(uri) = UNKNOWN, нужно CommonModule; среди модулей слитого CommonModule.ОбщийМодуль1 нет cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl

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

Итог: ошибка воспроизводится — см. строки «Итог» зонда mdclasses выше
```

В слитой конфигурации у документа оба модуля, а у общего модуля — только модуль основы. Без BSL основы это путь к файлу, которого нет.

В `analyze` по основе с расширением у файла заимствованного общего модуля нет ни типа, ни объекта метаданных: `mdoRef` равен URI файла, и `CompilationDirectiveNeedLess` на нём не срабатывает. На модуле документа из расширения появляется `MissingCommonModuleMethod` — «Метод Расш1_Обработать общего модуля ОбщийМодуль1 не существует». Если анализировать одно расширение, тот же файл привязан к `CommonModule.ОбщийМодуль1`.

С mdclasses 0.20.0, подставленной через `MDCLASSES_JAR`, первый шаг даёт тот же результат.

## Почему analyze в один поток

`analyze` здесь запускается с `-Djava.util.concurrent.ForkJoinPool.common.parallelism=1`. При параллельном разборе этот пример зависает: модули объекта `Документ1` из основы и из расширения ждут друг друга. Это другая ошибка BSL LS, к этому issue она не относится.

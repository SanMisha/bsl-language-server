# Слитая заимствованная форма теряет обработчики из Form.xml расширения

Пример к issue в 1c-syntax/mdclasses. Выгрузка конфигуратора:

```text
src/
  cf/    основа: документ Документ1 с управляемой формой ФормаДокумента;
         в Form.xml обработчики ПриСозданииНаСервере (форма) и НомерПриИзменении (поле Номер)
  cfe/   расширение Расширение1: заимствованы Документ1 и ФормаДокумента;
         в Form.xml расширения свои обработчики с callType и блок <BaseForm>:
           OnCreateAtServer    Before  Расш1_ПриСозданииНаСервереПеред
           BeforeWriteAtServer After   Расш1_ПередЗаписьюНаСервереПосле
           Номер.OnChange      After   Расш1_НомерПриИзмененииПосле
         в модуле формы — эти три процедуры и Расш1_Подготовить, которую вызывает первая
cfg/bsl-ls.json              настройки analyze: только UnusedLocalMethod
cfg/bsl-ls-no-base-bsl.json  то же и excludePaths: cf/** — BSL основы в анализ не попадает
FormHandlersProbe.java       прямой вызов API mdclasses
```

Структура заимствованной формы (`Forms/ФормаДокумента.xml` с `ObjectBelonging`/`ExtendedConfigurationObject`, `Form.xml` с `callType` и `<BaseForm>`) взята из рабочего расширения и сокращена.

## Как запустить

```bash
./run.sh /путь/к/bsl-language-server-1.1.0-rc.9-exec.jar
```

Если после распаковки у `run.sh` пропал признак исполняемого файла, запустите `bash run.sh …`.

Нужны JDK 21+ (`java`, `javac`, `jar`) и `jq`. mdclasses и её зависимости скрипт берёт из jar-а BSL LS (`BOOT-INF/lib`).

1. Компилирует `FormHandlersProbe.java` и вызывает `MDClasses.createSolution` на `src`. По этому шагу считаются итог и код выхода.
2. Трижды запускает `analyze` BSL LS: основа с расширением, то же без BSL основы, одно расширение. Эти прогоны показывают, как потеря видна в диагностиках, и на итог не влияют.

Другую сборку mdclasses, например с исправлением, можно подставить так: `MDCLASSES_JAR=/путь/к/mdclasses.jar ./run.sh …`. Она меняет только шаг 1: `analyze` всегда работает на mdclasses из jar-а BSL LS.

## Что должно быть

У слитой `Document.Документ1.Form.ФормаДокумента` есть обработчики и основы, и расширения. Пробник пишет «у слитой формы есть все обработчики расширения — ошибка не воспроизводится», последняя строка — «Итог по mdclasses: ошибка не воспроизводится», код выхода 0. Если и BSL LS собран на исправленной mdclasses, `analyze` по основе с расширением не помечает три обработчика расширения, как и при анализе одного расширения.

## Что получается

BSL LS 1.1.0-rc.9 (внутри mdclasses 0.21.0), macOS на Apple Silicon, OpenJDK 21. На Ubuntu 24.04 (aarch64, OpenJDK 21, без платформы 1С) вывод тот же, только без строк `Loaded … platform contexts`:

```text
== mdclasses, src (основа и расширение)
  mdclasses: mdclasses-0.21.0.jar
  Основа: Конфигурация, расширения: Расширение1
  Обработчики Document.Документ1.Form.ФормаДокумента:
    слитая (Solution), OWN:
      форма:    OnCreateAtServer → ПриСозданииНаСервере
      элементы: Номер: OnChange → НомерПриИзменении
      модули:   cf/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl, cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl
    основа, OWN:
      форма:    OnCreateAtServer → ПриСозданииНаСервере
      элементы: Номер: OnChange → НомерПриИзменении
      модули:   cf/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl
    расширение Расширение1, ADOPTED:
      форма:    OnCreateAtServer → Расш1_ПриСозданииНаСервереПеред, BeforeWriteAtServer → Расш1_ПередЗаписьюНаСервереПосле
      элементы: Номер: OnChange → Расш1_НомерПриИзмененииПосле
      модули:   cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl
  Solution.findChild(<cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl>) — Document.Документ1.Form.ФормаДокумента, это слитая форма
  Итог: у слитой формы нет обработчиков расширения OnCreateAtServer → Расш1_ПриСозданииНаСервереПеред, BeforeWriteAtServer → Расш1_ПередЗаписьюНаСервереПосле, OnChange → Расш1_НомерПриИзмененииПосле — ошибка воспроизводится

Дальше — analyze BSL LS: как потеря видна в диагностиках. analyze работает на mdclasses
из jar-а BSL LS, MDCLASSES_JAR на него не влияет; на итог и код выхода эти прогоны не влияют.

== BSL LS analyze --srcDir src (основа и расширение)
  Loaded 2542 platform contexts from 1C syntax helper
  cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl:2  UnusedLocalMethod  Расш1_ПриСозданииНаСервереПеред
  cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl:7  UnusedLocalMethod  Расш1_ПередЗаписьюНаСервереПосле
  cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl:11  UnusedLocalMethod  Расш1_НомерПриИзмененииПосле
  cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl:15  UnusedLocalMethod  Расш1_Подготовить

== BSL LS analyze --srcDir src, BSL основы исключён (excludePaths: cf/**)
  Loaded 2542 platform contexts from 1C syntax helper
  cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl:2  UnusedLocalMethod  Расш1_ПриСозданииНаСервереПеред
  cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl:7  UnusedLocalMethod  Расш1_ПередЗаписьюНаСервереПосле
  cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl:11  UnusedLocalMethod  Расш1_НомерПриИзмененииПосле

== BSL LS analyze --srcDir src/cfe (только расширение)
  Loaded 2542 platform contexts from 1C syntax helper
  замечаний нет

Итог по mdclasses: ошибка воспроизводится — обработчики формы из Form.xml расширения потеряны при слиянии
```

Расширение читается верно: `Solution.getExtensions()` отдаёт форму со всеми тремя обработчиками. В слитой форме модули обоих `Form.xml`, а обработчики — только из `Form.xml` основы. Модуль расширения `Solution.findChild(uri)` привязывает к этой слитой форме.

BSL LS строит тип формы по слитой конфигурации, и обработчики расширения в нём не объявлены. В варианте без BSL основы модуль формы один, конфликтовать ему не с чем, а три обработчика всё равно помечены. `Расш1_Подготовить` в первом прогоне — другой механизм, 1c-syntax/bsl-language-server#4266: ссылку на метод ищут в документе по `(mdoRef, тип модуля)` и попадают в модуль основы. Без BSL основы этого замечания нет. Синтакс-помощник на результат не влияет: с `v8platform.enabled: false` замечания те же.

## Почему analyze в один поток

`analyze` здесь запускается с `-Djava.util.concurrent.ForkJoinPool.common.parallelism=1`: при параллельном разборе первый вариант зависает. Это отдельная ошибка BSL LS (взаимоблокировка при параллельном разборе модулей основы и расширения, 1c-syntax/bsl-language-server#4952), в этот issue она не входит.

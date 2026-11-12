#!/usr/bin/env bash
# mdclasses: решение из одного расширения теряет «Назначение использования» (UsePurposes).
#
#   [MDCLASSES_JAR=<jar mdclasses>] ./run.sh <путь к bsl-language-server-<версия>-exec.jar> [<каталог платформы с shcntx_ru.hbk>]
#
# Нужны JDK 21+ (java, javac, jar) и jq. mdclasses и её зависимости берутся из jar-а BSL LS.
# MDCLASSES_JAR — необязательный jar mdclasses, например собранный с исправлением. Он ставится
# первым в -Dloader.path и перекрывает mdclasses из BOOT-INF/lib jar-а BSL LS; analyze тогда
# запускается через PropertiesLauncher.
#   1. UsePurposesProbe.java: MDClasses.createSolution на ext/ (расширение) и cf/ (конфигурация)
#      и корневые свойства основы, расширения и решения.
#   2. analyze BSL LS с bsl-ls.json (только MemberAccessUnavailable) на ext/ и cf/.
#      Доступность членов диагностика берёт из синтакс-помощника платформы. Без второго
#      аргумента BSL LS ищет установленную платформу сам; без справки замечаний нет ни в одном прогоне.
# Результаты — в out/<дата-время>/. Код выхода: 0 — ошибка не воспроизвелась, 1 — воспроизвелась, 2 — сбой.

set -u

usage="Использование: [MDCLASSES_JAR=<jar mdclasses>] $0 <путь к bsl-language-server-<версия>-exec.jar> [<каталог платформы с shcntx_ru.hbk>]"
if [ $# -lt 1 ] || [ $# -gt 2 ] || [ ! -f "$1" ]; then
  echo "$usage" >&2
  exit 2
fi
for tool in java javac jar jq; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "Не найден $tool" >&2
    exit 2
  fi
done

JAR="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
PLATFORM_DIR="${2:-}"
MDC=""
if [ -n "${MDCLASSES_JAR:-}" ]; then
  if [ ! -f "$MDCLASSES_JAR" ]; then
    echo "MDCLASSES_JAR: нет файла $MDCLASSES_JAR" >&2
    exit 2
  fi
  MDC="$(cd "$(dirname "$MDCLASSES_JAR")" && pwd)/$(basename "$MDCLASSES_JAR")"
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HERE/out/$STAMP"
mkdir -p "$OUT/lib" "$OUT/classes"
LAUNCHER=org.springframework.boot.loader.launch.PropertiesLauncher

echo "BSL LS: $(basename "$JAR")"
echo "Java: $(java -version 2>&1 | head -n 1)"

# 1. Прямой вызов API mdclasses
libs="$(jar tf "$JAR" | grep -E '^BOOT-INF/lib/(mdclasses|bsl-common-library|supportconf|utils)-[0-9][^/]*\.jar$')"
if ! echo "$libs" | grep -q 'mdclasses-'; then
  echo "В $JAR нет BOOT-INF/lib/mdclasses-*.jar" >&2
  exit 2
fi
(cd "$OUT/lib" && jar xf "$JAR" $libs) || exit 2
if [ -n "$MDC" ]; then
  echo "mdclasses: $(basename "$MDC") из MDCLASSES_JAR (перекрывает BOOT-INF/lib)"
  compile_cp="$MDC:$OUT/lib/BOOT-INF/lib/*"
  probe_path="$MDC,$OUT/classes"
else
  echo "mdclasses: $(echo "$libs" | grep 'mdclasses-' | sed -e 's#.*/mdclasses-##' -e 's#\.jar$##') из jar-а BSL LS"
  compile_cp="$OUT/lib/BOOT-INF/lib/*"
  probe_path="$OUT/classes"
fi
if ! javac -encoding UTF-8 -proc:none -cp "$compile_cp" -d "$OUT/classes" "$HERE/UsePurposesProbe.java" \
  > "$OUT/javac.log" 2>&1; then
  cat "$OUT/javac.log" >&2
  exit 2
fi

echo
echo "== mdclasses: MDClasses.createSolution"
java -cp "$JAR" -Dloader.path="$probe_path" -Dloader.main=UsePurposesProbe \
  "$LAUNCHER" "$HERE/ext" "$HERE/cf" > "$OUT/probe.log" 2>&1
if ! grep -q '^| ' "$OUT/probe.log"; then
  cat "$OUT/probe.log" >&2
  exit 2
fi
grep '^| ' "$OUT/probe.log" | sed 's/^| /  /'
reproduced=0
if grep -q '^|   Итог: у расширения назначение задано, у решения список пуст' "$OUT/probe.log"; then
  reproduced=1
fi

# 2. analyze BSL LS
config="$HERE/bsl-ls.json"
if [ -n "$PLATFORM_DIR" ]; then
  config="$OUT/bsl-ls-platform.json"
  jq --arg dir "$PLATFORM_DIR" '. + {v8platform: {binPath: $dir}}' "$HERE/bsl-ls.json" > "$config"
fi

bsl_ls() { # аргументы BSL LS; с MDCLASSES_JAR — через PropertiesLauncher
  if [ -n "$MDC" ]; then
    java -cp "$JAR" -Dloader.path="$MDC" -Dloader.main=com.github._1c_syntax.bsl.languageserver.MainApplication \
      "$LAUNCHER" "$@"
  else
    java -jar "$JAR" "$@"
  fi
}

analyze() { # <имя запуска> <каталог для --srcDir> <подпись>
  local name="$1" src="$2" title="$3"
  local dir="$OUT/$name"
  mkdir -p "$dir"
  echo
  echo "== BSL LS analyze --srcDir $(basename "$src") ($title)"
  (cd "$dir" && bsl_ls analyze --srcDir "$src" --configuration "$config" \
    --outputDir "$dir" --reporter json > "$dir/analyze.log" 2>&1)
  if [ ! -f "$dir/bsl-json.json" ]; then
    echo "  analyze не создал отчёт, лог — out/$STAMP/$name/analyze.log"
    return 1
  fi
  local helper
  helper="$(grep -h -o -E 'Loaded [0-9]+ platform contexts from 1C syntax helper|Failed to load platform contexts from 1C syntax helper: .*' \
    "$dir/analyze.log")"
  if [ -n "$helper" ]; then
    echo "  $helper"
  else
    echo "  справка платформы не загружена: передайте каталог платформы вторым аргументом"
  fi
  jq -r '[.fileinfos[].diagnostics[]]
    | if length == 0 then "  замечаний нет"
      else .[] | "  строка \(.range.start.line + 1): \(.message)" end' "$dir/bsl-json.json"
}

analyze ext "$HERE/ext" "корень — расширение"
analyze cf "$HERE/cf" "корень — конфигурация, тот же модуль"

mobile() { # <имя запуска> — число замечаний про режимы мобильного приложения
  if [ -f "$OUT/$1/bsl-json.json" ]; then
    jq '[.fileinfos[].diagnostics[] | select(.message | test("Мобильное приложение|Mobile application"))] | length' \
      "$OUT/$1/bsl-json.json"
  else
    echo "—"
  fi
}

echo
echo "Замечаний про мобильное приложение: ext — $(mobile ext), cf — $(mobile cf)"
if [ "$reproduced" -eq 1 ]; then
  echo "Итог: ошибка воспроизводится — у расширения getUsePurposes() не пуст, у решения пуст"
  exit 1
fi
echo "Итог: ошибка не воспроизводится"
exit 0

#!/usr/bin/env bash
# Таблица поля диаграммы Ганта в Form.xml лежит прямо в <GanttChartField>, без <ChildItems>,
# и mdclasses её не читает.
#
#   ./run.sh <путь к bsl-language-server-<версия>-exec.jar>
#
# Нужны JDK 21+ (java, javac, jar) и jq. mdclasses и её зависимости берутся из jar-а BSL LS.
#   1. Прямой вызов API mdclasses (probe/FormProbe.java): элементы формы в src/ и control/.
#   2. analyze BSL LS по src/ и control/.
# src/     — форма так, как её выгружает конфигуратор: <Table> прямо в <GanttChartField>.
# control/ — та же форма, <Table> обёрнут в <ChildItems>.
# MDCLASSES_JAR — другой jar mdclasses (например, сборка с исправлением): подкладывается
# перед mdclasses из jar-а BSL LS и в шаге 1, и в шаге 2.
# Результаты — в out/. Код выхода: 0 — ошибка не воспроизвелась, 1 — воспроизвелась, 2 — сбой.

set -u

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Использование: $0 <путь к bsl-language-server-<версия>-exec.jar>" >&2
  exit 2
fi
for tool in java javac jar jq; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "Не найден $tool" >&2
    exit 2
  fi
done

JAR="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
ELEMENTS="ДиаграммаТаблица ДиаграммаТаблицаТекст"
mkdir -p "$OUT/lib" "$OUT/classes"

echo "BSL LS: $(basename "$JAR")"
echo "Java: $(java -version 2>&1 | head -n 1)"

# 1. Прямой вызов API mdclasses
libs="$(jar tf "$JAR" | grep -E '^BOOT-INF/lib/(mdclasses|bsl-common-library|supportconf|utils)-[0-9][^/]*\.jar$')"
if ! echo "$libs" | grep -q 'mdclasses-'; then
  echo "В $JAR нет BOOT-INF/lib/mdclasses-*.jar" >&2
  exit 2
fi
(cd "$OUT/lib" && jar xf "$JAR" $libs) || exit 2
echo "mdclasses в jar-е BSL LS: $(echo "$libs" | grep 'mdclasses-' | sed -e 's#.*/mdclasses-##' -e 's#\.jar$##')"
probe_cp="$OUT/lib/BOOT-INF/lib/*"
overlay=""
if [ -n "${MDCLASSES_JAR:-}" ]; then
  if [ ! -f "$MDCLASSES_JAR" ]; then
    echo "MDCLASSES_JAR: нет файла $MDCLASSES_JAR" >&2
    exit 2
  fi
  MDCLASSES_JAR="$(cd "$(dirname "$MDCLASSES_JAR")" && pwd)/$(basename "$MDCLASSES_JAR")"
  echo "MDCLASSES_JAR: $MDCLASSES_JAR"
  probe_cp="$MDCLASSES_JAR:$probe_cp"
  overlay="$MDCLASSES_JAR,"
fi
if ! javac -encoding UTF-8 -proc:none -cp "$probe_cp" -d "$OUT/classes" "$HERE/probe/FormProbe.java" \
  > "$OUT/javac.log" 2>&1; then
  cat "$OUT/javac.log" >&2
  exit 2
fi

probe_lost=0
for variant in src control; do
  echo
  echo "== mdclasses, $variant/"
  # shellcheck disable=SC2086
  java -cp "$JAR" -Dloader.path="${overlay}$OUT/classes" -Dloader.main=FormProbe \
    org.springframework.boot.loader.launch.PropertiesLauncher "$HERE/$variant" $ELEMENTS \
    > "$OUT/probe-$variant.log" 2>&1
  if ! grep -q '^| Итог' "$OUT/probe-$variant.log"; then
    echo "  пробник не отработал, лог — out/probe-$variant.log" >&2
    exit 2
  fi
  grep '^| ' "$OUT/probe-$variant.log" | sed 's/^| /  /'
  if [ "$variant" = src ] && grep -q '^| Итог: mdclasses потеряла' "$OUT/probe-$variant.log"; then
    probe_lost=1
  fi
done

# 2. analyze BSL LS
analyze() { # <каталог>
  local name="$1" dir="$OUT/analyze-$1"
  mkdir -p "$dir"
  if [ -n "$overlay" ]; then
    java -cp "$JAR" -Dloader.path="${overlay%,}" \
      -Dloader.main=com.github._1c_syntax.bsl.languageserver.MainApplication \
      org.springframework.boot.loader.launch.PropertiesLauncher analyze \
      --srcDir "$HERE/$name" --outputDir "$dir" --reporter json --silent > "$dir/analyze.log" 2>&1
  else
    java -jar "$JAR" analyze \
      --srcDir "$HERE/$name" --outputDir "$dir" --reporter json --silent > "$dir/analyze.log" 2>&1
  fi
  if [ ! -f "$dir/bsl-json.json" ]; then
    echo "  analyze не создал отчёт, лог — out/analyze-$name/analyze.log" >&2
    exit 2
  fi
  jq -r '[.fileinfos[].diagnostics[]]
    | if length == 0 then "  замечаний нет"
      else .[] | "  строка \(.range.start.line + 1): \(.code) — \(.message)" end' "$dir/bsl-json.json"
}

echo
echo "== BSL LS analyze, src/"
analyze src
echo
echo "== BSL LS analyze, control/"
analyze control

unused="$(jq '[.fileinfos[].diagnostics[] | select(.code == "UnusedLocalMethod")] | length' \
  "$OUT/analyze-src/bsl-json.json")"
echo
if [ "$probe_lost" -eq 1 ] || [ "$unused" -gt 0 ]; then
  echo "Итог: ошибка воспроизводится — в src/ mdclasses не отдаёт таблицу поля диаграммы Ганта" \
    "и её колонку, BSL LS выдаёт UnusedLocalMethod: $unused"
  exit 1
fi
echo "Итог: ошибка не воспроизводится"
exit 0

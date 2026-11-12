#!/usr/bin/env bash
# Воспроизведение: при слиянии основы и расширения у заимствованной формы остаются обработчики
# событий только из Form.xml основы, а обработчики из Form.xml расширения (callType Before/After)
# теряются. BSL LS после этого считает их неиспользуемыми методами.
#
#   ./run.sh <путь к bsl-language-server-<версия>-exec.jar>
#
# Нужны JDK 21+ (java, javac, jar) и jq. mdclasses и её зависимости берутся из jar-а BSL LS.
#   1. Прямой вызов API mdclasses (FormHandlersProbe.java): обработчики формы в Solution, основе и расширении.
#   2. analyze BSL LS, только UnusedLocalMethod: основа с расширением; то же без BSL основы;
#      только расширение. Это следствие для BSL LS, на итог не влияет.
# TIMEOUT — сколько секунд ждать один analyze (по умолчанию 120).
# MDCLASSES_JAR — другой jar mdclasses для шага 1 (например, сборка с исправлением); analyze
# в шаге 2 всегда работает на mdclasses из jar-а BSL LS.
# Результаты — в out/<дата-время>/. Итог и код выхода — по шагу 1:
# 0 — ошибка не воспроизвелась, 1 — воспроизвелась, 2 — сбой.

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
TIMEOUT="${TIMEOUT:-120}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HERE/out/$STAMP"
PID=""
mkdir -p "$OUT/lib" "$OUT/classes"

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2> /dev/null; then
    kill -9 "$PID" 2> /dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

decode() { # %D0%9E… → UTF-8
  printf '%b' "${1//%/\\x}"
}

echo "BSL LS: $(basename "$JAR")"
echo "Java: $(java -version 2>&1 | head -n 1)"

# 1. Прямой вызов API mdclasses
libs="$(jar tf "$JAR" | grep -E '^BOOT-INF/lib/(mdclasses|bsl-common-library|supportconf|utils)-[0-9][^/]*\.jar$')"
if ! echo "$libs" | grep -q 'mdclasses-'; then
  echo "В $JAR нет BOOT-INF/lib/mdclasses-*.jar" >&2
  exit 2
fi
(cd "$OUT/lib" && jar xf "$JAR" $libs) || exit 2
probe_cp="$OUT/lib/BOOT-INF/lib/*"
loader_path="$OUT/classes"
if [ -n "${MDCLASSES_JAR:-}" ]; then
  if [ ! -f "$MDCLASSES_JAR" ]; then
    echo "MDCLASSES_JAR: нет файла $MDCLASSES_JAR" >&2
    exit 2
  fi
  MDCLASSES_JAR="$(cd "$(dirname "$MDCLASSES_JAR")" && pwd)/$(basename "$MDCLASSES_JAR")"
  probe_cp="$MDCLASSES_JAR:$probe_cp"
  loader_path="$MDCLASSES_JAR,$loader_path"
fi
if ! javac -encoding UTF-8 -proc:none -cp "$probe_cp" -d "$OUT/classes" "$HERE/FormHandlersProbe.java" \
  > "$OUT/javac.log" 2>&1; then
  cat "$OUT/javac.log" >&2
  exit 2
fi

echo
echo "== mdclasses, src (основа и расширение)"
java -cp "$JAR" -Dloader.path="$loader_path" -Dloader.main=FormHandlersProbe \
  org.springframework.boot.loader.launch.PropertiesLauncher "$HERE/src" > "$OUT/probe.log" 2>&1
if ! grep -q '^| Итог: ' "$OUT/probe.log"; then
  echo "  пробник не отработал, лог — out/$STAMP/probe.log" >&2
  exit 2
fi
grep '^| ' "$OUT/probe.log" | sed 's/^| /  /'
reproduced=0
if grep -q '^| Итог: .*ошибка воспроизводится' "$OUT/probe.log"; then
  reproduced=1
fi

# 2. analyze BSL LS. Один поток: с параллельным разбором пример с двумя модулями одной формы
# может зависнуть из-за другой ошибки BSL LS (модули основы и расширения ждут друг друга).
analyze() { # <имя запуска> <каталог для --srcDir> <файл настроек>
  name="$1"
  src="$2"
  dir="$OUT/$name"
  mkdir -p "$dir"
  cd "$dir" || exit 2
  java -Djava.util.concurrent.ForkJoinPool.common.parallelism=1 -jar "$JAR" analyze \
    --srcDir "$src" --outputDir "$dir" --reporter json -c "$3" > "$dir/analyze.log" 2>&1 &
  PID=$!
  cd "$HERE" || exit 2
  waited=0
  while kill -0 "$PID" 2> /dev/null; do
    if [ "$waited" -ge "$TIMEOUT" ]; then
      kill "$PID" 2> /dev/null
      sleep 5
      kill -9 "$PID" 2> /dev/null
      wait "$PID" 2> /dev/null
      PID=""
      echo "  analyze не завершился за $TIMEOUT с, лог — out/$STAMP/$name/analyze.log"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$PID"
  PID=""
  if [ ! -f "$dir/bsl-json.json" ]; then
    echo "  нет отчёта, лог — out/$STAMP/$name/analyze.log"
    return 1
  fi
  grep -h -o -E 'Loaded [0-9]+ platform contexts from 1C syntax helper' "$dir/analyze.log" | sed 's/^/  /'
  jq -r '[.fileinfos[] | (.path | sub("^.*/src/"; "")) as $p | .diagnostics[]
      | [$p, (.range.start.line + 1 | tostring), (.message | capture("\"(?<m>[^\"]+)\"").m)] | @tsv]
    | if length == 0 then "-\t-\tзамечаний нет" else .[] end' "$dir/bsl-json.json" |
  while IFS="$(printf '\t')" read -r path line method; do
    if [ "$path" = "-" ]; then
      echo "  $method"
    else
      echo "  $(decode "$path"):$line  UnusedLocalMethod  $method"
    fi
  done | tee "$dir/summary.txt"
  return 0
}

echo
echo "Дальше — analyze BSL LS: как потеря видна в диагностиках. analyze работает на mdclasses"
echo "из jar-а BSL LS, MDCLASSES_JAR на него не влияет; на итог и код выхода эти прогоны не влияют."
echo
echo "== BSL LS analyze --srcDir src (основа и расширение)"
analyze solution "$HERE/src" "$HERE/cfg/bsl-ls.json"
echo
echo "== BSL LS analyze --srcDir src, BSL основы исключён (excludePaths: cf/**)"
analyze solution-no-base-bsl "$HERE/src" "$HERE/cfg/bsl-ls-no-base-bsl.json"
echo
echo "== BSL LS analyze --srcDir src/cfe (только расширение)"
analyze extension-only "$HERE/src/cfe" "$HERE/cfg/bsl-ls.json"

echo
if [ "$reproduced" -eq 1 ]; then
  echo "Итог по mdclasses: ошибка воспроизводится — обработчики формы из Form.xml расширения потеряны при слиянии"
  exit 1
fi
echo "Итог по mdclasses: ошибка не воспроизводится"
exit 0

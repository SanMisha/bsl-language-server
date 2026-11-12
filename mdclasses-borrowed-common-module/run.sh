#!/usr/bin/env bash
# Воспроизведение: после слияния основной конфигурации и расширения mdclasses не находит
# по URI модуль заимствованного общего модуля из расширения.
#
#   ./run.sh <путь к bsl-language-server-<версия>-exec.jar>
#
# Нужны JDK 21+ (java, javac, jar) и jq. mdclasses и её зависимости берутся из jar-а BSL LS.
#   1. Прямой вызов API mdclasses (SolutionProbe.java) на with-base-bsl и without-base-bsl.
#   2. analyze BSL LS с bsl-ls.json: основа вместе с расширением и, для сравнения, только расширение.
# TIMEOUT — сколько секунд ждать один analyze (по умолчанию 120).
# MDCLASSES_JAR — другой jar mdclasses для шага 1 (например, сборка с исправлением); analyze
# в шаге 2 всегда работает на mdclasses из jar-а BSL LS.
# Результаты — в out/<дата-время>/. Код выхода: 0 — ошибка не воспроизвелась, 1 — воспроизвелась, 2 — сбой.

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
BORROWED="cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl"
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

pad() { # <строка> <ширина> — выравнивание по символам, а не по байтам
  printf '%s' "$1"
  n=$(($2 - ${#1}))
  if [ "$n" -gt 0 ]; then
    printf "%${n}s" ""
  fi
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
echo "mdclasses в jar-е BSL LS: $(echo "$libs" | grep 'mdclasses-' | sed -e 's#.*/mdclasses-##' -e 's#\.jar$##')"
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
if ! javac -encoding UTF-8 -proc:none -cp "$probe_cp" -d "$OUT/classes" "$HERE/SolutionProbe.java" \
  > "$OUT/javac.log" 2>&1; then
  cat "$OUT/javac.log" >&2
  exit 2
fi

reproduced=0
for variant in with-base-bsl without-base-bsl; do
  echo
  echo "== mdclasses, $variant"
  java -cp "$JAR" -Dloader.path="$loader_path" -Dloader.main=SolutionProbe \
    org.springframework.boot.loader.launch.PropertiesLauncher "$HERE/$variant" > "$OUT/probe-$variant.log" 2>&1
  grep '^| ' "$OUT/probe-$variant.log" | sed 's/^| /  /'
  if grep -q '^| Итог: .*ошибка воспроизводится' "$OUT/probe-$variant.log"; then
    reproduced=1
  fi
done

# 2. analyze BSL LS. Один поток: с параллельным разбором этот пример зависает из-за другой
# ошибки BSL LS — модули объекта Документ1 из основы и из расширения ждут друг друга.
analyze() { # <имя запуска> <каталог для --srcDir>
  name="$1"
  src="$2"
  dir="$OUT/$name"
  mkdir -p "$dir"
  cd "$dir" || exit 2
  java -Djava.util.concurrent.ForkJoinPool.common.parallelism=1 -jar "$JAR" analyze \
    --srcDir "$src" --outputDir "$dir" --reporter json -c "$HERE/bsl-ls.json" > "$dir/analyze.log" 2>&1 &
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
  base="$(basename "$src")"
  jq -r --arg base "$base" '
    .fileinfos[]
    | (.path | split("/")) as $s
    | [ ($s[(($s | rindex([$base])) + 1):] | join("/")),
        (if (.mdoRef // "" | startswith("file:")) then "mdoRef = URI файла" else (.mdoRef // "") end),
        ([.diagnostics[].code] | if length == 0 then "—" else join(", ") end) ]
    | @tsv' "$dir/bsl-json.json" | sort |
  while IFS="$(printf '\t')" read -r path ref codes; do
    printf '  %s %s %s\n' "$(pad "$(decode "$path")" 52)" "$(pad "$ref" 34)" "$codes"
  done
  return 0
}

echo
echo "== BSL LS analyze --srcDir with-base-bsl (основа и расширение)"
analyze solution "$HERE/with-base-bsl"
echo
echo "== BSL LS analyze --srcDir with-base-bsl/cfe (только расширение)"
analyze extension-only "$HERE/with-base-bsl/cfe"

echo
if [ "$reproduced" -eq 1 ]; then
  echo "Итог: ошибка воспроизводится — mdclasses не находит по URI $BORROWED"
  exit 1
fi
echo "Итог: ошибка не воспроизводится"
exit 0

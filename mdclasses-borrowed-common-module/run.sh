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
# Результаты — в out/<дата-время>/.
# Код выхода по итогу зонда mdclasses в обоих вариантах:
#   0 — ошибка не воспроизводится (выполнены все условия), 1 — воспроизводится,
#   2 — сбой: нет инструментов, зонд не собрался или упал, напечатал не одну строку «Итог»
#       или «Итог: сбой», analyze упал, завис или не записал отчёт.

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

fail() { # <сообщение> [лог] — сообщение, конец лога и код выхода 2
  echo >&2
  echo "Сбой: $1" >&2
  if [ -n "${2:-}" ] && [ -f "$2" ]; then
    echo "Конец лога ${2#"$HERE"/}:" >&2
    tail -n 20 "$2" | sed 's/^/  /' >&2
  fi
  exit 2
}

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
  fail "в $JAR нет BOOT-INF/lib/mdclasses-*.jar"
fi
(cd "$OUT/lib" && jar xf "$JAR" $libs) || fail "не удалось извлечь библиотеки из $JAR"
echo "mdclasses в jar-е BSL LS: $(echo "$libs" | grep 'mdclasses-' | sed -e 's#.*/mdclasses-##' -e 's#\.jar$##')"
probe_cp="$OUT/lib/BOOT-INF/lib/*"
loader_path="$OUT/classes"
if [ -n "${MDCLASSES_JAR:-}" ]; then
  if [ ! -f "$MDCLASSES_JAR" ]; then
    fail "MDCLASSES_JAR: нет файла $MDCLASSES_JAR"
  fi
  MDCLASSES_JAR="$(cd "$(dirname "$MDCLASSES_JAR")" && pwd)/$(basename "$MDCLASSES_JAR")"
  probe_cp="$MDCLASSES_JAR:$probe_cp"
  loader_path="$MDCLASSES_JAR,$loader_path"
fi
if ! javac -encoding UTF-8 -proc:none -cp "$probe_cp" -d "$OUT/classes" "$HERE/SolutionProbe.java" \
  > "$OUT/javac.log" 2>&1; then
  fail "SolutionProbe.java не скомпилировался" "$OUT/javac.log"
fi

reproduced=0
for variant in with-base-bsl without-base-bsl; do
  echo
  echo "== mdclasses, $variant"
  log="$OUT/probe-$variant.log"
  java -cp "$JAR" -Dloader.path="$loader_path" -Dloader.main=SolutionProbe \
    org.springframework.boot.loader.launch.PropertiesLauncher "$HERE/$variant" > "$log" 2>&1
  rc=$?
  grep '^| ' "$log" | sed 's/^| /  /'
  if [ "$rc" -ne 0 ]; then
    fail "зонд mdclasses на $variant завершился с кодом $rc" "$log"
  fi
  verdicts="$(grep -c '^| Итог: ' "$log")"
  if [ "$verdicts" -ne 1 ]; then
    fail "зонд mdclasses на $variant напечатал строк «Итог»: $verdicts, а должен одну" "$log"
  fi
  if grep -q '^| Итог: сбой' "$log"; then
    fail "зонд mdclasses не смог проверить $variant" "$log"
  elif grep -q '^| Итог: ошибка воспроизводится' "$log"; then
    reproduced=1
  elif ! grep -q '^| Итог: ошибка не воспроизводится' "$log"; then
    fail "непонятная строка «Итог» зонда mdclasses на $variant" "$log"
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
      fail "analyze --srcDir ${src#"$HERE"/} не завершился за $TIMEOUT с" "$dir/analyze.log"
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$PID"
  rc=$?
  PID=""
  if [ "$rc" -ne 0 ]; then
    fail "analyze --srcDir ${src#"$HERE"/} завершился с кодом $rc" "$dir/analyze.log"
  fi
  if [ ! -s "$dir/bsl-json.json" ]; then
    fail "analyze --srcDir ${src#"$HERE"/} не записал bsl-json.json" "$dir/analyze.log"
  fi
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
}

echo
echo "== BSL LS analyze --srcDir with-base-bsl (основа и расширение)"
analyze solution "$HERE/with-base-bsl"
echo
echo "== BSL LS analyze --srcDir with-base-bsl/cfe (только расширение)"
analyze extension-only "$HERE/with-base-bsl/cfe"

echo
if [ "$reproduced" -eq 1 ]; then
  echo "Итог: ошибка воспроизводится — см. строки «Итог» зонда mdclasses выше"
  exit 1
fi
echo "Итог: ошибка не воспроизводится — зонд mdclasses выполнил все условия в обоих вариантах"
exit 0

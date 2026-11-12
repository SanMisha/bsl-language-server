#!/usr/bin/env bash
# Воспроизведение взаимоблокировки analyze: основная конфигурация (src/cf) и расширение
# (src/cfe), в обеих есть модуль объекта одного документа.
#
#   ./run.sh <путь к bsl-language-server-<версия>-exec.jar>
#
# Нужны JDK 21+ (java; для дампа потоков — jstack или jcmd) и jq.
#   TIMEOUT — сколько секунд ждать один запуск analyze (по умолчанию 60);
#   RUNS    — сколько раз запустить analyze с настройками по умолчанию (по умолчанию 3).
# После них — один запуск с обходом -Djava.util.concurrent.ForkJoinPool.common.parallelism=1.
# Результаты — в out/<дата-время>/<запуск>/: bsl-json.json, analyze.log, при зависании threads.txt.
# Код выхода: 0 — зависаний не было, 1 — analyze завис хотя бы раз, 2 — ошибка запуска.

set -u

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Использование: $0 <путь к bsl-language-server-<версия>-exec.jar>" >&2
  exit 2
fi
for tool in java jq; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "Не найден $tool" >&2
    exit 2
  fi
done

JAR="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
HERE="$(cd "$(dirname "$0")" && pwd)"
TIMEOUT="${TIMEOUT:-60}"
RUNS="${RUNS:-3}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HERE/out/$STAMP"
PID=""

# Не оставлять JVM, если скрипт прервали.
cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2> /dev/null; then
    kill -9 "$PID" 2> /dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

dump_threads() { # <pid> <файл дампа> <лог процесса>
  if command -v jstack > /dev/null 2>&1; then
    jstack -l "$1" > "$2" 2>&1
  elif command -v jcmd > /dev/null 2>&1; then
    jcmd "$1" Thread.print -l > "$2" 2>&1
  else
    kill -3 "$1" 2> /dev/null # JVM пишет дамп в свой stdout, то есть в лог
    sleep 2
    cp "$3" "$2"
  fi
}

stop_jvm() { # <pid>
  kill "$1" 2> /dev/null
  i=0
  while [ "$i" -lt 10 ] && kill -0 "$1" 2> /dev/null; do
    sleep 1
    i=$((i + 1))
  done
  kill -9 "$1" 2> /dev/null
  wait "$1" 2> /dev/null
}

print_deadlock() { # <файл дампа>
  if ! grep -q 'Found one Java-level deadlock' "$1"; then
    echo "  в дампе нет секции «Found one Java-level deadlock»"
    return
  fi
  sed -n '/^Found one Java-level deadlock/,/^Java stack information/p' "$1" | sed '$d' | sed 's/^/  /'
  awk '
    /^Java stack information for the threads listed above/ { s = 1; next }
    s && /^Found [0-9]+ deadlock/ { exit }
    s && /^"/ { print "  " $0; n = 0; next }
    s && /com\.github\._1c_syntax\.bsl\.languageserver/ && !/Lambda|CGLIB|AjcClosure|aroundBody/ {
      if (n < 14) print "  " $0
      n++
    }
  ' "$1"
}

run_analyze() { # <имя запуска> [параметры JVM...]; 0 — завершился, 1 — завис
  name="$1"
  shift
  dir="$OUT/$name"
  mkdir -p "$dir"
  # Рабочий каталог процесса — пустой каталог результата: случайный
  # .bsl-language-server.json из текущего каталога не подхватится.
  cd "$dir" || exit 2
  java "$@" -jar "$JAR" analyze --srcDir "$HERE/src" --outputDir "$dir" --reporter json \
    > "$dir/analyze.log" 2>&1 &
  PID=$!
  cd "$HERE" || exit 2
  waited=0
  while kill -0 "$PID" 2> /dev/null; do
    if [ "$waited" -ge "$TIMEOUT" ]; then
      dump_threads "$PID" "$dir/threads.txt" "$dir/analyze.log"
      stop_jvm "$PID"
      PID=""
      echo "$name: analyze не завершился за $TIMEOUT с, дамп потоков — out/$STAMP/$name/threads.txt"
      print_deadlock "$dir/threads.txt"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$PID"
  rc=$?
  PID=""
  files="$(jq '.fileinfos | length' "$dir/bsl-json.json" 2> /dev/null || echo '?')"
  echo "$name: analyze завершился за ${waited} с, код выхода $rc, файлов в отчёте: $files"
  return 0
}

echo "BSL LS: $(basename "$JAR")"
echo "Java: $(java -version 2>&1 | head -n 1)"
echo "Пример: src/cf (основа) и src/cfe (расширение), модуль объекта Документ1 есть в обеих"
echo

hung=0
n=1
while [ "$n" -le "$RUNS" ]; do
  if ! run_analyze "default-$n"; then
    hung=$((hung + 1))
  fi
  n=$((n + 1))
done
echo
run_analyze "parallelism-1" -Djava.util.concurrent.ForkJoinPool.common.parallelism=1
echo
echo "Итог: зависаний с настройками по умолчанию — $hung из $RUNS"
[ "$hung" -eq 0 ]

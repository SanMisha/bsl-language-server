#!/usr/bin/env bash
# Какой .bsl-language-server.json BSL Language Server применяет к папке, в зависимости
# от каталога, из которого запущен analyze. Три запуска, подробности — в README.md.
#
# Использование: ./run.sh <путь к bsl-language-server-*-exec.jar>
# Нужны Java 21+ и jq. Отчёты и логи — в out/ рядом со скриптом.
# Код возврата: 0 — все три запуска дали ожидаемые настройки, 1 — нет, 2 — сбой запуска.
set -euo pipefail

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Использование: $0 <путь к bsl-language-server-*-exec.jar>" >&2
  exit 2
fi
for tool in java jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Не найден $tool" >&2; exit 2; }
done

JAR="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Чьи настройки применились, по составу замечаний в Module.bsl:
# файл multi/b поднимает maxLineLength до 200 (LineLength пропадает),
# файл multi/a выключает EmptyCodeBlock.
whose() {
  case "$1" in
    *EmptyCodeBlock*LineLength*) echo "по умолчанию" ;;
    *EmptyCodeBlock*) echo "папки multi/b" ;;
    *LineLength*) echo "папки multi/a" ;;
    *) echo "обоих файлов" ;;
  esac
}

# analyze <каталог запуска> <путь к папке от него> <имя прогона>; печатает коды замечаний
analyze() {
  local out="$HERE/out/$3"
  mkdir -p "$out"
  : > "$out/bsl-json.json"  # отчёт прошлого запуска не должен попасть в итог
  (cd "$HERE/$1" && java -jar "$JAR" analyze -s "$2" -o "$out" -r json -q) > "$out/log.txt" 2>&1 || true
  if [ ! -s "$out/bsl-json.json" ]; then
    echo "analyze не создал отчёт, см. out/$3/log.txt" >&2
    exit 2
  fi
  jq -r '[.fileinfos[].diagnostics[].code] | sort | join(", ")' "$out/bsl-json.json"
}

failed=""
# step <номер> <каталог запуска> <путь к папке> <пояснение> <ожидаемые настройки>
step() {
  local codes got
  codes=$(analyze "$2" "$3" "run$1")
  got=$(whose "$codes")
  echo "$1. cd $2 && analyze -s $3"
  echo "   $4"
  echo "   замечания: $codes"
  echo "   настройки: $got (ожидается: $5)"
  echo
  [ "$got" = "$5" ] || failed="${failed:+$failed, }$1"
}

echo "BSL Language Server $(java -jar "$JAR" version 2>/dev/null | tail -n 1 | sed 's/^version: //')"
echo
step 1 multi b "в каталоге запуска нет .bsl-language-server.json" "папки multi/b"
step 2 multi/a ../b "в каталоге запуска лежит файл папки multi/a" "папки multi/b"
step 3 multi/a src "у multi/a/src своего файла нет, как у src/cf при запуске из корня репозитория" "папки multi/a"

if [ -z "$failed" ]; then
  echo "Итог: все запуски дали ожидаемые настройки."
  exit 0
fi
case "$failed" in
  *,*) echo "Итог: не те настройки в запусках $failed." ;;
  *) echo "Итог: не те настройки в запуске $failed." ;;
esac
exit 1

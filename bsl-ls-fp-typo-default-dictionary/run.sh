#!/usr/bin/env bash
# Typo: встроенный словарь исключений и настройки по умолчанию.
# Нужны java 21+ и jq.
#
#   ./run.sh <путь к bsl-language-server-*-exec.jar>
#
# Два прогона analyze по src/:
#   default     — cfg/default.json, параметров Typo нет;
#   with-params — cfg/with-params.json, {"Typo": {"minWordLength": 3}},
#                 то есть значение по умолчанию, заданное явно.
# Печатаются только замечания Typo. Отчёты и логи — в out/<прогон>/.
set -euo pipefail

usage="Использование: ./run.sh <путь к bsl-language-server-*-exec.jar>"
JAR="${1:?$usage}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

analyze() {
  local name="$1" config="$2"
  local out="$HERE/out/$name"
  mkdir -p "$out"
  java -jar "$JAR" analyze \
    --srcDir "$HERE/src" \
    --configuration "$config" \
    --outputDir "$out" \
    --reporter json \
    --silent > "$out/analyze.log" 2>&1
  jq -r '[.fileinfos[].diagnostics[] | select(.code == "Typo")]
    | sort_by(.range.start.line, .range.start.character)
    | "замечаний Typo: \(length)",
      (.[] | "  строка \(.range.start.line + 1): \(.message)")' \
    "$out/bsl-json.json"
}

echo "== cfg/default.json — параметров Typo нет"
analyze default "$HERE/cfg/default.json"

echo "== cfg/with-params.json — Typo: {\"minWordLength\": 3}"
analyze with-params "$HERE/cfg/with-params.json"

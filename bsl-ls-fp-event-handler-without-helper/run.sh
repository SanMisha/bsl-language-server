#!/usr/bin/env bash
# EventHandlerInvalidSignature без синтакс-помощника платформы.
# Нужны java 21+ и jq.
#
#   ./run.sh <путь к bsl-language-server-*-exec.jar> [<каталог платформы с shcntx_ru.hbk>]
#
# Без второго аргумента — один прогон с выключенным синтакс-помощником
# (cfg/no-helper.json). Со вторым — ещё прогон с синтакс-помощником из указанного каталога.
# Печатаются только замечания EventHandlerInvalidSignature; полные отчёты и логи — в out/<прогон>/.
set -euo pipefail

usage="Использование: ./run.sh <путь к bsl-language-server-*-exec.jar> [<каталог платформы с shcntx_ru.hbk>]"
JAR="${1:?$usage}"
PLATFORM_DIR="${2:-}"
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
  grep -h -o -E 'Loaded [0-9]+ platform contexts from 1C syntax helper|Failed to load platform contexts from 1C syntax helper: .*' \
    "$out/analyze.log" || true
  jq -r '[.fileinfos[].diagnostics[] | select(.code == "EventHandlerInvalidSignature")]
    | if length == 0 then "замечаний EventHandlerInvalidSignature нет"
      else .[] | "строка \(.range.start.line + 1): \(.code) — \(.message)" end' \
    "$out/bsl-json.json"
}

echo "== Без синтакс-помощника (v8platform.enabled = false)"
analyze no-helper "$HERE/cfg/no-helper.json"

if [ -n "$PLATFORM_DIR" ]; then
  mkdir -p "$HERE/out"
  jq -n --arg dir "$PLATFORM_DIR" '{v8platform: {binPath: $dir}}' > "$HERE/out/with-helper.json"
  echo "== С синтакс-помощником ($PLATFORM_DIR)"
  analyze with-helper "$HERE/out/with-helper.json"
fi

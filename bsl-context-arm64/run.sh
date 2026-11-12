#!/usr/bin/env bash
# Что видит автопоиск платформы 1С из bsl-context на этой машине.
# Нужна java 21+.
#
#   ./run.sh <путь к bsl-context-0.10.2.jar>
#
# Сначала печатает каталоги версий с shcntx_ru.hbk, которые есть на диске,
# потом — что из них нашёл PlatformFinder.
set -euo pipefail

JAR="${1:?Использование: ./run.sh <путь к bsl-context-0.10.2.jar>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Система: $(uname -sm)"
if command -v dpkg >/dev/null 2>&1; then
  echo "== Архитектура пакетов: $(dpkg --print-architecture)"
fi

echo "== Справка платформы на диске (/opt/1cv8):"
found=0
for hbk in /opt/1cv8/*/shcntx_ru.hbk /opt/1cv8/*/*/shcntx_ru.hbk; do
  if [ -f "$hbk" ]; then
    echo "$hbk"
    found=1
  fi
done
if [ "$found" -eq 0 ]; then
  echo "не найдена"
fi

echo "== PlatformFinder:"
java -cp "$JAR" "$HERE/PlatformFinderProbe.java"

#!/usr/bin/env bash
# Harde regels van dart_code_linter, los van `flutter analyze`.
#
# `flutter analyze` wacht niet op de plugin, dus welke bestanden die dekt is
# willekeurig; daarom telt de analyzegate pluginmeldingen niet mee. Deze stap
# draait de CLI van dart_code_linter zelf (`metrics analyze`), die elk bestand
# onder lib/ en test/ zelf analyseert zonder analysis server: twee runs geven
# byte voor byte dezelfde uitvoer. Alleen de regels hieronder blokkeren; ze
# vinden echte fouten (setState na een await zonder mounted-check, en
# vergelijkingen tussen types die nooit gelijk kunnen zijn). De rest van de
# plugin blijft advies.
#
# ci_checks.sh (met --with-unused) en ci.yml roepen allebei dit script aan,
# zodat lokaal en CI dezelfde aanroep draaien.
set -uo pipefail

rules='use-setstate-synchronously|avoid-collection-methods-with-unrelated-types|avoid-unrelated-type-assertions'

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

# --no-fatal-warnings: exit 0 betekent dan "analyse voltooid". Elke andere
# exitcode (crash, pub niet opgehaald, een regel op error) laat de stap falen,
# zodat een stille crash nooit als groen telt.
dart run dart_code_linter:metrics analyze lib test --no-congratulate --no-fatal-warnings >"$out" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
  echo "dart_code_linter analyze stopte met exit $status:"
  tail -n 40 "$out"
  exit 1
fi

# Uitvoer per melding: tekst, "at <pad>:<regel>:<kolom>", "<regel-id> : <url>".
hits="$(grep -B1 -E "^[[:space:]]+($rules) : " "$out" | grep -E "^[[:space:]]+at " | sed -E 's/^[[:space:]]+at //' || true)"
if [ -n "$hits" ]; then
  echo "harde dart_code_linter-regels geschonden:"
  grep -A1 -E "^[[:space:]]+at " "$out" | grep -B1 -E "^[[:space:]]+($rules) : " | grep -vE '^--$' | sed 's/^[[:space:]]*/    /'
  exit 1
fi
echo "geen overtredingen van $rules"

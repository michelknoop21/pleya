#!/usr/bin/env bash
set -uo pipefail

# Vergelijkt de Flutter op PATH met de pin in .fvmrc.
#
# `dart format` verschilt per SDK-versie, dus een lokale SDK die een paar
# patches voorloopt op wat CI draait levert formatteringsverschillen op die
# pas in CI opvallen. Dit script onderschept dat vóór het commiten in plaats
# van het achteraf te rapporteren; het draait daarom aan het begin van
# ci_checks.sh, codegen.sh en testflight_release.sh.
#
#   scripts/check_flutter_version.sh          # controleer, exit 1 bij drift
#   scripts/check_flutter_version.sh --print  # print alleen de pin uit .fvmrc
#
# .fvmrc is bewust de enige bron van waarheid: subosito/flutter-action leest
# hetzelfde bestand via `flutter-version-file: .fvmrc`, dus de workflows en de
# werkplek kunnen niet uit elkaar lopen. pubspec.yaml is geen alternatief —
# `environment.flutter` is hier een range (>=3.44.0), geen exacte versie.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FVMRC="$ROOT/.fvmrc"

if [ ! -f "$FVMRC" ]; then
  echo "check_flutter_version: .fvmrc ontbreekt in $ROOT" >&2
  exit 1
fi

read_pin() {
  if command -v jq >/dev/null 2>&1; then
    jq -er '.flutter' "$FVMRC" 2>/dev/null
  else
    # Zelfde sleutel, zonder jq: "flutter": "3.44.0"
    sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FVMRC" | head -1
  fi
}

PINNED="$(read_pin)"
if [ -z "${PINNED:-}" ] || [ "$PINNED" = "null" ]; then
  echo "check_flutter_version: geen \"flutter\"-sleutel in .fvmrc" >&2
  exit 1
fi

if [ "${1:-}" = "--print" ]; then
  echo "$PINNED"
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "check_flutter_version: flutter staat niet op PATH (pin: $PINNED)" >&2
  exit 1
fi

# Eerste regel is "Flutter 3.44.0 • channel stable • …". Een SDK die zichzelf
# nog moet bouwen print daarvóór voortgang, dus filteren op de Flutter-regel.
FOUND="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9][^ ]*\).*/\1/p' | head -1)"
if [ -z "$FOUND" ]; then
  echo "check_flutter_version: kon de versie niet uit 'flutter --version' lezen" >&2
  exit 1
fi

if [ "$FOUND" != "$PINNED" ]; then
  cat >&2 <<EOF
check_flutter_version: Expected $PINNED, found $FOUND

  .fvmrc pint dit project op Flutter $PINNED; op PATH staat $FOUND ($(command -v flutter)).
  dart format verschilt per SDK-versie, dus doorwerken levert diff-ruis die
  pas in CI opvalt.

  Zet de gepinde SDK vóór de rest in PATH, bijvoorbeeld:
    export PATH="/Volumes/SSD/flutter-sdks/$PINNED/flutter/bin:\$PATH"
EOF
  exit 1
fi

exit 0

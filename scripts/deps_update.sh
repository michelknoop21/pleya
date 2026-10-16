#!/usr/bin/env bash
set -uo pipefail

# Wekelijkse ring-1-baan: tilt de pakketten op die check_updates.sh als ring 1
# aanmerkt, resolveert daarna de hele graph en laat classify_lock_diff.sh de
# volledige lockfile-diff beoordelen, dus ook alles wat stil meeverhuisde. De
# hoogste ring in die diff beslist; er wordt niet per pakket teruggedraaid.
# Schrijft alleen pubspec.lock; committen, gates en de PR doet
# dependency-health.yml.
#
#   scripts/deps_update.sh                 # werkt in de working tree
#   scripts/deps_update.sh --report r.json # gebruik een bestaand --json-rapport
#
# Exit: 0 bijgewerkt en de hele diff is ring 1, 4 bijgewerkt maar minstens één
# wijziging is ring 2, 3 of UNKNOWN (geen auto-merge), 3 niets te doen,
# 1 upgrade of resolutie faalde (lockfile teruggezet), 2 rapport onbruikbaar.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --report) REPORT="${2:-}"; shift 2 || exit 64 ;;
    *) echo "deps_update: onbekend argument: $1" >&2; exit 64 ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -z "$REPORT" ]; then
  REPORT="$TMP/report.json"
  "$SCRIPT_DIR/check_updates.sh" --only dart --json >"$REPORT" || true
fi

# De ring-1-lijst staat als "naam oud -> nieuw ..." in de reden van dart-lockfile.
# Geblokkeerde pakketten (DEC-026, rate_limiter) zitten daar al niet in.
NAMES="$(python3 - "$REPORT" <<'PY'
import json, re, sys
try:
    rows = json.load(open(sys.argv[1], encoding="utf-8"))["components"]
except Exception:
    sys.exit(2)
row = next((r for r in rows if r["component"] == "dart-lockfile"), None)
if row is None or row["status"] == "UNKNOWN":
    sys.exit(2)
print(" ".join(re.findall(r"(\S+) \S+ -> \S+", row["reason"])))
PY
)" || { echo "deps_update: rapport onbruikbaar ($REPORT)" >&2; exit 2; }

if [ -z "$NAMES" ]; then
  echo "deps_update: geen ring-1-pakketten achter"
  exit 3
fi

cp "$ROOT/pubspec.lock" "$TMP/old.lock"
# shellcheck disable=SC2086 # NAMES is bewust een woordenlijst
(cd "$ROOT" && flutter pub upgrade $NAMES) || {
  cp "$TMP/old.lock" "$ROOT/pubspec.lock"
  echo "deps_update: flutter pub upgrade faalde" >&2
  exit 1
}

# De hele graph moet nog kloppen met de nieuwe lockfile, niet alleen de
# pakketten die we noemden.
(cd "$ROOT" && flutter pub get --enforce-lockfile) || {
  cp "$TMP/old.lock" "$ROOT/pubspec.lock"
  echo "deps_update: volledige resolutie faalde" >&2
  exit 1
}

if cmp -s "$TMP/old.lock" "$ROOT/pubspec.lock"; then
  echo "deps_update: lockfile ongewijzigd"
  exit 3
fi

# Volledige diff, inclusief transitieve meeverhuizers. De hoogste ring wint.
"$SCRIPT_DIR/classify_lock_diff.sh" --old "$TMP/old.lock" --new "$ROOT/pubspec.lock" | tee "$TMP/classify.txt"
echo "deps_update: gevraagd: $NAMES"
if grep -q 'ring2=0 ring3=0 unknown=0' "$TMP/classify.txt"; then
  exit 0
fi
echo "deps_update: diff bevat ring 2, 3 of UNKNOWN; geen auto-merge" >&2
exit 4

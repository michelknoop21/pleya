#!/usr/bin/env sh
# TestFlight: elke platform-lane als EIGEN proces met timeout, zodat één hang
# de andere niet blokkeert (de reguliere `fastlane beta` draait alles serieel
# in één proces — een hang blokkeert dan de rest).
#
# Gebruik:
#   scripts/testflight_separate.sh              # ios tvos macos
#   scripts/testflight_separate.sh tvos         # alleen tvOS
#   scripts/testflight_separate.sh ios tvos     # subset, in die volgorde
#
# Timeout per lane instelbaar via env (default 30m):
#   TESTFLIGHT_LANE_TIMEOUT=45m scripts/testflight_separate.sh
set -u
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

[ -f .env ] || { echo "FOUT: .env ontbreekt (zie .env.example)" >&2; exit 1; }

LANES="${*:-ios tvos macos}"
TIMEOUT="${TESTFLIGHT_LANE_TIMEOUT:-30m}"

# Elke lane gaat door de gedeelde wachtrij voor zwaar werk. Die wacht op andere
# builds in plaats van ze te stoppen: dit script ruimde vroeger met `pkill`
# elke `flutter build` op de machine op, ook die van een andere sessie.
# Standaard de wachtrij uit deze repo (docs/agents/heavy-work.md), zoals
# testflight_release.sh; een andere kies je met PLEYA_HEAVY=/pad/naar/pleya-heavy.
if [ -n "${PLEYA_HEAVY:-}" ]; then
  [ -x "$PLEYA_HEAVY" ] || { echo "FOUT: wachtrij $PLEYA_HEAVY ontbreekt." >&2; exit 1; }
  heavy() { "$PLEYA_HEAVY" "$@"; }
else
  heavy() { python3 scripts/heavy_queue.py "$@"; }
fi

status=""
for pf in $LANES; do
  lane="${pf}_beta"
  echo "=== $lane (timeout $TIMEOUT) — $(date '+%H:%M:%S') ==="
  # De wachtrij begrenst de lane met zijn eigen procesgroep: na de timeout
  # SIGTERM, 15 s later SIGKILL, en exit 124 zoals coreutils timeout.
  heavy run --label "$lane" --run-timeout "$TIMEOUT" --kill-after 15s -- fastlane "$lane"
  rc=$?
  case "$rc" in
    0)   status="$status ${pf}:ok" ;;
    124) status="$status ${pf}:TIMEOUT" ; echo ">> $lane hing en is na $TIMEOUT gekilld — door naar de volgende." >&2 ;;
    *)   status="$status ${pf}:FAIL($rc)" ; echo ">> $lane faalde (exit $rc) — door naar de volgende." >&2 ;;
  esac
done

echo "=== klaar:$status ==="
# Non-zero als iets niet ok is, zodat launchd/CI het merkt.
case "$status" in
  *TIMEOUT*|*FAIL*) exit 1 ;;
  *) exit 0 ;;
esac

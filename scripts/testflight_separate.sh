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

# coreutils timeout: `timeout` (linux) of `gtimeout` (brew coreutils op macOS).
TO="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
[ -n "$TO" ] || echo "WAARSCHUWING: geen (g)timeout gevonden — lanes draaien zonder hang-guard." >&2

# Ruim stale flutter-build processen op: een achtergebleven `flutter build`
# houdt de flutter-toollock vast en laat de volgende build hangen op
# "Building ... for device". Dit was de oorzaak van de vorige vastloper.
pkill -f "flutter_tools.snapshot build" 2>/dev/null || true
pkill -f "flutter build ios" 2>/dev/null || true
pkill -f "flutter build macos" 2>/dev/null || true

status=""
for pf in $LANES; do
  lane="${pf}_beta"
  echo "=== $lane (timeout $TIMEOUT) — $(date '+%H:%M:%S') ==="
  # -k 15: 15s na SIGTERM alsnog SIGKILL. Eigen sessie (setsid indien aanwezig)
  # zodat de hele proces-tree meegaat bij een hang.
  if [ -n "$TO" ]; then
    if command -v setsid >/dev/null 2>&1; then
      setsid "$TO" -k 15 "$TIMEOUT" fastlane "$lane"
    else
      "$TO" -k 15 "$TIMEOUT" fastlane "$lane"
    fi
  else
    fastlane "$lane"
  fi
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

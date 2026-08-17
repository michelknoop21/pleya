#!/usr/bin/env bash
# TestFlight release: build & upload, commit het (auto-bepaalde) buildnummer.
# Gebruik: scripts/testflight_release.sh [beta|ios_beta|tvos_beta|macos_beta]
# Het buildnummer wordt in de Fastfile bepaald (hoogste TestFlight-build +1),
# dus dit script bumpt niet zelf. Draait ook headless via launchd (zie docs/TESTFLIGHT.md).
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# De gepinde SDK moet vóór homebrew staan, anders wint een nieuwere
# /opt/homebrew/bin/flutter van de pin uit .fvmrc en blokkeert de preflight
# hieronder zijn eigen release. Dit geldt ook headless: launchd start met een
# minimale PATH, dus zonder deze regel resolvet flutter daar naar homebrew.
# Geen match op deze machine betekent geen wijziging, dus elders blijft het
# gedrag zoals het was.
PINNED_FLUTTER="$(scripts/check_flutter_version.sh --print 2>/dev/null || true)"
PINNED_FLUTTER_BIN="${FLUTTER_SDKS_DIR:-/Volumes/SSD/flutter-sdks}/${PINNED_FLUTTER}/flutter/bin"
if [[ -n "$PINNED_FLUTTER" && -x "$PINNED_FLUTTER_BIN/flutter" ]]; then
  export PATH="$PINNED_FLUTTER_BIN:$PATH"
fi

LANE="${1:-beta}"
LOG_PREFIX="[testflight $(date '+%Y-%m-%d %H:%M')]"

# Blokkerend: een release die met een andere SDK is gebouwd dan CI verifieert,
# is niet dezelfde build.
scripts/check_flutter_version.sh

if [[ ! -f .env ]]; then
  echo "$LOG_PREFIX FOUT: .env ontbreekt (zie .env.example)" >&2
  exit 1
fi

# Adviserend, nooit blokkerend: vlak voor een release wil je zien wat er
# openstaat, maar offline of GitHub plat mag de build niet tegenhouden. Dit
# vervangt de losse MPVKit-aanroep — check_updates.sh roept die zelf aan en zet
# hem naast de engine, de Android-binaries, de git-forks en de Actions.
scripts/check_updates.sh || true

fastlane "$LANE"

# fastlane heeft pubspec.yaml op het nieuwe buildnummer gezet — leg dat vast.
new_number=$(grep -m1 '^version:' pubspec.yaml | sed 's/.*+//')
if ! git diff --quiet pubspec.yaml; then
  git add pubspec.yaml
  git commit -m "chore: bump build number to ${new_number} for TestFlight"
  git push origin HEAD || echo "$LOG_PREFIX WAARSCHUWING: push faalde, commit staat lokaal" >&2
fi
echo "$LOG_PREFIX klaar: lane ${LANE}, build ${new_number}"

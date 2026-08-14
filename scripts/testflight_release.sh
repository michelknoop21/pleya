#!/usr/bin/env bash
# TestFlight release: build & upload, commit het (auto-bepaalde) buildnummer.
# Gebruik: scripts/testflight_release.sh [beta|ios_beta|tvos_beta|macos_beta]
# Het buildnummer wordt in de Fastfile bepaald (hoogste TestFlight-build +1),
# dus dit script bumpt niet zelf. Draait ook headless via launchd (zie docs/TESTFLIGHT.md).
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

LANE="${1:-beta}"
LOG_PREFIX="[testflight $(date '+%Y-%m-%d %H:%M')]"

if [[ ! -f .env ]]; then
  echo "$LOG_PREFIX FOUT: .env ontbreekt (zie .env.example)" >&2
  exit 1
fi

# Adviserend, nooit blokkerend: MPVKit is exact gepind en levert prebuilt
# XCFrameworks, dus een nieuwe tag komt er alleen in als iemand hem haalt.
# Voor een release wil je weten dat je achterloopt; offline of GitHub plat mag
# de build niet tegenhouden.
scripts/check_mpvkit_update.sh || true

fastlane "$LANE"

# fastlane heeft pubspec.yaml op het nieuwe buildnummer gezet — leg dat vast.
new_number=$(grep -m1 '^version:' pubspec.yaml | sed 's/.*+//')
if ! git diff --quiet pubspec.yaml; then
  git add pubspec.yaml
  git commit -m "chore: bump build number to ${new_number} for TestFlight"
  git push origin HEAD || echo "$LOG_PREFIX WAARSCHUWING: push faalde, commit staat lokaal" >&2
fi
echo "$LOG_PREFIX klaar: lane ${LANE}, build ${new_number}"

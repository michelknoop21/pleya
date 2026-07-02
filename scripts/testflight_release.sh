#!/usr/bin/env bash
# TestFlight release: bump build number, commit+push, build & upload.
# Gebruik: scripts/testflight_release.sh [beta|ios_beta|tvos_beta|macos_beta]
# Draait ook headless via launchd (zie docs/TESTFLIGHT.md).
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

LANE="${1:-beta}"
LOG_PREFIX="[testflight $(date '+%Y-%m-%d %H:%M')]"

if [[ ! -f .env ]]; then
  echo "$LOG_PREFIX FOUT: .env ontbreekt (zie .env.example)" >&2
  exit 1
fi

# Bump build number in pubspec.yaml (bijv. 2.8.0+120 -> 2.8.0+121)
current=$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//')
build_name="${current%+*}"
build_number="${current#*+}"
new_number=$((build_number + 1))
sed -i '' "s/^version: .*/version: ${build_name}+${new_number}/" pubspec.yaml
echo "$LOG_PREFIX build number ${build_number} -> ${new_number}"

git add pubspec.yaml
git commit -m "chore: bump build number to ${new_number} for TestFlight"
git push origin HEAD || echo "$LOG_PREFIX WAARSCHUWING: push faalde, commit staat lokaal" >&2

fastlane "$LANE"
echo "$LOG_PREFIX klaar: lane ${LANE}, build ${new_number}"

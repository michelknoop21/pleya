#!/usr/bin/env bash
set -uo pipefail

# Reports whether the pinned MPVKit release is behind the fork's newest tag,
# and prints the commit subjects in between.
#
# MPVKit ships prebuilt XCFrameworks and carries the patches this app depends
# on (the parallel audiounit/avfoundation audio outputs, the Dolby paths, the
# inline-OSD video output). A floating SPM range would swap the mpv binary
# under the app between builds, so all three Apple projects pin an exact
# version. That pin only stays honest if something checks it — this script.
#
#   scripts/check_mpvkit_update.sh          # report only
#   scripts/check_mpvkit_update.sh --bump   # rewrite the pin to the newest tag
#
# After --bump, open each Runner.xcodeproj once (or run `xcodebuild
# -resolvePackageDependencies`) and verify playback before shipping: the
# binaries change, so audio/video regressions are the risk, not compile errors.

REPO="https://github.com/edde746/MPVKit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

BUMP=0
[ "${1:-}" = "--bump" ] && BUMP=1

PBXPROJS=(ios/Runner.xcodeproj/project.pbxproj tvos/Runner.xcodeproj/project.pbxproj macos/Runner.xcodeproj/project.pbxproj)

# The pinned version lives in the MPVKit XCRemoteSwiftPackageReference block.
current="$(awk '/XCRemoteSwiftPackageReference "MPVKit"/{f=1} f&&/version = /{gsub(/[^0-9.]/,"",$3); print $3; exit}' \
  ios/Runner.xcodeproj/project.pbxproj)"
if [ -z "$current" ]; then
  echo "Could not read the pinned MPVKit version from ios/Runner.xcodeproj." >&2
  exit 1
fi

# Highest vX.Y.Z tag by version order, not lexical order (v1.0.9 < v1.0.10).
latest="$(git ls-remote --tags --refs "$REPO" 2>/dev/null |
  sed -n 's#.*refs/tags/v##p' | sort -V | tail -1)"
if [ -z "$latest" ]; then
  echo "Could not reach $REPO to list tags." >&2
  exit 1
fi

echo "MPVKit pinned:  $current"
echo "MPVKit latest:  $latest"

if [ "$current" = "$latest" ]; then
  echo "Up to date."
  exit 0
fi

echo
echo "Changes since v$current:"
# The compare payload also carries base/merge-base commits; take only the
# commit list, so the range reads as the changes actually being pulled in.
curl -fsSL "https://api.github.com/repos/edde746/MPVKit/compare/v$current...v$latest" 2>/dev/null |
  python3 -c 'import json,sys
for c in json.load(sys.stdin).get("commits", []):
    print("  - " + c["commit"]["message"].splitlines()[0])' ||
  echo "  (could not fetch the changelog)"

if [ "$BUMP" -eq 0 ]; then
  echo
  echo "Run 'scripts/check_mpvkit_update.sh --bump' to move the pin to v$latest."
  exit 1
fi

rev="$(git ls-remote --tags --refs "$REPO" "refs/tags/v$latest" | cut -f1)"
if [ -z "$rev" ]; then
  echo "Could not resolve the commit for v$latest." >&2
  exit 1
fi

echo
for f in "${PBXPROJS[@]}"; do
  # Only the version line inside the MPVKit package reference block.
  perl -0pi -e "s/(XCRemoteSwiftPackageReference \"MPVKit\" \*\/ = \{.*?version = )\Q$current\E(;)/\${1}$latest\${2}/s" "$f"
  echo "  updated $f"
done

while IFS= read -r f; do
  perl -0pi -e "s/(\"identity\"\s*:\s*\"mpvkit\".*?\"revision\"\s*:\s*\")[0-9a-f]+(\".*?\"version\"\s*:\s*\")\Q$current\E(\")/\${1}$rev\${2}$latest\${3}/s" "$f"
  echo "  updated $f"
done < <(find . -path ./build -prune -o -name Package.resolved -print | grep -v '/build/')

echo
echo "Pin moved to v$latest. Resolve packages in Xcode and verify playback."

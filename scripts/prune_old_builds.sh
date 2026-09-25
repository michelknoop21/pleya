#!/usr/bin/env bash
# Ruimt oude builds op vóór een nieuwe build. Standaard in elke buildroute
# (scripts/tvos_sim.sh build en de TestFlight-lanes); overslaan met
# PLEYA_KEEP_BUILDS=1. Met --dry-run (of PLEYA_PRUNE_DRY_RUN=1) alleen tonen
# wat weg zou gaan.
#
# Wat weg mag en wat blijft:
#   .build/pleya-verify/<scenario>-<ms>   per scenario de nieuwste 2 bundels
#   Xcode Archives van nl.michelknoop.pleya de nieuwste 3 (een bevroren
#                                          release-archive valt daarbinnen)
#   build/ in andere Pleya-worktrees       weg als er 24 uur niets in is
#                                          geschreven en geen proces in die
#                                          worktree staat
#   Xcode DerivedData                      mappen waarin 3 dagen niets schreef
#   flutter_tools.* en tmp.* in de         na 24 uur zonder schrijfactie en
#   gebruikers-tempmap                     als geen proces ze open heeft
#   simulators van een oude SDK            xcrun simctl delete unavailable
# Incrementele build-mappen (tvos/build/dd, build/ios/SourcePackages) van de
# eigen worktree blijven: die worden bij elke build hergebruikt.
set -euo pipefail

[[ "${PLEYA_KEEP_BUILDS:-}" == 1 ]] && exit 0

DRY_RUN="${PLEYA_PRUNE_DRY_RUN:-0}"
[[ "${1:-}" == --dry-run ]] && DRY_RUN=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEEP_BUNDLES="${PLEYA_KEEP_VERIFY_BUNDLES:-2}"
KEEP_ARCHIVES="${PLEYA_KEEP_ARCHIVES:-3}"
WORKTREES="${PLEYA_WORKTREES_DIR:-$HOME/.supacode/repos/plezy-main}"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
# Niet $TMPDIR: agent-sessies zetten die vaak op een eigen map.
TMP_ROOT="${PLEYA_PRUNE_TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo "${TMPDIR:-/tmp}")}"
TMP_ROOT="${TMP_ROOT%/}"
freed=0

remove() {
  local kb
  kb=$(du -sk "$1" 2>/dev/null | cut -f1 || echo 0)
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "prune_old_builds: zou verwijderen ($((kb / 1024)) MB) $1"
    freed=$((freed + kb))
  else
    rm -rf "$1" && freed=$((freed + kb))
  fi
}

# Waar als in $1 de afgelopen $2 minuten niets is geschreven. Mapdatums zeggen
# niets over de inhoud, dus find kijkt naar elk bestand.
idle_for() {
  [[ -z "$(find "$1" -mmin "-$2" -print -quit 2>/dev/null)" ]]
}

avail_kb() { df -k "$HOME" | awk 'NR==2 {print $4}'; }
avail_before=$(avail_kb)

verify_dir="$ROOT/.build/pleya-verify"
if [[ -d "$verify_dir" ]]; then
  # Bundelnaam is <scenario-slug>-<epoch ms>; sorteer op tijdstempel, nieuwste
  # eerst, en houd per slug de eerste $KEEP_BUNDLES.
  while read -r name; do
    remove "$verify_dir/$name"
  done < <(ls "$verify_dir" | grep -E -- '-[0-9]{13}$' \
    | awk -F- '{print $NF" "$0}' | sort -rn | cut -d' ' -f2- \
    | awk -v keep="$KEEP_BUNDLES" '{slug=$0; sub(/-[0-9]+$/, "", slug); if (++n[slug] > keep) print}')
fi

archives="$HOME/Library/Developer/Xcode/Archives"
if [[ -d "$archives" ]]; then
  count=0
  while IFS= read -r archive; do
    id=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' \
      "$archive/Info.plist" 2>/dev/null || true)
    [[ "$id" == nl.michelknoop.pleya* ]] || continue
    count=$((count + 1))
    (( count > KEEP_ARCHIVES )) && remove "$archive"
  done < <(find "$archives" -maxdepth 2 -name '*.xcarchive' -print0 \
    | xargs -0 stat -f '%m %N' | sort -rn | cut -d' ' -f2-)
  [[ "$DRY_RUN" == 1 ]] || find "$archives" -mindepth 1 -maxdepth 1 -type d -empty -delete
fi

# build/ van andere worktrees. De eigen worktree slaan we over, en ook elke
# worktree waar nog een proces zijn werkmap heeft (sessie, idb, xcodebuild).
if [[ -d "$WORKTREES" ]]; then
  cwds=$(lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' || true)
  for build in "$WORKTREES"/*/build "$WORKTREES"/*/*/build; do
    [[ -d "$build" ]] || continue
    tree="${build%/build}"
    [[ "$(cd "$tree" && pwd)" == "$ROOT" ]] && continue
    grep -qF -- "$tree" <<<"$cwds" && continue
    idle_for "$build" 1440 && remove "$build"
  done
fi

if [[ -d "$DERIVED" ]]; then
  for entry in "$DERIVED"/*; do
    [[ -e "$entry" ]] || continue
    idle_for "$entry" 4320 && remove "$entry"
  done
fi

if [[ -d "$TMP_ROOT" ]]; then
  for entry in "$TMP_ROOT"/flutter_tools.* "$TMP_ROOT"/tmp.*; do
    [[ -e "$entry" ]] || continue
    idle_for "$entry" 1440 || continue
    lsof +D "$entry" >/dev/null 2>&1 && continue
    remove "$entry"
  done
fi

if command -v xcrun >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "prune_old_builds: zou 'xcrun simctl delete unavailable' draaien"
  else
    xcrun simctl delete unavailable 2>/dev/null || true
  fi
fi

avail_after=$(avail_kb)
if [[ "$DRY_RUN" == 1 ]]; then
  echo "prune_old_builds (dry-run): $((freed / 1024)) MB kan weg"
else
  echo "prune_old_builds: $((freed / 1024)) MB vrijgemaakt, vrij op schijf $((avail_before / 1048576)) GB -> $((avail_after / 1048576)) GB"
fi

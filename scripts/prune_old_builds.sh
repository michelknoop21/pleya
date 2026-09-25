#!/usr/bin/env bash
# Ruimt oude builds op vóór een nieuwe build. Standaard in elke buildroute
# (scripts/tvos_sim.sh build en de TestFlight-lanes); overslaan met
# PLEYA_KEEP_BUILDS=1.
#
# Wat weg mag en wat blijft:
#   .build/pleya-verify/<scenario>-<ms>   per scenario de nieuwste 2 bundels
#   Xcode Archives van nl.michelknoop.pleya de nieuwste 3 (een bevroren
#                                          release-archive valt daarbinnen)
# Incrementele build-mappen (tvos/build/dd, build/ios/SourcePackages) blijven:
# die worden bij elke build hergebruikt, wissen kost alleen een koude build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/link_build_dirs.sh"

[[ "${PLEYA_KEEP_BUILDS:-}" == 1 ]] && exit 0

KEEP_BUNDLES="${PLEYA_KEEP_VERIFY_BUNDLES:-2}"
KEEP_ARCHIVES="${PLEYA_KEEP_ARCHIVES:-3}"
freed=0

remove() {
  local kb
  kb=$(du -sk "$1" 2>/dev/null | cut -f1 || echo 0)
  rm -rf "$1" && freed=$((freed + kb))
}

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
  find "$archives" -mindepth 1 -maxdepth 1 -type d -empty -delete
fi

echo "prune_old_builds: $((freed / 1024)) MB vrijgemaakt"

# Alleen melden, nooit verwijderen: gemergede worktrees die een week stilliggen.
main_ref=$(git -C "$ROOT" rev-parse -q --verify github/main || git -C "$ROOT" rev-parse -q --verify origin/main || true)
if [[ -n "$main_ref" ]]; then
  week_ago=$(( $(date +%s) - 7 * 86400 ))
  git -C "$ROOT" worktree list --porcelain | awk '/^worktree /{wt=substr($0,10)} /^branch /{print wt"\t"substr($0,19)}' \
    | while IFS=$'\t' read -r wt branch; do
        [[ "$wt" == "$ROOT" ]] && continue
        git -C "$ROOT" merge-base --is-ancestor "$branch" "$main_ref" 2>/dev/null || continue
        index="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)/index"
        [[ -f "$index" ]] && (( $(stat -f %m "$index") < week_ago )) || continue
        echo "prune_old_builds: gemerged en een week stil, kan weg: $wt ($branch)"
      done
fi

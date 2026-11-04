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
#   build/ in andere Pleya-worktrees       alleen build/ direct in de root
#                                          van een worktree (daar staat .git),
#                                          weg als er 24 uur niets in is
#                                          geschreven en geen proces in die
#                                          worktree staat
#   build/ en tvos/build/ van andere       zijn ze een symlink naar
#   worktrees op de externe SSD            PLEYA_BUILD_HOME (link_build_dirs.sh),
#                                          dan geldt dezelfde regel voor de
#                                          inhoud van het doel; symlink en lege
#                                          doelmap blijven staan
#   wezen in PLEYA_BUILD_HOME              een map <sleutel> waar geen
#                                          geregistreerde worktree (ook locked
#                                          of prunable) meer bij hoort, met
#                                          bovenin alleen build, tvos, .build,
#                                          .owner of .DS_Store, en 24 uur
#                                          zonder schrijfactie; een map met
#                                          iets anders erin, of met een
#                                          .owner naar een bestaand pad (een
#                                          losse kloon), blijft altijd
#   Xcode DerivedData                      mappen waarin 3 dagen niets schreef
#   flutter_tools.* en tmp.* in de         na 24 uur zonder schrijfactie en
#   gebruikers-tempmap                     als geen proces ze open heeft
#   simulators van een oude SDK            xcrun simctl delete unavailable
# DerivedData en de tempmappen zijn niet van Pleya alleen: ook de index van
# andere Xcode-projecten en mktemp-mappen van andere tools gaan weg na die
# stilte. Dat is een bewuste keuze, want ze worden allemaal opnieuw opgebouwd.
# De sleutel van een worktree in PLEYA_BUILD_HOME rekent het script vooruit uit
# `git worktree list` met dezelfde functie als link_build_dirs.sh, plus de
# sleutels waar de symlinks van bestaande worktrees naar wijzen; een sleutel
# wordt nooit terugvertaald naar een pad. Is PLEYA_BUILD_HOME niet gekoppeld,
# dan slaat het script dat deel over, en het verwijdert nooit iets buiten die
# map. Incrementele build-mappen (tvos/build/dd, build/ios/SourcePackages) van
# de eigen worktree blijven: die worden bij elke build hergebruikt. .build/
# van andere worktrees blijft staan. Geneste build-mappen die geen symlink
# zijn (<wt>/tvos/build, <wt>/pleya_web/build) raakt het script nooit.
# Kan lsof niet zeggen wat er open is, dan blijft alles staan.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/link_build_dirs.sh"

[[ "${PLEYA_KEEP_BUILDS:-}" == 1 ]] && exit 0

DRY_RUN="${PLEYA_PRUNE_DRY_RUN:-0}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "prune_old_builds: onbekend argument '$arg' (alleen --dry-run)" >&2; exit 2 ;;
  esac
done
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
    rm -rf "${1:?}" && freed=$((freed + kb))
  fi
}

# Waar als in $1 de afgelopen $2 minuten niets is geschreven. Mapdatums zeggen
# niets over de inhoud, dus find kijkt naar elk bestand.
idle_for() {
  [[ -z "$(find "$1" -mmin "-$2" -print -quit 2>/dev/null)" ]]
}

# Waar als een proces iets onder $1 open heeft, of als lsof dat niet kan
# zeggen: een bescherming die faalt, houdt het wissen tegen. lsof +D geeft 1
# zonder uitvoer op stderr als er niets open is, en 1 met een melding bij een
# fout.
in_use() {
  local err
  command -v lsof >/dev/null 2>&1 || return 0
  err=$(lsof +D "$1" 2>&1 >/dev/null) && return 0
  [[ -n "$err" ]]
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

# Werkmappen van alle processen; leeg als lsof dat niet kan zeggen.
cwds=$(lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p') || cwds=""

# build/ van andere worktrees. De glob vindt ook <wt>/tvos/build in een
# worktree op één niveau, dus alleen een map met .git naast build/ telt als
# worktree. De eigen worktree slaan we over, en ook elke worktree waar nog een
# proces zijn werkmap heeft (sessie, idb, xcodebuild). Een symlink volgt
# hieronder bij PLEYA_BUILD_HOME.
if [[ -d "$WORKTREES" ]]; then
  if [[ -n "$cwds" ]]; then
    for build in "$WORKTREES"/*/build "$WORKTREES"/*/*/build; do
      [[ -d "$build" && ! -L "$build" ]] || continue
      tree="${build%/build}"
      [[ -e "$tree/.git" ]] || continue
      [[ "$(cd "$tree" && pwd)" == "$ROOT" ]] && continue
      grep -qF -- "$tree" <<<"$cwds" && continue
      idle_for "$build" 1440 && remove "$build"
    done
  else
    echo "prune_old_builds: lsof geeft geen werkmappen, build/ in andere worktrees blijft staan" >&2
  fi
fi

# Zelfde sleutel als link_build_dirs.sh: $HOME/ eraf, / wordt _, voorloop-punt eraf.
build_key() {
  local key="${1#"$HOME"/}"
  key="${key//\//_}"
  printf '%s\n' "${key#.}"
}

# Alleen een pad onder PLEYA_BUILD_HOME mag weg; al het andere weigeren we.
in_build_home() {
  [[ "${1:?}" == "${bh_real:?}"/?* && "$1" != *..* ]] && return 0
  echo "prune_old_builds: weigert $1, ligt niet onder $bh_real" >&2
  return 1
}

# Leegt het doel van een symlink; de map zelf blijft voor link_build_dirs.sh.
empty_target() {
  local dir="${1:?}" kb
  in_build_home "$dir" || return 0
  kb=$(du -sk "$dir" 2>/dev/null | cut -f1 || echo 0)
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "prune_old_builds: zou leegmaken ($((kb / 1024)) MB) $dir"
    freed=$((freed + kb))
  else
    rm -rf "${dir:?}" && mkdir "$dir" && freed=$((freed + kb))
  fi
}

BUILD_HOME="${PLEYA_BUILD_HOME:-/Volumes/SSD/pleya-builds}"
if [[ -d "$BUILD_HOME" && -z "$cwds" ]]; then
  echo "prune_old_builds: lsof geeft geen werkmappen, $BUILD_HOME blijft staan" >&2
elif [[ -d "$BUILD_HOME" ]]; then
  bh_real=$(cd "$BUILD_HOME" && pwd -P)
  root_real=$(cd "$ROOT" && pwd -P)
  live=$'\n'
  while IFS= read -r wt; do
    live+="$(build_key "$wt")"$'\n'
    [[ -d "$wt" ]] || continue
    wt_real=$(cd "$wt" && pwd -P)
    live+="$(build_key "$wt_real")"$'\n'
    for rel in build tvos/build .build; do
      dest=$(readlink "$wt/$rel" 2>/dev/null) || continue
      for base in "$BUILD_HOME" "$bh_real"; do
        [[ "$dest" == "$base"/?* ]] || continue
        dest="${dest#"$base"/}"
        live+="${dest%%/*}"$'\n'
        break
      done
    done
    [[ "$wt_real" == "$root_real" ]] && continue
    grep -qF -e "$wt" -e "$wt_real" <<<"$cwds" && continue
    for rel in build tvos/build; do
      [[ -L "$wt/$rel" ]] || continue
      target=$(cd "$wt/$rel" 2>/dev/null && pwd -P) || continue
      [[ "$target" == "$bh_real"/?* ]] || continue
      key_dir="${target#"$bh_real"/}"
      key_dir="$bh_real/${key_dir%%/*}"
      grep -qF -- "$key_dir" <<<"$cwds" && continue
      [[ -n "$(ls -A "$target")" ]] || continue
      idle_for "$target" 1440 && empty_target "$target"
    done
  done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')

  for dir in "$bh_real"/*; do
    [[ -d "$dir" && ! -L "$dir" ]] || continue
    grep -qxF -- "${dir##*/}" <<<"$live" && continue
    # Alleen buildinhoud; .owner en .DS_Store zijn metadata. Staat er iets
    # anders bovenin (een SDK, een probe), dan blijft de hele map.
    [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 ! -name build ! -name tvos \
      ! -name .build ! -name .owner ! -name .DS_Store -print -quit)" ]] || continue
    # Een losse kloon van de repo (geen worktree hiervan) schrijft hier ook; een
    # .owner die naar een bestaand pad wijst, houdt de map dus vast.
    owner=$(head -n 1 "$dir/.owner" 2>/dev/null) || owner=""
    [[ -n "$owner" && -e "$owner" ]] && continue
    grep -qF -- "$dir" <<<"$cwds" && continue
    idle_for "$dir" 1440 || continue
    in_build_home "$dir" && remove "$dir"
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
    in_use "$entry" && continue
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

# Alleen melden, nooit verwijderen: gemergede worktrees die een week stilliggen.
main_ref=$(git -C "$ROOT" rev-parse -q --verify github/main || git -C "$ROOT" rev-parse -q --verify origin/main || true)
if [[ -n "$main_ref" ]]; then
  week_ago=$(( $(date +%s) - 7 * 86400 ))
  git -C "$ROOT" worktree list --porcelain | awk '/^worktree /{wt=substr($0,10)} /^branch /{print wt"\t"substr($0,19)}' \
    | while IFS=$'\t' read -r wt branch; do
        [[ "$wt" == "$ROOT" ]] && continue
        git -C "$ROOT" merge-base --is-ancestor "$branch" "$main_ref" 2>/dev/null || continue
        git_dir="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)" || continue
        index="$git_dir/index"
        [[ -f "$index" ]] && (( $(stat -f %m "$index") < week_ago )) || continue
        echo "prune_old_builds: gemerged en een week stil, kan weg: $wt ($branch)"
      done
fi

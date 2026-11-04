#!/usr/bin/env bash
# Zelftest voor prune_old_builds.sh in een nep-HOME: oude build/, DerivedData
# en tempmappen gaan weg, verse blijven staan, en --dry-run wist niets.
# Geneste build-mappen in een worktree op één niveau (tvos/build,
# pleya_web/build) en een build/ die een symlink is blijven altijd staan; een
# onbekend argument of een falende lsof wist niets.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/prune_old_builds.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
cd "$sandbox"

old=$(date -v-4d '+%Y%m%d%H%M')
mk() { mkdir -p "$1"; touch "$1/f"; [[ "${2:-}" == old ]] && touch -t "$old" "$1/f" "$1"; true; }

mk home/Library/Developer/Xcode/DerivedData/Runner-oud old
mk home/Library/Developer/Xcode/DerivedData/Runner-vers
mk trees/feat/oud/build old
mk trees/vers/build
mk trees/single/tvos/build old
mk trees/other/pleya_web/build old
mk trees/linkdoel old
touch trees/feat/oud/.git trees/vers/.git trees/single/.git trees/other/.git
mkdir -p trees/lnk && touch trees/lnk/.git && ln -s ../linkdoel trees/lnk/build
touch -h -t "$old" trees/lnk/build
mk tmp/tmp.oud old
mk tmp/flutter_tools.oud old
mk tmp/tmp.vers

# PLEYA_BUILD_HOME wijst naar een map zonder ouder, zodat link_build_dirs.sh
# de build-mappen van de echte worktree niet verplaatst.
run() {
  HOME="$sandbox/home" PLEYA_WORKTREES_DIR="$sandbox/trees" \
    PLEYA_PRUNE_TMPDIR="$sandbox/tmp" PLEYA_BUILD_HOME="$sandbox/geen-ssd/builds" \
    "$script" "$@"
}
gone=(home/Library/Developer/Xcode/DerivedData/Runner-oud trees/feat/oud/build tmp/tmp.oud tmp/flutter_tools.oud)
kept=(home/Library/Developer/Xcode/DerivedData/Runner-vers trees/vers/build tmp/tmp.vers
  trees/single/tvos/build trees/other/pleya_web/build trees/lnk/build trees/linkdoel/f)

if run --dryrun >/dev/null 2>&1; then echo "FOUT: onbekend argument werd geaccepteerd"; exit 1; fi
for p in "${gone[@]}"; do [[ -e "$p" ]] || { echo "FOUT: onbekend argument wiste $p"; exit 1; }; done

# Missing registered worktrees must not abort the advisory report.
mkdir -p bin
cat >bin/git <<'GIT'
#!/usr/bin/env bash
case "$*" in
  *"worktree list --porcelain") printf 'worktree %s\nbranch refs/heads/test\n' "$PRUNE_MISSING_TREE" ;;
  *"merge-base --is-ancestor"*) exit 0 ;;
  *) exec /usr/bin/git "$@" ;;
esac
GIT
chmod +x bin/git
out=$(PATH="$sandbox/bin:$PATH" PRUNE_MISSING_TREE="$sandbox/missing" run --dry-run)
for p in "${gone[@]}" "${kept[@]}"; do [[ -e "$p" ]] || { echo "FOUT: dry-run wiste $p"; exit 1; }; done
for p in "${gone[@]}"; do grep -qF "$p" <<<"$out" || { echo "FOUT: dry-run noemt $p niet"; exit 1; }; done

PLEYA_KEEP_BUILDS=1 run
for p in "${gone[@]}"; do [[ -e "$p" ]] || { echo "FOUT: PLEYA_KEEP_BUILDS=1 wiste $p"; exit 1; }; done

# lsof die faalt: de bescherming kan niets zeggen, dus blijven build/ en de
# tempmappen staan (DerivedData hangt niet aan lsof).
mkdir -p bin && printf '#!/bin/sh\necho "lsof: kapot" >&2\nexit 1\n' >bin/lsof && chmod +x bin/lsof
PATH="$sandbox/bin:$PATH" run >/dev/null 2>&1
for p in trees/feat/oud/build tmp/tmp.oud tmp/flutter_tools.oud; do
  [[ -e "$p" ]] || { echo "FOUT: met falende lsof is $p gewist"; exit 1; }
done

run >/dev/null
for p in "${gone[@]}"; do [[ ! -e "$p" ]] || { echo "FOUT: $p staat er nog"; exit 1; }; done
for p in "${kept[@]}"; do [[ -e "$p" ]] || { echo "FOUT: $p is gewist"; exit 1; }; done
# link_build_dirs.sh in een eigen nep-worktree: een kapotte symlink (doel
# opgeruimd, ook een doel onder een andere sleutel) wordt hersteld en wijst
# daarna naar de doelmap van deze worktree; een heel symlink blijft ongemoeid.
mkdir -p ssd wt/scripts && cp "$(dirname "$script")/link_build_dirs.sh" wt/scripts/
root=$(cd wt && pwd); key="${root//\//_}"; key="${key#.}"; bh="$sandbox/ssd/builds"
mkdir -p wt/tvos "$bh/heel"; touch "$bh/heel/f"
ln -s "$bh/$key/build" wt/build                  # doel bestaat niet
ln -s "$bh/andere-sleutel/tvos/build" wt/tvos/build   # doel bestaat niet, andere sleutel
ln -s "$bh/heel" wt/.build                       # heel
HOME="$sandbox/home" PLEYA_BUILD_HOME="$bh" wt/scripts/link_build_dirs.sh
for rel in build tvos/build; do
  [[ -L "wt/$rel" && -d "wt/$rel" ]] || { echo "FOUT: kapotte symlink $rel niet hersteld"; exit 1; }
  [[ "$(readlink "wt/$rel")" == "$bh/$key/$rel" ]] || { echo "FOUT: $rel wijst naar $(readlink "wt/$rel")"; exit 1; }
done
[[ "$(readlink wt/.build)" == "$bh/heel" && -e "$bh/heel/f" ]] || { echo "FOUT: heel symlink .build is aangeraakt"; exit 1; }
HOME="$sandbox/home" PLEYA_BUILD_HOME="$bh" wt/scripts/link_build_dirs.sh   # tweede run verandert niets
[[ "$(readlink wt/build)" == "$bh/$key/build" ]] || { echo "FOUT: tweede run wijzigde build"; exit 1; }

# PLEYA_BUILD_HOME op een nep-SSD met echte worktrees van een nep-repo. Een
# symlink-doel van een andere worktree wordt na 24 uur leeggemaakt (build/ en
# tvos/build/, symlink en doelmap blijven), een vers doel blijft. Een wees
# (sleutel zonder worktree, alleen buildinhoud, 24 uur stil) gaat weg; een wees
# met iets anders erin, een verse wees of een wees met een .owner naar een
# bestaand pad (losse kloon) blijft, net als de map van een
# bestaande of prunable worktree. Paden zijn fysiek (/private/var), zodat de
# sleutels van link_build_dirs.sh en git worktree list overeenkomen.
psb=$(cd "$sandbox" && pwd -P)
bh2="$psb/ssd2/builds"
mkdir -p "$bh2" "$psb/bin2" "$psb/tmp2" "$psb/repo2/scripts" "$psb/repo2/tvos"
printf '#!/bin/sh\nexit 0\n' >"$psb/bin2/xcrun" && chmod +x "$psb/bin2/xcrun"
cp "$(dirname "$script")/prune_old_builds.sh" "$(dirname "$script")/link_build_dirs.sh" "$psb/repo2/scripts/"
g() { git -C "$psb/repo2" -c user.name=t -c user.email=t@t "$@"; }
g init -q && g add scripts && g commit -q -m init
for w in oud vers tv bestaand prunable; do g worktree add -q --detach "$psb/w-$w"; done
key() { local k="${1#"$psb/home"/}"; k="${k//\//_}"; echo "${k#.}"; }
age() { find "$@" -exec touch -h -t "$old" {} +; }
link() { HOME="$psb/home" PLEYA_BUILD_HOME="$bh2" "$psb/w-$1/scripts/link_build_dirs.sh"; }
for w in oud vers tv prunable; do mkdir -p "$psb/w-$w/tvos" && link "$w"; done
mk "$psb/w-oud/build/ios" old; age "$bh2/$(key "$psb/w-oud")"
mk "$psb/w-vers/build/ios"
mk "$psb/w-tv/tvos/build/Release" old; age "$bh2/$(key "$psb/w-tv")"
mk "$bh2/$(key "$psb/w-bestaand")/.build/pleya-verify" old; age "$bh2/$(key "$psb/w-bestaand")"
mk "$bh2/$(key "$psb/w-prunable")/build/ios" old; age "$bh2/$(key "$psb/w-prunable")"
rm -rf "$psb/w-prunable"
mk "$bh2/wees-oud/build/macos" old; mk "$bh2/wees-oud/tvos/build" old
echo /weg >"$bh2/wees-oud/.owner"; age "$bh2/wees-oud"
mk "$bh2/wees-sdk/build" old; mk "$bh2/wees-sdk/flutter/bin" old; age "$bh2/wees-sdk"
mk "$bh2/wees-vers/build/ios"
mkdir -p "$psb/kloon"; mk "$bh2/wees-kloon/build" old; echo "$psb/kloon" >"$bh2/wees-kloon/.owner"; age "$bh2/wees-kloon"
run2() {
  PATH="$psb/bin2:$PATH" HOME="$psb/home" PLEYA_WORKTREES_DIR="$psb/geen-trees" \
    PLEYA_PRUNE_TMPDIR="$psb/tmp2" PLEYA_BUILD_HOME="$bh2" "$psb/repo2/scripts/prune_old_builds.sh" "$@"
}
gone2=("$bh2/$(key "$psb/w-oud")/build/ios" "$bh2/$(key "$psb/w-tv")/tvos/build/Release" "$bh2/wees-oud")
kept2=("$bh2/$(key "$psb/w-vers")/build/ios/f" "$bh2/$(key "$psb/w-bestaand")/.build/pleya-verify/f"
  "$bh2/$(key "$psb/w-prunable")/build/ios/f" "$bh2/wees-sdk/flutter/bin/f" "$bh2/wees-vers/build/ios/f"
  "$bh2/wees-kloon/build/f")
out=$(run2 --dry-run)
for p in "${gone2[@]}" "${kept2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: dry-run wiste $p"; exit 1; }; done
for p in "$bh2/$(key "$psb/w-oud")/build" "$bh2/$(key "$psb/w-tv")/tvos/build" "$bh2/wees-oud"; do
  grep -qE "zou (leegmaken|verwijderen) \([0-9]+ MB\) $p\$" <<<"$out" || { echo "FOUT: dry-run noemt $p niet"; exit 1; }
done
PLEYA_KEEP_BUILDS=1 run2
for p in "${gone2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: PLEYA_KEEP_BUILDS=1 wiste $p"; exit 1; }; done
PATH="$sandbox/bin:$PATH" run2 >/dev/null 2>&1   # falende lsof uit het blok hierboven
for p in "${gone2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: met falende lsof is $p gewist"; exit 1; }; done
run2 >/dev/null
for p in "${gone2[@]}"; do [[ ! -e "$p" ]] || { echo "FOUT: $p staat er nog"; exit 1; }; done
for p in "${kept2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: $p is gewist"; exit 1; }; done
for rel in build tvos/build; do
  w=oud; [[ "$rel" == tvos/build ]] && w=tv
  [[ -L "$psb/w-$w/$rel" && -d "$bh2/$(key "$psb/w-$w")/$rel" ]] \
    || { echo "FOUT: symlink of lege doelmap $rel van w-$w is weg"; exit 1; }
done

echo "test_prune_old_builds: OK"

#!/usr/bin/env bash
# Zelftest voor prune_old_builds.sh in een nep-HOME: oude build/, DerivedData
# en tempmappen gaan weg, verse blijven staan, en --dry-run wist niets.
# Geneste build-mappen in een worktree op één niveau (tvos/build,
# pleya_web/build) en een build/ die een symlink is blijven altijd staan; een
# onbekend argument of een falende lsof wist niets.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/prune_old_builds.sh"
sandbox="$(mktemp -d)"
pids=""
trap '[[ -z "$pids" ]] || kill $pids 2>/dev/null; chmod -R u+w "$sandbox" 2>/dev/null; rm -rf "$sandbox"' EXIT
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
mkdir -p "$bh/$key" && echo /ander >"$bh/$key/.owner"   # bestaande eigenaar blijft
HOME="$sandbox/home" PLEYA_BUILD_HOME="$bh" wt/scripts/link_build_dirs.sh
[[ "$(head -n 1 "$bh/$key/.owner")" == /ander ]] || { echo "FOUT: bestaande .owner overschreven"; exit 1; }
grep -qxF "$root" "$bh/$key/.owner" || { echo "FOUT: worktree niet aan .owner toegevoegd"; exit 1; }
for rel in build tvos/build; do
  [[ -L "wt/$rel" && -d "wt/$rel" ]] || { echo "FOUT: kapotte symlink $rel niet hersteld"; exit 1; }
  [[ "$(readlink "wt/$rel")" == "$bh/$key/$rel" ]] || { echo "FOUT: $rel wijst naar $(readlink "wt/$rel")"; exit 1; }
done
[[ "$(readlink wt/.build)" == "$bh/heel" && -e "$bh/heel/f" ]] || { echo "FOUT: heel symlink .build is aangeraakt"; exit 1; }
HOME="$sandbox/home" PLEYA_BUILD_HOME="$bh" wt/scripts/link_build_dirs.sh   # tweede run verandert niets
[[ "$(readlink wt/build)" == "$bh/$key/build" ]] || { echo "FOUT: tweede run wijzigde build"; exit 1; }
# Een met de hand gelegde symlink via `..` schrijft geen .owner buiten BUILD_HOME.
mkdir -p "$bh/../buiten"; rm wt/.build && ln -s "$bh/../buiten" wt/.build
HOME="$sandbox/home" PLEYA_BUILD_HOME="$bh" wt/scripts/link_build_dirs.sh
[[ ! -e "$sandbox/ssd/.owner" ]] || { echo "FOUT: .owner buiten BUILD_HOME geschreven"; exit 1; }

# PLEYA_BUILD_HOME op een nep-SSD met echte worktrees van een nep-repo. Paden
# zijn fysiek (/private/var), zodat de sleutels van link_build_dirs.sh en git
# worktree list overeenkomen. Leeg na 24 uur: het symlink-doel van build/ en
# tvos/build/ van een andere worktree; symlink en doelmap blijven. Blijft: een
# vers doel, de eigen worktree, een worktree of sleutelmap met een proces erin,
# een symlink naar buiten PLEYA_BUILD_HOME. Een alleen-lezen map breekt de run
# niet af. Een wees (geen worktree, .owner naar een pad dat weg is, alleen
# buildinhoud, 24 uur stil) gaat weg, ook met .DS_Store. Blijft: een wees met
# iets anders erin (ook onder tvos/), een verse wees, een wees zonder .owner,
# een met een .owner naar een bestaand pad (losse kloon), een met een proces
# erin, en de map van een bestaande of prunable worktree. --dry-run en
# PLEYA_KEEP_BUILDS=1 veranderen geen symlink. Een PLEYA_BUILD_HOME die niet
# pleya-builds heet of gelijk is aan $HOME blijft ongemoeid. Een .owner met
# meer regels houdt de map zolang één eigenaar bestaat; een relatief pad, een
# pad met CR of spaties erachter, of een eigenaar op een niet gekoppeld volume
# telt niet als weg. Een verhuisde worktree van een losse kloon zet zichzelf
# in de .owner van zijn oude sleutelmap. Een symlink recht naar een sleutelmap
# leegt die niet.
psb=$(cd "$sandbox" && pwd -P)
bh2="$psb/ssd2/pleya-builds"
mkdir -p "$bh2" "$psb/bin2" "$psb/tmp2" "$psb/repo2/scripts" "$psb/repo2/tvos"
printf '#!/bin/sh\nexit 0\n' >"$psb/bin2/xcrun" && chmod +x "$psb/bin2/xcrun"
cp "$(dirname "$script")/prune_old_builds.sh" "$(dirname "$script")/link_build_dirs.sh" "$psb/repo2/scripts/"
g() { git -C "$psb/repo2" -c user.name=t -c user.email=t@t "$@"; }
g init -q && g add scripts && g commit -q -m init
trees=(oud vers tv bestaand prunable cwd keycwd buiten ro kdlink)
for w in "${trees[@]}"; do g worktree add -q --detach "$psb/w-$w" && mkdir -p "$psb/w-$w/tvos"; done
key() { local k="${1#"$psb/home"/}"; k="${k//\//_}"; echo "${k#.}"; }
kd() { echo "$bh2/$(key "$psb/w-$1")"; }
age() { find "$@" -exec touch -h -t "$old" {} +; }
link() { HOME="$psb/home" PLEYA_BUILD_HOME="$bh2" "$1/scripts/link_build_dirs.sh"; }
for w in oud vers tv prunable cwd keycwd ro; do link "$psb/w-$w"; done
link "$psb/repo2"
[[ "$(cat "$(kd oud)/.owner")" == "$psb/w-oud" ]] || { echo "FOUT: .owner van w-oud klopt niet"; exit 1; }
mk "$psb/w-oud/build/ios" old; age "$(kd oud)"
mk "$psb/w-vers/build/ios"
mk "$psb/w-tv/tvos/build/Release" old; age "$(kd tv)"
mk "$psb/w-cwd/build/ios" old; age "$(kd cwd)"
mk "$psb/w-keycwd/build/ios" old; age "$(kd keycwd)"
mk "$psb/w-ro/build/ro" old; age "$(kd ro)"; chmod 555 "$(kd ro)/build/ro"
mk "$psb/elders" old; ln -s "$psb/elders" "$psb/w-buiten/build"; age "$psb/elders"
mk "$bh2/$(key "$psb/repo2")/build/ios" old; age "$bh2/$(key "$psb/repo2")"
mk "$bh2/kd-direct/.build" old; ln -s "$bh2/kd-direct" "$psb/w-kdlink/build"; age "$bh2/kd-direct"
# Losse kloon B (geen worktree van repo2) met een worktree die verhuist.
mkdir -p "$psb/repoB/scripts" "$psb/repoB/tvos" && cp "$psb/repo2/scripts/"*.sh "$psb/repoB/scripts/"
gb() { git -C "$psb/repoB" -c user.name=t -c user.email=t@t "$@"; }
gb init -q && gb add scripts && gb commit -q -m init && gb worktree add -q --detach "$psb/b-w1"
mkdir -p "$psb/b-w1/tvos" && link "$psb/b-w1" && mk "$psb/b-w1/build/ios" old
gb worktree move "$psb/b-w1" "$psb/b-w2" && link "$psb/b-w2"
age "$bh2/$(key "$psb/b-w1")"
rm "$psb/repo2/.build" && ln -s "$psb/nergens" "$psb/repo2/.build"   # kapot: alleen een echte run herstelt
mk "$(kd bestaand)/.build/pleya-verify" old; age "$(kd bestaand)"
mk "$(kd prunable)/build/ios" old; age "$(kd prunable)"; rm -rf "$psb/w-prunable"
wees() { mk "$bh2/$1/build/x" "${2:-old}"; echo /weg >"$bh2/$1/.owner"; }
wees wees-oud; mk "$bh2/wees-oud/tvos/build" old
wees wees-ds; touch "$bh2/wees-ds/.DS_Store"
wees wees-sdk; mk "$bh2/wees-sdk/flutter/bin" old
wees wees-tvos; mk "$bh2/wees-tvos/tvos/anders" old
wees wees-cwd
mk "$bh2/wees-zonder/build" old
mkdir -p "$psb/kloon"; wees wees-kloon; echo "$psb/kloon" >"$bh2/wees-kloon/.owner"
wees wees-dubbel; printf '/weg\n%s\n' "$psb/kloon" >"$bh2/wees-dubbel/.owner"
wees wees-rel; echo relatief/pad >"$bh2/wees-rel/.owner"
wees wees-cr; printf '%s\r  \n' "$psb/kloon" >"$bh2/wees-cr/.owner"
mkdir -p "$psb/vols/aan"
wees wees-vol-aan; echo "$psb/vols/aan/weg" >"$bh2/wees-vol-aan/.owner"
wees wees-vol-uit; echo "$psb/vols/uit/wt" >"$bh2/wees-vol-uit/.owner"
age "$bh2"/wees-*
wees wees-vers new
# Processen met hun werkmap in een worktree, een sleutelmap en een wees.
for d in "$psb/w-cwd" "$(kd keycwd)/tvos" "$bh2/wees-cwd/build"; do
  (cd "$d" && exec sleep 300) & pids+=" $!"
done
run2() {
  PATH="$psb/bin2:$PATH" HOME="${H2:-$psb/home}" PLEYA_WORKTREES_DIR="$psb/geen-trees" \
    PLEYA_PRUNE_TMPDIR="$psb/tmp2" PLEYA_BUILD_HOME="${BH2:-$bh2}" PLEYA_VOLUMES_ROOT="$psb/vols" \
    "$psb/repo2/scripts/prune_old_builds.sh" "$@"
}
gone2=("$(kd oud)/build/ios" "$(kd tv)/tvos/build/Release" "$bh2/wees-oud" "$bh2/wees-ds" "$bh2/wees-vol-aan")
kept2=("$(kd vers)/build/ios/f" "$(kd bestaand)/.build/pleya-verify/f" "$(kd prunable)/build/ios/f"
  "$(kd cwd)/build/ios/f" "$(kd keycwd)/build/ios/f" "$psb/elders/f"
  "$bh2/$(key "$psb/repo2")/build/ios/f"
  "$bh2/wees-sdk/flutter/bin/f" "$bh2/wees-tvos/tvos/anders/f" "$bh2/wees-vers/build/x/f"
  "$bh2/wees-kloon/build/x/f" "$bh2/wees-zonder/build/f" "$bh2/wees-cwd/build/x/f"
  "$bh2/wees-dubbel/build/x/f" "$bh2/wees-rel/build/x/f" "$bh2/wees-cr/build/x/f"
  "$bh2/wees-vol-uit/build/x/f" "$bh2/kd-direct/.build/f" "$bh2/$(key "$psb/b-w1")/build/ios/f")
links_ok() { [[ "$(readlink "$psb/repo2/.build")" == "$psb/nergens" ]]; }
out=$(run2 --dry-run)
for p in "${gone2[@]}" "${kept2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: dry-run wiste $p"; exit 1; }; done
for p in "$(kd oud)/build" "$(kd tv)/tvos/build" "$bh2/wees-oud" "$bh2/wees-ds"; do
  grep -qE "zou (leegmaken|verwijderen) \([0-9]+ MB\) $p\$" <<<"$out" || { echo "FOUT: dry-run noemt $p niet"; exit 1; }
done
grep -qF "houdt $bh2/wees-zonder (eigenaar onbekend" <<<"$out" || { echo "FOUT: dry-run meldt wees-zonder niet"; exit 1; }
links_ok || { echo "FOUT: dry-run veranderde een symlink"; exit 1; }
PLEYA_KEEP_BUILDS=1 run2
for p in "${gone2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: PLEYA_KEEP_BUILDS=1 wiste $p"; exit 1; }; done
links_ok || { echo "FOUT: PLEYA_KEEP_BUILDS=1 veranderde een symlink"; exit 1; }
PATH="$sandbox/bin:$PATH" run2 >/dev/null 2>&1   # falende lsof uit het blok hierboven
for p in "${gone2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: met falende lsof is $p gewist"; exit 1; }; done
err=$(run2 2>&1 >/dev/null) || { echo "FOUT: prune brak af: $err"; exit 1; }
for p in "${gone2[@]}"; do [[ ! -e "$p" ]] || { echo "FOUT: $p staat er nog"; exit 1; }; done
for p in "${kept2[@]}"; do [[ -e "$p" ]] || { echo "FOUT: $p is gewist"; exit 1; }; done
for rel in build tvos/build; do
  w=oud; [[ "$rel" == tvos/build ]] && w=tv
  [[ -L "$psb/w-$w/$rel" && -d "$(kd $w)/$rel" ]] \
    || { echo "FOUT: symlink of lege doelmap $rel van w-$w is weg"; exit 1; }
done
grep -qF "weigert $psb/elders" <<<"$err" || { echo "FOUT: symlink naar buiten niet geweigerd"; exit 1; }
grep -qF "kon $(kd ro)/build niet" <<<"$err" || { echo "FOUT: alleen-lezen map niet gemeld"; exit 1; }
[[ "$(readlink "$psb/repo2/.build")" == "$bh2/$(key "$psb/repo2")/.build" ]] \
  || { echo "FOUT: echte run herstelde de kapotte .build-symlink niet"; exit 1; }
chmod 755 "$(kd ro)/build/ro"
# Verkeerde PLEYA_BUILD_HOME: andere naam, of gelijk aan $HOME.
for bh3 in "$psb/ssd3/builds" "$psb/ssd4/pleya-builds"; do
  mkdir -p "$bh3/wees/build" && touch "$bh3/wees/build/f" && echo /weg >"$bh3/wees/.owner"; age "$bh3/wees"
  h3="$psb/home"; [[ "$bh3" == */pleya-builds ]] && h3="$bh3"
  err=$(H2="$h3" BH2="$bh3" run2 2>&1 >/dev/null)
  [[ -e "$bh3/wees/build/f" ]] || { echo "FOUT: wees in $bh3 is gewist"; exit 1; }
  grep -qF "PLEYA_BUILD_HOME=$bh3" <<<"$err" || { echo "FOUT: $bh3 niet geweigerd"; exit 1; }
done
# shellcheck disable=SC2086 # pids is een lijst
kill $pids 2>/dev/null || true

echo "test_prune_old_builds: OK"

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

run() {
  HOME="$sandbox/home" PLEYA_WORKTREES_DIR="$sandbox/trees" \
    PLEYA_PRUNE_TMPDIR="$sandbox/tmp" "$script" "$@"
}
gone=(home/Library/Developer/Xcode/DerivedData/Runner-oud trees/feat/oud/build tmp/tmp.oud tmp/flutter_tools.oud)
kept=(home/Library/Developer/Xcode/DerivedData/Runner-vers trees/vers/build tmp/tmp.vers
  trees/single/tvos/build trees/other/pleya_web/build trees/lnk/build trees/linkdoel/f)

if run --dryrun >/dev/null 2>&1; then echo "FOUT: onbekend argument werd geaccepteerd"; exit 1; fi
for p in "${gone[@]}"; do [[ -e "$p" ]] || { echo "FOUT: onbekend argument wiste $p"; exit 1; }; done

out=$(run --dry-run)
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
echo "test_prune_old_builds: OK"

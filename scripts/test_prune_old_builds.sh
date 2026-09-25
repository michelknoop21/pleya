#!/usr/bin/env bash
# Zelftest voor prune_old_builds.sh in een nep-HOME: oude build/, DerivedData
# en tempmappen gaan weg, verse blijven staan, en --dry-run wist niets.
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
mk tmp/tmp.oud old
mk tmp/flutter_tools.oud old
mk tmp/tmp.vers

run() {
  HOME="$sandbox/home" PLEYA_WORKTREES_DIR="$sandbox/trees" \
    PLEYA_PRUNE_TMPDIR="$sandbox/tmp" "$script" "$@"
}
gone=(home/Library/Developer/Xcode/DerivedData/Runner-oud trees/feat/oud/build tmp/tmp.oud tmp/flutter_tools.oud)
kept=(home/Library/Developer/Xcode/DerivedData/Runner-vers trees/vers/build tmp/tmp.vers)

out=$(run --dry-run)
for p in "${gone[@]}" "${kept[@]}"; do [[ -e "$p" ]] || { echo "FOUT: dry-run wiste $p"; exit 1; }; done
for p in "${gone[@]}"; do grep -qF "$p" <<<"$out" || { echo "FOUT: dry-run noemt $p niet"; exit 1; }; done

PLEYA_KEEP_BUILDS=1 run
for p in "${gone[@]}"; do [[ -e "$p" ]] || { echo "FOUT: PLEYA_KEEP_BUILDS=1 wiste $p"; exit 1; }; done

run >/dev/null
for p in "${gone[@]}"; do [[ ! -e "$p" ]] || { echo "FOUT: $p staat er nog"; exit 1; }; done
for p in "${kept[@]}"; do [[ -e "$p" ]] || { echo "FOUT: $p is gewist"; exit 1; }; done
echo "test_prune_old_builds: OK"

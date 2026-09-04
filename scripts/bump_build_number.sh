#!/usr/bin/env bash
# Hoogt het buildnummer in pubspec.yaml op, zodat elke build die een toestel
# haalt onder een eigen nummer binnenkomt.
#
# Waarom dit bestaat: een build zonder eigen nummer is op het toestel niet van
# zijn voorganger te onderscheiden. "Over Pleya" toont dan hetzelfde nummer als
# de build die er al stond, en een correctieronde vinkt bevindingen af tegen een
# binary die de fix niet draagt.
#
# De release-lane botst hier niet mee. `ensure_build_number` in fastlane/Fastfile
# hergebruikt het pubspec-nummer zolang dat boven het hoogste TestFlight-nummer
# ligt, en pakt anders het eerstvolgende vrije. Een lokaal opgehoogd nummer wordt
# dus overgenomen of overgeslagen, nooit dubbel uitgegeven.
#
#   scripts/bump_build_number.sh            # +1
#   scripts/bump_build_number.sh --to 248   # naar een bepaald nummer
#   scripts/bump_build_number.sh --print    # alleen het huidige nummer tonen
#
# Print het nieuwe nummer op stdout, zodat een aanroeper hem kan vastleggen.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubspec="$root/pubspec.yaml"

line="$(grep -m1 '^version:' "$pubspec")" || {
  echo "geen version-regel in $pubspec" >&2
  exit 1
}
name="${line#version: }"
name="${name%%+*}"
current="${line##*+}"

case "${1:-}" in
  --print)
    echo "$current"
    exit 0
    ;;
  --to)
    target="${2:-}"
    [[ "$target" =~ ^[0-9]+$ ]] || { echo "--to vraagt een getal" >&2; exit 1; }
    if [ "$target" -le "$current" ]; then
      echo "buildnummer gaat niet omlaag: $current is er al, --to $target geweigerd" >&2
      exit 1
    fi
    ;;
  "")
    target=$((current + 1))
    ;;
  *)
    echo "onbekend argument: $1" >&2
    exit 1
    ;;
esac

# In-place met een tussenbestand: sed -i verschilt tussen BSD en GNU.
tmp="$(mktemp)"
sed "s|^version: .*|version: ${name}+${target}|" "$pubspec" > "$tmp"
mv "$tmp" "$pubspec"

echo "$target"

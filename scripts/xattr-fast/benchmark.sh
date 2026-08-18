#!/usr/bin/env bash
# Meet hoeveel workers zinnig zijn voor de xattr-shim, met échte
# attribuutverwijderingen in plaats van een leesbenadering. Zie DEC-029.
#
# Draai dit op hetzelfde volume als de repo: de winst hangt af van de latency
# van dat opslagapparaat, niet van de CPU. Standaard gebruikt het script daarom
# de map naast de repo, niet TMPDIR (dat op de interne schijf staat).
#
# WAT DIT NIET MEET. De bestanden worden hier vlak voor de meting aangemaakt en
# van een attribuut voorzien, dus hun metadata staat warm in de cache. Wat je
# hier ziet is syscall-doorvoer, en die is hoog: ruim 3600 bestanden per
# seconde, ook serieel. In een release is de boom juist koud en haalde dezelfde
# operatie 21 bestanden per seconde. Het echte knelpunt is dus het koud inlezen
# van metadata over USB, en dat valt hier niet na te bootsen: `purge` vereist
# root, dus de cache is niet leeg te maken.
#
# Gebruik dit script om te zien of een hoger aantal workers nog iets oplevert of
# juist gaat schuren, niet om de winst in een echte release te voorspellen. Die
# meet je aan de wandklok van `flutter build ios --config-only`.
#
#   scripts/xattr-fast/benchmark.sh [aantal-bestanden] [doelmap]
set -uo pipefail

SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xattr"
REAL=/usr/bin/xattr
ATTR=com.pleya.benchmark
FILES=${1:-4000}
BASE=${2:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.xattr-bench"}

command -v python3 >/dev/null || { echo "python3 nodig voor de timing" >&2; exit 1; }

root="$BASE/tree"
rm -rf "$BASE"
mkdir -p "$root"
trap 'rm -rf "$BASE"' EXIT

echo "volume: $(df -h "$BASE" | tail -1 | awk '{print $1, $NF}')"
echo "bestanden: $FILES"

# Spreid over submappen, zoals een echte boom, zodat de traversal meetelt.
for d in $(seq 0 19); do mkdir -p "$root/d$d"; done
for i in $(seq 1 "$FILES"); do : > "$root/d$((i % 20))/f$i"; done

arm() { find "$root" -type f -print0 | xargs -0 -P 8 -n 256 "$REAL" -w "$ATTR" x; }
now() { python3 -c 'import time; print(time.monotonic())'; }
elapsed() { python3 -c "print(f'{$2 - $1:.1f}')"; }

remaining() {
  local n=0 p
  while IFS= read -r p; do
    "$REAL" -p "$ATTR" "$p" >/dev/null 2>&1 && n=$((n + 1))
  done < <(find "$root" -type f)
  echo "$n"
}

printf '\n%-28s %10s %12s\n' "variant" "seconden" "bestanden/s"

arm
t0=$(now); "$REAL" -r -d "$ATTR" "$root" >/dev/null 2>&1; t1=$(now)
s=$(elapsed "$t0" "$t1")
printf '%-28s %10s %12s\n' "serieel (/usr/bin/xattr)" "$s" "$(python3 -c "print(int($FILES/max($s,0.001)))")"
left=$(remaining)
[ "$left" -eq 0 ] || echo "  LET OP: $left bestanden hielden het attribuut"

best_jobs=""
best_time=""
for jobs in 4 8 12 16; do
  arm
  t0=$(now)
  PLEYA_XATTR_JOBS="$jobs" "$SHIM" -r -d "$ATTR" "$root" >/dev/null 2>&1
  rc=$?
  t1=$(now)
  s=$(elapsed "$t0" "$t1")
  printf '%-28s %10s %12s%s\n' "shim, $jobs workers" "$s" \
    "$(python3 -c "print(int($FILES/max($s,0.001)))")" \
    "$([ "$rc" -eq 0 ] || echo "   rc=$rc")"
  left=$(remaining)
  [ "$left" -eq 0 ] || echo "  LET OP: $left bestanden hielden het attribuut"
  if [ -z "$best_time" ] || python3 -c "exit(0 if $s < $best_time else 1)"; then
    best_time=$s; best_jobs=$jobs
  fi
done

printf '\nsnelste: %s workers in %s s\n' "$best_jobs" "$best_time"

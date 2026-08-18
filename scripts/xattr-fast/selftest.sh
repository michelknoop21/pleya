#!/usr/bin/env bash
# Zelftest voor de xattr-shim. Draait volledig in een wegwerpmap onder TMPDIR
# en raakt de repo niet aan. Zie DEC-029.
#
# Het proefattribuut is bewust com.pleya.selftest en niet com.apple.provenance:
# die laatste is kernel-beschermd en laat zich in userspace niet verwijderen
# (`xattr -d` geeft 0 en het attribuut blijft staan), zodat een test daarop het
# gedrag van de kernel meet in plaats van dat van de shim. Er is verderop één
# test die dat gedrag expliciet vastlegt, en één met com.apple.FinderInfo,
# het attribuut dat Flutter wél echt kan verwijderen.
set -uo pipefail

SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xattr"
REAL=/usr/bin/xattr
ATTR=com.pleya.selftest
FINDER_HEX="54455854 74747874 00000000 00000000 00000000 00000000 00000000 00000000"

pass=0
fail=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (verwacht '$3', kreeg '$2')"; fi; }

root=$(mktemp -d "${TMPDIR:-/tmp}/xattr-selftest.XXXXXX")
trap 'chmod -R u+rwx "$root" 2>/dev/null; rm -rf "$root"' EXIT

set_attr() { "$REAL" -w "$ATTR" x "$1"; }
has_attr() { "$REAL" -p "$ATTR" "$1" >/dev/null 2>&1 && echo yes || echo no; }

echo "==> doorgeefgedrag"
f="$root/plain.txt"; : > "$f"
"$SHIM" -w com.pleya.fwd hallo "$f"
check "-w zet het attribuut"   "$("$REAL" -p com.pleya.fwd "$f" 2>/dev/null)" "hallo"
check "-p leest via de shim"   "$("$SHIM" -p com.pleya.fwd "$f" 2>/dev/null)" "hallo"
check "-l noemt het attribuut" "$("$SHIM" -l "$f" 2>/dev/null | grep -c com.pleya.fwd)" "1"
"$SHIM" -d com.pleya.fwd "$f"
check "-d op één bestand"      "$("$SHIM" -l "$f" 2>/dev/null | grep -c com.pleya.fwd)" "0"
check "onbekende optie faalt"  "$("$SHIM" --zzz "$f" >/dev/null 2>&1; echo $?)" "1"
# Het vierde argument is hier een bestand, geen map, dus de shim onderschept
# niet. Wat er dan uit komt hoort exact gelijk te zijn aan het origineel, dus
# vergelijken en niet zelf een code voorschrijven.
check "-r -d op een bestand gaat ongewijzigd door" \
  "$("$SHIM"  -r -d "$ATTR" "$f" >/dev/null 2>&1; echo $?)" \
  "$("$REAL"  -r -d "$ATTR" "$f" >/dev/null 2>&1; echo $?)"

echo "==> recursief verwijderen en batching"
mkdir -p "$root/tree/a/b/c"
for i in $(seq 1 700); do : > "$root/tree/a/f$i"; done
: > "$root/tree/a/b/c/deep"
find "$root/tree" -type f -print0 | xargs -0 "$REAL" -w "$ATTR" x
total=$(find "$root/tree" -type f | wc -l | tr -d ' ')
"$SHIM" -r -d "$ATTR" "$root/tree"
check "exitcode bij enkel goedaardige fouten" "$?" "0"
left=0
while IFS= read -r p; do [ "$(has_attr "$p")" = yes ] && left=$((left + 1)); done \
  < <(find "$root/tree" -type f)
check "alle $total bestanden schoon (dus meer dan één xargs-batch)" "$left" "0"

echo "==> tweede ronde op een al schone boom"
"$SHIM" -r -d "$ATTR" "$root/tree"
check "geen attributen = nog steeds exit 0" "$?" "0"

echo "==> rare bestandsnamen"
mkdir -p "$root/raar/met spatie/en 'quote'"
odd="$root/raar/met spatie/en 'quote'/na am, unicode ü.txt"
: > "$odd"; set_attr "$odd"
"$SHIM" -r -d "$ATTR" "$root/raar"
check "spaties, quotes, komma en unicode" "$(has_attr "$odd")" "no"

echo "==> prune-contract"
mkdir -p "$root/prune/node_modules/pkg" "$root/prune/.git/objects" \
         "$root/prune/.dart_tool" "$root/prune/.fvm" "$root/prune/lib/deep" \
         "$root/prune/build/ios"
for p in node_modules/pkg/f .git/objects/f .dart_tool/f .fvm/f lib/deep/f build/ios/f; do
  : > "$root/prune/$p"; set_attr "$root/prune/$p"
done
"$SHIM" -r -d "$ATTR" "$root/prune"
check "node_modules blijft"  "$(has_attr "$root/prune/node_modules/pkg/f")" "yes"
check ".git blijft"          "$(has_attr "$root/prune/.git/objects/f")"     "yes"
check ".dart_tool blijft"    "$(has_attr "$root/prune/.dart_tool/f")"       "yes"
check ".fvm blijft"          "$(has_attr "$root/prune/.fvm/f")"             "yes"
check "lib wordt geschoond"  "$(has_attr "$root/prune/lib/deep/f")"         "no"
check "build wordt geschoond, want die gaat de bundel in" \
                             "$(has_attr "$root/prune/build/ios/f")"        "no"

echo "==> symlinks"
mkdir -p "$root/link/inside"
: > "$root/link/inside/target"; set_attr "$root/link/inside/target"
outside="$root/outside-target"; : > "$outside"; set_attr "$outside"
ln -s "$outside" "$root/link/points-out"
"$SHIM" -r -d "$ATTR" "$root/link"
check "bestand in de boom is geschoond" "$(has_attr "$root/link/inside/target")" "no"
# Gedrag vastleggen, niet wensdenken: zonder -s werkt xattr -d op het doel van
# een symlink, dus een doel buiten de boom wordt meegenomen. /usr/bin/xattr -r
# doet hetzelfde, dus dit is geen gedragswijziging.
ref="$root/ref-target"; : > "$ref"; set_attr "$ref"
mkdir -p "$root/ref"; ln -s "$ref" "$root/ref/points-out"
/usr/bin/xattr -r -d "$ATTR" "$root/ref" >/dev/null 2>&1
check "shim volgt symlinks net als /usr/bin/xattr -r" \
  "$(has_attr "$outside")" "$(has_attr "$ref")"

echo "==> attributen uit de echte wereld"
: > "$root/finder.txt"
"$REAL" -w -x com.apple.FinderInfo "$FINDER_HEX" "$root/finder.txt"
mkdir -p "$root/finder"; mv "$root/finder.txt" "$root/finder/"
"$SHIM" -r -d com.apple.FinderInfo "$root/finder"
check "FinderInfo wordt echt verwijderd" \
  "$("$REAL" -p com.apple.FinderInfo "$root/finder/finder.txt" >/dev/null 2>&1 && echo yes || echo no)" "no"
mkdir -p "$root/prov"; : > "$root/prov/f"
"$REAL" -w com.apple.provenance x "$root/prov/f" 2>/dev/null
"$SHIM" -r -d com.apple.provenance "$root/prov"
check "provenance overleeft (kernel-beschermd) en dat is geen fout" "$?" "0"

echo "==> echte fouten blijven zichtbaar"
check "PLEYA_XATTR_JOBS=abc" \
  "$(PLEYA_XATTR_JOBS=abc "$SHIM" -r -d "$ATTR" "$root/tree" >/dev/null 2>&1; echo $?)" "2"
check "PLEYA_XATTR_JOBS=0" \
  "$(PLEYA_XATTR_JOBS=0 "$SHIM" -r -d "$ATTR" "$root/tree" >/dev/null 2>&1; echo $?)" "2"
mkdir -p "$root/perm/sub"; : > "$root/perm/sub/f"; chmod 000 "$root/perm/sub"
out=$("$SHIM" -r -d "$ATTR" "$root/perm" 2>&1); rc=$?
chmod 755 "$root/perm/sub"
if [ "$rc" -ne 0 ] && [ -n "$out" ]; then ok "onleesbare map geeft een fout"
else bad "onleesbare map werd stilgeslikt (rc=$rc)"; fi

echo "==> marker"
marker="$root/marker.tsv"
PLEYA_XATTR_MARKER="$marker" "$SHIM" -r -d "$ATTR" "$root/tree" >/dev/null 2>&1
check "marker geschreven bij onderscheppen" "$(grep -c "^$ATTR	" "$marker" 2>/dev/null)" "1"
PLEYA_XATTR_MARKER="$marker" "$SHIM" -p com.pleya.fwd "$f" >/dev/null 2>&1
check "marker niet geschreven bij doorgeven" "$(wc -l < "$marker" | tr -d ' ')" "1"

printf '\n%s geslaagd, %s gefaald\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

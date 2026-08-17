#!/usr/bin/env bash
set -uo pipefail

# Vult het "Unreleased"-blok van docs/RELEASES.md met de commits sinds de
# bovenste gepubliceerde versie.
#
#   scripts/gen_release_notes.sh            # schrijf het blok bij
#   scripts/gen_release_notes.sh --check    # schrijf niets, exit 1 bij verschil
#   scripts/gen_release_notes.sh --quiet    # alleen fouten
#
# Puur git en bash: geen netwerk, geen model. De uitvoer is een werklijst, geen
# publicatietekst — de bullets zijn letterlijke commitregels en dus Nederlands.
# /update-docs herschrijft ze naar Engelse gebruikerstaal en sluit het blok af
# tot een echte versiekop zodra er een buildnummer bij komt.
#
# Het ankerpunt is de `<!-- commit: … -->`-regel onder de bovenste versiekop.
# Zonder anker zou het script bij elke run de hele historie opnieuw opsommen,
# en met een tag-gebaseerd anker zou het niets vinden: deze repo heeft er nul.
#
# Exit: 0 niets te doen of bijgewerkt, 1 verschil onder --check, 64 bij een
# kapot of ontbrekend anker.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASES="$ROOT/docs/RELEASES.md"

# Scopes die nooit in de app-releasenotes horen. `feat(website): …` gaat over
# pleya.app en niet over de app die iemand geïnstalleerd heeft; zonder deze
# uitsluiting zou een sitewijziging als nieuwe app-functie worden gepubliceerd.
SKIP_SCOPES='website|site|docs|ci|infra'

CHECK=0
QUIET=0

die() { echo "gen_release_notes: $*" >&2; exit 64; }
say() { [ "$QUIET" = 1 ] || echo "$@"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "onbekende optie: $1" ;;
  esac
  shift
done

[ -f "$RELEASES" ] || die "docs/RELEASES.md bestaat niet"

# Het anker: de eerste `<!-- commit: … -->` ná de eerste versiekop. Kopregels
# vóór die versiekop (het "Unreleased"-blok) worden overgeslagen, anders zou een
# handgeschreven commit-verwijzing daarin het anker kapen.
ANCHOR="$(awk '
  /^## / { if ($0 !~ /^## +Unreleased/) seen = 1; next }
  seen && match($0, /^<!-- *commit: *[0-9a-f]+ *-->$/) {
    # Niet met gsub op [^0-9a-f] uitknippen: de "c" van "commit" is zelf hex.
    sub(/^<!-- *commit: */, ""); sub(/ *-->$/, ""); print; exit
  }
' "$RELEASES")"

[ -n "$ANCHOR" ] || die "geen <!-- commit: … --> onder de bovenste versiekop in docs/RELEASES.md"
git -C "$ROOT" rev-parse --verify --quiet "${ANCHOR}^{commit}" >/dev/null \
  || die "ankercommit $ANCHOR bestaat niet in deze repo"

grep -q '^<!-- BEGIN GENERATED -->$' "$RELEASES" || die "markering BEGIN GENERATED ontbreekt"
grep -q '^<!-- END GENERATED -->$' "$RELEASES" || die "markering END GENERATED ontbreekt"

TMP_BLOCK="$(mktemp)"
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_BLOCK" "$TMP_OUT"' EXIT

# feat → New, perf/refactor → Improved, fix → Fixed. chore, docs, build, ci,
# test en style vallen af: die veranderen niets aan wat een gebruiker ziet.
collect() {
  local type_pattern="$1"
  git -C "$ROOT" log --no-merges --reverse --format='%s' "${ANCHOR}..HEAD" \
    | grep -E "^(${type_pattern})(\([^)]*\))?!?: " \
    | grep -Ev "^(${type_pattern})\((${SKIP_SCOPES})\)!?: " \
    | sed -E "s/^(${type_pattern})(\([^)]*\))?!?: //" \
    | awk 'NF && !seen[$0]++'
}

emit_group() {
  local heading="$1" body="$2"
  [ -n "$body" ] || return 0
  printf '### %s\n' "$heading" >>"$TMP_BLOCK"
  printf '%s\n' "$body" | sed 's/^/- /' >>"$TMP_BLOCK"
  printf '\n' >>"$TMP_BLOCK"
}

NEW="$(collect 'feat')"
IMPROVED="$(collect 'perf|refactor')"
FIXED="$(collect 'fix')"

if [ -z "$NEW$IMPROVED$FIXED" ]; then
  printf 'Nothing user-facing since the last published build.\n' >>"$TMP_BLOCK"
else
  emit_group New "$NEW"
  emit_group Improved "$IMPROVED"
  emit_group Fixed "$FIXED"
  # De laatste emit_group laat een lege regel achter die pal boven
  # END GENERATED zou landen; die hoort bij de scheiding tússen groepen.
  awk 'NR > 1 { print prev } { prev = $0 } END { if (prev != "") print prev }' "$TMP_BLOCK" >"$TMP_OUT"
  mv "$TMP_OUT" "$TMP_BLOCK"
fi

awk -v blockfile="$TMP_BLOCK" '
  $0 == "<!-- BEGIN GENERATED -->" {
    print
    while ((getline line < blockfile) > 0) print line
    close(blockfile)
    skipping = 1
    next
  }
  $0 == "<!-- END GENERATED -->" { skipping = 0; print; next }
  !skipping { print }
' "$RELEASES" >"$TMP_OUT"

if cmp -s "$TMP_OUT" "$RELEASES"; then
  say "docs/RELEASES.md is bij (anker ${ANCHOR:0:7})"
  exit 0
fi

if [ "$CHECK" = 1 ]; then
  echo "gen_release_notes: docs/RELEASES.md loopt achter op de commits sinds ${ANCHOR:0:7}" >&2
  exit 1
fi

cat "$TMP_OUT" >"$RELEASES"
say "docs/RELEASES.md bijgewerkt (anker ${ANCHOR:0:7})"

#!/usr/bin/env bash
# Bewaakt dat een merge een authority-bestand niet stil terugzet naar één kant.
#
# `git checkout --ours <bestand>` en `--theirs` nemen het HELE bestand, niet de
# conflicterende hunk. Bij een bestand waar beide takken aan hebben gewerkt wist dat
# de andere kant volledig uit, zonder dat git, de tests of de CI iets melden. Dat is
# op 4 september 2026 gebeurd met CLAUDE.md (128 regels weg, waaronder de stand dat
# PS-9 gesloten is) en met docs/RELEASES.md (14 releasenote-regels weg).
#
# De controle: voor elk authority-bestand waar BEIDE ouders van de laatste merge van
# de merge-base afwijken, mag het bestand in de werkboom niet byte-identiek zijn aan
# één van die ouders. Is het dat wel, dan is er niet gemergd maar gekozen.
#
# Dit is geen stijlregel maar een feitencontrole, en hij geneest vanzelf: zodra de
# merge alsnog goed is opgelost, is het bestand van beide ouders verschillend.
#
# WAT DEZE CONTROLE BEWUST NIET DOET, en niet moet gaan doen: hij bewijst de
# vingerafdruk, niet de intentie. Wie `--ours` draait en daarna één regel met de
# hand wijzigt, komt er ongezien langs, want dan is het bestand niet meer
# byte-identiek aan die ouder. Dat is geen gat om met heuristiek te dichten.
# Een drempel op "hoeveel lijkt het op die ouder" levert vals alarm bij een merge
# die legitiem grotendeels één kant volgt, en vals vertrouwen zodra iemand de
# drempel leert kennen. De fout die werkelijk is opgetreden is exact deze, en
# daar is dit een scherpe en onderhoudbare poort voor. Laat hem zo.
#
# Wil je een kant écht in zijn geheel overnemen, zet het bestand dan in ALLOW
# hieronder met de reden erbij. Dat is een bewuste, zichtbare uitzondering.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Bestanden die projectwaarheid dragen: wie ze terugdraait, stuurt elke volgende
# sessie verkeerd. Aanvullen wanneer er een bijkomt.
FILES=(
  "CLAUDE.md"
  "docs/RELEASES.md"
  "docs/DECISIONS.md"
  "docs/CHANGELOG.md"
  "STATUS.md"
  "docs/PLEYA-SERVER-MASTERLIST.md"
)

# Bewuste uitzonderingen, als "pad # reden".
ALLOW=()

PASS=0
FAIL=0
pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  ....  %s\n' "$1"; }

MERGE="$(git rev-list --merges -1 HEAD 2>/dev/null || true)"
if [ -z "$MERGE" ]; then
  echo "geen merge in de geschiedenis van HEAD; niets te controleren"
  exit 0
fi

P1="$(git rev-parse "$MERGE^1")"
P2="$(git rev-parse "$MERGE^2" 2>/dev/null || true)"
if [ -z "$P2" ]; then
  echo "de laatste merge heeft één ouder; niets te controleren"
  exit 0
fi
BASE="$(git merge-base "$P1" "$P2")"

echo "==> laatste merge $(git rev-parse --short "$MERGE") ($(git rev-parse --short "$P1") + $(git rev-parse --short "$P2"))"

blob() { git rev-parse "$1:$2" 2>/dev/null || echo "-"; }

for f in "${FILES[@]}"; do
  for allowed in ${ALLOW[@]+"${ALLOW[@]}"}; do
    if [ "${allowed%% *}" = "$f" ]; then
      skip "$f (uitzondering: ${allowed#*# })"
      continue 2
    fi
  done

  [ -f "$f" ] || { skip "$f (bestaat niet)"; continue; }

  b_base="$(blob "$BASE" "$f")"
  b_p1="$(blob "$P1" "$f")"
  b_p2="$(blob "$P2" "$f")"

  # Alleen interessant als beide kanten het bestand hebben aangeraakt. Raakte er
  # maar één kant aan, dan is "gelijk aan die kant" precies de goede uitkomst.
  if [ "$b_p1" = "$b_base" ] || [ "$b_p2" = "$b_base" ] || [ "$b_base" = "-" ]; then
    skip "$f (maar één kant wijzigde hem)"
    continue
  fi

  b_now="$(git hash-object "$f")"
  if [ "$b_now" = "$b_p1" ]; then
    fail "$f is byte-identiek aan $(git rev-parse --short "$P1"), terwijl beide kanten hem wijzigden"
  elif [ "$b_now" = "$b_p2" ]; then
    fail "$f is byte-identiek aan $(git rev-parse --short "$P2"), terwijl beide kanten hem wijzigden"
  else
    pass "$f draagt beide kanten"
  fi
done

echo
if [ "$FAIL" -gt 0 ]; then
  cat >&2 <<'EOF'
Een authority-bestand is gelijk aan één merge-ouder terwijl beide kanten het
wijzigden. Dat is de vingerafdruk van `git checkout --ours/--theirs` op
bestandsniveau: het hele bestand van één kant, en de andere kant stil weg.

Los het op als echte driewegmerge:

  git show <merge-base>:<bestand> > /tmp/base
  git show <ouder-1>:<bestand>    > /tmp/a
  git show <ouder-2>:<bestand>    > /tmp/b
  cp /tmp/a <bestand> && git merge-file <bestand> /tmp/base /tmp/b

Daarna staan alleen de werkelijke conflicten met markers in het bestand; die
los je met de hand op. Gegenereerde bestanden niet met de hand mergen maar
opnieuw laten genereren.

Wil je één kant écht in zijn geheel, zet het bestand dan in ALLOW in dit script
met de reden erbij.
EOF
  echo "$PASS pass, $FAIL fail"
  exit 1
fi
echo "$PASS pass, 0 fail"

#!/usr/bin/env bash
# Print de bestanden die deze CI-run beoordeelt, één per regel.
#
#   scripts/ci_changed_files.sh                 # alles wat in git staat
#   scripts/ci_changed_files.sh <basis> <kop>   # het bereik van een pull request
#
# Alleen bij een pull request valt er iets af te bakenen: daar is de basis
# bekend. Bij een push naar main, een handmatige run of het schema is er geen
# zinnige ondergrens, en dan is "alles" het eerlijke antwoord. Een lege lijst
# zou een gate stilzwijgend overslaan, dus elke twijfel valt de kant van meer
# werk op.
#
# Dit script kiest niet wélke gate draait; het levert alleen de lijst. De
# workflow die hem aanroept filtert zelf, zodat de reden waarom een gate
# overgeslagen wordt naast die gate staat en niet hier.
#
# --no-renames: git print bij een rename alleen het nieuwe pad. Een bestand
# dat pleya_server/ verlaat (of lib/) zou daarmee onzichtbaar zijn voor een
# filter dat op het oude pad let, terwijl beide kanten wel degelijk wijzigen.
# core.quotePath=false: een pad met een niet-ASCII teken komt anders met
# aanhalingstekens omheen terug (`"pleya_server/inter\303\251n/a.go"`), en dat
# matcht geen enkel filter meer.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

base="${1:-}"
head="${2:-HEAD}"

if [ -z "$base" ] || ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  git ls-files
  exit 0
fi

# Drie stippen: het verschil sinds het gezamenlijke voorouder-commit, niet
# sinds de kop van main op het moment van het event (die beweegt verder).
# fetch-depth: 0 in de aanroepende job zorgt dat die voorouder er staat.
git -c core.quotePath=false diff --no-renames --name-only "$base"..."$head"

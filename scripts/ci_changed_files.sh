#!/usr/bin/env bash
# Bestanden voor de scopefilters, één per regel. PR: merge-base...head;
# push: event.before..event.after (niet HEAD^: een push kan meerdere commits zijn).
# De workflows geven beide event-SHA's als argumenten door.
#
# __CI_FULL__ betekent expliciet alle gates, ook als een hele bronmap is gewist.
# Handmatig/schema, nieuwe branch, force-push en een lege diff vallen daarop terug.
# Een detectiefout faalt de scopejob; de afhankelijke jobs vallen dan open.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

full() { echo "ci scope: $*; volledige controles" >&2; echo '__CI_FULL__'; }
fail() { echo "::error::ci scope: $*" >&2; exit 1; }

base="${1:-}"
head="${2:-HEAD}"
event="${GITHUB_EVENT_NAME:-local}"
case "$event" in
  workflow_dispatch|schedule) full "$event"; exit 0 ;;
  push|pull_request)
    [ -n "${2:-}" ] || fail 'event.head ontbreekt'
    ;;
  local)
    if [ -z "$base" ]; then full 'geen bereik opgegeven'; exit 0; fi
    ;;
  *) full "onbekend event $event"; exit 0 ;;
esac

if [ "$event" = push ] && [[ "$base" =~ ^0+$ ]]; then
  full 'nieuwe branch'; exit 0
fi
[ -n "$base" ] || fail 'basis ontbreekt'
base="$(git rev-parse --verify --quiet --end-of-options "${base}^{commit}")" || fail 'basiscommit ontbreekt'
head="$(git rev-parse --verify --quiet --end-of-options "${head}^{commit}")" || fail 'headcommit ontbreekt'

if [ "$event" = push ]; then
  # Een afwijkende checkout mag geen geldige maar ongerelateerde diff opleveren.
  [ "$(git rev-parse HEAD)" = "$head" ] || fail 'checkout wijkt af van event.after'
  if ! git merge-base --is-ancestor "$base" "$head"; then
    full 'push zonder voorouderrelatie'; exit 0
  fi
  range="$base..$head"
else
  range="$base...$head"
fi

listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
# Geen rename-detectie: oude én nieuwe padnaam moeten hun domein activeren.
# NUL-delimiters voorkomen quoting van Unicode/spaties. De bestaande filters
# lezen regels, dus een newline/CR in een pad valt expliciet terug op alles.
git diff --no-renames --name-only -z "$range" -- > "$listing" || fail 'git diff mislukt'
files=()
while IFS= read -r -d '' path; do
  case "$path" in
    *$'\n'*|*$'\r'*) full 'regelafbreking in pad'; exit 0 ;;
  esac
  files+=("$path")
done < "$listing"
if [ "${#files[@]}" -eq 0 ]; then full 'lege diff'; exit 0; fi
printf '%s\n' "${files[@]}"

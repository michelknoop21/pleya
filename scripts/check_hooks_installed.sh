#!/usr/bin/env bash
set -uo pipefail

# Waarschuwt zodra de git-hooks van deze repo niet actief zijn.
#
#   scripts/check_hooks_installed.sh            # adviserend, exit altijd 0
#   scripts/check_hooks_installed.sh --strict   # exit 1 als ze niet actief zijn
#   scripts/check_hooks_installed.sh --quiet    # geen uitvoer, alleen de exitcode
#
# `core.hooksPath` staat niet in de repo maar in `.git/config`, dus hij reist
# niet mee met een clone. Wie `scripts/setup_hooks.sh` nooit draaide heeft dus
# stilzwijgend geen pre-commit en geen pre-push, en merkt dat pas als CI rood
# staat of als docs/RELEASES.md maanden achterloopt. Dit script maakt dat gat
# zichtbaar op de plekken waar een ontwikkelaar toch al langskomt.
#
# Adviserend, niet blokkerend: hooks zijn een lokale keuze en een harde fout zou
# een clone onbruikbaar maken tot iemand ze installeert. `--strict` bestaat voor
# een setup-check die het wél wil afdwingen.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STRICT=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "check_hooks_installed: onbekende optie: $arg" >&2; exit 64 ;;
  esac
done

# In CI zijn hooks per definitie niet aan de orde: de workflows roepen dezelfde
# scripts rechtstreeks aan.
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  exit 0
fi

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

configured="$(git -C "$ROOT" config --get core.hooksPath || true)"

problem=""
if [ -z "$configured" ]; then
  problem="core.hooksPath staat niet ingesteld"
elif [ "$configured" != ".githooks" ]; then
  problem="core.hooksPath staat op '$configured' in plaats van '.githooks'"
else
  for hook in pre-commit pre-push; do
    if [ ! -x "$ROOT/.githooks/$hook" ]; then
      problem=".githooks/$hook is niet uitvoerbaar"
      break
    fi
  done
fi

[ -n "$problem" ] || exit 0

if [ "$QUIET" != 1 ]; then
  cat >&2 <<EOF

  git-hooks staan niet aan: $problem

    pre-commit  draait de CI-gate voordat je commit
    pre-push    houdt docs/RELEASES.md bij met de commits sinds de laatste build

  Aanzetten:  scripts/setup_hooks.sh
  Bewust uit? Draai dan zelf scripts/ci_checks.sh vóór een commit en
              scripts/gen_release_notes.sh vóór een push.

EOF
fi

[ "$STRICT" = 1 ] && exit 1
exit 0

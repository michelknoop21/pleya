#!/usr/bin/env bash
# Negatieve controle op scripts/check_authority_merge.sh.
#
# De poort meldde op 4 september een merge fout af: docs/PLEYA-SERVER-MASTERLIST.md
# bestaat alleen op de integratiebranch, en een bestand dat maar aan één kant bestaat
# hoort in de skip te vallen. Het viel in de vergelijking, want de blob-helper gaf bij
# een onbekend pad niet "-" terug maar het argument zelf. Deze test bouwt precies dat
# geval na in een wegwerp-repo en eist dat de poort groen blijft. Hij eist daarnaast
# dat de poort de echte fout wél nog vindt, anders is groen niets waard.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/check_authority_merge.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
check() {
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s (verwacht %s, kreeg %s)\n' "$1" "$3" "$2"; FAILED=1; fi
}

setup() {
  rm -rf "$TMP/repo"; mkdir -p "$TMP/repo"; cd "$TMP/repo"
  git init -q -b main
  git config user.email t@t; git config user.name t
  mkdir -p scripts docs
  cp "$GATE" scripts/check_authority_merge.sh
  printf 'basis\n' > CLAUDE.md
  git add -A && git commit -qm base

  git checkout -q -b zijtak
  printf 'basis\nbranch\n' > CLAUDE.md
  printf 'alleen op de branch\n' > docs/PLEYA-SERVER-MASTERLIST.md
  git add -A && git commit -qm branch

  git checkout -q main
  printf 'basis\nmain\n' > CLAUDE.md
  git add -A && git commit -qm main
}

# Geval 1: een authority-bestand dat maar aan één kant bestaat, en een bestand dat
# beide kanten draagt. De poort hoort groen te zijn.
setup
git merge -q zijtak --no-commit 2>/dev/null || true
printf 'basis\nmain\nbranch\n' > CLAUDE.md
git add -A && git commit -qm merge
set +e; out="$(scripts/check_authority_merge.sh 2>&1)"; rc=$?; set -e
check "eenzijdig bestand valt in de skip" "$rc" "0"
check "en wordt als skip gemeld" "$(printf '%s' "$out" | grep -c 'MASTERLIST.md (maar één kant')" "1"

# Geval 2: de fout die de poort moet vangen. CLAUDE.md komt in zijn geheel van één
# ouder, precies de vingerafdruk van `git checkout --ours`.
setup
git merge -q zijtak --no-commit 2>/dev/null || true
git checkout --theirs CLAUDE.md 2>/dev/null || git show zijtak:CLAUDE.md > CLAUDE.md
git add -A && git commit -qm merge
set +e; out="$(scripts/check_authority_merge.sh 2>&1)"; rc=$?; set -e
check "een --ours-merge wordt nog steeds gevangen" "$rc" "1"
check "en noemt het bestand" "$(printf '%s' "$out" | grep -c 'FAIL  CLAUDE.md')" "1"

echo
[ "$FAILED" = 0 ] && { echo "alle controles groen"; exit 0; }
echo "er faalde een controle"; exit 1

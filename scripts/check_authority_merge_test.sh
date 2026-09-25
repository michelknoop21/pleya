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
  BASE_COMMIT="$(git rev-parse HEAD)"

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
set +e; out="$(scripts/check_authority_merge.sh "$BASE_COMMIT" 2>&1)"; rc=$?; set -e
check "eenzijdig bestand valt in de skip" "$rc" "0"
check "en wordt als skip gemeld" "$(printf '%s' "$out" | grep -c 'MASTERLIST.md (maar één kant')" "1"

# Geval 2: de fout die de poort moet vangen. CLAUDE.md komt in zijn geheel van één
# ouder, precies de vingerafdruk van `git checkout --ours`.
setup
git merge -q zijtak --no-commit 2>/dev/null || true
git checkout --theirs CLAUDE.md 2>/dev/null || git show zijtak:CLAUDE.md > CLAUDE.md
git add -A && git commit -qm merge
set +e; out="$(scripts/check_authority_merge.sh "$BASE_COMMIT" 2>&1)"; rc=$?; set -e
check "een --ours-merge wordt nog steeds gevangen" "$rc" "1"
check "en noemt het bestand" "$(printf '%s' "$out" | grep -c 'FAIL  CLAUDE.md')" "1"

# Geval 3: een authority-bestand bestond in de merge-base, maar de merge wist
# het. Dat is verlies van authority en hoort nooit als "bestaat niet" te worden
# overgeslagen.
setup
git merge -q zijtak --no-commit 2>/dev/null || true
git rm -q CLAUDE.md
git commit -qm 'merge met verwijderde authority'
set +e; out="$(scripts/check_authority_merge.sh "$BASE_COMMIT" 2>&1)"; rc=$?; set -e
check "een verwijderde authority wordt gevangen" "$rc" "1"
check "en wordt als verwijdering gemeld" "$(printf '%s' "$out" | grep -c 'FAIL  CLAUDE.md is verwijderd')" "1"

# Geval 4: de foute merge zit binnen de featurebranch. Een latere buitenste
# merge is zelf legitiem en maskeert de fout wanneer alleen de laatste merge
# wordt bekeken. De poort moet daarom elke merge in BASE..HEAD controleren.
setup
git checkout -q zijtak
git merge -q main --no-commit 2>/dev/null || true
git checkout --ours CLAUDE.md 2>/dev/null || git show HEAD:CLAUDE.md > CLAUDE.md
git add -A && git commit -qm 'foute innerlijke merge'
git checkout -q main
mkdir -p docs
printf 'buitenste merge\n' > docs/outer.txt
git add -A && git commit -qm 'main gaat verder'
git merge -q --no-ff zijtak -m 'buitenste merge'
set +e; out="$(scripts/check_authority_merge.sh "$BASE_COMMIT" 2>&1)"; rc=$?; set -e
check "een gemaskeerde innerlijke merge wordt gevangen" "$rc" "1"
check "en controleert meer dan alleen de laatste merge" "$(printf '%s' "$out" | grep -c '^==> merge ')" "2"

# Geval 5: een uitzondering in ALLOW_MERGES geldt voor precies één merge en één
# pad. Hetzelfde pad in een andere merge, en een ander pad in dezelfde merge,
# blijven gevangen.
setup_twee() {
  rm -rf "$TMP/repo"; mkdir -p "$TMP/repo/scripts"; cd "$TMP/repo"
  git init -q -b main
  git config user.email t@t; git config user.name t
  cp "$GATE" scripts/check_authority_merge.sh
  printf 'basis\n' > CLAUDE.md; printf 'basis\n' > STATUS.md
  git add -A && git commit -qm base
  BASE_COMMIT="$(git rev-parse HEAD)"
  git checkout -q -b zijtak
  printf 'basis\nbranch\n' > CLAUDE.md; printf 'basis\nbranch\n' > STATUS.md
  git add -A && git commit -qm branch
  git checkout -q main
  printf 'basis\nmain\n' > CLAUDE.md; printf 'basis\nmain\n' > STATUS.md
  git add -A && git commit -qm main
}
merge_van_een_kant() {
  git merge -q zijtak --no-commit 2>/dev/null || true
  git show zijtak:CLAUDE.md > CLAUDE.md; git show zijtak:STATUS.md > STATUS.md
  git add CLAUDE.md STATUS.md && git commit -qm "$1"
}
sta_toe() {
  awk -v e="$1" '{ print } /^ALLOW_MERGES=\($/ { print "  \"" e "\"" }' \
    scripts/check_authority_merge.sh > "$TMP/gate" && cat "$TMP/gate" > scripts/check_authority_merge.sh
}
setup_twee
merge_van_een_kant 'kwade merge'
KWAAD="$(git rev-parse HEAD)"
sta_toe "$KWAAD CLAUDE.md # test"
set +e; out="$(scripts/check_authority_merge.sh "$BASE_COMMIT" 2>&1)"; rc=$?; set -e
check "een ander pad in dezelfde merge valt niet onder de uitzondering" "$rc" "1"
check "STATUS.md blijft gevangen" "$(printf '%s' "$out" | grep -c 'FAIL  STATUS.md')" "1"
check "CLAUDE.md valt onder de uitzondering" "$(printf '%s' "$out" | grep -c 'CLAUDE.md (uitzondering voor deze merge')" "1"
sta_toe "$KWAAD STATUS.md # test"
set +e; scripts/check_authority_merge.sh "$BASE_COMMIT" >/dev/null 2>&1; rc=$?; set -e
check "met beide paden uitgezonderd is die ene merge groen" "$rc" "0"
git checkout -q zijtak
printf 'basis\nbranch\nnog een\n' > CLAUDE.md; printf 'basis\nbranch\nnog een\n' > STATUS.md
git commit -qam 'branch verder'
git checkout -q main
printf 'basis\nmain\nbranch\nmain verder\n' > CLAUDE.md; printf 'basis\nmain\nbranch\nmain verder\n' > STATUS.md
git commit -qam 'main verder'
merge_van_een_kant 'nieuwe kwade merge'
set +e; out="$(scripts/check_authority_merge.sh "$BASE_COMMIT" 2>&1)"; rc=$?; set -e
check "een nieuwe merge met hetzelfde pad valt niet onder de uitzondering" "$rc" "1"
check "en faalt op beide bestanden" "$(printf '%s' "$out" | grep -c 'FAIL  \(CLAUDE\|STATUS\).md is byte-identiek')" "2"

echo
[ "$FAILED" = 0 ] && { echo "alle controles groen"; exit 0; }
echo "er faalde een controle"; exit 1

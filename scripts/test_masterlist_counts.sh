#!/usr/bin/env bash
# Test voor scripts/masterlist_counts.sh met een fixture-masterlijst, inclusief negatieve controles:
# een kloppende lijst geeft exit 0, elke afwijkende teller geeft exit 1.
set -u

here=$(cd "$(dirname "$0")" && pwd)
tool="$here/masterlist_counts.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# Fixture: S0 gesloten (2 van 2), S1 gesloten met een vervolgtaak buiten venster, S2 bezig (1 van 2
# gereed plus 1 bezig), S3 open, PS-12 keuzefase. X1 in tabel 3a telt niet mee.
cat > "$work/ok.md" <<'MD'
# Fixture

## 1. Stand in één blik

| Blok | Slices | Gereed | Bezig | Open |
| --- | --- | --- | --- | --- |
| Fundament | S0 | 1 | 0 | 0 |
| Basis | S1 tot S3 | 1 | 0 | 2 |
| **Totaal** | **4** | **2** | **0** | **2** |

Per taak, en dat is de maat die telt: **9 taken, 4 gereed, 1 bezig, 4 open.** Rest van de zin.

---

## 2. Planning

### 2.1 De golven

| Golf | Slices | Taken | Wat het oplevert | Wacht op |
| --- | --- | --- | --- | --- |
| 1, gesloten | S0, S1 | 0 | fundament | niets |
| 2 | S2, S3 | 3 | catalogus | S1 |
| keuze | PS-12 | 1 | migratie | Michel |

---

## 3. Slices

### S0 Fundament

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S0.1 | Eerste | `[x]` | sha | 2026-01-01 |
| S0.2 | Tweede | `[x]` | sha | 2026-01-01 |

### S1 Basis

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S1.1 | Eerste | `[x]` | sha | 2026-01-01 |
| S1.2 | Vervolg, buiten venster 1: een gat | `[ ]` | | |

### 3a Op main geland zonder taakregel

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| X1 | Los werk | `[x]` | sha | 2026-01-01 |

### S2 Tweede

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S2.1 | Eerste | `[x]` | sha | 2026-01-01 |
| S2.2 | Tweede | `[~]` | | |

### S3 Derde

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S3.1 | Eerste | `[ ]` | | |
| S3.2 | Tweede | `[ ]` | | |

### PS-12 Plex-migratie (keuzefase)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| PS-12.0 | Vrijgave | `[ ]` | | |

---

## 4. Poorten
MD

# 1. print-modus reproduceert de taakregel exact.
out=$("$tool" "$work/ok.md"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "9 taken, 4 gereed, 1 bezig, 4 open." ] && ok "taakregel gemeten" \
  || fail "taakregel gemeten (rc=$rc, uit: $out)"

# 2. --check op de kloppende fixture: exit 0.
"$tool" --check "$work/ok.md" > "$work/ok.out"; rc=$?
[ "$rc" -eq 0 ] && ok "check op kloppende lijst geeft exit 0" || { fail "check op kloppende lijst (rc=$rc)"; cat "$work/ok.out"; }

# 3. De taakregel telt de X-rijen van tabel 3a niet mee: de fixture heeft 9 taakrijen en een X1.
out=$("$tool" --slices "$work/ok.md" | grep -c -E '^(S[0-9]+|PS-12) ')
[ "$out" -eq 5 ] && ok "per slice: vier slices en PS-12, zonder X1" || fail "per slice (aantal regels: $out)"

# Negatieve controles: elke mutatie moet exit 1 geven en het afwijkende onderdeel noemen.
mutate() { # naam, sed-expressie, verwacht fragment in de uitvoer
  sed -E "$2" "$work/ok.md" > "$work/mut.md"
  if cmp -s "$work/ok.md" "$work/mut.md"; then fail "$1 (mutatie veranderde niets)"; return; fi
  out=$("$tool" --check "$work/mut.md"); rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q -F "$3"; then ok "$1 geeft exit 1"
  else fail "$1 (rc=$rc, verwacht fragment: $3)"; fi
}

mutate "afwijkende taakregel: gereed" 's/9 taken, 4 gereed/9 taken, 5 gereed/' 'taakregel: gereed'
mutate "afwijkende taakregel: totaal" 's/9 taken, 4 gereed/10 taken, 4 gereed/' 'taakregel: taken'
mutate "afwijkende blokkentabel: gereed" 's/\| S1 tot S3 \| 1 \|/| S1 tot S3 | 2 |/' 'gereed'
mutate "afwijkende golftabel: taken" 's/\| S2, S3 \| 3 \|/| S2, S3 | 4 |/' 'golf'
mutate "taakstatus gewijzigd zonder tellers bij te werken" 's/\| S3.1 \| Eerste \| `\[ \]`/| S3.1 | Eerste | `[x]`/' 'taakregel'

if [ "$fails" -eq 0 ]; then echo "alle controles geslaagd"; exit 0; fi
echo "$fails controle(s) gefaald"
exit 1

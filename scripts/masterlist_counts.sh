#!/usr/bin/env bash
# masterlist_counts.sh: meet de taaktellers van docs/PLEYA-SERVER-MASTERLIST.md.
#
# Gebruik:
#   scripts/masterlist_counts.sh [BESTAND]            druk de taakregel af
#   scripts/masterlist_counts.sh --slices [BESTAND]   taakregel plus tellers per slice (S0 t/m S25, PS-12)
#   scripts/masterlist_counts.sh --check [BESTAND]    exit 1 met verschiltabel als de masterlijst afwijkt
#
# Exitcodes: 0 klopt of niets te melden, 1 afwijking gevonden, 2 gebruiks- of leesfout.
#
# Wat telt als taak: een rij in hoofdstuk 3 ("## 3." tot "## 4.") waarvan de eerste cel begint met
# S<nummer>.<nummer> of PS-12.<nummer>. De rijen X1 tot en met X3 uit tabel 3a tellen niet mee, en dat
# is dezelfde afbakening als de bestaande taakregel ("154 taken, ...") die dit script reproduceert.
# Status komt uit het eerste `[.]`-vakje in de rij: `[x]` gereed, `[~]` bezig, `[ ]` open,
# `[!]` geblokkeerd, `[-]` vervallen.
#
# Wat --check vergelijkt, en alleen wat betrouwbaar afleidbaar is:
#   1. De taakregel ("Per taak, en dat is de maat die telt"): totaal, gereed, bezig, open.
#   2. De blokkentabel in hoofdstuk 1: het aantal slices per blok, de totaalrij, en de kolom Gereed.
#      Een slice is gereed als al zijn taken `[x]` of `[-]` zijn. Taken waarvan de taaktekst
#      "buiten venster" bevat (S2.7) zijn vervolgwerk en houden een slice niet open; de masterlijst
#      zegt dat zelf bij de taakregel.
#   3. De kolom "Taken" van de golftabel in 2.1: per golf het aantal taken in de genoemde slices dat
#      nog niet `[x]` of `[-]` is, met dezelfde uitzondering voor "buiten venster". De keuzefase
#      PS-12 valt buiten deze controle: de golfcel "keuze, PS-12" staat bewust op 0, want PS-12 is
#      een keuze van Michel en geen werk dat in de golven wordt weggewerkt. Een PS-12-token in een
#      slicelijst telt dus niet mee en een rij die alleen PS-12 noemt wordt overgeslagen.
#
# Wat --check bewust niet vergelijkt: de kolommen Bezig en Open van de blokkentabel. Die zijn niet
# afleidbaar uit de taakstatus, want S22.6 staat op `[~]` terwijl S22 in de tabel als open telt, en
# S12.1 en S13.1 zijn goedgekeurde mockups in slices die verder niet begonnen zijn. De proza-zinnen
# ("dicht (acht van acht, ...)") en de getallen in hoofdstuk 2.2 worden evenmin gelezen.
#
# Beperking: de uitzondering "buiten venster" is een tekstconventie in de taakcel (S2.7). Wie zo'n
# taak anders noemt, laat de slice in de check als bezig tellen. Een expliciete kolomwaarde zou de
# kolomindeling van de masterlijst veranderen en is daarom niet ingevoerd.
#
# Alleen awk, grep en sed; geen afhankelijkheden daarbuiten.

set -u

mode=print
file=
for arg in "$@"; do
  case "$arg" in
    --check) mode=check ;;
    --slices) mode=slices ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "onbekende optie: $arg" >&2; exit 2 ;;
    *) file=$arg ;;
  esac
done

if [ -z "$file" ]; then
  root=$(cd "$(dirname "$0")/.." && pwd)
  file="$root/docs/PLEYA-SERVER-MASTERLIST.md"
fi
if [ ! -r "$file" ]; then
  echo "masterlijst niet leesbaar: $file" >&2
  exit 2
fi

awk -v mode="$mode" '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function num(s) { gsub(/[^0-9]/, "", s); return s + 0 }
function grp(id,   a) { split(id, a, "."); return a[1] }

/^## 1\./ { ch = 1 }
/^## 2\./ { ch = 2 }
/^## 3\./ { ch = 3 }
/^## 4\./ { ch = 4 }

# Taakrijen in hoofdstuk 3.
ch == 3 && /^\| (S[0-9]+\.[0-9]+|PS-12\.[0-9]+)/ {
  n = split($0, f, "|")
  id = trim(f[2]); g = grp(id)
  st = ""
  if (match($0, /`\[.\]`/)) st = substr($0, RSTART + 2, 1)
  if (st != "x" && st != "~" && st != " " && st != "!" && st != "-") { bad++; next }
  if (!(g in seen)) { seen[g] = 1; order[++ng] = g }
  total++; cnt[st]++
  tot[g]++; c[g, st]++
  if (index(f[3], "buiten venster") == 0 && st != "x" && st != "-") rest[g]++
  next
}

# De taakregel.
/Per taak, en dat is de maat die telt/ {
  line = $0
  if (match(line, /[0-9]+ taken/))   s_tot  = num(substr(line, RSTART, RLENGTH))
  if (match(line, /[0-9]+ gereed/))  s_gen  = num(substr(line, RSTART, RLENGTH))
  if (match(line, /[0-9]+ bezig/))   s_bez  = num(substr(line, RSTART, RLENGTH))
  if (match(line, /[0-9]+ open/))    s_open = num(substr(line, RSTART, RLENGTH))
  have_line = 1
}

# Blokkentabel in hoofdstuk 1.
ch == 1 && /^\|/ {
  n = split($0, f, "|")
  if (f[2] ~ /Totaal/) { b_tot = num(f[3]); b_gen = num(f[4]); have_btot = 1; next }
  spec = trim(f[3])
  if (spec ~ /^S[0-9]/ && n >= 7) {
    nb++; bname[nb] = trim(f[2]); bspec[nb] = spec
    bgen[nb] = num(f[4]); bbez[nb] = num(f[5]); bopen[nb] = num(f[6])
  }
  next
}

# Golftabel in hoofdstuk 2.1.
ch == 2 && /^\|/ {
  n = split($0, f, "|")
  spec = trim(f[3])
  if ((spec ~ /^S[0-9]/ || spec ~ /^PS-12/) && trim(f[4]) ~ /^[0-9]+$/ && trim(f[2]) !~ /^#/) {
    ngl++; gname[ngl] = trim(f[2]); gspec[ngl] = spec; gtaken[ngl] = num(f[4])
  }
}

function expand(spec, out,   parts, np, i, k, p, lo, hi, m, cnt2) {
  # "S1 tot S6", "S0", "S14, S16", "PS-12" naar een lijst in out[1..cnt2]
  cnt2 = 0
  np = split(spec, parts, /, */)
  for (i = 1; i <= np; i++) {
    p = trim(parts[i])
    if (match(p, /^S[0-9]+ tot S[0-9]+$/)) {
      split(p, m, / tot /)
      lo = num(m[1]); hi = num(m[2])
      for (k = lo; k <= hi; k++) out[++cnt2] = "S" k
    } else if (p != "") out[++cnt2] = p
  }
  return cnt2
}

function emit(what, stated, measured) {
  dev++
  rows[dev] = sprintf("| %s | %s | %s |", what, stated, measured)
}

function closed(g) { return (g in tot) && rest[g] == 0 }

END {
  if (total == 0) { print "geen taakrijen gevonden in hoofdstuk 3" > "/dev/stderr"; exit 2 }
  open_n = cnt[" "] + 0; bez_n = cnt["~"] + 0; gen_n = cnt["x"] + 0
  blk_n = cnt["!"] + 0; ver_n = cnt["-"] + 0
  linestr = total " taken, " gen_n " gereed, " bez_n " bezig, " open_n " open"
  if (blk_n > 0) linestr = linestr ", " blk_n " geblokkeerd"
  if (ver_n > 0) linestr = linestr ", " ver_n " vervallen"
  linestr = linestr "."

  if (mode == "print" || mode == "slices") {
    print linestr
    if (mode == "slices") {
      printf "%-7s %6s %7s %6s %6s %6s %6s\n", "slice", "taken", "gereed", "bezig", "open", "geblk", "verv"
      for (i = 1; i <= ng; i++) {
        g = order[i]
        printf "%-7s %6d %7d %6d %6d %6d %6d\n", g, tot[g], c[g, "x"], c[g, "~"], c[g, " "], c[g, "!"], c[g, "-"]
      }
    }
    exit 0
  }

  # --check
  dev = 0
  if (!have_line) emit("taakregel", "ontbreekt", linestr)
  else {
    if (s_tot != total)  emit("taakregel: taken",  s_tot,  total)
    if (s_gen != gen_n)  emit("taakregel: gereed", s_gen,  gen_n)
    if (s_bez != bez_n)  emit("taakregel: bezig",  s_bez,  bez_n)
    if (s_open != open_n) emit("taakregel: open",  s_open, open_n)
  }

  # blokkentabel
  nslices = 0; ngerd = 0
  for (b = 1; b <= nb; b++) {
    k = expand(bspec[b], sl)
    gm = 0
    for (j = 1; j <= k; j++) { if (closed(sl[j])) gm++; if (!(sl[j] in tot)) missing[sl[j]] = 1 }
    nslices += k; ngerd += gm
    if (bgen[b] != gm) emit("blok \"" bname[b] "\": gereed", bgen[b], gm)
    if (bbez[b] + bopen[b] != k - gm) emit("blok \"" bname[b] "\": bezig plus open", bbez[b] + bopen[b], k - gm)
  }
  for (m in missing) emit("blok: slice " m " zonder taken", "genoemd", "geen taakrijen")
  if (have_btot) {
    if (b_tot != nslices) emit("blok totaal: slices", b_tot, nslices)
    if (b_gen != ngerd)   emit("blok totaal: gereed", b_gen, ngerd)
  } else emit("blokkentabel", "totaalrij ontbreekt", "-")

  # golftabel
  for (gi = 1; gi <= ngl; gi++) {
    if (gspec[gi] ~ /^PS-12$/) continue
    k = expand(gspec[gi], sl)
    r = 0
    for (j = 1; j <= k; j++) if (sl[j] !~ /^PS-12/) r += rest[sl[j]]
    if (gtaken[gi] != r) emit("golf \"" gname[gi] "\" (" gspec[gi] "): taken", gtaken[gi], r)
  }

  if (dev == 0) { print "masterlijst klopt: " linestr; exit 0 }
  print "masterlijst wijkt af van de gemeten tellers (" linestr ")"
  print ""
  print "| onderdeel | in masterlijst | gemeten |"
  print "| --- | --- | --- |"
  for (i = 1; i <= dev; i++) print rows[i]
  exit 1
}
' "$file"

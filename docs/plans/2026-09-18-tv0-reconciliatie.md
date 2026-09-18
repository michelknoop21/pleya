# TV0 Reconciliatie Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Elk open tvOS-item heeft precies één ID, één eigenaar-document en één status, zodat TV1 tot en met TV8 niet op tegenstrijdige administratie bouwen.

**Architecture:** Alleen documentatie. De drie bestaande documenten worden ter plekke gecorrigeerd; er komt geen vierde mastertabel. `docs/unified-2026-closure.md` blijft eigenaar van volgorde en gate, `docs/tvos-redesign-register.md` van de status per workitem, `docs/tvos-fysieke-correctieronde.md` van de bevindingen. Geen enkele taak in dit plan raakt `lib/` of `test/`.

**Tech Stack:** Markdown, `git`, `grep`. Geen Flutter-build, geen codegen.

**Spec:** `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md`, hoofdstuk 2.

**Werkwijze:** dit plan wijzigt geen code, dus TDD is hier niet van toepassing. In plaats van een falende test krijgt elke taak een **verificatiecommando** dat vóór de wijziging het conflict aantoont en erna leeg of gecorrigeerd is. Voer dat commando echt uit en plak de uitvoer in de commit-body als het iets anders zegt dan hier staat.

---

## Task 0: Preflight

**Files:** geen.

**Step 1: Controleer de baseline**

```bash
cd /Users/michelknoop/.supacode/repos/plezy-main/feat/superpowers-tvos-redesign
git status --porcelain
git fetch --prune github
git rev-parse HEAD github/main
```

Verwacht: `git status --porcelain` toont hooguit ongetrackte sessielogs (`?? .serena/`). `HEAD` is de spec-commit, `github/main` is `9342ab7c` of nieuwer.

**Step 2: Als `github/main` verder staat dan de spec-commit**

```bash
git rebase github/main
```

Daarna de inventaris opnieuw nalopen (Task 14 doet dat sowieso) en in de commit-body melden dat de baseline verschoven is.

**Step 3: Geen aparte branch**

Dit plan werkt door op `feat/superpowers-tvos-redesign`, waar de spec al staat. TV1 begint pas na de commit uit Task 15.

---

## Task 1: MOC-09 tot en met MOC-12 op één status

**Files:**
- Modify: `docs/tvos-redesign-register.md` (de rijen MOC-09, MOC-10, MOC-11, MOC-12)

**Step 1: Toon het conflict**

```bash
grep -nE '^\| MOC-(09|10|11|12) \|' docs/tvos-redesign-register.md | cut -c1-90
grep -n 'T2a tvOS detail en LIB7' docs/unified-2026-closure.md
```

Verwacht: het register zegt vier keer `IN PROGRESS`; closure §5 stap 6 zegt `CODE/SIM CLOSED` met `1805c75e`, `968d794e`, `62e48d12` en `eb5de4c9`.

**Step 2: Zet de vier statuskolommen om**

In `docs/tvos-redesign-register.md` verandert in elk van de vier rijen alleen de statuskolom (de vierde), van:

```
| IN PROGRESS |
```

naar:

```
| CODE/SIM CLOSED · HARDWARE OPEN |
```

Laat de bewijskolom ongemoeid: die bevat al de SHA's en de auditnotities.

**Step 3: Voeg per rij de closure-verwijzing toe**

Achteraan de bewijskolom van elke rij, als laatste zin:

```
Status gelijkgetrokken met `unified-2026-closure.md` §5 stap 6 (TV0, 18 september 2026).
```

**Step 4: Verifieer**

```bash
grep -cE '^\| MOC-(09|10|11|12) \|.*IN PROGRESS' docs/tvos-redesign-register.md
```

Verwacht: `0`.

```bash
grep -cE '^\| MOC-(09|10|11|12) \|.*CODE/SIM CLOSED · HARDWARE OPEN' docs/tvos-redesign-register.md
```

Verwacht: `4`.

**Step 5: Commit**

```bash
git add docs/tvos-redesign-register.md
SKIP_HOOKS=1 git commit -m "docs: MOC-09 tot en met MOC-12 op de closure-status

Het register stond op IN PROGRESS terwijl unified-2026-closure.md paragraaf 5
stap 6 de vier al op CODE/SIM CLOSED had staan, met SHA. Paragraaf 1 van de
closure bepaalt dat de closure wint bij tegenspraak."
```

`SKIP_HOOKS=1` omdat de pre-commit-gate `flutter analyze` draait en die wisselend faalt op het laden van `dart_code_linter`. Dit is een docs-only commit en raakt geen Dart.

---

## Task 2: De drie contextmenu-gaten krijgen een ID

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (nieuwe rijen in de bevindingentabel)
- Modify: `docs/tvos-redesign-register.md` (de MOC-12-rij verwijst ernaar)

**Step 1: Bevestig dat er geen contextmenu-categorie bestaat**

```bash
grep -cE '^\| *CTX[0-9]' docs/tvos-fysieke-correctieronde.md
grep -cE '^\| *MENU[0-9]' docs/tvos-fysieke-correctieronde.md
```

Verwacht: beide `0`. Bestaat er wél al een `CTX`-rij, stop dan en gebruik het eerstvolgende vrije nummer in die reeks in plaats van 1, 2 en 3.

**Step 2: Voeg drie rijen toe**

Aan het einde van de bevindingentabel in `docs/tvos-fysieke-correctieronde.md`, in het formaat van de bestaande rijen (`| ID | Bevinding | Status | SHA | Notitie |`):

```markdown
| CTX1 | Het unified contextmenu mist de metadata-subregel onder de titel (genre, duur, bronnen, kijktijd) die mockup 12 toont | OPEN | n.v.t. | Uit de MOC-12-compositie-audit van 12 september, bewust niet gebouwd in `62e48d12`. Had tot 18 september geen eigen ID en stond alleen in proza in `unified-2026-closure.md` §5 stap 6 en de MOC-12-registerrij. Eigenaar: `showTvUnifiedContextMenu`. Gebruik de canonieke metadatahelpers, geen tweede formatteringslaag ernaast. Toegewezen aan TV3 |
| CTX2 | De "Hervatten"-rij in het unified contextmenu toont geen resterende tijd | OPEN | n.v.t. | Zelfde herkomst als CTX1. Leest de bestaande watch state (`resolveWatchState`), geen eigen berekening. Toegewezen aan TV3 |
| CTX3 | De actierijen in het unified contextmenu hebben geen icoon per rij | OPEN | n.v.t. | Zelfde herkomst als CTX1. Toegewezen aan TV3 |
```

**Step 3: Verwijs ernaar vanuit de MOC-12-registerrij**

Vervang in `docs/tvos-redesign-register.md` in de MOC-12-rij de zinsnede:

```
Drie visuele gaten blijven open t.o.v. de mockup: (1) metadata-subregel onder de titel (genre/duur/bronnen/kijktijd) ontbreekt, (2) resterende tijd op de "Hervatten"-rij ontbreekt, (3) geen icoon per actierij.
```

door:

```
Drie visuele gaten blijven open t.o.v. de mockup, sinds TV0 met een eigen ID in de correctieronde: CTX1 (metadata-subregel), CTX2 (resterende tijd op "Hervatten") en CTX3 (icoon per actierij).
```

**Step 4: Verifieer**

```bash
grep -cE '^\| CTX[123] \|' docs/tvos-fysieke-correctieronde.md
grep -c 'CTX1' docs/tvos-redesign-register.md
```

Verwacht: `3` en `1`.

**Step 5: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md docs/tvos-redesign-register.md
SKIP_HOOKS=1 git commit -m "docs: CTX1 tot en met CTX3 voor de drie contextmenu-gaten

De drie visuele gaten uit de MOC-12-audit stonden alleen in proza en hadden
geen ID, waarmee ze buiten elke werklijst vielen. De correctieronde had nog
geen categorie voor het contextmenu, dus CTX is nieuw."
```

---

## Task 3: De tweede OFF2 wordt OFF5

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md`

**Step 1: Toon de dubbele identiteit**

```bash
grep -nE '^\| OFF2 \|' docs/tvos-fysieke-correctieronde.md | cut -c1-120
```

Verwacht: twee treffers. De ene gaat over de offline-tab-routingbug in `main_screen.dart:2143`, de andere over focusbare dode pills in de offline topnav.

**Step 2: Bevestig welk nummer vrij is**

```bash
grep -nE '^\| OFF[0-9] \|' docs/tvos-fysieke-correctieronde.md | cut -c1-70
```

Verwacht: OFF1, OFF2 (twee keer), OFF3, OFF4. `OFF5` is vrij. Is dat niet zo, neem dan het eerstvolgende vrije nummer.

**Step 3: Hernoem de routingbug-rij**

De rij die begint met de routingbug (`_handleOfflineStatusChanged` overschrijft de zojuist gekozen offline-tab) krijgt `OFF5` in de eerste kolom. **De andere OFF2-rij blijft OFF2**: die spiegelt register `OFF-2` en het hernoemen ervan zou de verwijzing daar kapotmaken.

Voeg aan de notitiekolom van de hernoemde rij toe:

```
Heette tot 18 september ook OFF2, naast de dode-pills-bevinding; hernoemd in TV0 omdat één ID niet twee problemen kan dragen.
```

**Step 4: Zoek verwijzingen naar de oude identiteit**

```bash
grep -rn 'OFF2' docs/ --include=*.md | grep -v 'OFF5' | cut -c1-120
```

Loop de treffers na. Elke verwijzing die over de routingbug gaat wordt `OFF5`; verwijzingen naar de dode pills blijven `OFF2`. Let op de spec zelf (`docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md`): die noemt al `OFF5` en hoeft niet te wijzigen.

**Step 5: Verifieer**

```bash
grep -cE '^\| OFF2 \|' docs/tvos-fysieke-correctieronde.md
grep -cE '^\| OFF5 \|' docs/tvos-fysieke-correctieronde.md
```

Verwacht: `1` en `1`.

**Step 6: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: de offline-tab-routingbug wordt OFF5

OFF2 droeg twee verschillende bevindingen: de dode pills in de offline topnav
en de routingbug in main_screen.dart:2143. De eerste spiegelt register OFF-2 en
houdt zijn nummer, de tweede krijgt het eerstvolgende vrije nummer."
```

---

## Task 4: De verouderde REQ1-noot

**Files:**
- Modify: `docs/tvos-redesign-register.md` (de MOC-15-rij)

**Step 1: Toon het conflict**

```bash
grep -n 'REQ1 is fixture-blocked' docs/tvos-redesign-register.md
grep -nE '^\| REQ1 \|' docs/tvos-fysieke-correctieronde.md | cut -c1-140
```

Verwacht: het register zegt "fixture-blocked", de correctieronde zegt `FIXED, simulator geverifieerd` met `f72466f2`, `39f266be`, `df3dab65` en `2be95338`.

**Step 2: Vervang de noot**

In de MOC-15-rij van `docs/tvos-redesign-register.md`, vervang:

```
REQ1 is fixture-blocked, zie T3a in `unified-2026-closure.md`
```

door:

```
REQ1 is gesloten op de simulator (`f72466f2`, `39f266be`, `df3dab65`, `2be95338`): `SeerrFakeServer` vulde het fixturegat omdat Seerr toch al tegen een eigen geconfigureerde URL praat
```

**Step 3: Verifieer**

```bash
grep -c 'fixture-blocked' docs/tvos-redesign-register.md
```

Verwacht: `0`.

**Step 4: Commit**

```bash
git add docs/tvos-redesign-register.md
SKIP_HOOKS=1 git commit -m "docs: REQ1 is geen fixture-blocker meer

De noot bij MOC-15 dateerde van voor SeerrFakeServer. De correctieronde had
REQ1 al op FIXED met vier SHA's."
```

---

## Task 5: De PS-9F-verwijzing

**Files:**
- Modify: `docs/unified-2026-closure.md` (§5, stap 7)

**Step 1: Bewijs dat het document nergens bestaat**

```bash
ls docs/pleya-server-ps9f-favorites-proposal.md
git log --all --diff-filter=A --name-only -- '*ps9f*' '*favorites-proposal*'
grep -rln 'PS-9F' docs/ --include=*.md
```

Verwacht: de `ls` faalt, de `git log` is leeg, en de `grep` noemt alleen `docs/unified-2026-closure.md` en de spec. Vindt de `git log` wél iets, stop dan: het voorstel bestaat en moet hersteld worden in plaats van geschrapt.

**Step 2: Schrap de verwijzing**

In `docs/unified-2026-closure.md` §5 stap 7, vervang:

```
vastgelegd als roadmap-afwijkingsvoorstel `docs/pleya-server-ps9f-favorites-proposal.md`, nog niet beoordeeld
```

door:

```
de uitweg staat in de WL2-rij van de correctieronde zelf: sluiten zodra er een fixture is die favorieten voert, of vastleggen dat de dekking op een echte Jellyfin-aanmelding hoort (TV0, 18 september: het PS-9F-voorstel waar hier naar verwezen werd bestaat in geen enkele branch en is nooit geschreven)
```

Pas in dezelfde stap ook de laatste zin aan, waar MYP1's kijklijsthelft aan "de PS-9F-afwijkingsvoorstel-beoordeling" wordt toegewezen: die wijst nu naar TV2, dat WL2 als verificatie-infrastructuurgat behandelt.

**Step 3: Verifieer**

```bash
grep -c 'ps9f-favorites-proposal' docs/unified-2026-closure.md
```

Verwacht: `0`.

**Step 4: Commit**

```bash
git add docs/unified-2026-closure.md
SKIP_HOOKS=1 git commit -m "docs: schrap de verwijzing naar een PS-9F-voorstel dat nooit bestond

git log --all --diff-filter=A vindt docs/pleya-server-ps9f-favorites-proposal.md
in geen enkele branch, en de string PS-9F stond in precies een bestand: deze
closure. De WL2-rij in de correctieronde draagt zijn eigen uitweg al."
```

---

## Task 6: SYS-1, SYS-5 en SYS-6 als umbrella's

Drie werkitems in het register staan `OPEN` of `IN PROGRESS` terwijl al hun kinderen een eindstatus hebben. Dat is administratief, niet technisch, en het verschil bepaalt of TV1 er code voor schrijft.

**Files:**
- Modify: `docs/tvos-redesign-register.md`
- Modify: `docs/tvos-fysieke-correctieronde.md` (de SYS-1-rij)

**Step 1: Toon de drie umbrella's en hun kinderen**

```bash
grep -nE '^\| SYS-(1|5|6)' docs/tvos-redesign-register.md | cut -c1-110
grep -nE '^\| SYS-1[abc]' docs/tvos-redesign-register.md | cut -c1-110
awk -F'|' '/^\| *(I18N|STR|TOK)-?[0-9]/{gsub(/^ +| +$/,"",$2);gsub(/^ +| +$/,"",$4);print $2" :: "$4}' docs/tvos-fysieke-correctieronde.md
```

Verwacht op `9342ab7c`:

| Umbrella | Kinderen | Stand |
|---|---|---|
| SYS-1 | SYS-1a `5cafc10`, SYS-1b `bb79a82`, SYS-1c `ad8c456` | alledrie `DONE` |
| SYS-5 | I18N1 tot en met I18N6, STR1 tot en met STR5 | alle elf `FIXED` |
| SYS-6 | TOK1, TOK2, TOK3 | TOK1 en TOK3 `FIXED`, TOK2 `OPEN` |

**Step 2: Doe per umbrella één gerichte controle**

Alleen een aangetoond defect maakt het codewerk. Voor SYS-1:

```bash
grep -rn 'tvContentRouteRegistry\|TvNestedRoute' lib/navigation/tv/tv_content_route_registry.dart | head
grep -rn 'Navigator.of(context).push' lib/screens/tv lib/widgets/tv | head
```

Vind je een TV-contentroute die buiten `tv_content_route_registry.dart` om pusht en dus de shell afdekt, dan is dat een concrete bevinding: geef hem een eigen ID in de correctieronde en wijs hem toe aan TV1. Vind je niets, dan sluit SYS-1 administratief.

Voor SYS-5, één verse sweep op nieuwe hardcoded strings in de TV-oppervlakken:

```bash
grep -rnE "Text\('[A-Z][a-z]{2,}" lib/screens/tv lib/widgets/tv | grep -v '//' | head -20
```

Voor SYS-6 hoeft niets: TOK2 is het enige open kind en die gaat naar TV1 (Task 3 van dat plan).

**Step 3: Werk de drie registerrijen bij**

SYS-1, in `docs/tvos-fysieke-correctieronde.md`, statuskolom van `IN PROGRESS` naar (afhankelijk van stap 2) `GESLOTEN via SYS-1a/1b/1c` of `IN PROGRESS`, met in de notitiekolom:

```
TV0 (18 september): de drie kinderen SYS-1a (`5cafc10`, DEC-091), SYS-1b (`bb79a82`) en SYS-1c (`ad8c456`) staan alledrie op DONE in het register. Gerichte controle op contentroutes die buiten `tv_content_route_registry.dart` om pushen leverde <uitkomst van stap 2> op.
```

SYS-5 in `docs/tvos-redesign-register.md`, statuskolom naar `GESLOTEN via I18N1-6 en STR1-5` met dezelfde soort notitie, of `OPEN` met de concrete nieuwe treffers uit de sweep erbij.

SYS-6 naar `OPEN, alleen TOK-2` met de notitie dat TOK-1 en TOK-3 gesloten zijn en TOK-2 aan TV1 is toegewezen.

**Step 4: Verifieer**

```bash
grep -nE '^\| SYS-(1|5|6)' docs/tvos-redesign-register.md | cut -c1-140
grep -nE '^\| SYS-1 \|' docs/tvos-fysieke-correctieronde.md | cut -c1-140
```

Elke rij noemt nu ofwel een eindstatus met de kinderen erbij, ofwel een concrete openstaande bevinding. Geen rij staat nog op een status die alleen "ooit begonnen" betekent.

**Step 5: Commit**

```bash
git add docs/tvos-redesign-register.md docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: SYS-1, SYS-5 en SYS-6 als umbrella beoordeeld

Alle drie stonden open terwijl hun kinderen een eindstatus hadden: SYS-1a t/m
1c op DONE, I18N1 t/m 6 en STR1 t/m 5 op FIXED, en van TOK1 t/m 3 alleen TOK2
nog open. Per umbrella een gerichte controle gedaan voordat hij sluit, zodat
een echt defect niet administratief verdwijnt."
```

---

## Task 7: LANG1 gelijk aan MOC-31

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (de LANG1-rij)

**Step 1: Toon het verschil**

```bash
awk -F'|' '/^\| *LANG1 \|/{gsub(/^ +| +$/,"",$4);print "LANG1 :: "$4}' docs/tvos-fysieke-correctieronde.md
grep -nE '^\| MOC-31 \|' docs/tvos-redesign-register.md | cut -c1-200
```

Verwacht: LANG1 `OPEN`, MOC-31 `CODE/SIM CLOSED · HARDWARE OPEN` met `tvos.settings.language-preferences.yaml` groen op `a5730f35` en een `git log`-controle op de geraakte bestanden.

**Step 2: Herhaal die controle**

```bash
git log --oneline a5730f35..HEAD -- \
  lib/screens/settings/parts/language_settings_tv.dart \
  lib/screens/settings/parts/series_language_row.dart \
  lib/screens/settings/parts/series_language_sheet.dart \
  pleya_verify/scenarios/tvos.settings.language-preferences.yaml
```

Verwacht: leeg. Komt er wél iets terug, dan is het scenario niet meer geldig voor de huidige code en blijft LANG1 `OPEN`; noteer dat dan in de rij en wijs hem toe aan TV7.

**Step 3: Zet de status gelijk**

LANG1's statuskolom van `OPEN` naar `CODE/SIM CLOSED · HARDWARE OPEN`, met in de notitie:

```
TV0 (18 september): gelijkgetrokken met register MOC-31. Het scenario is groen op `a5730f35` en `git log a5730f35..HEAD` op de geraakte bestanden is leeg. Er is geen implementatiewerk meer; de hardware-acceptatie hoort bij closure §7.
```

**Step 4: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: LANG1 gelijkgetrokken met MOC-31

De rij stond op OPEN terwijl zijn eigen tekst al zei dat het Verify-scenario
groen is en alleen de hardwareronde nog openstaat. De git log-controle op de
geraakte bestanden is opnieuw gedraaid en leeg."
```

---

## Task 8: De aliasconventie vastleggen

**Files:**
- Modify: `docs/tvos-redesign-register.md` (de kop, boven de eerste tabel)

**Step 1: Toon de omvang**

```bash
grep -oE '^\| *[A-Z][A-Z0-9]*-?[0-9]+[a-z]? *\|' docs/tvos-redesign-register.md | tr -d '| ' | sed 's/-//' | sort -u > /tmp/reg.n
grep -oE '^\| *[A-Z][A-Z0-9]*-?[0-9]+[a-z]? *\|' docs/tvos-fysieke-correctieronde.md | tr -d '| ' | sed 's/-//' | sort -u > /tmp/cor.n
comm -12 /tmp/reg.n /tmp/cor.n | wc -l
```

Verwacht: `22`.

**Step 2: Voeg de conventie toe**

In `docs/tvos-redesign-register.md`, direct onder de statusregel in de kop:

```markdown
**Koppeltekens.** De correctieronde schrijft historisch `FOC1`, dit register `FOC-1`. Dat zijn
aliassen van hetzelfde werkitem, geen aparte ID's; op 18 september gold dat voor 22 ID-paren. Er
wordt niet hernoemd: een renaming-diff over 22 ID's levert alleen het risico van verweesde
verwijzingen op. Een nieuw ID volgt de schrijfwijze van het document waar het in ontstaat.
```

**Step 3: Verifieer**

```bash
grep -c 'Koppeltekens' docs/tvos-redesign-register.md
```

Verwacht: `1`.

**Step 4: Commit**

```bash
git add docs/tvos-redesign-register.md
SKIP_HOOKS=1 git commit -m "docs: leg de aliasconventie tussen register en correctieronde vast

Twee-en-twintig ID's staan in beide documenten met alleen een koppelteken
verschil. Een steekproef op zeven paren laat zien dat het telkens hetzelfde
werkitem is, dus dit is een conventie en geen botsing."
```

---

## Task 9: VER2 en de TOK-2-regelverwijzing

Twee kleine correcties in één commit, omdat ze allebei één regel zijn en geen eigen verhaal hebben.

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (VER2)
- Modify: `docs/tvos-redesign-register.md` (TOK-2)

**Step 1: Bevestig VER2**

```bash
grep -nE '^\| VER2 \|' docs/tvos-fysieke-correctieronde.md | cut -c1-140
```

Verwacht: `DEFERRED`, over automation-ids die geen blokhaken escapen. Laat de status staan en voeg aan de notitie toe:

```
TV0 (18 september): bevestigd als DEFERRED. TV8 behandelt dit niet als ontbrekende closure.
```

Is er sinds de deferral een scenario bijgekomen dat op geëscapete blokhaken stukloopt, dan gaat VER2 naar `OPEN` en naar TV8.

**Step 2: Corrigeer de TOK-2-regelverwijzing**

```bash
grep -n '3FBF5F' lib/screens/tv/tv_my_pleya_screen.dart
grep -n 'tv_my_pleya_screen.dart:830' docs/tvos-redesign-register.md
```

Verwacht: de kleur staat op regel 833, het register zegt 830. Zet het register op `tv_my_pleya_screen.dart:833`.

**Step 3: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md docs/tvos-redesign-register.md
SKIP_HOOKS=1 git commit -m "docs: VER2 bevestigd als DEFERRED, TOK-2-regelnummer bijgewerkt

De serverstip staat op regel 833, niet 830."
```

---

## Task 10: CTA1 en HTTP1 als GATE0

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (de rijen CTA1 en HTTP1)

**Step 1: Controleer of ze nog reproduceren**

```bash
flutter test test/theme/no_local_cta_shape_override_test.dart 2>&1 | tail -20
flutter test test/utils/http_lifecycle_test.dart 2>&1 | tail -20
```

Beide zijn genoteerd als rood op `main`. HTTP1 is tijdgevoelig en reproduceert volgens de correctieronde niet lokaal op de gepinde 3.44.0-SDK. Noteer per test wat je werkelijk ziet, inclusief de SDK-versie:

```bash
flutter --version | head -1
```

**Step 2: Classificeer beide rijen**

Voeg aan de notitiekolom van allebei toe:

```
TV0 (18 september): geclassificeerd als cross-platform closure-gate debt, niet als tvOS-featurewerk. Werkstroom GATE0, parallel aan TV1 en blokkerend voor TV8. TV1 tot en met TV8 raken deze bestanden niet. Lokale reproductie op <SDK-versie>: <uitkomst van stap 1>.
```

**Step 3: Geen fix in dit plan**

CTA1's fix ligt in `lib/screens/media_detail/mobile_detail_view.dart` of in de `allowed`-lijst van de test, en dat is een mobiel besluit. HTTP1 is een CI-stabiliteitsvraag. Allebei krijgen een eigen plan; dit plan wijst ze alleen toe.

**Step 4: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: CTA1 en HTTP1 toegewezen aan GATE0

Geen tvOS-featurewerk, maar wel rood op main en daarmee blokkerend voor
closure-stap 16. Krijgen een eigen plan; de tvOS-plannen raken deze bestanden
niet."
```

---

## Task 11: De open-set tegen de spec leggen

**Files:** geen wijziging, tenzij er een item ontbreekt.

**Step 1: Haal de actuele open-set op**

```bash
awk -F'|' '/^\| *[A-Z][A-Z0-9-]{1,9} *\|/ {gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$4); if ($2!="ID") print $2" :: "$4}' \
  docs/tvos-fysieke-correctieronde.md \
  | grep -viE ':: *(FIXED|VERIFIED|GESLOTEN|VERVALLEN|NOT REPRODUCED|KLAAR|DONE|VASTGELEGD|DEFERRED|CODE/SIM CLOSED)'
```

**Step 2: Vergelijk met hoofdstuk 3 van de spec**

Open `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md` en loop de mappingtabel na. Elk ID uit stap 1 moet er in staan, met een plan.

**Step 3: Bij een ontbrekend item**

Voeg het toe aan de mappingtabel van de spec, met het plan waar het hoort en één zin waarom. Ontbreekt er niets, dan verandert er niets.

**Step 4: Doe hetzelfde voor het register**

```bash
awk -F'|' '/^\| *[A-Z][A-Z0-9-]{1,9} *\|/ {gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$5); if ($2!="ID") print $2" :: "$5}' \
  docs/tvos-redesign-register.md | grep -iE 'OPEN|IN PROGRESS'
```

**Step 5: Commit, alleen als er iets veranderde**

```bash
git add docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md
SKIP_HOOKS=1 git commit -m "docs: <ID> toegevoegd aan de mapping van de closure-spec"
```

---

## Task 12: Eindcontrole

**Files:** geen.

**Step 1: Geen dubbele ID's binnen één document**

```bash
for f in docs/tvos-fysieke-correctieronde.md docs/tvos-redesign-register.md; do
  echo "== $f"
  grep -oE '^\| *[A-Z][A-Z0-9-]*[0-9]+[a-z]? *\|' "$f" | tr -d '| ' | sort | uniq -d
done
```

Verwacht: beide leeg. Een dubbel ID hier betekent dat Task 3 iets gemist heeft.

**Step 2: Geen tegenstrijdige statussen meer**

```bash
grep -cE '^\| MOC-(09|10|11|12) \|.*IN PROGRESS' docs/tvos-redesign-register.md   # 0
grep -c 'fixture-blocked' docs/tvos-redesign-register.md                          # 0
grep -c 'ps9f-favorites-proposal' docs/unified-2026-closure.md                     # 0
awk -F'|' '/^\| *LANG1 \|/{gsub(/^ +| +$/,"",$4);print $4}' docs/tvos-fysieke-correctieronde.md
```

**Step 3: De documenten zijn nog leesbaar markdown**

```bash
git diff --stat 9342ab7c..HEAD -- docs/
```

Verwacht: alleen `docs/tvos-fysieke-correctieronde.md`, `docs/tvos-redesign-register.md`, `docs/unified-2026-closure.md`, `docs/superpowers/specs/...` en `docs/plans/...`. Geen enkel bestand onder `lib/` of `test/`.

**Step 4: Bewijs dat er geen code is geraakt**

```bash
git diff --name-only 9342ab7c..HEAD | grep -E '^(lib|test|pleya_verify)/' | wc -l
```

Verwacht: `0`.

**Step 5: Commit het sessieverslag**

```bash
git add docs/CHANGELOG.md docs/STATUS.md
SKIP_HOOKS=1 git commit -m "docs: TV0-sessieverslag

Zeven conflicten gesloten: MOC-09 t/m 12, CTX1-3, OFF5, REQ1, PS-9F, de drie
umbrella's SYS-1/5/6, en LANG1. Aliasconventie vastgelegd, CTA1 en HTTP1 naar
GATE0. Geen codewijziging."
```

---

## TV0 exit

Alle vijf waar, anders is TV0 niet klaar:

1. `git diff --name-only 9342ab7c..HEAD | grep -E '^(lib|test|pleya_verify)/'` is leeg.
2. Geen document bevat twee rijen met hetzelfde ID.
3. MOC-09 tot en met MOC-12, REQ1, LANG1 en de drie umbrella's hebben één status.
4. Elk ID uit de actuele open-set staat in hoofdstuk 3 van de spec met een plan.
5. CTA1 en HTTP1 zijn toegewezen aan GATE0 en aan geen enkel tvOS-plan.

**Pas hierna begint TV1**, met een verse preflight tegen de nieuwe HEAD.

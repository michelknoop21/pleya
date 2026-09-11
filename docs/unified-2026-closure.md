# Unified 2026: afronding van iOS en tvOS

Vastgelegd op 11 september 2026 als UNI0, op `main` = `76492ec2` (build 269). tvOS fase 0 tot en
met 10A en iOS fase 1 tot en met 3 staan op dat moment op `main`. Wat er nog moet gebeuren voordat
de redesign naar TestFlight gaat, en in welke volgorde, staat hier en nergens anders.

Dit document bezit de werkvolgorde, de statusladder, de werkwijze per workitem, de releasegate,
het protocol van de hardware-eindronde en de TestFlight-regel. De registers verwijzen hierheen en
kopiëren die onderdelen niet. Staat er in een register iets anders over volgorde of gate, dan
wint dit document.

**Uitgangspunt.** De fysieke hardwareronde is de allerlaatste testfase. Hij draait op één vaste
SHA en één binary, en precies die goedgekeurde build gaat naar TestFlight. Er komt geen eerdere
hardware- of RC-ronde.

## 1. Welk document wat bezit

| Document | Bezit |
|---|---|
| dit document | werkvolgorde, statusladder, werkwijze per workitem, releasegate, hardware-eindronde, TestFlight-regel |
| [DESIGN-INDEX.md](DESIGN-INDEX.md) | welke beeldenset bindt, waar hij staat, en de verwijzing naar de registers |
| [ios-unified-implementation-register.md](ios-unified-implementation-register.md) | de iOS-workitems met hun status |
| [tvos-redesign-register.md](tvos-redesign-register.md) | de tvOS-workitems met hun status |
| [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md) | de masterlijst van hardwarebevindingen, met haar eigen statussen |
| [DECISIONS.md](DECISIONS.md) | besluiten, append-only |
| [ios-unified-2026-audit.md](ios-unified-2026-audit.md) | bevroren; paragraaf 10 wordt niet meer aangeraakt, DEC-110 sluit hem |

## 2. Statusladder

Beide registers gebruiken dezelfde ladder:

```
OPEN → IN PROGRESS → CODE CLOSED · VERIFY/SIM OPEN → CODE/SIM CLOSED · HARDWARE OPEN → DONE
```

Buiten de ladder staan `DEFERRED`, `BLOCKED` en `VERVANGEN`, met hun bestaande betekenis.

Een stap die voor een item geen bewijs vraagt wordt overgeslagen. Een puur visueel item zonder
focus- of navigatiegedrag hoeft geen Verify-scenario, een iPhone-scherm zonder hardwarepunt geen
device-run. Wat overgeslagen wordt, staat in de bewijskolom met de reden. `DONE` vraagt alle
bewijssoorten die voor dat item gelden.

De correctieronde houdt `FIXED`, `VERIFIED`, `HARDWARE ONLY` en de rest. Vertaald naar deze ladder
is `FIXED` daar hooguit `CODE CLOSED · VERIFY/SIM OPEN` hier, tenzij er een Verify-run bij staat.

## 3. Bewijsregel

Drie soorten bewijs, en elk register noteert ze apart:

| Soort | Wat telt | Wat niet telt |
|---|---|---|
| `CODE` | een SHA op `main`, met de tests die het gedrag vastleggen | een branch die niet gemerged is |
| `VERIFY/SIM` | een groene Pleya Verify-run of simulatorrun, met bundel en de SHA waarop hij draaide | het bestaan van een scenario-YAML |
| `HARDWARE` | een device-run op een genoemde build | een simulatorrun, een golden |

Ontbreekt een soort, dan blijft de status eronder. Een run op een oudere SHA telt alleen als de
bestanden die het item raakt sindsdien niet gewijzigd zijn, en dat staat er dan bij met het
`git log`-commando waarmee het is nagegaan. Liever een lagere status die aantoonbaar klopt dan de
status die een latere fase moet halen.

## 4. Werkwijze per workitem

### Branch-preflight

Vóór elk workitem, en na elke merge opnieuw:

```bash
git status --porcelain                      # leeg, op ongetrackte sessielogs na
git fetch --prune origin && git fetch --prune github
git rev-parse HEAD origin/main github/main  # drie gelijke SHA's
git rev-list --left-right --count HEAD...origin/main   # 0 0 (origin is de canonical remote)
```

Dan een verse branch vanaf die `main`. Werk stapelt nooit op de baseline van een vorig workitem.

### Umbrella en children

I7 (Mijn Pleya) en T2b (tvOS-rest) bestaan alleen in de volgorde. Gebouwd wordt in de
child-workitems, elk op een eigen branch vanaf de actuele `main` en elk tussentijds gemerged.
Een umbrella is klaar als al zijn children klaar zijn; hij heeft zelf geen commits.

### Preflight van het workitem

Voordat er code verandert, vier vragen, en de antwoorden gaan in het register:

1. Wie is de eigenaar: welk bestand, welke functie?
2. Welk contract bestaat er al, en wat belooft het?
3. Welke tests en Verify-scenario's dekken het vandaag?
4. Bestaat de abstractie die het werk nodig heeft? `UnifiedActivationCoordinator`,
   `OverlaySheetHost` met `OverlaySheetController` en `searchProjection` bestaan op `76492ec2`,
   maar bestaan is niet hetzelfde als een passend contract. Past hij niet, dan volgt een expliciet
   besluit met contracttests. Er komt nooit een tweede infrastructuur naast de bestaande.

### Volgorde binnen een workitem

Preflight, bewijs dat het probleem er is, fix bij de gedeelde eigenaar, gerichte tests en de
Verify-stap die het item vraagt, commit. Het register krijgt de SHA in een volgende commit en niet
met een amend, want een amend verandert de hash die je er net in zette. Dan mergen.

Voor tvOS-bevindingen uit de correctieronde gelden daarbovenop de zes stappen bovenaan dat
document, inclusief de negatieve controle die aantoonbaar rood was.

### NOT REPRODUCED

Mag alleen met: de SHA, de fixture of toestand, de stappen, de logs, en het aantal pogingen.
Het betekent dat het met die middelen niet te zien was, niet dat de bug niet bestaat. Een melding
die op hardware gezien is en in de simulator niet, blijft `HARDWARE ONLY` en schuift naar de
eindronde.

## 5. Werkvolgorde

| # | Workitem | Kern | Exit |
|---|---|---|---|
| 1 | UNI0 | de documenten laten zeggen wat er op `main` staat | dit document, beide registers bijgewerkt, DEC-110 |
| 2 | I4 iOS Zoeken (05) | mobiele presentatie op de gedeelde search, identity en activation; SRCH-2 in de gedeelde eigenaar | widgettests, ios-sim Verify, screenshot tegen 05, activation vanuit elke resultaatgroep bewezen |
| 3 | T1 tvOS-blockers | PLR6 (eerst de fork lezen met `scripts/tvos_engine_source.sh`), LAND5, VER3, VER5, I18N1-4 en I18N6, STR3-5, GOLD2 via `goldens.yml`, LIB5 (reproductie of onderbouwd NOT REPRODUCED) | per item de stappen van de correctieronde; PLR6 komt niet verder dan `CODE/SIM CLOSED · HARDWARE OPEN`. **`CODE/SIM CLOSED`**: gemerged in `main` via `314d5207`, LIB5/STR3-5/I18N1-4/I18N6/LAND5/VER3/VER5/GOLD2 elk `FIXED` in de correctieronde; PLR6 blijft `HARDWARE ONLY, blokkerend` tot §7 |
| 4 | I5 bronkeuze (08) en contextmenu (09) | `UnifiedActivationCoordinator` beslist; sheets via de bestaande `OverlaySheetHost`; markeer-bekeken met groepssemantiek | geen tweede sheet-stack; contracttests |
| 5 | I6 film- en seriedetail (06, 07) | gedeelde data, identity en activation, eigen mobiele widget; volledige synopsis; seizoenstaat blijft bewaard | widgettests en ios-sim Verify |
| 6 | T2a tvOS detail en LIB7 | MOC-09 en MOC-10 compositie tegen mockup 37, MOC-11, MOC-12, LIB7 | per MOC eigen bewijs |
| 7 | T3a fixtures | alle vier: `catalog.watchlist.v1`, `seerr.requests.v1`, `activity.active-session.v1`, `catalog.long-rails.v1` | WL2, REQ1, ACT1 en VER4 dicht op de simulator; MYP1 dicht als deze fixtures Mijn Pleya volledig dekken, anders expliciet toegewezen aan I7-child 18 of T2b-child MOC-16 |
| 8 | I7 Mijn Pleya (umbrella) | children, elk met eigen branch en tussentijdse merge: 18, 11, 12, 13 (projectie van bestaande events), 14, 15 (mobiel ontworpen, niet de TV verkleind), 19, 21 | elk child los naar `CODE/SIM CLOSED` |
| 9 | T2b tvOS rest (umbrella) | children: MOC-16, MOC-17, MOC-18, MOC-20, MOC-21 met 22, MOC-23, MOC-24 met 25, SYS-2, SYS-4, SYS-5, SYS-6, SYS-7 | per child eigen bewijs |
| 10 | I8 account | 16, 17 en de profiel-laadcomp; PIN, toevoegen en wisselen, server offline, deels verbonden multi-server, eerste start, geen sessie, sessieherstel | widgettests en Verify |
| 11 | I9a Live TV (10) | Nu op TV, Gids, Opnames; bestaande gids- en opnamefuncties blijven | widgettests en Verify |
| 12 | I9b Speler (20) | landschap is het primaire acceptatiedoel; geen functie verdwijnt | widgettests en Verify |
| 13 | T3b fixtures | de capabilities die de afronding daarna nog mist | per fixture het scenario dat erop wachtte |
| 14 | IOS-HOME-AB | de indicator wordt de segmentindicator; A staat al op `moreInfo` | een test op de default |
| 15 | Functionele closuregate | alle open Verify- en testschuld van gebouwde schermen dicht: 01 tot en met 04, de widgettest van de filtersheet, de landing-Verify voor 02 | geen open functionele schuld |
| 16 | I10 visual acceptance | 21 schermen en 5 comps, per scherm huidige screenshot, northstar, verschil, fix, Verify; iPhone SE-klasse en iPhone 15 Pro; iPad als regressiegrens | alleen visueel werk; een functionele fix betekent dat die Verify opnieuw draait |
| 17 | Hardware-eindronde | zie paragraaf 7 | |
| 18 | TestFlight | exact de goedgekeurde archive | |

Vóór stap 17 moeten implementatie, tests, Verify, de simulatorgates, visual acceptance en de
iPad-regressie klaar zijn, en `main` groen en schoon.

Stap 16 controleert per scherm: marges, tekstgrootte, kaartverhouding en -dichtheid, koppen, de
tabbalk, gekozen en inactieve staat, sheets, safe areas en Dynamic Island, licht, donker en OLED
waar dat telt, lange Nederlandse strings, lege, laad- en foutstaten, en tekstschaal voor
toegankelijkheid.

## 6. Releasegate

De redesign is pas af als elke regel in deze tabel waar is:

| iOS | tvOS |
|---|---|
| 21 van 21 northstar-schermen beoordeeld | alle geldende mockup-oppervlakken beoordeeld |
| 5 comps beoordeeld | fysieke Apple TV-ronde voltooid |
| de 2 Home-besluiten gesloten (DEC-110) en gebouwd (IOS-HOME-AB) | geen release-blocking hardwarebevinding |
| Zoeken unified | geen route zonder uitweg voor de focus |
| detail unified | Verify-journeys groen |
| Mijn Pleya compleet | hardware-open items gesloten |
| speler gecontroleerd | speler en Menu volledig bruikbaar |
| iPad niet onbedoeld gewijzigd | overscan, 4K en afstandsbediening gecontroleerd |
| ios-sim Verify groen | tvos-sim en hardware groen |

Voor beide platforms daarbovenop:

- `flutter analyze` zonder waarschuwingen;
- de volledige testsuite groen tegen de geldende baseline;
- `scripts/codegen.sh` levert een lege gegenereerde diff;
- de unused-code- en unused-files-checks uit CI groen;
- goldens bijgewerkt via `.github/workflows/goldens.yml`, geen enkele bewust stale;
- geen afwijking van een northstar of goedgekeurde mockup zonder DEC.

## 7. Hardware-eindronde

De release-identiteit is vier dingen samen: de SHA, de versie met buildnummer, de
Release-configuratie met de compile-time flags, en de archive.

1. Kies één finale SHA op `main`. Leg SHA, versie, buildnummer, configuratie en flags vast in de
   correctieronde.
2. Maak per Apple-target één finale `.xcarchive` vanaf die SHA en leg de hash van de archive vast.
   Tel de binary markers vóór de run, zodat een build van vóór een feature niet alles groen
   afvinkt.
3. Zet de devicebuild vanuit diezelfde archive op de apparaten. De distributievorm mag verschillen
   in signing en verpakking, niet in compilatie.
4. Test op de Apple TV 4K de volledige route Home, Films, Series, alle catalogi, filters,
   sorteren, detail, bronkeuze, speler, spelerpaneel, Zoeken, Mijn Pleya, Bibliotheken, Kijklijst,
   Aanvragen, Activiteit, Instellingen, profielwissel, offline en herstel. Per route: de vier
   pijlen, SELECT, MENU of BACK, lang SELECT, PLAY/PAUSE waar relevant; de focusring nooit
   afgesneden, de kolompositie behouden, de juiste focus na terugkeer, nooit twee focusindicatoren,
   geen doodlopende route, geen paneel zonder uitweg. Daarbij overscan, 4K-output, Reduce Motion,
   VoiceOver, PLR6, MOC-31, MOC-33, de edge-cases J2, J4, J8 en J9, en elke `HARDWARE ONLY` uit de
   correctieronde. Voor iPhone de hardwarepunten die het iOS-register noemt.
5. Vraagt een bevinding een codewijziging of een nieuwe compilatie, dan gaat de gate weer open:
   nieuwe SHA, de regressies opnieuw, een nieuwe archive, en de relevante delen van de matrix
   opnieuw. Acceptatie van de vorige archive gaat niet mee.

## 8. TestFlight

TestFlight is het versturen van exact de archive uit de hardware-eindronde naar App Store Connect.
Tussen de hardwareacceptatie en de upload wordt er niets gecompileerd en niets vanaf source
gebouwd.

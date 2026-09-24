# TV9: tvOS naar TestFlight

Vastgelegd op 24 september 2026, op `main` = `76b83521` (TV8 gemerged via PR #62). TV0 tot en met
TV8 en GATE0 zijn dicht. Dit plan brengt de tvOS-helft van de releasegate
(`docs/unified-2026-closure.md` §6) rond, draait de hardware-eindronde (§7) en stuurt exact die
archive naar TestFlight (§8).

## Besluiten van Michel (24 september)

| Punt | Keuze | Aanscherping |
|---|---|---|
| Scope | tvOS eerst | De iOS-stappen I7 tot en met I10 volgen als eigen spoor. Wijkt af van de volgorde in §5, dus een DEC. |
| VIS1 | naar 36 B | Zoekpil op ongeveer halve breedte, telling verticaal gecentreerd. |
| VIS2 | naar 37 C | Seizoenchips op de kopregel "Afleveringen", aantal afleveringen erachter. |
| VER1 | vervangen | Nieuwe DEC: `tvos.nav.walk` en `tvos.nav.focus-switches-destination` nemen de DEC-081-gate over, `tvos.sidebar.collapse` gaat weg. |
| APP1 | focus repareren | LEFT vanuit elke rij in de rechterkolom gaat naar de actieve categorie. RIGHT vanuit een categorie gaat naar de eerste focusbare rij van die categorie. De omweg van zeven keer UP verdwijnt uit `tvos.settings.appearance`. Beide richtingen in tests en Verify. |
| OFF6 | sectie behouden | Een rebind van hetzelfde profiel wist de geneste Mijn Pleya-route niet. Terug naar de hub alleen als de sectie na de nieuwe binding echt niet meer bestaat, met focus op de tegel van die sectie. |
| PROF1 | `TvProfileGate` | Voor `nav.profile`, maar niet als `requireSelection: true`. In de app sluit Menu de route en keert de focus terug naar `nav.profile`. De launch-gate houdt zijn verplichte-selectiecontract, inclusief app-exit waar dat hoort. "Profielen beheren" blijft naar de bestaande beheerflow gaan. Geen tweede picker. |
| Hardware | zodra alles klaar is | Geen tussenbuild voor PLR6: §7 staat één vaste SHA en archive toe. PLR6 staat bovenaan de checklist, zodat een fout meteen opvalt. |

## Fase 0: administratie (docs, één commit)

1. DEC-119: tvOS gaat vóór de iOS-stappen I7 tot en met I10 naar TestFlight. De releasegate van §6
   geldt voor deze release alleen in de tvOS-kolom plus de gedeelde regels. §5 krijgt een
   verwijzing, het iOS-register een regel dat I7 tot en met I10 het volgende spoor zijn.
2. DEC-120: de DEC-081-gate gaat over op `tvos.nav.walk` en `tvos.nav.focus-switches-destination`.
3. De correctieronde heeft twee rijen VER1 en twee rijen VER2 (de oude uit fase 10 en die van TV8).
   De TV8-rijen worden VER6 (sidebar-scenario) en VER7 (flaky spelerscenario's), inclusief de
   verwijzingen in het register en de TV8-notities.
4. VIS1, VIS2, APP1, OFF6 en PROF1 krijgen in de correctieronde het besluit van hierboven.

## Fase 1: code, drie branches, elk met eigen PR en merge

Elke branch volgt de vaste volgorde: reproduceren (test of Verify rood), fixen, `scripts/ci_checks.sh`,
gerichte tests, de betrokken Verify-scenario's op de tvOS-simulator, screenshots lezen, goldens via
`goldens.yml` met de testbestanden expliciet opgegeven, PR, merge als de zes verplichte checks
groen zijn en de branch up-to-date is.

### 1a `feat/tv9-visual`: VIS1, VIS2, PLR10

- VIS1: breedte van de zoekpil en uitlijning van de telling in de TV-zoekkop. Verify:
  `tvos.search.results` met een `rightOf`/`below`-assert op de telling en een screenshot tegen 36 B.
  SEARCH2 (clipping) en SEARCH3 (DOWN naar het eerste resultaat) mogen niet terugkomen.
- VIS2: chips naar de kopregel met het aantal. Dit raakt de hoogteberekening uit DET4 en de route
  UP vanaf de afleveringsrail. De bestaande DET4-intrinsieke-hoogtetest blijft en krijgt de nieuwe
  compositie, `tvos.detail.series` krijgt een `rightOf`-assert van de chips op de kop en een check
  dat UP vanaf aflevering 1 op de actieve chip landt. `media_detail_screen.dart` staat op 5532
  regels (DET4-SIZE): de kop met chips gaat bij deze wijziging naar een eigen widgetbestand, zonder
  gedragswijziging, zoals de refactorregel vraagt.
- PLR10: "5minuten" wordt "5 minuten" in de slaaptimer, met een unittest op de formattering.

### 1b `feat/tv9-focus`: APP1, OFF6, PROF1

- APP1: expliciete focusovergangen in de categorie-indeling van Uiterlijk, niet langer
  geometrisch. Widgettest voor LEFT vanaf een lage rij en RIGHT naar de eerste rij.
  `tvos.settings.appearance` loopt daarna zonder de zeven keer UP en assert beide richtingen.
- OFF6: `_invalidateAllScreens` roept bij een rebind van hetzelfde profiel
  `clearNestedRoutes()` niet meer aan. Is de sectie na de binding weg, dan gaat de kijker naar de
  hub met de focus op de tegel. Test in de bestaande `MainScreen`-harness
  (`test/screens/main_screen_tv_offline_destination_test.dart`). Verify: de offline-fixture
  (`POST /__verify/offline`) met een geopende sectie, dan herverbinden, en de sectie moet nog open
  staan.
- PROF1: `nav.profile` opent `TvProfileGate` als gewone route met een eigen modus naast
  `requireSelection`. Tests voor beide modi: Menu sluit de in-app route met de focus terug op
  `nav.profile`, en de launch-gate gedraagt zich zoals nu. Nieuwe journey `tvos.profile.gate`, en
  `tvos.profile.picker` loopt opnieuw.

### 1c `feat/tv9-verify-hygiene`: VER6, VER7, SYS-3d, SYS-3e

- VER6: `tvos.sidebar.collapse.yaml` weg. De MCP-tests en docs die hem noemen gaan naar de twee
  nav-scenario's (DEC-120).
- VER7: de fixtureclip wordt ruim langer dan 2 seconden, zodat de spelerscenario's niet meer
  afhangen van het einde van de clip. Bewijs: `tvos.player.osd`, `tvos.player.panel` en
  `tvos.player.zoom` elk drie keer achter elkaar groen.
- SYS-3d en SYS-3e: de drie resterende aanroepers van `scaleForSize` op `MediaQuery` gaan naar
  `TvLayoutConstants.scaleOf`, met een test per aanroeper, naar het patroon van SYS-3c.

## Fase 2: tvOS-releasegate op de simulator

Op `main` na de drie merges:

1. `scripts/ci_checks.sh` groen, de volledige testsuite groen met de gepinde Flutter 3.44.0 en
   `scripts/codegen.sh` zonder diff.
2. De volledige tvOS-Verify-suite één keer groen op één build. Herhaalruns alleen na aantoonbare
   harnasfouten (idb-verbinding), en die staan dan in het rapport.
3. `goldens.yml` over alle goldenbestanden: niets gewijzigd en niets bewust stale.
4. Tabel "mockup-oppervlak beoordeeld" voor alle geldende MOC's in `docs/tvos-redesign-register.md`:
   per MOC een screenshot uit een Verify-bundel naast de mockup, of de DEC die de afwijking dekt.
   Een MOC zonder een van beide is een nieuwe VIS-rij en blokkeert fase 3 tot die is beslist.
5. Controle "geen route zonder uitweg voor de focus": elke route uit §7 punt 4 heeft een journey
   met MENU terug, of staat als `HARDWARE ONLY` in de checklist.

## Fase 3: release-identiteit en archive

1. Nieuwe branch voor de lane: `tvos_beta` bouwt en uploadt nu in één stap, en dat botst met §8.
   Er komen twee lanes: `tvos_archive` (`build_app` met `skip_package_ipa` naar een vaste
   `.xcarchive`, en de SHA-256 van die map) en `tvos_upload archive:` (exporteert app-store uit die
   archive en uploadt met `upload_beta`, zonder compilatie). De devicebuild komt uit dezelfde
   archive via een development-export en `devicectl`.
2. Finale SHA op `main` kiezen, buildnummer ophogen via de bestaande `ensure_build_number`. SHA,
   versie, buildnummer, Release-configuratie, compile-time flags en de archive-hash gaan in de
   correctieronde.
3. Binary markers tellen in de archive vóór de installatie: een string of symbool per fix uit TV1
   tot en met TV9 (onder andere LAND6b, SEARCH3, VIS1, APP1, PROF1). Ontbreekt er één, dan
   wordt er niet geïnstalleerd.
4. Installeren op de Apple TV 4K met `devicectl`.

## Fase 4: hardware-eindronde (Michel)

Ik schrijf de checklist als `docs/tvos-hardware-eindronde.md`, in de volgorde van testen:

1. PLR6 als eerste: speler openen, spelerpaneel openen, Menu. Faalt dit, dan stopt de ronde hier.
2. AUD1 en AUD3 op het gehoor, SEL2 (Select na het systeemtoetsenbord), REV1b (Jellyfin-bibliotheek
   via Mijn Pleya > Bibliotheken).
3. De routematrix uit §7 punt 4 met per route de vier pijlen, SELECT, MENU, lang SELECT en
   PLAY/PAUSE, en per route een vakje voor ring afgesneden, kolom behouden, focus na terugkeer,
   dubbele indicator en doodlopend.
4. J2 4K-output, J4 overscan, J8 VoiceOver en J9 Reduce Motion, plus MOC-31 en MOC-33.
5. De nieuwe TV9-gedragingen: APP1, OFF6 (met de server even uit en weer aan) en PROF1.

Per vakje "OK" of een korte bevinding. Een bevinding die code vraagt opent de gate opnieuw: nieuwe
SHA, regressies, nieuwe archive en de relevante delen van de matrix opnieuw (§7 punt 5).

## Fase 5: TestFlight

`tvos_upload` met de geaccepteerde archive, alleen naar de interne groep. Die groep deelt elke
build automatisch met Guido. Daarna de build in App Store Connect controleren (export compliance,
zichtbaar in TestFlight) en de release-notes onder het gegenereerde blok in `docs/RELEASES.md`.

## Buiten deze release

- iOS I7 (11, 12, 13), I8, I9a, I9b, IOS-HOME-AB en I10: het volgende spoor, volgens DEC-119.
- Acceptance gaps zonder productbesluit: ACT1 (wacht op PS-9), WL2, LIVE2, MOC-14, MOC-16 en LAND7.
- REV1-MERGE: gedocumenteerd gevolg, geen melding van een gebruiker. Oppakken bij de volgende
  wijziging aan cross-server mergen.
- LIVE7: TV4 heeft de lezing al vastgelegd.
- Bestandsgrootte (CTX1-SIZE, CAT21, WL2-SIZE, LIVE5, LIVE6, REV1-SIZE): alleen opsplitsen als
  een TV9-wijziging het bestand raakt.

## Stoppunten

Er is één geplande stop: fase 4 vraagt Michel met de Apple TV in de hand. Verder stop ik alleen bij
een echte blocker, zoals een DEC die een eerder besluit tegenspreekt of een CI-storing buiten de
repo.

# TV2 Zoeken, Landings, Catalogus en Kijklijst Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** De acht TV2-bevindingen sluiten die op de vier contentoppervlakken zitten waar een kijker
het meeste tijd doorbrengt: Zoeken dat door zijn eigen header heen scrolt (SEARCH2), een landing die
leeg is en daarmee de catalogus verbergt (LAND6) en de actieve rail niet op een vaste hoogte zet
(LAND7), een kijklijstkaart die bij verwijderen de ring meeneemt (WL3), de Apple Review-melding dat
Films en Series leeg blijven op Jellyfin terwijl Home vol staat (REV1), het bewijs dat een echte
cross-backend titel één unified item wordt (AGG1), het bronfilter van Alle films dat een trage
server permanent kwijtraakt (CAT20), en een vastgelegde grens voor de kijklijstverificatie (WL2).

**Architecture:** Geen nieuwe infrastructuur, en geen nieuwe widget-familie. SEARCH2 en LAND7 gaan
naar bestaande eigenaren: de scrollviewport die de header al buiten zichzelf houdt, en
`TvHomeLayout.rowTileScrollAlignment`, de anker-helper die Home sinds DEC-095 al gebruikt. LAND6
hergebruikt `_openAllScreen`, dat de shell-route al kent. REV1 kopieert het precedent dat de
Pleya-protocolclient in VER4 kreeg: een hub leidt zijn type af uit zijn items in plaats van
`mixed` te claimen. WL3 repareert de bestaande rescue in `TvCatalogCardGrid._reconcileNodes` in
plaats van er een tweede naast te zetten. CAT20 zoekt de eigenaar in de bronfilter-pruning en niet
in de catalogusscreen. WL2 bouwt niets.

**Tech Stack:** Flutter 3.44.0 exact (`.fvmrc`), `flutter test`, `flutter analyze`,
`scripts/ci_checks.sh`, goldens uitsluitend via `.github/workflows/goldens.yml` op Linux.

**Spec:** `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md`, hoofdstuk 4, TV2
("zoeken, landings, catalogus en kijklijst").

**Voorwaarde:** TV0 en TV1 zijn uitgevoerd, gereviewd en gemerged. Deze branch
(`feat/tv2-search-catalog-landings-watchlist`) is vers afgetakt van `main` boven die merge
(`330a51e4`). Dit plan begint met een preflight die elk van de acht bevindingen opnieuw tegen die
HEAD toetst, en neemt geen enkele status uit de correctieronde op gezag over.

## Global Constraints

- Geen AI- of vendorvermelding in commits, documentatie, code-comments of MR-teksten, en geen
  co-auteur- of sessieregel onderaan een commit. Auteur is Michel Knoop.
- Geen em-dashes in prozabestanden. De hook `~/.claude/hooks/anti-slop-check.sh` controleert elke
  Write/Edit op een `.md`, en meldt treffers met regelnummer.
- Flutter SDK 3.44.0 exact. `scripts/check_flutter_version.sh` draait vooraan in `ci_checks.sh` en
  `codegen.sh` en weigert een andere SDK, omdat `dart format` per versie verschilt.
- `flutter analyze` waarschuwingen zijn CI-failures.
- Nieuwe TV-contentroutes gaan via `openTvContentRoute` (`lib/navigation/tv/tv_content_route_registry.dart:63`)
  met een kale `Navigator.push` als fallback wanneer geen shell luistert. Dat is SYS-1a's contract
  en SYS-1d/SYS-1e's fix.
- Elke bevinding die onderweg opduikt krijgt eerst een eigen rij in
  `docs/tvos-fysieke-correctieronde.md` en, waar hij een werkitem raakt, in
  `docs/tvos-redesign-register.md`, voordat hij als gesloten telt.
- `SKIP_HOOKS=1` alleen bij een commit die uitsluitend documentatie raakt. Nooit bij een commit die
  `lib/` of `test/` aanraakt.
- Een bestand dat richting 500 regels loopt en dat je toch aanraakt: noteer in de taak of het
  gesplitst moet worden, en splits chirurgisch zonder gedragswijziging.
- Goldens worden nooit lokaal op macOS geregenereerd. De route is `workflow_dispatch` op
  `.github/workflows/goldens.yml`.

---

## Task 0: Preflight, elke bevinding opnieuw tegen deze HEAD

De correctieronde is op onderdelen ouder dan de code. CAT20 draagt de instructie letterlijk
("reproduceer eerst tegen de huidige `main`, dan pas beslissen"), en LAND7 beschrijft Home in een
staat die HOME1/DEC-095 al veranderd kan hebben. Deze taak schrijft niets in `lib/`.

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (alleen de rijen die aantoonbaar niet meer kloppen)

- [ ] **Step 1: Bevestig de basis**

```bash
cd /Users/michelknoop/.supacode/repos/plezy-main/feat/superpowers-tvos-redesign
git status --porcelain
git branch --show-current
git log --oneline -5
flutter --version | head -1
scripts/check_flutter_version.sh
```

Verwacht: branch `feat/tv2-search-catalog-landings-watchlist`, `330a51e4` als merge-commit in de
log, SDK 3.44.0. Een schone boom op ongetrackte sessielogs na.

- [ ] **Step 2: Nulmeting van de testsuite**

```bash
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -5
flutter test test/screens/watchlist_screen_test.dart 2>&1 | tail -5
flutter test test/providers/ test/services/unified_catalog/ 2>&1 | tail -5
```

Noteer per commando het aantal groen en rood, en de namen van de falers. Alles wat hier al rood is
mag aan het einde van TV2 niet als "door TV2 veroorzaakt" gelezen worden, en alles wat hier groen is
moet groen blijven.

- [ ] **Step 3: WL3, staat de rode test er nog**

```bash
flutter test test/screens/watchlist_screen_test.dart \
  --plain-name "removing the card the remote is on leaves the remote on a card" 2>&1 | tail -20
```

Verwacht: FAIL op `the slot is kept, so the card that slid up into the empty cell takes the ring`.
Is hij groen, dan is WL3 onderweg gesloten: zet de rij op `FIXED` met de SHA die dat deed
(`git log -S "..." -- lib/` op de betrokken bestanden) en laat Task 4 vervallen.

- [ ] **Step 4: SEARCH2, staat de clip er nog**

```bash
grep -n 'clipBehavior: Clip.none' lib/screens/tv/tv_search_view.dart
grep -rn 'SingleChildScrollView' -A 3 lib/screens/tv/tv_search_view.dart lib/screens/tv/tv_seerr_discover_view.dart | grep -n 'Clip.none'
```

Verwacht: `tv_search_view.dart:295` en `tv_seerr_discover_view.dart:627`, allebei een
`SingleChildScrollView` met `clipBehavior: Clip.none` en hetzelfde commentaar erboven.

- [ ] **Step 5: LAND6, is de lege landing nog actie-loos**

```bash
sed -n '317,331p' lib/screens/tv/tv_discovery_landing_screen.dart
```

Verwacht: de laatste regel van `_buildEmptyOrLoading` bouwt `_LandingMessage` met alleen `title` en
`body`, zonder `actionLabel`/`onAction`. Staat er wel een actie, dan is LAND6 gesloten.

- [ ] **Step 6: LAND7, wat doet Home vandaag werkelijk**

```bash
grep -rn 'tileScrollAlignment' lib | grep -v 'tv_discovery_rail.dart'
grep -n 'rowTileScrollAlignment' -A 4 lib/widgets/tv/tv_unified_layout.dart | head -12
```

Verwacht: `lib/widgets/tv/tv_content_feed.dart:639` geeft `TvHomeLayout.rowTileScrollAlignment(...)`
door, en `lib/widgets/tv/tv_content_row.dart:65` heeft een default van `0.5`. Geen enkele andere
aanroeper. Dat betekent: **Home heeft het canonieke anker al, de landings en Zoeken niet.** Werk de
LAND7-rij in de correctieronde bij met die vaststelling voordat je Task 3 begint, want de rij
beschrijft Home nu als het probleemoppervlak.

- [ ] **Step 7: CAT20, reproduceer of ontkracht**

```bash
git log --oneline --since=2026-09-13 -- \
  lib/screens/tv/tv_unified_catalog_screen.dart \
  lib/services/unified_catalog/ lib/providers/unified_catalog_provider.dart
sed -n '310,332p' lib/screens/tv/tv_unified_catalog_screen.dart
sed -n '246,262p' lib/services/unified_catalog/unified_catalog_filters.dart
```

Verwacht: geen commit sinds 13 september op deze eigenaren, en `_restorePreferences` dat
`withKnownSources` toepast en het resultaat terugschrijft met
`UnifiedCatalogQueryStore.write`. Michels melding "op 15 september opgelost" is dan niet door een
commit gedekt, en de rij mag niet op `FIXED` staan. Zet hem op `IN PROGRESS` met die vaststelling.

- [ ] **Step 8: REV1, is de hub-typering nog hard**

```bash
grep -n "type: 'mixed'\|type: 'episode'\|type: 'movie'\|type: 'show'" lib/services/jellyfin_client/parts/browse.dart
grep -n '_hubItemsType' -A 6 lib/services/pleya_server_client/parts/browse.dart | head -14
```

Verwacht: elke Jellyfin-hub draagt `'mixed'` of `'episode'`, en geen enkele `'movie'` of `'show'`,
terwijl de Pleya-protocolclient zijn type wel uit de items afleidt. Dat is REV1's root cause, en
Task 5 bouwt erop. Is dat al anders, stop en onderzoek voordat je Task 5 begint.

- [ ] **Step 9: AGG1 en WL2, de twee die geen codegat zijn**

```bash
grep -n '_neverMergedBackends' -A 3 lib/services/unified_catalog/grouping_service.dart
grep -c 'watchlist\|favorite' docs/pleya-protocol/v1/openapi.yaml || echo "0 treffers"
ls test/services/watchlist_source_factory_test.dart
```

Verwacht: `{MediaBackend.local, MediaBackend.pleyaServer}` in de uitsluitingslijst, **nul** treffers
op watchlist of favorites in het bevroren `/v1`-protocol, en een bestaand
`watchlist_source_factory_test.dart`. Alle drie zijn input voor Task 8 en Task 9.

- [ ] **Step 10: Werk de rijen bij die aantoonbaar niet meer kloppen**

Alleen wat de stappen hierboven hebben aangetoond, met het commando erbij waarmee je het zag. Niets
op gevoel. Verwachte kandidaten: LAND7 (Home heeft het anker al), CAT20 (geen commit onder de
"opgelost"-melding), WL2 (de unit-naad bestaat al, het gat zit in het transport).

- [ ] **Step 11: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: TV2-preflight, acht bevindingen opnieuw tegen main getoetst

Per bevinding vastgelegd wat er op deze HEAD werkelijk staat, met het commando
waarmee het is nagegaan. Drie rijen beschreven een situatie die de code niet
meer heeft: LAND7 noemt Home als probleemoppervlak terwijl DEC-095 dat oppervlak
als enige een canoniek anker gaf, CAT20 stond op een melding zonder commit
eronder, en WL2 vraagt om onderzoek naar een testnaad die al bestaat.

Geen code gewijzigd."
```

---

## Task 1: SEARCH2, de scrollviewport die niet clipt aan de bovenkant

**Root cause, te bevestigen in stap 1.** `TvSearchView._buildBody` bouwt zijn resultaten in een
`SingleChildScrollView` met `clipBehavior: Clip.none`. Dat commentaar zegt waarom: een gefocuste
kaart groeit buiten zijn band, en de default clip zou de ring afsnijden. `Clip.none` schakelt de
clip echter aan **alle** randen uit, ook de bovenste. De zoekbalk en de topnav staan boven deze
viewport, in dezelfde `Column`, en worden vóór de body geschilderd. Wat naar boven weggescrold is,
tekent er dus overheen. Dat is precies het gemelde beeld: de labels en de resultaattelling blijven
op hun hoogte staan terwijl er een rij doorheen loopt.

Dezelfde constructie staat in `lib/screens/tv/tv_seerr_discover_view.dart:627`, met woordelijk
hetzelfde commentaar. De fix hoort bij de gedeelde vorm, niet bij Zoeken alleen (regel 4 van de
correctieronde: fix bij de gedeelde eigenaar).

**Files:**
- Modify: `lib/screens/tv/tv_search_view.dart:288-297`
- Modify: `lib/screens/tv/tv_seerr_discover_view.dart:620-631`
- Test: `test/screens/tv/tv_search_view_test.dart` (nieuwe groep aan het einde van `main()`)

**Interfaces:**
- Consumes: `TvCatalogGrid.forWidth`, `TvCatalogLayout.cardContentInset`, allebei ongewijzigd.
- Produces: niets publieks. De wijziging is lokaal aan twee viewports.

- [ ] **Step 1: Bevestig dat er echt niets anders scrolt**

```bash
grep -n 'SingleChildScrollView\|ListView\|CustomScrollView\|Scrollable' lib/screens/tv/tv_search_view.dart
grep -rn 'class SearchScreen' lib/screens/search_screen.dart | head -3
grep -n 'TvSearchView(' -B 10 lib/screens/search_screen.dart | head -30
```

Er is precies één scrollable in deze view, en de zoekbalk komt van `SearchScreen` en staat erbuiten.
Vind je een tweede scrollable of een tweede render van dezelfde tekst, stop: dan is de hypothese
onjuist en moet de root cause opnieuw bepaald worden voordat er iets verandert.

- [ ] **Step 2: Schrijf de negatieve controle**

Voeg toe aan het einde van `main()` in `test/screens/tv/tv_search_view_test.dart`. Gebruik de
bestaande pump-helper uit dat bestand; bouw geen eigen opstelling.

```dart
  // ---------------------------------------------------------------------------
  // SEARCH2: weggescrolde resultaten mogen niet over de header heen tekenen
  // ---------------------------------------------------------------------------

  group('SEARCH2, the results viewport', () {
    testWidgets('clips at its own top edge', (tester) async {
      await pumpSearch(tester, sections: manySections());

      final viewport = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(TvSearchView),
          matching: find.byType(SingleChildScrollView),
        ),
      );

      // Clip.none switches clipping off on every edge, not just the two the
      // focus ring needs. The header sits above this viewport in the same
      // Column and paints first, so anything scrolled past the top edge paints
      // over it.
      expect(viewport.clipBehavior, isNot(Clip.none));
    });

    testWidgets('a scrolled result does not reach the search field', (tester) async {
      await pumpSearch(tester, sections: manySections());

      final field = tester.getRect(find.byKey(searchFieldKey));
      final firstCard = find.byKey(const ValueKey('tv.catalog.grid.item[search.movies.0]'));
      expect(firstCard, findsOneWidget);

      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -600));
      await tester.pumpAndSettle();

      // The card either scrolled out of the tree or is below the field. What it
      // must not be is painted across it.
      if (tester.any(firstCard)) {
        expect(tester.getRect(firstCard).top, greaterThanOrEqualTo(field.bottom));
      }
    });
  });
```

`manySections()` en `searchFieldKey` bestaan mogelijk nog niet in dit testbestand. Lees het bestand
eerst; is er al een sectie-bouwer, gebruik die en geef hem genoeg items om verticaal te kunnen
scrollen (drie banden van twaalf kaarten op een viewport van 1280x720 is ruim genoeg). Is er nog
geen sleutel op het veld, geef de placeholder-widget die de test aan `searchField` meegeeft er een.
De spec vraagt hier expliciet om: "Eerst een fixture met genoeg resultaten om echt verticaal te
scrollen."

- [ ] **Step 3: Draai en bevestig dat hij rood is**

```bash
flutter test test/screens/tv/tv_search_view_test.dart --plain-name "SEARCH2"
```

Verwacht: de eerste test faalt op `Clip.none`, de tweede op een `top` die boven `field.bottom` ligt.
Faalt de tweede niet, noteer dat: dan bewijst alleen de eerste het defect en is de tweede een
regressiegrens in plaats van een reproductie.

- [ ] **Step 4: Commit de rode test**

```bash
git add test/screens/tv/tv_search_view_test.dart
git commit -m "test: negatieve controle voor SEARCH2

Rood op deze commit: de resultatenviewport op Zoeken clipt aan geen enkele rand,
dus wat naar boven wegscrolt tekent over de zoekbalk en de bovenbalk heen."
```

- [ ] **Step 5: De fix in Zoeken**

De ring heeft ruimte nodig aan de zijkanten en aan de onderkant van een band, niet boven de pagina.
Zet de clip terug aan en geef de ring zijn ruimte via padding in plaats van via het ontbreken van
een clip:

```dart
    return SingleChildScrollView(
      // SEARCH2. `Clip.none` gaf de focusring zijn ruimte door aan geen enkele
      // rand te clippen, en dat kost de bovenrand: de zoekbalk en de bovenbalk
      // staan in dezelfde Column boven deze viewport en worden ervoor
      // geschilderd, dus een weggescrolde band tekende eroverheen. De ring
      // heeft alleen ruimte nodig waar een kaart groeit, en dat is binnen de
      // viewport: `padding` geeft hem die, `clipBehavior` houdt de pagina heel.
      padding: EdgeInsets.only(
        top: TvCatalogLayout.cardFocusRingGap * scale,
        bottom: geometry.bottomSafeMargin,
      ),
      child: Column(
```

Controleer de naam van de ringgap-constante voordat je hem gebruikt:

```bash
grep -n 'cardFocusRingGap\|focusRingGap\|focusBorderWidth' lib/widgets/tv/tv_unified_layout.dart | head
```

Bestaat `cardFocusRingGap` niet onder die naam, gebruik de constante die
`TvCatalogCard`/`TvCatalogCardRail` zelf voor de ring hanteert. Verzin geen nieuwe waarde en zet er
geen getal neer.

De zijranden zijn hier geen probleem: `TvCatalogCardRail` scrolt horizontaal binnen zijn eigen box
en heeft zijn eigen `clipBehavior: Clip.none` op regel 307, die ongewijzigd blijft.

- [ ] **Step 6: Draai de test**

```bash
flutter test test/screens/tv/tv_search_view_test.dart
```

Verwacht: de SEARCH2-groep groen, en geen enkele bestaande test in dit bestand die omvalt. Valt er
een focus- of geometrietest om, dan is de padding te groot gekozen en hoort hij op de werkelijke
ringmaat.

- [ ] **Step 7: Dezelfde fix op Ontdekken**

`lib/screens/tv/tv_seerr_discover_view.dart:627` heeft woordelijk dezelfde constructie en dus
hetzelfde defect. Pas hem identiek aan, met een commentaarregel die naar SEARCH2 verwijst.

**Dit is een aparte bevinding**, ook al is het dezelfde fix: hij is niet gemeld en niet gereproduceerd
op hardware. Voeg een rij toe aan `docs/tvos-fysieke-correctieronde.md` voordat je hem als gesloten
telt:

```markdown
| SEARCH2b | Ontdekken draagt dezelfde viewport-constructie als SEARCH2 (`tv_seerr_discover_view.dart:627`, `SingleChildScrollView` met `clipBehavior: Clip.none` en woordelijk hetzelfde commentaar), dus weggescrolde shelves tekenen daar op dezelfde manier over de kop en de bovenbalk. Gevonden tijdens TV2's SEARCH2-taak, niet los gemeld en niet op hardware gezien | CODE CLOSED · VERIFY/SIM OPEN | (SHA uit stap 8) |
```

Voeg ook een widgettest toe aan het Ontdekken-testbestand die dezelfde `clipBehavior`-assertie doet.

```bash
ls test/screens/tv/ | grep -i seerr
```

- [ ] **Step 8: Volle ronde en commit**

```bash
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -5
flutter analyze
```

Vergelijk met Task 0 stap 2. Geen enkele test die daar groen was mag hier rood zijn.

```bash
git add lib/screens/tv/tv_search_view.dart lib/screens/tv/tv_seerr_discover_view.dart \
  test/screens/tv/tv_search_view_test.dart docs/tvos-fysieke-correctieronde.md
git commit -m "fix: de resultatenviewport op Zoeken clipt weer aan zijn bovenrand (SEARCH2)

Clip.none gaf de focusring zijn ruimte door nergens te clippen, en dat kost de
bovenrand: de zoekbalk en de bovenbalk staan in dezelfde Column erboven en
worden eerder geschilderd, dus een weggescrolde band tekende eroverheen. Dat is
wat op hardware gezien is als een header die over de content blijft staan.

De ring krijgt zijn ruimte nu van padding, binnen de viewport, en de pagina
blijft heel. Ontdekken droeg dezelfde constructie met hetzelfde commentaar en is
in dezelfde ronde meegefixt, als SEARCH2b in de correctieronde."
```

---

## Task 2: LAND6, een lege landing houdt de route naar de catalogus

**Besluit, niet meer open.** Optie (a) uit de correctieronde: de lege staat draagt zelf de
"Alle films"/"Alle series"-actie, zodat de complete catalogus bereikbaar blijft. De landing wordt
verder niet heringericht. Dit staat vast en wordt in deze taak niet heropend.

Er zit een tweede helft aan vast die de correctieronde nog niet noemt en die deze fix gratis
meeneemt: de lege tak van `_buildEmptyOrLoading` tekent vandaag **geen enkele focusbare widget**, en
`focusActiveTabIfReady` valt in dat geval terug op `_focusFirstRail()`, dat zonder rails niets doet.
Op tvOS is een pagina met focus en zonder gefocust item er een die je niet kunt verlaten, precies
CAT12 en CAT14. De fouttak heeft die actie wel, de lege tak niet.

**Files:**
- Modify: `lib/screens/tv/tv_discovery_landing_screen.dart:317-330` en `:286-300`
- Test: `test/screens/tv/tv_discovery_landing_screen_test.dart` (nieuwe groep)

**Interfaces:**
- Consumes: `_openAllScreen()` (`tv_discovery_landing_screen.dart:310`), dat `widget.onOpenAll` al
  probeert voordat het op een kale push terugvalt. Dit is het SYS-1-conforme pad en wordt niet
  gedupliceerd.
- Consumes: `widget.allTitle`, de label die de gevulde tak al op zijn `TvViewAllAction` zet.
- Produces: niets publieks.

- [ ] **Step 1: Schrijf de negatieve controle**

Gebruik de bestaande fakes bovenin `test/screens/tv/tv_discovery_landing_screen_test.dart`
(`_FakeAggregationService` en de providers eromheen). Pump de landing met een `DiscoverProvider` die
klaar is met laden, geen fout heeft, en nul hubs oplevert.

```dart
  // ---------------------------------------------------------------------------
  // LAND6: een lege landing verbergt de catalogus niet
  // ---------------------------------------------------------------------------

  group('LAND6, an empty landing', () {
    testWidgets('still offers the route into the complete catalog', (tester) async {
      await pumpLanding(tester, hubs: const []);

      expect(find.text(t.unifiedCatalog.discovery.emptyTitle), findsOneWidget);
      // The rails are the only other way in, and there are none. Without this
      // action the complete catalog is unreachable from this screen even when
      // Bibliotheken shows a library with content in it, which is the case the
      // finding came off the simulator with.
      expect(find.text(allTitle), findsOneWidget);
    });

    testWidgets('puts the remote on that action', (tester) async {
      await pumpLanding(tester, hubs: const []);
      await tester.pumpAndSettle();

      // A tvOS page with the focus and nothing focused on it is one the remote
      // can neither move within nor leave (CAT12, CAT14). The error branch
      // already had an autofocusing button; the empty branch had nothing.
      expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot(contains('ModalScope')),
        reason: 'the focus must be on the action, not on the page scope',
      );
    });

    testWidgets('opens it through the shell when one is listening', (tester) async {
      var opened = 0;
      await pumpLanding(tester, hubs: const [], onOpenAll: () => opened++);

      await tester.tap(find.text(allTitle));
      await tester.pumpAndSettle();

      // SYS-1a's contract: the shell callback, not a bare Navigator.push that
      // would draw over the top navigation.
      expect(opened, 1);
    });
  });
```

`pumpLanding` en `allTitle` bestaan mogelijk onder een andere naam. Lees het bestand eerst en
gebruik wat er staat; voeg alleen een `hubs: const []`-variant toe als de helper die nog niet kan.

- [ ] **Step 2: Draai en bevestig rood**

```bash
flutter test test/screens/tv/tv_discovery_landing_screen_test.dart --plain-name "LAND6"
```

Verwacht: alle drie rood. De eerste op een ontbrekende tekst, de tweede op de modal scope, de derde
op nul aanroepen.

- [ ] **Step 3: Commit de rode tests**

```bash
git add test/screens/tv/tv_discovery_landing_screen_test.dart
git commit -m "test: negatieve controle voor LAND6

Rood op deze commit: een landing zonder hubs tekent alleen een tekstblok. De
catalogus is er niet vanaf te bereiken, en er staat geen enkele focusbare widget
op, dus de afstandsbediening komt er ook niet meer vanaf."
```

- [ ] **Step 4: De fix**

In `_buildEmptyOrLoading`, de lege tak:

```dart
    return _LandingMessage(
      title: t.unifiedCatalog.discovery.emptyTitle,
      body: t.unifiedCatalog.discovery.emptyBody,
      // LAND6. De rails zijn de enige andere ingang naar de complete catalogus,
      // en die zijn er hier niet. Dat "geen hubs" is niet hetzelfde als "geen
      // inhoud": de bevinding kwam van een simulator waar Bibliotheken een
      // Jellyfin-bibliotheek met zes films toonde terwijl de hubs van een
      // offline Pleya Server moesten komen. Dezelfde actie als boven de rails,
      // dus dezelfde route: `_openAllScreen` kent het shell-contract al.
      //
      // De knop is bovendien het enige focusbare ding op deze pagina. Zonder
      // hem opent de landing met de focus op de modal scope en geen item eronder
      // (CAT12, CAT14), en op tvOS is dat een eindstation.
      actionLabel: widget.allTitle,
      onAction: _openAllScreen,
    );
```

`_LandingMessage` tekent zijn knop al met `autofocus: true` (regel 371), dus de focus regelt zichzelf
zodra de actie er is. Controleer dat en voeg geen tweede focusaanvraag toe.

- [ ] **Step 5: `focusActiveTabIfReady` moet de knop kennen**

Vandaag valt die terug op `_focusFirstRail()` zodra `_viewAllFocus` niet kan focussen, en op een lege
landing doet dat niets. Laat de lege staat zijn eigen antwoord geven. Kijk eerst of
`_LandingMessage`'s autofocus dit al dekt in de test uit stap 1; doet hij dat, laat deze stap dan
weg en noteer dat in de commit. Doet hij dat niet, geef `_LandingMessage` een `FocusNode` die het
scherm vasthoudt en vraag die aan in `focusActiveTabIfReady` voordat je op `_focusFirstRail` terugvalt.
Geen postFrame-hack en geen timer: de knop bestaat of hij bestaat niet, en dat is synchroon te zien.

- [ ] **Step 6: Draai**

```bash
flutter test test/screens/tv/tv_discovery_landing_screen_test.dart
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -5
flutter analyze
```

- [ ] **Step 7: Goldens**

```bash
flutter test test/goldens/tv_discovery_landing_production_golden_test.dart 2>&1 | tail -20
```

Deze goldens tekenen gevulde landings, dus ze horen niet te bewegen. Bewegen ze wel, stop en zoek
uit waarom: dan raakt de fix ook de gevulde tak, en dat hoort hij niet te doen. Moeten er toch
goldens vernieuwd worden, dan via `workflow_dispatch` op `.github/workflows/goldens.yml`, nooit
lokaal.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/tv/tv_discovery_landing_screen.dart test/screens/tv/tv_discovery_landing_screen_test.dart
git commit -m "fix: een lege landing houdt de route naar de complete catalogus (LAND6)

De lege tak van _buildEmptyOrLoading tekende alleen een tekstblok. Alle films
staat in de andere tak, boven de rails, en er is geen andere ingang, dus zonder
rails was de catalogus vanaf dit scherm onbereikbaar. Dat is niet hetzelfde als
niets hebben: de bevinding kwam van een simulator waar Bibliotheken zes films
toonde terwijl de hubs van een offline server moesten komen.

De lege staat draagt die actie nu zelf, via hetzelfde _openAllScreen dat het
shell-contract al kent. Daarmee valt ook de focusval weg die eronder zat: deze
tak had geen enkele focusbare widget, dus de pagina opende met de focus op de
modal scope en geen item eronder, hetzelfde eindstation als CAT12 en CAT14."
```

---

## Task 3: LAND7, één canoniek anker voor de actieve rail

**Wat Task 0 stap 6 heeft laten zien.** Home heeft het anker al: `tv_content_feed.dart:639` geeft
`TvHomeLayout.rowTileScrollAlignment(viewportHeight, scale)` door, en die helper is geschreven voor
precies deze eis ("één anker voor elke rij: het label van de gefocuste rail staat onder de
bovenbalk"). De landings gebruiken `TvDiscoveryRail` zonder `tileScrollAlignment`, dus met de default
`0.5`: de gefocuste tegel gaat naar het midden van de viewport, en boven een rail die verder naar
beneden staat blijft daardoor een leeg blok staan. Zoeken gebruikt `TvCatalogCardRail`, waarvan de
kaarten `FocusableWrapper` met de default `scrollAlignment: 0.5` dragen.

LAND7's root cause staat daarmee niet meer op UNKNOWN: het is één anker dat op één oppervlak bestaat
en op drie niet. De taak is dat anker delen, niet een tweede focus-engine bouwen.

**Non-goals uit de correctieronde, die hier binden:** LAND2, LAND3 en LAND4 blijven dicht. Geen
tweede focus-engine. Geen negatieve marge per scherm. Geen vaste "100 px omhoog". Geen
`Scrollable.ensureVisible` die alleen "ergens zichtbaar" belooft. Horizontale traversal mag geen
verticale scroll veroorzaken. Geen timing- of postFrame-hacks.

**Files:**
- Modify: `lib/screens/tv/tv_discovery_landing_screen.dart` (de `TvDiscoveryRail`-constructie rond
  regel 224)
- Modify: `lib/widgets/tv/tv_unified_layout.dart` (alleen als de helper een naam nodig heeft die
  niet Home-specifiek klinkt)
- Test: `test/screens/tv/tv_discovery_landing_screen_test.dart`

**Interfaces:**
- Consumes: `TvHomeLayout.rowTileScrollAlignment(double viewportHeight, double scale) -> double`,
  bestaand, `lib/widgets/tv/tv_unified_layout.dart:1318`. Geeft de fractie van de viewport waar het
  midden van de gefocuste tegel naartoe scrolt.
- Consumes: `TvDiscoveryRail.tileScrollAlignment` (`lib/widgets/tv/tv_discovery_rail.dart:230`),
  bestaand, wordt doorgegeven aan elke tegel.
- Produces: niets publieks, tenzij de helper hernoemd wordt. Doe dat alleen als hij letterlijk
  Home-specifieke aannames bevat; hij bevat ze niet (hij rekent met de railband en de koptekst,
  niet met de hero), dus de verwachte uitkomst is hergebruik onder dezelfde naam.

- [ ] **Step 1: Audit de vier oppervlakken voordat je iets wijzigt**

```bash
grep -rn 'TvDiscoveryRail(' lib | grep -v 'tv_discovery_rail.dart'
grep -rn 'TvCatalogCardRail(' lib | grep -v 'tv_catalog_card_rail.dart'
```

Schrijf per call site op: welk oppervlak, welke rail-familie, en of er een `tileScrollAlignment`
staat. De spec noemt vier te auditeren oppervlakken: Home, de Films-landing, de Series-landing en
Zoeken. Zoeken en Ontdekken gebruiken de catalogusrail; die heeft geen `tileScrollAlignment`-parameter
en zijn kaarten leunen op `FocusableWrapper`'s default. Noteer of Zoeken wel of niet in scope hoort:
Zoeken heeft één header boven een kortere pagina en een ander probleem (SEARCH2), dus het antwoord
mag "niet in deze taak" zijn, mits opgeschreven.

- [ ] **Step 2: Schrijf de negatieve controle**

De assertie meet de positie van de kop van de actieve rail ten opzichte van de bovenkant van de
contentviewport, in tolerantie, zoals de correctieronde vraagt ("op de oude implementatie staat de
actieve heading aantoonbaar onder de canonieke anchor").

```dart
  // ---------------------------------------------------------------------------
  // LAND7: de actieve rail komt op een vaste verticale positie
  // ---------------------------------------------------------------------------

  group('LAND7, the active rail', () {
    testWidgets('lands on the same anchor whichever rail takes the focus', (tester) async {
      await pumpLanding(tester, hubs: threeRails());
      final viewport = tester.getRect(find.byType(ListView));

      Future<double> headingTopAfterFocusing(int rail) async {
        await focusRail(tester, rail);
        await tester.pumpAndSettle();
        return tester.getRect(find.text(railTitle(rail))).top - viewport.top;
      }

      final first = await headingTopAfterFocusing(0);
      final second = await headingTopAfterFocusing(1);
      final third = await headingTopAfterFocusing(2);

      // One anchor, not three. Without it the third rail's heading sits far
      // below the first one's, which is the black band the finding describes.
      expect((second - first).abs(), lessThan(8));
      expect((third - first).abs(), lessThan(8));
    });

    testWidgets('horizontal movement does not move the page', (tester) async {
      await pumpLanding(tester, hubs: threeRails());
      await focusRail(tester, 1);
      await tester.pumpAndSettle();

      final before = scrollOffset(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // LAND7's own acceptance: LEFT/RIGHT changes the card, never the page.
      expect(scrollOffset(tester), before);
    });
  });
```

`threeRails()`, `focusRail`, `railTitle` en `scrollOffset` bestaan mogelijk nog niet. Lees het
testbestand: er staat al een harness met hubs en rails voor LAND2/LAND4-achtige tests. Gebruik die,
en geef hem drie rails met genoeg tegels zodat de pagina echt kan scrollen. Doet de fixture dat niet,
herinner je VER4: een scenario dat niet kan scrollen toetst niets.

- [ ] **Step 3: Draai en bevestig rood**

```bash
flutter test test/screens/tv/tv_discovery_landing_screen_test.dart --plain-name "LAND7"
```

Verwacht: de eerste test rood, de tweede groen. De tweede is een grens, geen reproductie:
`FocusableWrapper` slaat een scroll over zodra het doel binnen een halve tegelhoogte ligt
(`focusable_wrapper.dart:448`), en horizontaal bewegen verandert het verticale midden niet. Is de
tweede toch rood, dan is er een tweede defect en krijgt dat een eigen rij in de correctieronde
voordat je verdergaat.

Is de **eerste** test groen, stop. Dan doet de landing dit al goed en gaat LAND7 over iets anders dan
deze test meet. Noteer dat in de correctieronde in plaats van een fix te schrijven voor iets wat je
niet gezien hebt.

- [ ] **Step 4: Commit de rode test**

```bash
git add test/screens/tv/tv_discovery_landing_screen_test.dart
git commit -m "test: negatieve controle voor LAND7

Rood op deze commit: elke rail op de landing scrolt naar het midden van de
viewport in plaats van naar één vaste kopositie, dus hoe lager de rail, hoe
groter het lege blok erboven. De tweede test is de grens die al klopt:
horizontaal bewegen verandert de verticale offset niet."
```

- [ ] **Step 5: De fix**

De landing bouwt zijn rails in een `LayoutBuilder`-loze `Builder`; de viewporthoogte komt uit
`MediaQuery.sizeOf(context).height` of uit de `ListView`-constraints. Lees eerst welke van de twee
de contentviewport werkelijk is, want de spec verbiedt expliciet dat Zoeken en Home blind dezelfde
absolute offset krijgen: het anker is relatief aan de eigen contentviewport.

```dart
                  child: TvDiscoveryRail(
                    ...
                    // LAND7. Hetzelfde anker dat Home sinds DEC-095 gebruikt:
                    // het label van de gefocuste rail komt onder de bovenbalk te
                    // staan, voor elke rail gelijk. De default 0.5 zette elke
                    // rail in het midden van de viewport, dus hoe lager de rail
                    // in de lijst, hoe groter het lege blok erboven.
                    //
                    // Relatief aan de contentviewport van dit scherm, niet aan
                    // die van Home: de helper rekent met de railband en de
                    // kopregel en krijgt de hoogte hier binnen.
                    tileScrollAlignment: TvHomeLayout.rowTileScrollAlignment(viewportHeight, scale),
```

Heeft de landing die hoogte nog niet bij de hand, wikkel de railsectie dan in een `LayoutBuilder` op
dezelfde manier als `tv_content_feed.dart:505` dat doet. Geen `MediaQuery` van het hele scherm als de
contentbox kleiner is: SYS-1c zette die contentbox er bewust in.

- [ ] **Step 6: Draai, inclusief de buren die LAND2 tot en met LAND5 bewaken**

```bash
flutter test test/screens/tv/tv_discovery_landing_screen_test.dart
flutter test test/widgets/tv/ 2>&1 | tail -5
flutter test test/screens/tv/ 2>&1 | tail -5
flutter analyze
```

Vergelijk met Task 0 stap 2. LAND2, LAND3, LAND4 en LAND5 hebben eigen tests; die moeten groen
blijven, want deze taak mag ze niet heropenen.

- [ ] **Step 7: Goldens**

```bash
flutter test test/goldens/tv_discovery_landing_production_golden_test.dart 2>&1 | tail -20
```

Deze goldens tekenen de landing in rust, met de focus op het kopblok, dus een scrollanker hoort ze
niet te raken. Raakt hij ze wel, regenereer via `goldens.yml` en noteer in de commit welke en
waarom.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/tv/tv_discovery_landing_screen.dart test/screens/tv/tv_discovery_landing_screen_test.dart
git commit -m "fix: de actieve rail op een landing krijgt het anker dat Home al had (LAND7)

De landings gaven TvDiscoveryRail geen tileScrollAlignment, dus elke tegel
scrolde naar het midden van de viewport. Hoe lager de rail in de lijst, hoe
groter het zwarte blok tussen de bovenbalk en de rail die de focus had.

Home kreeg dat anker met DEC-095: TvHomeLayout.rowTileScrollAlignment zet het
label van de gefocuste rail onder de bovenbalk, voor elke rij gelijk. Dezelfde
helper, gevoed met de contentviewport van dit scherm in plaats van met die van
Home. Geen tweede focus-engine, geen vaste offset, en de horizontale traversal
blijft onaangeroerd."
```

---

## Task 4: WL3, verwijderen laat de ring op een kaart staan

**De bestaande rode test is de opdracht.** `test/screens/watchlist_screen_test.dart`,
`removing the card the remote is on leaves the remote on a card`, groep
`TV, in the catalog language (DEC-108, mockup 34)`. Er komt geen nieuwe test voor het gemelde
gedrag: deze test beschrijft het al en staat aantoonbaar rood (Task 0 stap 3).

**De werkhypothese, die stap 1 bevestigt of verwerpt.** `TvCatalogCardGrid._reconcileNodes`
(`lib/widgets/tv/tv_catalog_card_grid.dart:390`) heeft de rescue al, en `watchlist_screen.dart:128`
vertrouwt er expliciet op ("Nothing is done about the focus here any more"). Maar de rescue vuurt
alleen wanneer `heldTheFocus` waar is, en dat wordt gelezen op het moment dat de kaart verdwijnt.
Op dat moment is de kaart niet het ding dat de focus heeft: de kijker heeft Select gedrukt, het
item-blad heeft de focus overgenomen, en de verwijdering volgt op het indrukken van Verwijderen in
dat blad. `losesFocus` is dan waar (de onthouden id verdwijnt), `heldTheFocus` niet, dus
`_focusedId` wordt wel op de vervanger gezet en de focus wordt niet verplaatst.

**Files:**
- Modify: `lib/widgets/tv/tv_catalog_card_grid.dart:390-435` (de gedeelde eigenaar) of
  `lib/screens/watchlist_screen.dart:123-141` (de aanroeper), afhankelijk van stap 1
- Test: `test/screens/watchlist_screen_test.dart` (bestaand, niet uitbreiden tenzij stap 1 dat
  vraagt)

**Interfaces:**
- Consumes: `TvCatalogCardGrid._reconcileNodes({required List<String> previous})`, privé, en
  `_nearestSurvivor({required List<String> previous, required int from}) -> String?`, privé.
- Produces: geen publieke wijziging tenzij de fix een parameter op `TvCatalogCardGrid` nodig heeft.
  Krijgt hij die, documenteer hem hier voordat je hem gebruikt.

- [ ] **Step 1: Bewijs welke tak faalt, voordat je iets wijzigt**

Instrumenteer tijdelijk, draai de rode test, lees de uitvoer, en haal de instrumentatie er weer uit.
Niet committen.

```dart
    // TIJDELIJK, niet committen.
    debugPrint('WL3 reconcile: focusedId=$focusedId losesFocus=$losesFocus '
        'heldTheFocus=$heldTheFocus oldIndex=$oldIndex removed=$removed');
```

En na `final replacement = _nearestSurvivor(...)`:

```dart
    debugPrint('WL3 replacement=$replacement primary=${FocusManager.instance.primaryFocus?.debugLabel}');
```

```bash
flutter test test/screens/watchlist_screen_test.dart \
  --plain-name "removing the card the remote is on leaves the remote on a card" 2>&1 | grep WL3
```

Vier uitkomsten, en elk wijst een andere fix aan:

1. `losesFocus=false`: `_focusedId` was niet de verwijderde kaart. De grid weet niet welke kaart de
   ring had. De fix zit in wat `_buildCell` schrijft.
2. `losesFocus=true, heldTheFocus=false`: de werkhypothese. Het blad had de focus toen de kaart
   verdween.
3. `heldTheFocus=true, replacement=null`: `_nearestSurvivor` vindt niets terwijl er vijf kaarten
   over zijn. De fix zit in die walk.
4. `heldTheFocus=true, replacement='d'` en toch rood: de post-frame callback wordt overtroefd door
   de supersede-check, of de node van `d` is nog niet attached. De fix zit in het frame-venster.

**Schrijf op welke het is voordat je verdergaat.** Een fix voor de verkeerde tak is precies wat de
correctieronde met stap 2 van zijn werkwijze verbiedt.

- [ ] **Step 2: Fix bij de gedeelde eigenaar, per uitkomst**

**Bij uitkomst 2** (de verwachte). De grid kan niet zien of de focus "van hem was" wanneer een modaal
blad hem tijdelijk heeft. Wat hij wel weet is of de focus **binnen zijn eigen scope** zat vlak
voordat het blad opende. De kleinste correcte fix is de vraag verplaatsen van "heeft deze node nu de
focus" naar "was deze grid de laatste eigenaar van de ring". Lees eerst of er al zo'n begrip in de
codebase zit:

```bash
grep -rn 'FocusMemoryTracker\|lastFocusedIn\|hadFocus' lib/widgets/tv/ lib/focus/ | head -20
```

Bestaat het, gebruik het. Bestaat het niet, dan is de kleinere ingreep aan de aanroeperkant, en dan
mag hij daar: `watchlist_screen.dart:_openSheet` weet dat het blad de focus heeft geleend en kan hem
teruggeven voordat het de verwijdering doet. Dat is geen aanroeper-workaround maar eigenaarschap:
degene die de focus leende, geeft hem terug. Schrijf in het commentaar op waarom gedeeld oplossen
hier niet het kleinste antwoord is, zoals stap 4 van de correctieronde-werkwijze vraagt.

**Bij uitkomst 1, 3 of 4**: de fix zit in `tv_catalog_card_grid.dart` zelf, bij de tak die stap 1
heeft aangewezen. Raak de andere drie takken niet aan.

- [ ] **Step 3: Draai de test die de opdracht was**

```bash
flutter test test/screens/watchlist_screen_test.dart 2>&1 | tail -10
```

Verwacht: de hele groep groen, inclusief
`removing the last card leaves the remote on the empty state, not on nothing`, die vandaag al groen
is en de grens aan de andere kant vastlegt.

- [ ] **Step 4: Draai de buren die op dezelfde rescue leunen**

```bash
flutter test test/widgets/tv/tv_catalog_card_grid_test.dart 2>&1 | tail -5
flutter test test/screens/tv/tv_unified_catalog_screen_focus_test.dart 2>&1 | tail -5
flutter test test/screens/tv/tv_watchlist_view_test.dart 2>&1 | tail -5
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -5
flutter analyze
```

`_reconcileNodes` draagt CAT17 op zijn rug: een sorteerwissel herpagineert de catalogus, en de
rescue mocht toen niet vuren terwijl de kijker in de rail stond. Een fix die `heldTheFocus` verruimt
kan CAT17 heropenen. Zit daar een test op, dan moet die groen blijven; is die er niet, schrijf hem
erbij voordat je commit.

```bash
grep -rn 'CAT17' test | head
```

- [ ] **Step 5: Notitie over bestandsgrootte**

`lib/screens/tv/tv_watchlist_view.dart` is 760 regels en `test/screens/watchlist_screen_test.dart`
1092. Raakt deze taak `tv_watchlist_view.dart`, noteer in de commit of hij gesplitst moet worden
(de rail-opbouw en de focustraversal zijn de twee natuurlijke helften) en doe dat in een aparte
commit zonder gedragswijziging, met de testsuite als bewijs. Raakt de taak alleen
`tv_catalog_card_grid.dart` (560 regels), dan is er geen splitsing nodig.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/tv/tv_catalog_card_grid.dart lib/screens/watchlist_screen.dart
git commit -m "fix: een verwijderde kijklijstkaart geeft de ring door (WL3)

De rescue in TvCatalogCardGrid._reconcileNodes bestond al en watchlist_screen
vertrouwde er expliciet op, maar hij vuurt alleen wanneer de verdwijnende kaart
op dat moment de focus houdt. Bij verwijderen is dat niet zo: Select opent het
itemblad, het blad neemt de focus, en de kaart verdwijnt pas als Verwijderen
daar is ingedrukt. De vervanger werd wel onthouden en de ring niet verplaatst.

De bestaande rode test in watchlist_screen_test.dart legde dit al vast en was
rood op de commit ervoor. CAT17's grens blijft staan: een herpaginering terwijl
de kijker in de rail staat trekt de ring nog steeds niet het raster in."
```

---

## Task 5: REV1a, een Jellyfin-hub typeert zichzelf uit zijn items

**Root cause, statisch aangetoond in Task 0 stap 8.** `TvDiscoveryLandingProvider._project()`
(`lib/providers/tv_discovery_landing_provider.dart:105`) verdeelt de backend-hubs over de
Films- en de Series-landing met `UnifiedHubKind.fromHubType(hub.type).singleKindSurface`. Die is
`null` voor `mixed`, `episode` en `other`, en zo'n hub gaat dus naar geen van beide landings.

De Jellyfin-client typeert **elke** hub hard: `home.recent`, `home.continue`, `home.toprated`,
`home.somethingdifferent`, `library.<id>.recent` en `library.<id>.continue` krijgen allemaal
`type: 'mixed'`, en de twee next-up-rijen `type: 'episode'`. Geen enkele Jellyfin-hub draagt ooit
`movie` of `show`. Een huishouden dat via Jellyfin verbindt ziet daarom op Films en Series altijd
"Niets te ontdekken", terwijl Home diezelfde rijen wel toont omdat Home elk type accepteert. Dat is
exact wat bij Apple Review gemeld is.

**Het precedent bestaat al.** VER4 vond dezelfde fout in de Pleya-protocolclient en sloot hem met
`_hubItemsType` (`lib/services/pleya_server_client/parts/browse.dart:351`), inclusief de regel dat
een pagina met uitsluitend afleveringen onder `show` valt en niet in een eigen bak. De docstring daar
beweert bovendien dat "Plex en Jellyfin een hub-kind zelf melden", en dat klopt voor Plex en niet
voor Jellyfin. Die zin wordt in deze taak gecorrigeerd.

**Files:**
- Modify: `lib/services/jellyfin_client/parts/browse.dart` (de acht `syntheticHub`-aanroepen met een
  hard `type`)
- Modify: `lib/services/pleya_server_client/parts/browse.dart:337-347` (de docstringzin die Jellyfin
  ten onrechte vrijpleit)
- Test: `test/services/` (het bestaande Jellyfin-browse-testbestand; zoek het in stap 1)

**Interfaces:**
- Consumes: `MediaKind.isShowRelated` (`lib/media/media_kind.dart:29`), bestaand.
- Produces: een gedeelde helper met de signatuur `String hubItemsType(List<MediaItem> items)`, die
  `'movie'` geeft als elk item een film is, `'show'` als elk item show-gerelateerd is, en anders
  `'mixed'` (ook voor een lege lijst). Plaats hem waar beide clients hem kunnen lezen, of laat de
  Jellyfin-client zijn eigen privé-kopie houden met een verwijzing naar het origineel. Dupliceer de
  regel niet stilzwijgend: kies en schrijf op waarom.

- [ ] **Step 1: Vind de testplek en de betrokken hubs**

```bash
ls test/services | grep -i jellyfin
grep -rn "identifier: 'home\.\|identifier: 'library\." -A 2 lib/services/jellyfin_client/parts/browse.dart | grep -n "type:"
grep -rn 'fetchHubs\|syntheticHub' test/services/*jellyfin* | head
```

- [ ] **Step 2: Schrijf de negatieve controle**

Twee niveaus, want het defect zit in de client en het gevolg in de landingprovider. Schrijf ze
allebei; de tweede is wat de bevinding beschrijft en de eerste is waar de fix landt.

In het Jellyfin-browse-testbestand:

```dart
  test('REV1: a recently added hub of films types itself as movie', () async {
    final hubs = await clientWithLatest([movieJson('m1'), movieJson('m2')]).fetchHomeHubs();

    final recent = hubs.firstWhere((h) => h.identifier == 'home.recent');
    // 'mixed' has no singleKindSurface, so a hub typed that way is dropped by
    // both the Films and the Series landing no matter what is in it. That is
    // what Apple Review saw: Home full, Films and Series empty.
    expect(recent.type, 'movie');
  });

  test('REV1: an all-episode hub types itself as show', () async {
    final hubs = await clientWithLatest([episodeJson('e1')]).fetchHomeHubs();

    // Episodes belong on Series, which is exactly where an episode-only hub
    // would vanish from if it kept its own bucket (the Pleya Server precedent).
    expect(hubs.firstWhere((h) => h.identifier == 'home.recent').type, 'show');
  });

  test('REV1: a genuine mix stays mixed', () async {
    final hubs = await clientWithLatest([movieJson('m1'), episodeJson('e1')]).fetchHomeHubs();

    expect(hubs.firstWhere((h) => h.identifier == 'home.recent').type, 'mixed');
  });
```

En in `test/providers/tv_discovery_landing_provider_test.dart`:

```dart
  test('REV1: a Jellyfin-only setup fills the Films landing', () async {
    final provider = landingProviderWith(hubs: [
      jellyfinHub(identifier: 'home.recent', type: 'movie', items: [movie('m1')]),
    ]);
    await pumpProjection(provider);

    expect(provider.movieHubs, isNotEmpty);
  });
```

De helpernamen zijn de vorm, niet de letter: lees allebei de testbestanden en gebruik wat er al
staat.

- [ ] **Step 3: Draai en bevestig rood**

```bash
flutter test test/services/ --plain-name "REV1" 2>&1 | tail -20
flutter test test/providers/tv_discovery_landing_provider_test.dart --plain-name "REV1" 2>&1 | tail -20
```

Verwacht: de eerste twee clienttests rood (`'mixed' != 'movie'`), de derde groen, en de
provider-test groen zodra er een hub met `type: 'movie'` in gaat (die test bewijst de keten, niet het
defect).

- [ ] **Step 4: Commit de rode tests**

```bash
git add test/services test/providers/tv_discovery_landing_provider_test.dart
git commit -m "test: negatieve controle voor REV1

Rood op deze commit: elke Jellyfin-hub draagt een hardgecodeerde type 'mixed' of
'episode', ongeacht wat erin zit. UnifiedHubKind.singleKindSurface sluit die
allebei uit van de Films- en de Serieslanding, dus een Jellyfin-huishouden ziet
daar altijd niets terwijl Home vol staat."
```

- [ ] **Step 5: De fix**

Vervang elk hard `type:` in `lib/services/jellyfin_client/parts/browse.dart` door het afgeleide type,
behalve de twee next-up-rijen: die zijn per definitie een aflevering-wachtrij en houden `'episode'`,
net als `PleyaHubId.nextUp` in het precedent.

```dart
  /// `movie` wanneer elk item een film is, `show` wanneer elk item
  /// show-gerelateerd is (`show`, `season` of `episode`, zie
  /// [MediaKind.isShowRelated]), en anders `mixed`, inclusief de lege lijst en
  /// een echte film/serie-mix.
  ///
  /// REV1. Deze client typeerde elke rij hard als `mixed`, en
  /// [UnifiedHubKind.singleKindSurface] sluit `mixed` uit van zowel de Films-
  /// als de Serieslanding: een huishouden dat via Jellyfin verbindt kon die
  /// twee schermen dus nooit gevuld zien, wat er ook in de bibliotheek stond.
  /// Precies het defect dat VER4 bij de Pleya-protocolclient sloot.
  ///
  /// Een pagina met uitsluitend afleveringen valt onder `show` en niet in een
  /// eigen bak: [MediaKind.episode] draagt geen eigen `singleKindSurface`, dus
  /// zo'n rij zou van Series verdwijnen, en dat is juist waar hij hoort.
  String _hubItemsType(List<MediaItem> items) {
    if (items.isEmpty) return 'mixed';
    if (items.every((item) => item.kind == MediaKind.movie)) return 'movie';
    if (items.every((item) => item.kind.isShowRelated)) return 'show';
    return 'mixed';
  }
```

`syntheticHub` krijgt het type als argument en de items pas daarna, dus het afgeleide type moet uit
de al gemapte items komen. Kijk hoe `syntheticHub` zijn items mapt (`mapItem`) en leid het type af uit
dezelfde gemapte lijst, niet uit de ruwe JSON: anders raken de twee uit elkaar zodra de mapper een rij
laat vallen. De kleinste vorm is `syntheticHub` het type zelf laten afleiden wanneer de aanroeper er
geen meegeeft; kies dat als het past, en schrijf de keuze op.

Corrigeer daarna de zin in `lib/services/pleya_server_client/parts/browse.dart:334` die zegt dat Plex
en Jellyfin hun hub-kind zelf melden. Alleen Plex doet dat.

- [ ] **Step 6: Draai**

```bash
flutter test test/services/ 2>&1 | tail -5
flutter test test/providers/ 2>&1 | tail -5
flutter test test/services/unified_catalog/ 2>&1 | tail -5
flutter analyze
```

Vergelijk met Task 0 stap 2. Let in het bijzonder op tests die `home.recent` of `'mixed'` als
verwachte waarde vastleggen: die legden het defect vast als contract en moeten meebewegen, met een
regel in de commit waarom.

```bash
grep -rn "'mixed'" test | head -20
```

- [ ] **Step 7: Bestandsgrootte**

`lib/services/jellyfin_client/parts/browse.dart` is 1863 regels. Deze taak maakt hem niet groter (hij
vervangt argumenten), dus splitsen is hier niet aan de orde en het zou de diff onleesbaar maken naast
een gedragswijziging. Noteer in de commit dat het bestand een splitsing verdient en dat die apart
hoort, en zet er een rij voor in de correctieronde als die er nog niet is.

- [ ] **Step 8: Commit**

```bash
git add lib/services/jellyfin_client/parts/browse.dart lib/services/pleya_server_client/parts/browse.dart \
  test/services test/providers/tv_discovery_landing_provider_test.dart
git commit -m "fix: een Jellyfin-hub leidt zijn type af uit zijn items (REV1)

Elke synthetische Jellyfin-rij droeg een hardgecodeerde type: 'mixed' voor
recent toegevoegd, verder kijken, best beoordeeld en iets anders, en 'episode'
voor de twee next-up-rijen. UnifiedHubKind.singleKindSurface sluit allebei uit
van de Films- en de Serieslanding, dus TvDiscoveryLandingProvider liet ze in
_project() vallen en beide schermen bleven leeg, terwijl Home dezelfde rijen wel
toont omdat Home elk type accepteert. Dat is het beeld dat bij Apple Review
gemeld is.

Zelfde fix als VER4 bij de Pleya-protocolclient: het type volgt uit de items,
met een pagina van uitsluitend afleveringen onder show in plaats van in een
eigen bak. De next-up-rijen houden hun episode, want die zijn per definitie een
afleveringwachtrij. De docstring daar pleitte Jellyfin ten onrechte vrij en is
gecorrigeerd."
```

---

## Task 6: REV1b, de concrete Jellyfin-bibliotheek via Mijn Pleya

REV1 heeft twee helften. Task 5 sluit de eerste, die statisch te bewijzen is. De tweede is de
melding dat "een concrete, zichtbare Jellyfin-library niet bereikbaar lijkt op de verwachte plek",
oftewel via Mijn Pleya en Bibliotheken. Die helft heeft geen bewezen root cause en kan niet uit de
code alleen volgen: hij hangt aan de werkelijke topologie van de demo-server.

Deze taak eindigt in een van twee uitkomsten, en beide zijn geldig. Een geraden fix is dat niet.

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (REV1-sectie, uitkomst vastleggen)
- Mogelijk: `lib/services/jellyfin_mappers.dart:288-302`, `lib/services/unified_catalog/source_cursor.dart:62-86`

- [ ] **Step 1: Loop de keten af die de correctieronde zelf noemt**

De bevinding schrijft de te onderzoeken keten voor. Loop hem af, en noteer per schakel wat je ziet:

```bash
grep -n '_libraryKindFromCollectionType' -A 18 lib/services/jellyfin_mappers.dart
grep -n 'eligibleCatalogLibraries' -A 22 lib/services/unified_catalog/source_cursor.dart
grep -rn 'isServerVisible' lib/services/multi_server_manager.dart | head
grep -rn 'hiddenLibraryKeys' lib/providers/hidden_libraries_provider.dart | head
```

Wat je verwacht te vinden, en wat het betekent:

- `_libraryKindFromCollectionType` mapt `movies` op `MediaKind.movie`, `tvshows` op `show`, en alles
  wat het niet kent op `MediaKind.unknown`.
- `eligibleCatalogLibraries` accepteert `MediaKind.unknown` expliciet ("we cannot say" is iets anders
  dan "we can say, and it is something else").

Als allebei kloppen, dan valt de "bibliotheek is niet eligible"-hypothese af en blijven
`isServerVisible`, `library.hidden` en `hiddenLibraryKeys` over. Val dan niet terug op raden.

- [ ] **Step 2: Leg de demotopologie vast, of leg vast dat je hem niet hebt**

De bevinding eist dit letterlijk: view- en library-id, naam, `CollectionType`/`Type`, parent,
zichtbaarheid, user access, werkelijke film- en serie-inhoud, en de relevante query-capabilities.

```bash
grep -n 'PLEYA_DEMO_URL\|PLEYA_DEMO_USER' .env 2>/dev/null | cut -c1-40 || echo "geen .env-regels"
scripts/tvos_sim.sh doctor
```

Is de demo-server bereikbaar, haal dan `/Users/{userId}/Views` op en schrijf de uitkomst in de
REV1-sectie van de correctieronde. Is hij dat niet, schrijf dan op dat de topologie ontbreekt en wat
er precies nodig is om hem te krijgen. Verzin geen topologie.

- [ ] **Step 3: Kies de uitkomst**

**Uitkomst A, een bewezen defect.** De keten wijst een concrete schakel aan die een zichtbare
bibliotheek laat vallen. Schrijf eerst de negatieve controle op het niveau van die schakel (een unit
test op de mapper of op `eligibleCatalogLibraries`, geen widgettest), bevestig dat hij rood is, fix
bij die schakel, en commit met de SHA in de REV1-rij. Blijkt de fix breder dan één schakel, splits
hem in eigen rijen in de correctieronde voordat je begint.

**Uitkomst B, geen defect aantoonbaar zonder de server.** De code laat een `unknown`-bibliotheek toe
en geen enkele schakel valt aan te wijzen. Zet de tweede helft van REV1 op `HARDWARE ONLY` met
precies de meting die hem kan sluiten: het tvOS-reviewpad Home, Films, Series, Mijn Pleya,
Bibliotheken, de concrete Jellyfin-bibliotheek, een item, detail en terug, op een build die Task 5's
SHA bevat. Dat pad staat al in de bevinding als acceptatiecriterium.

Wat in beide gevallen niet mag, letterlijk uit de non-goals van de bevinding: geen Apple
Review-uitzondering, geen hardgecodeerd demo-server-id, geen Home-items naar Films of Series
kopiëren, geen lege staat verbergen, niet alle Jellyfin-views blind film- en serie-eligible maken,
geen volledige catalog-preload, verborgen bibliotheken niet zichtbaar maken, en het paging-contract
niet breken.

- [ ] **Step 4: Commit**

Bij uitkomst A een gewone fix-commit met de test ervoor. Bij uitkomst B:

```bash
git add docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: REV1 tweede helft, de concrete Jellyfin-bibliotheek

De hub-typering die Films en Series leeg liet is gesloten met een eigen SHA. De
tweede helft van de melding, dat een concrete bibliotheek niet bereikbaar lijkt
via Mijn Pleya, blijft over. De keten uit de bevinding is afgelopen en wijst
geen schakel aan: de Jellyfin-mapper geeft een onbekend CollectionType de waarde
unknown, en de eligibility-filter laat unknown bewust toe.

Wat ontbreekt is de werkelijke topologie van de demo-server. De bevinding
verhuist naar HARDWARE ONLY met het reviewpad als de meting die hem sluit."
```

---

## Task 7: CAT20, het bronfilter dat een trage server kwijtraakt

Task 0 stap 7 heeft vastgesteld dat er geen commit onder Michels "opgelost"-melding zit. Deze taak
reproduceert of ontkracht, en pas daarna volgt een besluit.

**De werkhypothese.** `TvUnifiedCatalogScreen._restorePreferences`
(`lib/screens/tv/tv_unified_catalog_screen.dart:310-331`) leest de opgeslagen filters, snoeit ze met
`withKnownSources` tegen `_knownServerIds`/`_knownLibraryKeys`, en **schrijft het resultaat terug**
naar `UnifiedCatalogQueryStore`. Die twee sets komen uit
`widget.catalog.eligibleLibraries`, en dat is wat er op dat moment gebonden is. De koude start uit
log `ijqxp` laat zien dat G-Plexflix pas om 23:06:27 binnenkwam, ná de eerste opvraging. Een
opgeslagen bronkeuze die die server noemt overleeft die seconde niet, en de terugschrijving maakt het
blijvend: bij de volgende start staat hij er niet meer in.

Er is een tweede, zachtere route naar hetzelfde beeld: `_librarySelector` blijft in
`UnifiedCatalogProvider` staan (`lib/providers/unified_catalog_provider.dart:80`), en
`_reconcileEligibleLibraries` vergelijkt de sleutels ná die selector. Een laat gebonden bibliotheek
die de selector uitsluit verandert die verzameling niet, dus er komt geen herstart. Dat is correct
gedrag onder een bewust filter, en fout gedrag onder een filter dat per ongeluk is ingekort.

**Files:**
- Test: `test/screens/tv/tv_unified_catalog_screen_filter_override_test.dart` of een nieuw
  testbestand naast `test/services/unified_catalog/unified_catalog_filters_test.dart`
- Modify (bij reproductie): `lib/screens/tv/tv_unified_catalog_screen.dart:310-331` en
  `lib/screens/home/mobile_catalog_screen.dart:159`

- [ ] **Step 1: Reproduceer, headless**

De goedkoopste reproductie is niet de widget maar de pruning zelf plus de terugschrijving. Schrijf
de test die een koude start nabootst: een opgeslagen selectie met twee servers, een
`eligibleLibraries` die er maar één kent, en de vraag wat er daarna in de store staat.

```dart
  test('CAT20: a server that has not bound yet is not pruned out of the stored filter', () async {
    await UnifiedCatalogQueryStore.write(MediaKind.movie, storedWith(serverIds: {'plexflix', 'nas'}));

    // The cold start from log ijqxp: one of the two servers answered after the
    // catalog had already opened. Only 'nas' is bound at this moment.
    await pumpCatalog(tester, eligible: [library(serverId: 'nas')]);
    await tester.pumpAndSettle();

    final stored = await UnifiedCatalogQueryStore.read(MediaKind.movie);
    expect(
      stored.filters.serverIds,
      contains('plexflix'),
      reason: 'a server that is merely late is not a server that was removed',
    );
  });
```

Draai hem:

```bash
flutter test test/screens/tv/tv_unified_catalog_screen_filter_override_test.dart --plain-name "CAT20"
```

- [ ] **Step 2: Kies de uitkomst, en schrijf hem op**

**Rood.** Het defect bestaat. Ga door naar stap 3.

**Groen.** De pruning raakt de trage server niet, en CAT20 heeft een andere oorzaak dan de
correctieronde vermoedde. Herhaal de reproductie dan één niveau hoger, op
`UnifiedCatalogProvider._reconcileEligibleLibraries` met een actieve `_librarySelector`, en meet of
een laat gebonden bibliotheek de merge nog binnenkomt. Blijft ook dat groen, zet CAT20 op
`NOT REPRODUCED` met allebei de commando's en hun uitkomst erbij, en sla stap 3 over. Dat is een
geldige eindstatus in dit document en beter dan een fix voor iets wat je niet gezien hebt.

- [ ] **Step 3: De fix, bij de gedeelde eigenaar**

Het onderscheid dat ontbreekt is "deze server bestaat niet meer" tegenover "deze server heeft nog
niet geantwoord". `withKnownSources` kent dat onderscheid niet en kan het ook niet kennen: hij krijgt
alleen de gebonden bibliotheken. De aanroeper weet het wel, want de serverregistratie kent iedere
geconfigureerde server, ook een die nog aan het binden is.

```bash
grep -rn 'knownServerIds\|registeredServerIds\|allServerIds' lib/services/server_registry.dart lib/services/multi_server_manager.dart | head -20
```

De kleinste correcte ingreep is de snoei tegen de **registratie** te doen in plaats van tegen de
gebonden bibliotheken, en de terugschrijving alleen te doen wanneer de bronnenlijst compleet is. Doe
het op beide aanroepers, want `lib/screens/home/mobile_catalog_screen.dart:159` heeft woordelijk
dezelfde regel en dus hetzelfde defect. Is de mobiele variant aantoonbaar geraakt, dan krijgt die een
eigen rij in de correctieronde voordat hij als gesloten telt.

- [ ] **Step 4: Draai**

```bash
flutter test test/screens/tv/ test/services/unified_catalog/ test/providers/ 2>&1 | tail -5
flutter test test/screens/home/ 2>&1 | tail -5
flutter analyze
```

- [ ] **Step 5: Bestandsgrootte**

`lib/screens/tv/tv_unified_catalog_screen.dart` is 960 regels en dus al over de grens. Deze taak
raakt hem. Noteer in de commit welke twee verantwoordelijkheden eruit kunnen (de voorkeuren- en
filterlaag, en de focus- en railtraversal) en zet er een rij voor in de correctieronde. Splits hem
**niet** in dezelfde commit als de gedragswijziging: eerst de fix met zijn test, daarna eventueel de
extractie met een groene suite als bewijs dat er niets veranderde.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/tv/tv_unified_catalog_screen.dart lib/screens/home/mobile_catalog_screen.dart \
  test/screens/tv docs/tvos-fysieke-correctieronde.md
git commit -m "fix: een trage server verdwijnt niet uit het opgeslagen bronfilter (CAT20)

_restorePreferences snoeide de opgeslagen bronkeuze tegen de bibliotheken die op
dat moment gebonden waren, en schreef het resultaat terug. Bij een koude start
waarin een server de endpoint-race verliest betekende dat: de keuze wordt
ingekort en de inkorting is blijvend, want hij staat vanaf dan in de store. Alle
films toonde daarna één server minder, ook na een herstart.

Het onderscheid dat ontbrak is verdwenen tegenover nog niet geantwoord. De snoei
gaat nu tegen de serverregistratie, die ook een nog bindende server kent, en de
terugschrijving wacht tot de bronnenlijst compleet is. mobile_catalog_screen
droeg dezelfde regel en is meegefixt."
```

---

## Task 8: AGG1, het bewijs dat twee bronnen één item worden

De spec is hier expliciet over de omvang: "AGG1 vraagt geen nieuwe merge-architectuur, alleen het
bewijs dat een echte Plex- plus Jellyfin-titel met een sterke externe ID één unified item wordt, de
juiste bronbadge toont en correct activeert."

De live ronde van 14 september kwam tot hier: Plex en de Jellyfin-demo draaien samen, de landing
laadt uit beide backends door elkaar, en geen enkele geopende titel toonde een badge, omdat de
gedeelde open Blender-films geen TMDB- of TVDB-id dragen. Het mergepad zelf is via code-tracing
bevestigd. Wat ontbreekt is een test die het vastlegt in plaats van een sessie die het niet kon
aantonen.

**Files:**
- Test: `test/services/unified_grouping_service_test.dart` (bestaand)
- Test: `test/widgets/tv/` (het testbestand van `TvUnifiedMediaCard`, zoek het in stap 1)

**Interfaces:**
- Consumes: `groupUnifiedMediaSources` (`lib/services/unified_catalog/grouping_service.dart`),
  bestaand, en `_neverMergedBackends = {MediaBackend.local, MediaBackend.pleyaServer}` op regel 30.
- Consumes: `UnifiedMediaGroup.sources`, waarop `TvUnifiedMediaCard` zijn badge zet
  (`sources.length > 1`, hoofdstuk 10.3).
- Produces: niets in `lib/`. Deze taak schrijft alleen tests en documentatie.

- [ ] **Step 1: Kijk wat er al gedekt is**

```bash
grep -n 'jellyfin' test/services/unified_grouping_service_test.dart | head -20
ls test/widgets/tv/ | grep -i 'unified_media_card\|catalog_card'
grep -rn 'sources.length' test/widgets/tv/ | head
```

Bestaat de cross-backend-mergetest al met een sterke externe id, dan is de helft van AGG1 gedekt en
staat er alleen nog een badge-test open. Schrijf op wat er al is voordat je iets toevoegt: een
tweede test die hetzelfde bewijst is geen bewijs.

- [ ] **Step 2: De mergetest**

```dart
  test('AGG1: a Plex and a Jellyfin title with the same TMDB id become one group', () {
    final groups = groupUnifiedMediaSources([
      candidate(backend: MediaBackend.plex, serverId: 'plexflix', tmdb: '27205', title: 'Inception'),
      candidate(backend: MediaBackend.jellyfin, serverId: 'demo', tmdb: '27205', title: 'Inception'),
    ]);

    expect(groups, hasLength(1));
    // Two memberships, which is what puts the badge on the card: hoofdstuk 10.3
    // draws it on sources.length > 1 and nowhere else.
    expect(groups.single.sources, hasLength(2));
  });

  test('AGG1: Pleya Server stays its own group even on a shared id', () {
    final groups = groupUnifiedMediaSources([
      candidate(backend: MediaBackend.plex, serverId: 'plexflix', tmdb: '27205', title: 'Inception'),
      candidate(backend: MediaBackend.pleyaServer, serverId: 'pleya', tmdb: '27205', title: 'Inception'),
    ]);

    // DEC-063 and _neverMergedBackends: until PS-7 gives Pleya Server external
    // ids, its identity data is not proven equivalent. This is the boundary the
    // live round ran into, and it is deliberate, not a gap.
    expect(groups, hasLength(2));
  });
```

- [ ] **Step 3: De badgetest**

```dart
  testWidgets('AGG1: a two-source group draws the multi-source badge', (tester) async {
    await pumpCard(tester, group: groupWithSources(2));

    expect(find.byKey(tvUnifiedMediaCardSourceBadgeKey), findsOneWidget);
  });

  testWidgets('AGG1: a one-source group draws none', (tester) async {
    await pumpCard(tester, group: groupWithSources(1));

    // "1 bron" is not a fact worth a capsule (hoofdstuk 10.3).
    expect(find.byKey(tvUnifiedMediaCardSourceBadgeKey), findsNothing);
  });
```

Bestaat er nog geen sleutel op de badge, voeg die dan in dezelfde stap toe aan de widget die hem
tekent. Verzin geen tekstmatcher op een badge-label: dat breekt op de eerste vertaling.

- [ ] **Step 4: Draai**

```bash
flutter test test/services/unified_grouping_service_test.dart --plain-name "AGG1"
flutter test test/widgets/tv/ --plain-name "AGG1"
flutter analyze
```

- [ ] **Step 5: Werk de AGG1-rij bij**

De rij is lang en draagt al de volledige live-ronde. Zet er de uitkomst onder: het mergepad en de
badge liggen nu in tests vast, de badge-bevestiging met een levende titel die een gedeelde externe id
draagt blijft over, en dat is een hardwarepunt en geen codegat. Status
`CODE CLOSED · VERIFY/SIM OPEN`, met de opmerking dat een levende bevestiging een bibliotheek vraagt
met een titel die wél een TMDB- of TVDB-id heeft, wat de open Blender-content niet levert.

Herhaal daarbij de productnotitie van 14 september onaangeraakt: Pleya Server en Pleya Share horen op
termijn wel mee te doen in het unified-mergeconcept, en de weg terug is PS-7. Dat is een
roadmap-aantekening, geen open werk in TV2.

- [ ] **Step 6: Commit**

```bash
git add test/services/unified_grouping_service_test.dart test/widgets/tv lib/widgets/tv/tv_unified_media_card.dart \
  docs/tvos-fysieke-correctieronde.md
git commit -m "test: het cross-backend mergepad en de bronbadge liggen vast (AGG1)

De live ronde van 14 september kon de badge niet bevestigen: de gedeelde open
films tussen de Plex- en de Jellyfin-bibliotheek dragen geen TMDB- of TVDB-id,
dus geen enkele titel kon er twee bronnen onder krijgen. Het mergepad zelf was
alleen via code-tracing bevestigd.

Vier tests leggen het nu vast: een Plex- en een Jellyfin-bron met dezelfde TMDB
worden één groep met twee bronnen, Pleya Server blijft ook op een gedeelde id
zijn eigen groep (DEC-063, tot PS-7), en de kaart tekent de badge op twee
bronnen en niet op één. Geen wijziging aan de merge zelf."
```

---

## Task 9: WL2, de grens van de kijklijstverificatie vastleggen

De spec zegt wat deze taak wel en niet is: "WL2 is een verificatie-infrastructuurgat, geen
featuregat. Onderzoek eerst of er een testnaad rond `WatchlistSourceFactory` mogelijk is. Kan dat
niet, dan wordt vastgelegd dat deze dekking op een echte Jellyfin-aanmelding hoort. **Er wordt geen
favorietenbron gebouwd.**"

Task 0 stap 9 heeft de twee feiten al opgehaald die het antwoord bepalen. Deze taak schrijft ze op
en sluit de rij.

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (de WL2-rij)
- Modify: `docs/tvos-redesign-register.md` (de MOC-14-rij, de bewijskolom)
- Modify: `docs/unified-2026-closure.md` (rij 7, T3a, alleen de WL2-zin)

- [ ] **Step 1: Beantwoord de vraag die de spec stelt**

```bash
sed -n '20,45p' lib/services/watchlist/watchlist_source_factory.dart
head -30 test/services/watchlist_source_factory_test.dart
```

De naad bestaat al: `plexClientBuilder` en `clientsById` zijn allebei injecteerbaar,
`test/services/watchlist_source_factory_test.dart` gebruikt ze met een `MockClient` en een
`FakeFavoritesClient`, en de unit-dekking op de bronopbouw is daarmee aanwezig. **Het gat zit niet op
unit-niveau.**

- [ ] **Step 2: Bepaal waarom het transport het wel is**

```bash
grep -c 'watchlist\|favorite\|Favorite' docs/pleya-protocol/v1/openapi.yaml || echo 0
sed -n '/Het protocol ligt vast/,+6p' CLAUDE.md
```

Het `/v1`-protocol dat de fixture-server spreekt kent geen watchlist en geen favorieten, en het
protocol is bevroren zolang PS-5 loopt. Een fixture die een kijklijst kan dragen vraagt dus een
protocolwijziging, en die wordt eerst langs de zes compatibiliteitsregels uit hoofdstuk 3 van de
specificatie getoetst. Dat is per definitie geen TV2-werk, en het is ook niet wat de spec hier wil.

Het REQ1-precedent bevestigt dat langs de andere kant: Seerr kon wél een eigen fake server krijgen
(`SeerrFakeServer`, apiKey-only op dezelfde fixture-poort), precies omdat Seerr tegen zijn eigen
geconfigureerde URL praat en niets met het mediaserverprotocol te maken heeft. Jellyfin-favorieten
lopen wel over een mediaserververbinding, dus die route bestaat hier niet zonder een tweede
volledige backend-fake te bouwen.

- [ ] **Step 3: Leg de uitkomst vast**

WL2 gaat naar `ACCEPTANCE GAP`, met de reden en met de meting die hem alsnog sluit. Schrijf in de rij:

- de naad rond `WatchlistSourceFactory` bestaat en is gedekt, dus het onderzoek dat de spec vroeg is
  gedaan en het antwoord is dat het gat daar niet zit;
- `/v1` kent geen watchlist of favorieten en is bevroren tijdens PS-5, dus een fixture die er een kan
  dragen is een protocolwijziging;
- een tweede volledige Jellyfin-fake is niet in verhouding tot wat het zou bewijzen, en het
  REQ1-precedent geldt hier niet, want Seerr praat buiten het mediaserverprotocol om;
- de dekking hoort daarmee op een echte Jellyfin-aanmelding, en dat is de meting die WL2 sluit;
- de automation-ids zijn er al (`tv.catalog.grid[watchlist]` en de vier andere), dus zodra er een
  echte aanmelding is, is er geen bouwwerk meer nodig.

Werk dezelfde uitkomst bij in de MOC-14-bewijskolom van `docs/tvos-redesign-register.md` en in rij 7
(T3a) van `docs/unified-2026-closure.md`, die allebei nu nog naar de open WL2-rij verwijzen.

- [ ] **Step 4: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md docs/tvos-redesign-register.md docs/unified-2026-closure.md
SKIP_HOOKS=1 git commit -m "docs: WL2 krijgt zijn grens, geen favorietenbron gebouwd

De spec vroeg eerst te onderzoeken of er een testnaad rond WatchlistSourceFactory
mogelijk is. Die bestaat al: plexClientBuilder en clientsById zijn injecteerbaar
en watchlist_source_factory_test.dart gebruikt ze met een fake favorietenclient.
Het gat zit dus niet op unit-niveau.

Het zit op het transport. De fixture-server spreekt /v1, en dat protocol kent
geen watchlist en geen favorieten en is bevroren zolang PS-5 loopt: een fixture
die er een kan dragen is een protocolwijziging. Het REQ1-precedent helpt niet,
want Seerr praat tegen zijn eigen URL, buiten het mediaserverprotocol om.

WL2 gaat naar ACCEPTANCE GAP met de echte Jellyfin-aanmelding als de meting die
hem sluit. De automation-ids staan er al, dus er is dan niets meer te bouwen."
```

---

## Task 10: TV2 exit

- [ ] **Step 1: De volledige relevante suite**

```bash
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -8
flutter test test/screens/watchlist_screen_test.dart 2>&1 | tail -5
flutter test test/providers/ test/services/ 2>&1 | tail -8
flutter analyze
scripts/ci_checks.sh
```

Verwacht: geen enkele test die rood is en in Task 0 stap 2 groen was, en `flutter analyze` zonder
waarschuwingen. Een test die in Task 0 al rood was en dat nog is, noteer je met naam in de
exit-notitie; die hoort niet bij TV2.

- [ ] **Step 2: Codegen-verschil**

```bash
scripts/codegen.sh
git status --porcelain
```

Verwacht: leeg. Dit plan raakt geen `@freezed`-model en geen `lib/i18n/*.i18n.json`. Is er toch een
gegenereerde diff, dan is er iets onbedoelds meegekomen en hoort dat uitgezocht te worden voordat
TV2 sluit.

- [ ] **Step 3: Goldens**

```bash
flutter test test/goldens/ 2>&1 | tail -10
```

Vergelijk het aantal en de namen met de bekende stale set. TV2 mag geen enkele nieuwe golden stale
achterlaten zonder dat er een `goldens.yml`-run onder staat. Is er een nieuwe stale golden, noteer
welke, met de reden en de runner-URL zodra hij gedraaid heeft. De eindgate van
`docs/unified-2026-closure.md` verbiedt "geen enkele bewust stale" golden, en dat is de gate waar
dit naartoe werkt.

- [ ] **Step 4: Werk de registers bij**

In een **aparte commit**, nooit met een amend: een amend verandert de hash die je er net in zette.

In `docs/tvos-fysieke-correctieronde.md`:

| Rij | Nieuwe status |
|---|---|
| SEARCH2 | `FIXED` met de SHA uit Task 1, hardware open |
| SEARCH2b (nieuw) | `CODE CLOSED · VERIFY/SIM OPEN` met dezelfde SHA |
| LAND6 | `FIXED` met de SHA uit Task 2, hardware open |
| LAND7 | `FIXED` met de SHA uit Task 3, of `NOT REPRODUCED` met het commando eronder als Task 3 stap 3 groen was |
| WL3 | `FIXED` met de SHA uit Task 4 |
| REV1 | `FIXED` voor de landinghelft met de SHA uit Task 5, plus de uitkomst van Task 6 voor de bibliotheekhelft |
| AGG1 | `CODE CLOSED · VERIFY/SIM OPEN`, badge-bevestiging op hardware open |
| CAT20 | `FIXED` met de SHA uit Task 7, of `NOT REPRODUCED` met de twee reproductiecommando's |
| WL2 | `ACCEPTANCE GAP`, al gezet in Task 9 |

In `docs/tvos-redesign-register.md`:

| Rij | Wat erbij komt |
|---|---|
| MOC-13 (Zoeken) | SEARCH2's SHA in de bewijskolom |
| MOC-14 (Kijklijst) | WL3's SHA, en WL2's ACCEPTANCE GAP uit Task 9 |
| SYS-7 | de Verify-journeys die TV2 niet zelf levert, doorverwezen naar TV8 |

Zit er voor een gesloten bevinding geen register-rij (de landings en Zoeken-scroll hebben er geen
eigen), noteer dat dan in de exit-notitie in plaats van een rij te verzinnen.

- [ ] **Step 5: Exit-criteria**

Alle acht waar, elk met een commando of een SHA eronder:

1. **SEARCH2** is gesloten met een negatieve controle die aantoonbaar rood was op de commit ervoor,
   en `grep -n 'clipBehavior: Clip.none' lib/screens/tv/tv_search_view.dart` is leeg.
2. **LAND6** is gesloten, de lege landing draagt de catalogusactie, en een widgettest bewijst dat de
   afstandsbediening op die actie landt in plaats van op de modal scope.
3. **LAND7** is gesloten met één anker dat op de landings dezelfde kopositie geeft ongeacht welke
   rail de focus heeft, of staat op `NOT REPRODUCED` met de groene test eronder. LAND2, LAND3, LAND4
   en LAND5 zijn niet heropend: hun tests zijn groen.
4. **WL3** is gesloten, `test/screens/watchlist_screen_test.dart` is in zijn geheel groen, en de
   falende tak uit Task 4 stap 1 staat met naam in de commit.
5. **REV1** is voor de landinghelft gesloten met een test die aantoont dat een Jellyfin-hub van
   films `movie` teruggeeft, en `grep -n "type: 'mixed'" lib/services/jellyfin_client/parts/browse.dart`
   levert geen onvoorwaardelijke treffer meer op. De bibliotheekhelft heeft een eindstatus.
6. **AGG1** heeft een test die twee bronnen met dezelfde TMDB-id tot één groep met twee bronnen
   maakt, en een test die de badge op twee bronnen tekent en op één niet. De merge zelf is
   ongewijzigd.
7. **CAT20** is gereproduceerd en gefixt, of staat op `NOT REPRODUCED` met de twee commando's en hun
   uitkomst in de rij. Er staat geen `FIXED` zonder SHA meer.
8. **WL2** staat op `ACCEPTANCE GAP` met de reden en de meting die hem sluit, en er is geen
   favorietenbron gebouwd.

Plus de twee die over het plan zelf gaan: `flutter analyze` is schoon, en elke bevinding die onderweg
is opgedoken heeft een eigen rij in de correctieronde voordat hij als gesloten telt.

- [ ] **Step 6: De Verify-journeys horen hier niet**

SEARCH2, LAND6, LAND7 en WL3 zijn alle vier focus- of layoutgedrag op een oppervlak dat al gebouwd
was, en de agentregel uit `CLAUDE.md` vraagt daar passende Pleya Verify-assertions bij. Die horen bij
TV8, om dezelfde reden als FOC1 en SYS-1d in TV1: het is een historisch gat in een bestaand oppervlak,
niet een oppervlak dat TV2 zelf bouwt. Zet de vier in de spec-mapping onder TV8 als ze er nog niet
staan, met de SHA's uit Task 1 tot en met Task 4 erbij, zodat TV8 weet welke commit elk scenario moet
dekken.

WL2 is de uitzondering en gaat níet naar TV8: Task 9 heeft vastgelegd dat die dekking op een echte
Jellyfin-aanmelding hoort, en een scenario dat nooit kan slagen is precies de fout die
`tvos.library.sort` een ronde eerder maakte.

- [ ] **Step 7: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md docs/tvos-redesign-register.md
SKIP_HOOKS=1 git commit -m "docs: TV2-registers bijgewerkt met de SHA's van deze ronde

Per bevinding de eindstatus en de commit die hem draagt. Wat geen eindstatus
kreeg staat er met de meting die hem alsnog sluit, niet met een belofte."
```

---

## Wat dit plan bewust niet doet

| Niet hier | Waar wel |
|---|---|
| CAT8 | de paragraaf-7-groep. De rij is `DEELS GEDEKT door CAT10` en heeft geen codewerk meer, alleen een hardwareronde |
| DET4, CTX1 tot en met CTX3 | TV3 |
| MOC-17 en LIVE1 | TV4 |
| Verify-journeys voor SEARCH2, LAND6, LAND7 en WL3 | TV8 |
| Een favorietenbron voor de kijklijstfixture | nergens. Dat vraagt een protocolwijziging tijdens een bevroren venster |
| De landing heringericht bij een lege projectie | nergens. Het besluit is de minimale ingreep, optie (a) |
| Pleya Server in het unified-mergeconcept | PS-7, buiten de correctieronde |
| `tv_unified_catalog_screen.dart` splitsen | een eigen commit na Task 7, met de suite als bewijs |
| Goldens lokaal regenereren | nergens. De route is `goldens.yml` op Linux |

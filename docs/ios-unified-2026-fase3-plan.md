# Pleya iOS Unified 2026 fase 3: Alle films, Alle series en de filtersheet

**Status:** voorstel, meteen gevolgd door bouw in dezelfde sessie (geen aparte goedkeuringsronde
beschikbaar in deze uitvoering). Geen productiecode gewijzigd vóór dit document.
**Datum:** 6 september 2026
**Branch:** `claude/ios-fase3-catalogus`, afgetakt van `claude/ios-fase2-review-fixes` op `86d91bcc`.
**Authority:** DEC-090 (bevroren northstar), DEC-102, DEC-103, DEC-104, de beelden
`03-alle-films.png` en `04-filters-sheet.png` in `docs/assets/ios-unified/northstar/`, paragraaf 5,
6 en 10 van [docs/ios-unified-2026-audit.md](ios-unified-2026-audit.md), en sectie E van
[docs/ios-unified-2026-fase1-plan.md](ios-unified-2026-fase1-plan.md).

Fase 2 heeft Series en Films tot bestemming gemaakt, met een "Alle series ›"/"Alle films ›"-actie
die getekend en inert op de landing staat. Fase 3 zet daar de complete, bronoverstijgende catalogus
onder plus de filtersheet die erbij hoort. Het is geen nieuwe visuele ronde op wat al staat: de
header, de rail en de kaart uit fase 1 en 2 blijven ongewijzigd.

## A. Preflight

| Controle | Uitkomst |
|---|---|
| Branch, HEAD | `claude/ios-fase3-catalogus`, afgetakt van `86d91bcc` |
| Working tree | schoon vóór dit document |
| Fase 2 | gesloten, DEC-104 op `accepted` |
| Northstar-freeze | intact |
| Flutter-SDK | 3.44.0 zelf geïnstalleerd in deze sessie (git-clone van de pinned tag, geen Mac
  beschikbaar in deze uitvoeringsomgeving, wel Linux met netwerktoegang) |
| `flutter analyze` op `86d91bcc` | 0 errors, 0 warnings, 40 bekende info-lints, exact de lijst uit de
  opdracht |
| `flutter test` op `86d91bcc` | loopt op het moment van schrijven, resultaat volgt in het
  eindrapport |
| `scripts/ci_checks.sh` | verwacht rood op de 17 F0-meldingen (10 unused-code, 7 unused-files) uit
  DEC-104, ongewijzigd sinds fase 2 |
| `pleya_verify` (ios-sim, macOS, tvOS-sim) | **niet uitvoerbaar in deze sessie**: geen Xcode, geen
  simulator, geen macOS. Dit is geen kortere inspanning die ik oversla, het is een omgeving zonder
  Apple-toolchain. Zie sectie H. |
| `scripts/format_native.sh --check` | niet uitvoerbaar, geen `swift-format` en geen native
  bestanden geraakt door fase 3 |

De agentomgeving voor deze sessie is een Linux-container zonder Mac, Xcode of simulators, ondanks
dat de opdracht "op deze Mac kan alles" aanneemt. Ik heb de Flutter-SDK zelf gehaald zodat
`flutter analyze` en `flutter test` wel echt draaien; de drie Apple-platformstukken
(`ios.home.northstar`, `ios.landing.northstar`, `discover.hero.layout`, `ios.catalog.northstar`,
`scripts/format_native.sh --check`) blijven net als bij het sluiten van fase 2 ontbrekend bewijs, nu
uit omgevingsbeperking in plaats van uit tijdgebrek. Dat meld ik expliciet in het eindrapport in
plaats van te doen alsof het gedraaid is.

## B. Wat fase 2 heeft achtergelaten dat fase 3 gebruikt

| Onderdeel | Bestand | Wat fase 3 ermee doet |
|---|---|---|
| `UnifiedCatalogs` | `lib/providers/unified_catalogs.dart` | registreren als `Provider<UnifiedCatalogs>` in `profile_session_screen.dart`, met een expliciete `dispose:` |
| `UnifiedCatalogProvider` | `lib/providers/unified_catalog_provider.dart` | `ensureStarted`, `loadMore`, `refresh`, `setQuery`, `snapshot`, `isInitialLoading`, `loadFailed`, `eligibleLibraries`, `participatingLibraries` dragen het hele scherm |
| Filtermodel | `lib/services/unified_catalog/unified_catalog_filters.dart` | `UnifiedCatalogPreferences`, `UnifiedCatalogFilterSelection`, `UnifiedCatalogSort`, `unifiedFilterCapabilitiesFor`, `buildUnifiedCatalogQuery` |
| Filterkeuzes | `lib/services/unified_catalog/unified_filter_options.dart` | `loadUnifiedFilterOptions` voor de genre- en jaarlijsten in de sheet |
| Onthouden | `lib/services/unified_catalog/unified_catalog_query_store.dart` | `read`/`write` per opening/wijziging, `clearForProfileScope` in de profiel-delete-flow |
| Artwork vooruit | `lib/services/unified_catalog/unified_artwork_prefetcher.dart` | `prefetchAround` gekoppeld aan de scrollpositie van het grid |
| `MobileMediaCard` | `lib/widgets/mobile/mobile_media_card.dart` | ongewijzigd hergebruikt in het grid, portret-vorm |
| `MediaCardGridLayout` | `lib/widgets/media_card_grid_layout.dart` | titel-/onderschriftstijl en `textExtentFor` voor de kaarthoogte |
| `MobileRefreshScope` | `lib/widgets/mobile/mobile_refresh_scope.dart` | pull-to-refresh op het grid |
| `FocusableFilterChip` | `lib/widgets/focusable_filter_chip.dart` | de drie header-chips, `outlined`-variant |
| `BottomSheetHeader`, `FocusableListTile` | `lib/widgets/bottom_sheet_header.dart`, `lib/widgets/focusable_list_tile.dart` | koptekst en optierijen in beide sheets |
| `WatchlistSortSheet` | `lib/widgets/watchlist_sort_sheet.dart` | visueel model voor de nieuwe sorteersheet: `OverlaySheetController.showAdaptive`, één lijst, radiobutton-iconen |
| `_TitleRow` in `mobile_landing_screen.dart` | `lib/screens/home/mobile_landing_screen.dart:165-204` | de inerte "Alle series/films ›"-actie krijgt hier zijn handler |

De TV-tegenhanger op `origin/main`, `lib/screens/tv/tv_unified_catalog_screen.dart` (868 regels) en
`lib/widgets/tv/tv_catalog_filter_panel.dart` (857 regels), bestaat **niet** op deze branch: F0 heeft
de platformneutrale kern gemerged, niet de TV-presentatie. Ik heb beide bestanden gelezen via
`git show origin/main:...` als vormmodel: dezelfde `UnifiedCatalogProvider`-levenscyclus, hetzelfde
draft-tot-Toepassen-patroon in de filtersheet, dezelfde vier inhoudstoestanden (skeleton, leeg,
foutmelding, gevuld). Er is niets van over te nemen als code: de tv-widgets bestaan niet op deze
branch en de d-pad-focuslogica erin is niet van toepassing op touch.

## C. Kernbesluiten

**C1. Eén scherm, twee kinds, net als de landing.** `MobileCatalogScreen(kind: MediaKind)` leest
`context.read<UnifiedCatalogs>().forKind(kind)` en bouwt titel, chip-labels en automation-ids uit een
klein `MobileCatalogKind`-enum, exact het patroon dat `MobileLandingKind` al zet. Geen bronlogica in
het scherm zelf: activatie gaat via dezelfde route als de rail-kaarten (`navigateToMediaItemDetails`
op de representatieve bron), niet via een tweede bronkiezer. Fase 5 (bronwissel via S8) raakt dit
scherm niet.

**C2. Het scherm is een push, geen tabtoestand.** De vier beelden waarin de bindende mockups de
onderbalk tonen (03, 04, en ook 06-film-detail) zijn geverifieerd: `06-film-detail.png` toont Films
nog steeds gemarkeerd terwijl `media_detail_screen.dart` vandaag al een volledige `Navigator.push`
is zonder onderbalk. De onderbalk in de mockups is dus generieke apparaatchrome voor de reviewer, geen
functionele eis dat een gepushte pagina de balk laat doorschijnen. "Alle films"/"Alle series" is
daarmee een gewone `Navigator.push(context, MaterialPageRoute(...))` vanuit `_TitleRow`, net als een
detailpagina, en dekt zich zo ook onder `ProfileNavigationScope` zonder iets nieuws.

**C3. `open:` blijft ongemoeid, het scenario gebruikt `tap`.** `_screenToTab` in
`automation_signin.dart` bestaat voor bestemmingen die een tabwissel zijn; deze twee schermen zijn
dat niet, ze zijn een push zoals een detailpagina. Ze aan `_screenToTab` toevoegen zou een gepushte
pagina voorstellen als een tab, wat de volgende agent op het verkeerde been zet. Het scenario bereikt
het scherm daarom met `tap` op `landing.view_all[series]`/`[movies]`, die al bestaan en al bewezen
`insideViewport` zijn (`ios.landing.northstar`).

`tap` in de huidige Verify-engine accepteert alleen letterlijke `{x, y}`-coördinaten
(`run_scenario.dart`, `case 'tap'`), geen automation-id. Coördinaten met de hand uitrekenen en
vastzetten in een YAML-bestand is precies de brosheid die `ios.landing.northstar`'s eigen commentaar
afwijst voor `open`. Daarom krijgt `tap` in dit fase-3-werk een klein, generiek staartje: `tap: {id:
"..."}` naast `tap: {x, y}`, dat het middelpunt van de node opzoekt via dezelfde `GET /v1/ui_tree` en
dezelfde rect-parser die `assert`'s geometriepredikaten al gebruiken (`geometry_assertions.dart`'s
`_rectFor`, hernoemd naar een publieke `rectForNode` zodat `run_scenario.dart` hem kan hergebruiken).
Geen nieuwe automation-capaciteit in de app, geen tweede rect-parser: één bestaande lookup op een
tweede plek toegepast, met een eigen test in `pleya_verify/runner/test/run_scenario_test.dart`.

**C4. Eén nieuwe i18n-sleutel, na controle van de bestaande set.** `unifiedCatalog.filters.*`,
`.sort.*`, `.states.*`, `titlesLoaded`, `allSources`, `oneSource`, `sources` bestaan al en dekken
vrijwel alles. Mockup 04 toont een "N actief"-regel naast de sheettitel die nergens in de bestaande
set een tegenhanger heeft (de TV-sheet, gelezen via `origin/main`, toont die regel niet: het is een
mobiel-only detail). Nieuwe sleutel: `unifiedCatalog.filters.activeCount` = `"${count} active"`,
zelfde vorm als het bestaande `sources`. Geen andere sleutel toegevoegd.

**C5. De headerchip met badge is een lokale wrapper, geen wijziging aan `FocusableFilterChip`.**
`FocusableFilterChip` heeft geen badge-parameter en wordt op te veel plekken in de app hergebruikt om
er zomaar een aan toe te voegen voor één scherm. Het getal op de Filters-chip (mockup 03: een witte
cirkel met "2") wordt een kleine, schermlokale `_CatalogHeaderChip`-widget die `FocusableFilterChip`
inpakt in een `Stack` met een `Positioned`-badge. Dat is dezelfde aanpak als `discoverHeroPlay` en
andere eenmalige composities in deze codebase: een gedeeld primitief blijft gedeeld, de opsmuk is
lokaal.

**C6. De filtersheet is nieuw, geen uitbreiding van `FiltersBottomSheet`.** DEC-104 en paragraaf 6/8
van het auditrapport zijn hier eenduidig: `FiltersBottomSheet`
(`lib/screens/libraries/filters_bottom_sheet.dart`) is Plex-gebonden (`MediaFilter`, `PlexClient`,
serverId/libraryKey als verplichte parameters) en blijft waar hij is, onder Bibliotheken. De nieuwe
sheet, `MobileCatalogFiltersSheet`, werkt op `UnifiedCatalogFilterSelection` en `UnifiedFilterOptions`
en kent geen backend. De TV-tegenhanger (`tv_catalog_filter_panel.dart`, gelezen via `origin/main`)
is het vormmodel voor drie dingen die overnemen de moeite waard is:

- **Twee zones, niet vijf gestapelde secties.** Links een rail van categorieën (Status, Genre, Jaar,
  Servers, Bibliotheken, elk alleen aanwezig als de deelnemende backends hem kunnen uitvoeren),
  rechts de opties van de actieve categorie. Op een telefoonbreedte van 393pt is een gestapelde lijst
  van vijf secties met kop nog onhandiger dan op een 10-voet tv-scherm: precies de reden die de
  TV-doc-comment voor zijn eigen omslag geeft.
- **Niets wordt toegepast tot Toepassen.** Een `_draft`-kopie van de selectie, pas bij Toepassen naar
  `UnifiedCatalogProvider.setQuery` geschreven. Op mobiel is de reden net zo geldig als op afstandsbediening:
  een grid dat na elke aanraking herlaadt en scrollpositie verliest is vervelend op touch en
  onbruikbaar met een remote.
- **Twee voetacties, niet drie.** "Wissen" (tekst, alleen zichtbaar als er iets te wissen valt) en
  "Toepassen" (gevulde capsule), exact zoals mockup 04 het tekent en exact zoals de TV-sheet het na
  zijn eigen ronde deed.

Focus-styling (witte ring, schaal, glow) komt niet mee: paragraaf 8 van het auditrapport sluit dat
uitdrukkelijk uit voor touch. Selectie op mobiel is een vinkje plus een lichte achtergrondtint, met
`Pressable`/`FocusableListTile`'s eigen tikstaat, geen d-pad-traversal.

**C7. De sorteersheet is nieuw en klein, gemodelleerd naar `WatchlistSortSheet`.** Zeven
`UnifiedCatalogSort`-waarden, één lijst, radiobutton-iconen, `OverlaySheetController.showAdaptive`.
Geen tweede paneel: de TV-sort-panel bestaat op deze branch niet en de mobiele vorm is eenvoudig
genoeg om niet naar de tv-vorm te hoeven kijken.

**C8. Het grid is een eigen `SliverGrid`, geen hergebruik van `MediaGridGeometry`.**
`library_browse_tab.dart`'s grid-geometrie is gebouwd voor het brede desktop/tablet-bereik van
`MediaCard` (dichtheid, brede aspect-ratio-optie, alpha-jumpbar-reservering) en werkt op `MediaItem`,
niet op `UnifiedMediaGroup`. Fase 3 is mobiel-only en drie kolommen zijn bevroren door mockup 03, dus
een vaste `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3)` met `MobileMediaCard` erin
is de kleinere en juistere keuze. `mobileRailInset`/`mobileRailGutter` uit `mobile_media_rail.dart`
worden hergebruikt voor de buitenrand en de tussenruimte, zodat het grid dezelfde 16pt/12pt-maatvoering
draagt als de rails erboven.

**C9. `UnifiedCatalogQueryStore.clearForProfileScope` krijgt zijn ene aanroeper.** In
`profile_delete_flow.dart`'s `deleteProfile`, met `storage.userScopeForProfileId(profile.id)` als
scope (niet `activeUserScope()`: de te verwijderen profiel hoeft niet het actieve profiel te zijn).
`PreferredServerStore.clearForProfileScope` en `SourcePreferenceStore.clearForProfileScope` blijven
zelf ook ongeroepen buiten hun eigen tests; dat is een bevinding voor het eindrapport, geen fase-3-fix
die ik er stilzwijgend bij pak.

## D. Scope

- `MobileCatalogScreen` voor Films en Series (mockup 03), gepusht vanaf de "Alle films/series
  ›"-actie op de landing.
- `MobileCatalogFiltersSheet` (mockup 04): twee zones, draft-tot-Toepassen, capability-gefilterde
  categorieën.
- `MobileCatalogSortSheet`: de zeven bestaande sorts.
- Automation-ids voor het scherm, de drie header-chips, de telling, het grid en zijn cellen, en beide
  sheets, in `instanceableIds` en `catalog()` waar van toepassing, plus `pleya_verify/automation_ids.yaml`
  met de hand bijgewerkt (zie valkuil 2 van de opdracht).
- `Provider<UnifiedCatalogs>`-registratie in `profile_session_screen.dart`.
- `UnifiedCatalogQueryStore.clearForProfileScope`-aanroep in de profiel-delete-flow.
- `UnifiedArtworkPrefetcher` gekoppeld aan de scrollpositie van het grid.
- Eén nieuwe i18n-sleutel (`unifiedCatalog.filters.activeCount`).
- `tap: {id: "..."}` in de Verify-engine, met eigen test.
- Nieuw scenario `ios.catalog.northstar`, geschreven maar in deze sessie niet uitvoerbaar (sectie H).
- Widgettests op de iPhone 15 Pro-viewport voor scherm, grid, beide sheets en de gekoppelde handler
  op de landing.
- CHANGELOG- en DEC-entry voor de kernbesluiten hierboven.

## E. Expliciete non-scope

- `LibraryBrowseTab` en `FiltersBottomSheet` blijven ongewijzigd en blijven de route onder
  Bibliotheken (sectie E fase-1-plan, DEC-104).
- Geen bronwissel, geen contextmenu, geen detailpagina-wijziging: dat is fase 5.
- Geen wijziging aan `MobilePageHeader`, `MobileMediaRail`, `MobileMediaCard`, `home_hero_layout.dart`
  of de tabbalk: fase 1 en 2 blijven zoals ze zijn.
- Geen opruiming van de overige 15 F0-unused-meldingen die niet door dit werk vanzelf verdwijnen (zie
  sectie F, laatste stap, voor de acht die wel verdwijnen).
- `PreferredServerStore`/`SourcePreferenceStore`'s eigen ontbrekende aanroepers: gerapporteerd, niet
  opgelost.
- Geen wijziging aan `handleAutomationOpen`/`_screenToTab`: zie C3.
- Geen transcoderen, geen gebruikersbeheer, geen Pleya-Server-scope: buiten `docs/pleya-server-*`
  sowieso, en fase 3 hier is een ander traject (iOS Unified 2026, niet PS-5).

## F. Stappen

Elke stap is één commit die compileert. Volgorde is opzettelijk: het scherm bestaat voordat de sheets
er content aan geven, de sheets bestaan voordat de landing-handler ernaartoe wijst, de opruiming komt
als laatste omdat hij pas klopt zodra alles ervoor gebruikt wordt.

1. **Automation-ids en de ene nieuwe i18n-sleutel.** `automation_ids.dart` (nieuwe consts,
   `instanceableIds`, `catalog()`), `pleya_verify/automation_ids.yaml` met de hand bijgewerkt,
   `test/architecture/automation_ids_yaml_test.dart` blijft groen. `en.i18n.json` plus `dart run
   slang`. Geen scherm gebouwd, dus geen widgettest hier; wel een aanpassing van
   `automation_ids_test.dart`'s eigen verwachtingen als die een vaste lijst bijhoudt.
2. **`MobileCatalogScreen` op een lege/skeleton/foutmelding-toestand.** Header (terug, titel, zoek),
   drie chips zonder werkende sheets erachter (`onPressed` is een no-op tot stap 3/4), de
   telling-regel, het grid op `UnifiedCatalogProvider.snapshot`. Widgettest: skeleton bij
   `isInitialLoading`, foutmelding bij `loadFailed`, leeg-bij-geen-filters versus
   leeg-bij-filters-actief (dezelfde twee lege staten als de TV-tegenhanger, hoofdstuk 29).
3. **`MobileCatalogSortSheet` en de sorteerchip.** `showMobileCatalogSortSheet`,
   `UnifiedCatalogQueryStore.write` bij een keuze, grid-scroll terug naar boven. Widgettest: de
   huidige sort krijgt het vinkje, een andere keuze update de chipwaarde en herstart de query.
4. **`MobileCatalogFiltersSheet` en de filters-/bronnenchip.** Twee zones, capability-gefilterde
   rail, draft-tot-Toepassen, Wissen alleen zichtbaar bij een niet-lege selectie, badge-telling op de
   chip. Widgettest: capability-uitsluiting verbergt een categorie zonder de opgeslagen waarde te
   wissen (`constrainedTo` versus de gestelde selectie), Toepassen herstart de query,
   sluiten-zonder-Toepassen laat de vorige query intact.
5. **Onthouden en herstellen.** `UnifiedCatalogQueryStore.read` bij het openen van het scherm,
   `withKnownSources` voor een verdwenen server/library, net als de TV-tegenhanger doet.
   Widgettest: een eerder opgeslagen selectie staat bij een volgende opening weer klaar.
6. **De handler onder de landing-actie.** `_TitleRow` in `mobile_landing_screen.dart` krijgt een
   `GestureDetector`/`InkWell` die naar `MobileCatalogScreen(kind: ...)` pusht. Verder verandert er
   niets aan dat bestand, zoals de doc-comment op regel 155-164 al vastlegt. Widgettest op
   `mobile_landing_screen_test.dart`: tikken op `landing.view_all[movies]` pusht het scherm.
7. **`UnifiedArtworkPrefetcher` aan het grid.** Eigen instantie in de state, `dispose()` ermee,
   `prefetchAround` op elke scroll-notificatie met de zichtbare index-range uit de scrollpositie en
   drie kolommen.
8. **`UnifiedCatalogQueryStore.clearForProfileScope` in de profiel-delete-flow.** Eén regel in
   `profile_delete_flow.dart`, met `storage.userScopeForProfileId(profile.id)`.
9. **`Provider<UnifiedCatalogs>`-registratie.** In `profile_session_screen.dart`, naast
   `TvDiscoveryLandingProvider`/`TvHomeProjectionProvider`, met een expliciete `dispose:` zoals de
   doc-comment in `unified_catalogs.dart:86-89` voorschrijft. Dit is de stap die de acht
   F0-unused-meldingen (`UnifiedCatalogs`, `buildUnifiedCatalogQuery`, `UnifiedCatalogQueryStore`,
   `loadUnifiedFilterOptions` en hun bestanden, plus `unified_artwork_prefetcher.dart` als stap 7 hem
   al aan het grid koppelde) laat verdwijnen, dus die staat expres laat: eerder registreren zonder
   consumenten zou dezelfde melding alleen verplaatsen.
10. **`tap: {id}` in de Verify-engine.** `rectForNode` publiek in `geometry_assertions.dart`,
    `run_scenario.dart`'s `tap`-case uitgebreid, test in `run_scenario_test.dart`.
11. **Scenario `ios.catalog.northstar`.** Header, chips, telling, grid, filtersheet-opening,
    sorteersheet-opening, tegen `03-alle-films.png` en `04-filters-sheet.png`. Niet uitvoerbaar in
    deze sessie (sectie H); geschreven en gevalideerd met `dart run bin/verify.dart run ... --json`
    voor zover dat zonder simulator kan (schema-validatie).
12. **CHANGELOG- en DEC-entry**, met de echte cijfers uit sectie H/het eindrapport.

## G. Definition of Done

1. `flutter analyze`: 0 errors, 0 warnings, de bekende info-lints niet uitgebreid met nieuwe.
2. `flutter test`: alles groen dat vóór fase 3 groen was, plus de nieuwe tests uit stap 2 t/m 6.
3. `scripts/ci_checks.sh`: de 17 F0-meldingen dalen naar het aantal dat stap 9 overlaat (verwacht 9:
   17 min de 8 die stap 9 opheft), gemeten en niet aangenomen.
4. `dart run slang` reproduceert `strings.g.dart` zonder diff na de i18n-wijziging.
5. `test/architecture/automation_ids_yaml_test.dart` en `automation_ids_test.dart` groen.
6. `ios.catalog.northstar` **PASS** met bewaarde bewijsbundel en een contactvel naast
   `03-alle-films.png`/`04-filters-sheet.png`, **of** expliciet gerapporteerd als ontbrekend bewijs
   met de reden (geen Apple-toolchain in deze sessie).
7. `ios.home.northstar`, `ios.landing.northstar` en `discover.hero.layout` gedraaid op de
   fase-3-tip, **of** expliciet gerapporteerd als ontbrekend bewijs.
8. `scripts/format_native.sh --check`: niet van toepassing (geen native bestand geraakt), of
   gerapporteerd als ontbrekend bewijs als dat toch verandert.
9. Eén CHANGELOG-entry, één DEC-entry (nummer ná controle van `origin/main`, zie valkuil 1).
10. Elke correctheidsclaim in dit document heeft een test die zonder de bijbehorende fix rood is.

## H. Toolchain in deze sessie

Deze uitvoeringsomgeving is een Linux-cloudcontainer, geen Mac. Er is geen Xcode, geen iOS/tvOS/macOS-
simulator en geen `swift-format`. Wat wel kan en hier ook echt gedraaid wordt:

- Flutter 3.44.0 zelf opgehaald (`git clone --branch 3.44.0 https://github.com/flutter/flutter.git`)
  en gebruikt voor `flutter pub get`, `flutter analyze`, `flutter test`. Dit is dezelfde SDK-pin als
  `.fvmrc`, dus de resultaten zijn niet "bij benadering": het is de gepinde toolchain, alleen op
  Linux in plaats van macOS, precies zoals CI dat voor `portable` ook doet.
- `dart run slang` (onderdeel van de Flutter/Dart-toolchain, geen Xcode nodig).
- `pleya_verify`'s Dart-kant (parser, validator, `dart test` in `pleya_verify/runner`) draait op
  Linux; alleen de drivers die een simulator of macOS-app starten kunnen dat niet.

Wat niet kan, en dus expliciet als ontbrekend bewijs gerapporteerd wordt in plaats van als
"geverifieerd": elk Verify-scenario met `target: ios-sim`, `target: macos` of `target: tvos-sim`
(`ios.home.northstar`, `ios.landing.northstar`, `discover.hero.layout`, het nieuwe
`ios.catalog.northstar`), en `scripts/format_native.sh --check`.

## I. Open vragen

Geen. De twee besluiten die fase 1 en fase 2 halverwege de bouw moesten nemen (de hero-CTA/indicator,
de chip-tab-scheiding) zijn al genomen en blijven buiten fase-3-scope. C1 t/m C9 hierboven zijn de
besluiten die fase 3 zelf nodig had; ze zijn hier genomen, niet halverwege de bouw.

## J. Stop

Fase 3 stopt zodra sectie G's tien punten gemeten zijn (groen, of expliciet gerapporteerd als
ontbrekend bewijs met reden) en de twee commits voor CHANGELOG/DEC binnen staan. Bronwissel,
contextmenu en detailpagina zijn fase 5 en worden hier niet vooruit gebouwd, ook niet als de sheets
ernaar zouden kunnen verwijzen.

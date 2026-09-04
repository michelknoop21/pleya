# Code-parity-audit van de candidate-set 09 tot en met 25

Datum: 3 september 2026. Branch `claude/netflix-redesign-b4x21v` op `f8e0e59`, worktree
`pleya-teleport`. Geen productiecode gewijzigd. De code is de functionele waarheid; de mockups
zijn visuele voorstellen. Waar de tekst een bestand en regelnummer noemt, is dat het bewijs.

Zes lezingen liggen eronder: 09/10/24/25, 11/12, 13 tot en met 16 plus Samen Kijken, 17 tot en
met 19, 20 tot en met 23, en een tokenaudit van `tv.css` tegen `tv_unified_layout.dart`,
`mono_theme.dart` en `focus_theme.dart`. Alle labelverschillen zijn tegen `lib/i18n/nl.i18n.json`
gecontroleerd.

## Correcties die al in de candidate-HTML zijn doorgevoerd

Alleen wat aantoonbaar een verkeerde weergave van bestaand of goedgekeurd gedrag was:

- 11: één statusmarkering per rij; "Beschikbaar op 3 servers"; "Altijd NAS gebruiken";
  "Bekeken" in plaats van een verzonnen "Vanaf het begin"-status; geen resttijd.
- 12: labels "Aan kijklijst toevoegen", "Markeer als gekeken", "Verwijder uit Doorgaan met
  kijken"; Sluiten-knop in de voet.
- 13: geen "Dicteren"-knop (op Apple TV zit de microfoon op de remote); letterrij expliciet
  als NATIVE TVOS KEYBOARD REPRESENTED SCHEMATICALLY; geen telling naast de railkop.
- 14: filterchip "Beschikbaar" (het omgekeerde filter bestaat niet); sorteren als
  "Sorteren · Recent toegevoegd"; geen bronnencapsules, geen "Aangevraagd" of "Aanvragen" op
  kaarten; niet-beschikbare kaart toont alleen het jaar.
- 16: Samen Kijken en Pleya Remote van de pagina af (aparte surface, DEC-070); schermkop "Nu
  aan het kijken"; geen inactief-apparaat-kaart.
- 18: "Pauzeren"; hints gesplitst in veeg omlaag (infopaneel), druk omlaag (wachtrij) en Menu
  (bediening verbergen).
- 09 en 10: "Trailers & Extra's"; bronregel "Bron: NAS • Films 4K".
- 20: groepskop "Weergave", optie "Systeem", "Bibliotheek dichtheid", "Taal".
- 21: titel "Wie is er aan het kijken?"; geen Toevoegen-tegel in de selectiepoort; ronde avatars.
- 22: alleen Plex en Jellyfin; "Kies hoe je inlogt"; QR zonder tekstcode; "Wachten op
  authenticatie..."; "Opnieuw proberen"; Jellyfin-uitweg; geen Continuity-regel, geen aftelklok.
- 23: "Opnieuw verbinden"; geen "Verbinden…"-status (bestaat alleen op het splashscherm).

Alles wat hieronder als PRODUCT DECISION staat, is bewust niet aangepast.

## Drie bevindingen die de hele set raken

1. **Topnav op gepushte routes.** Detail (09, 10), collectie (24), persoon (25), Live TV-sheets
   en alle Instellingen-subpagina's worden op de `ProfileSessionNavigator` gepusht
   (`lib/navigation/profile_session_screen.dart:490`) en dekken de shell volledig af.
   `TvRootShell` heeft geen eigen navigator. De mockups tonen de topnav op al die schermen.
   Ofwel de balk gaat uit die mockups, ofwel het routecontract van hoofdstuk 6.2 verandert.
   Eén besluit voor de hele set.
2. **Broncoverage buiten de bronkiezer.** "Beschikbaar op 3 servers", "2 bronnen", "over alle
   servers" komen in 09, 10, 13, 14, 15 en 25 terug. De strings bestaan
   (`sourcePicker.availableOnManyServers`, `unifiedCatalog.sources`), maar buiten de picker en
   de unified kaarten van Home/Films/Series/Zoeken rendert niets ze. Kijklijst, Seerr en de
   persoonspagina zijn geen unified surfaces.
3. **BACK1 blijft open.** `AppBarBackButton` is een `GestureDetector` zonder `FocusNode`
   (`lib/widgets/app_bar_back_button.dart:125-146`), dus zichtbaar en onbereikbaar. De
   detailmockups halen hem weg. Weghalen en focusbaar maken lossen BACK1 allebei op, met andere
   gevolgen voor Android TV en pointerinvoer. Dat is een besluit, geen bijvangst.

## Per mockup

### 09 Filmdetail

MOCKUP: 09. SURFACE: brongebonden detailpagina van één `MediaItem`.
CURRENT PRODUCTION SCREEN: `lib/screens/media_detail_screen.dart` (TV-tak `:3529`,
`_buildTvDetailScreen` `:3796-3893`), `lib/screens/media_detail/action_buttons.dart`,
`cast_section.dart`, `extras_section.dart`, `now_watching_line.dart`, `watch_stats_row.dart`,
`watched_by_row.dart`, `lib/widgets/tv_browse_rail.dart`, `lib/widgets/tv_spotlight_background.dart`.
CURRENT ROUTE: `MaterialPageRoute` op de profielnavigator via `navigateToMediaItem`
(`lib/utils/media_navigation_helper.dart:204`); vanuit unified kaarten via
`tv_media_source_picker_route.dart:268`.
CURRENT TV PRIMITIVES: `TvSpotlightBackground`, `TvBrowseRail`, `FocusableActionBar`,
`FocusableWrapper` (bronchip), `OverlaySheetHost` panel, `MediaContextMenu`, `AppBarBackButton`.
Geen `TvUnifiedLayout`-tokens; schaal via `TvLayoutConstants.scaleForSize`.
CURRENT USER ACTIONS (volgorde `action_buttons.dart:278-287`): Play/Resume (film: alleen icoon,
label leeg `:4938-4957`), Trailer, Download, Bekeken, Kijklijst, Aanvragen, Meer, bronchip "Wijzigen".
CURRENT CONDITIONAL ACTIONS: shuffle alleen show/season; trailer als gevonden; download niet op
Apple TV en niet offline; kijklijst film/serie online; aanvragen bij Seerr; Meer verborgen
offline; bronregel alleen bij meer dan één bron.
CURRENT STATES: reveal-gate (`:784-834`) met ontsnapknop; metadata-fout via
`TvPlaybackFailureAlternative` (`:1542-1562`); rail-error met retry; offline; playback-failure
via `_offerAlternativeAfterPlaybackFailure`.
CURRENT FOCUS ENTRY: film naar de playknop (`:3810`).
CURRENT D-PAD CONTRACT: UP op actierij no-op; DOWN naar rail; LEFT/RIGHT tussen knoppen, randen
dood; SELECT activeert; LONG SELECT bestaat niet in `FocusableActionBar` (in de rail 500 ms
naar contextmenu); MENU/BACK pop met `_watchStateChanged`.
CURRENT CONTEXT MENUS / OVERLAYS: `MediaContextMenu` (`lib/widgets/media_context_menu.dart:215-560`),
bronkiezer, beoordelingsdialoog, Seerr-sheet.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING FROM MOCKUP: Trailer-knop; Download (Android TV); Aanvragen-knop; Acteurs-rail; related
rails; NowWatchingLine, WatchedByRow, WatchStatsRow; genrelijn; retry per rail; loading-,
offline- en foutstaat.
MOCKUP ADDS NON-EXISTING PRODUCT BEHAVIOUR: "Vanaf het begin" als hero-knop (alleen als
menu-item); "Hervatten · nog 1u 12m" (film heeft geen label en geen resttijd); coverage op de
bronregel; topnav; soort- en lengtebadges op extra's; 4K/HDR10/Atmos als pills.
LABEL DIFFERENCES: kijklijst-tooltip "Aan kijklijst toevoegen"; bekeken "Markeer als gekeken";
"Vanaf het begin" heet "Afspelen vanaf het begin".
ARCHITECTURAL CONFLICT: BACK1; coverage op detail is een contractuitbreiding van hoofdstuk 15;
actierij-randen zonder uitweg naar een topnav die er niet is.
RECOMMENDATION: REVISE MOCKUP (topnav en terugknop zijn een PRODUCT DECISION).

### 10 Seriedetail

Zelfde scherm, tak `isShow`. Seizoenen zijn op TV **één rail-hub per seizoen** in `TvBrowseRail`
(`:4315-4340`); `_buildSeasonTabs` draait alleen niet-TV (`:3633`, `showSeasonPosters` uit op TV
`:2436`). Wisselen van seizoen is UP/DOWN, niet LEFT/RIGHT over chips.
CURRENT USER ACTIONS: Play met label `discover.playEpisode` = "S2E4", Shuffle, trailer,
download, bekeken, kijklijst, aanvragen, Meer, Wijzigen.
CURRENT STATES: loading per seizoen, paginering bij focus op de laatste aflevering
(`:4455-4475`), error per hub met retry, seizoenen uit downloads offline, spoilervrije synopsis.
CURRENT FOCUS ENTRY: niet de playknop maar de rail: `initialHubId` = geselecteerd seizoen,
`initialItemId` = on-deck-aflevering (`:4378-4392`).
CURRENT D-PAD CONTRACT: UP vorig seizoen (hub 0 naar actierij); DOWN volgend seizoen, daarna
Acteurs, Trailers & Extra's, related; LEFT/RIGHT afleveringen, RIGHT pagineert; SELECT afspelen;
LONG SELECT contextmenu met "Ga naar serie"; MENU pop met KeyUp-suppressie.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: Shuffle; trailer, download, aanvragen; Menu-hint en terugknop; Acteurs, Extra's, related;
genrelijn; loading en retry per seizoen; spoilers verbergen; kijkers en statistieken.
ADDS: seizoenchips boven één rail (grootste structurele afwijking van de set);
"10 afleveringen · 6 bekeken"; "Hervatten · S2 E4 · nog 18 min"; "nieuw"-badge; synopsis in de
kaart in plaats van in de hero-samenvatting (`_tvDetailDescription` `:4188-4209`).
ARCHITECTURAL CONFLICT: chips vernietigen seizoen-per-rail. Loading, retry, paginering en
prefetch (`_prefetchAdjacentSeasonEpisodePages` `:1878`) hangen aan `hubIndex`; focusgeheugen
is per hub (`_rememberFocus`).
RECOMMENDATION: PRODUCT DECISION REQUIRED (seizoenkiezer horizontaal of verticaal).

### 11 Bronkeuze

CURRENT PRODUCTION SCREEN: `lib/widgets/tv/tv_media_source_picker.dart`, `tv_source_row.dart`,
`tv_source_row_descriptor.dart` (statuslabel-rangorde `:88-97`), `lib/screens/tv/tv_media_source_picker_route.dart`,
`lib/services/unified_catalog/unified_activation_coordinator.dart` (`decide` `:201-276`),
`lib/widgets/overlay_sheet_geometry.dart` (`_tvPanelReferenceWidth` 1000 `:155`, gedeeld door alle
TV-panels).
CURRENT ROUTE: geen; `OverlaySheetController.showAdaptive` met `presentation: panel` en
`restoreLauncherFocus`.
CURRENT USER ACTIONS: bronrij kiezen; "Altijd ${server} gebruiken" (alleen als de gefocuste rij
bruikbaar is en niet al voorkeur; selecteert niets); "Servers beheren" (alleen bij nul
bruikbaar); Sluiten; Back.
CURRENT STATES: online, offline ("Niet beschikbaar"), authError ("Opnieuw aanmelden vereist"),
disabled rij zonder focus; niets-bereikbaar-notice; "Meer bronnen controleren…"; late bron
zonder focusverplaatsing. Eén bruikbare bron of een bruikbare voorkeursserver: de picker opent
niet (`decide` `:235-266`).
CURRENT FOCUS ENTRY: laatst gebruikte online bron, anders recentste progress, anders beste
online, anders eerste rij (`selectInitialFocus` `:420-441`).
CURRENT D-PAD CONTRACT: traversal binnen de sheet; SELECT activeert; LONG SELECT niet bedraad;
MENU sluit en herstelt de launcher-focus (test `tv_media_source_picker_test.dart:462-519`).
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: progressbalk per rij (`tv_source_row.dart:461-497`); markering "Huidige bron" bij
openen via Wijzigen; niets-bereikbaar-staat met "Servers beheren"; scroll-fade; artwork-fallback;
details-intent-kop.
ADDS (na correctie nog open): backend-icoonwel per rij (33.9 noemt hem richtinggevend, code
heeft alleen een tekstsegment); picker-eigen backdrop; de getekende situatie (voorkeursserver
bruikbaar én picker open) is via normale activatie onbereikbaar, alleen via Wijzigen, en dan
zonder "Laatst gebruikt".
LABEL DIFFERENCES: na correctie geen.
ARCHITECTURAL CONFLICT: 14.8a: de voorkeursserver kiest zelf, de picker is dan niet zichtbaar;
gedeelde paneelbreedte 1000 tegenover 760 in mockup 12.
RECOMMENDATION: REVISE MOCKUP (progressbalk, Huidige bron-variant) plus PRODUCT DECISION over
de backend-icoonwel.

### 12 Contextmenu

CURRENT PRODUCTION SCREEN: `lib/screens/tv/tv_unified_context_menu.dart` (acties `:138-160`,
paneel `:432-511`; doc `:434-436`: "No artwork and no metadata header beyond the title"),
`tv_unified_context_actions.dart`, `TvCatalogOptionRow` in `tv_catalog_sort_panel.dart:159-260`
(geen icoon, geen trailing-waarde, gedeeld met filter- en sorteerpaneel).
Bereik: het unified menu heeft twee aanroepers (discovery-mixin en catalogus). Detail,
afleveringen, playlists en mappen gebruiken nog `MediaContextMenu`, en die valt op tvOS in de
bottom-sheet-tak omdat `Platform.isIOS` daar waar is (`media_context_menu.dart:239`): een blad
van 400×400 (`overlay_sheet_geometry.dart:299-300`).
CURRENT USER ACTIONS (exacte volgorde): Markeer als gekeken of ongekeken; Aan kijklijst toevoegen
of Uit kijklijst verwijderen of niets; Beoordelen; Verwijder uit Doorgaan met kijken; Sluiten.
CURRENT CONDITIONAL ACTIONS: kijklijst en beoordelen verdwijnen offline (DEC-020); CW-removal
alleen als `isInContinueWatching`; leeg menu opent niet.
CURRENT STATES: `ApplyActionToAllSources` (sources, deferred, unreachable), `ActionUnavailable`
(noUsableSource, signInRequired), uitkomstmeldingen "Gereed op X van Y bronnen".
CURRENT FOCUS ENTRY: eerste actierij. D-pad: traversal; SELECT kiest, sluit en voert uit;
LONG SELECT op de kaart opent het menu (500 ms); MENU sluit, focus terug.
CURRENT CONTEXT MENUS / OVERLAYS: de rating-sheet opent zonder `presentation: panel` en wordt
op TV dus een 400×400 bottom sheet.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: offline-varianten; unsupported-kijklijststaat; "Markeer als ongekeken"; blokkade- en
uitkomstmeldingen; VoiceOver "Actie N van M".
ADDS: Hervatten, Vanaf het begin, Meer info, Bron wijzigen (bestaan niet als menu-actie, geen
ingang menu naar picker); posterkop met metadata (in code expliciet afgewezen); iconen en
trailing-waarden; scheidingslijnen; breedte 760.
ARCHITECTURAL CONFLICT: hoofdstuk 23 noemt Afspelen/Hervatten, Meer info en Bron wijzigen als
veilige groepsacties, de code heeft ze niet: dat is functionele achterstand, geen mockupfout.
OVR1 staat OPEN zonder diagnose; de geometrie in code is al proportioneel (900 tot 1040 breed,
marge boven 20%, hoogte tot 0,84 viewport, tests `overlay_sheet_geometry_test.dart:185-207`),
dus 760 fixeert een getal op een onbekende oorzaak.
RECOMMENDATION: PRODUCT DECISION REQUIRED: (a) vier ontbrekende acties bouwen of hoofdstuk 23
bijstellen; (b) posterkop toestaan; (c) paneelbreedte splitsen, pas na OVR1-diagnose.

### 13 Zoeken

CURRENT PRODUCTION SCREEN: `lib/screens/search_screen.dart` (1117), `apple_tv_native_text_entry.dart`,
`tv_virtual_keyboard.dart`, `tv_discovery_rail.dart`, `search_projection.dart`.
CURRENT ROUTE: top-level TV-destination, compacte icoonpil (`tv_destination.dart:28-52`).
CURRENT TV PRIMITIVES: `FocusableButton` als querypil, SELECT opent het native tvOS-toetsenbord
(`:192-223`, partial text streamt live); `TvVirtualKeyboardPanel` alleen als gelatchte fallback
na een kapotte native surface (`:227-236`); `TvDiscoveryRail` met `alwaysDescribesCurrent: true`
(`:848-857`); `TvRailStack`; `FocusableMediaCard` in lijstmodus voor Collecties, Afspeellijsten,
Personen, Overig.
CURRENT USER ACTIONS: pil openen; dicteren via de Siri Remote in dat toetsenbord (geen eigen
knop op Apple TV, `:729-748`); submit naar eerste resultaat; SELECT tegel; LONG SELECT
contextmenu; recent-chip; Wissen; Seerr-fallback "Niet in je bibliotheek? Zoek op Jellyseerr /
Overseerr"; retry.
CURRENT STATES: skeletons; netwerkfout; geen servers; "Recent gezocht"; "Zoek in je media";
geen resultaten met of zonder Seerr.
CURRENT FOCUS ENTRY: de pil (`:163`); na submit het eerste resultaat.
CURRENT D-PAD CONTRACT: UP eerste rail naar pil; rails via `_tvRails.up/down` met behoud van
kolom; DOWN pil naar resultaten; LEFT eerste tegel naar bovenbalk; harde stops aan railranden;
MENU op de pil wist de query, daarna bovenbalk, daarna de `tvBackStep`-keten.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: secties Series, Afleveringen, Afspeellijsten, Overig (Personen bestaat als sectie maar
blijft leeg: `people` wordt niet meegegeven, `:466`); Recent gezocht; Seerr-fallback;
lege- en foutstaten; het metablok onder de rail (titel, context, synopsis).
ADDS (na correctie nog open): collecties als brede rij (code: verticale lijst; servernaam
alleen bij meer dan één server).
LABEL DIFFERENCES: hint "Zoek films, series, muziek..."; paginatitel "Zoeken".
ARCHITECTURAL CONFLICT: SEARCH1 (DEFERRED). `alwaysDescribesCurrent` staat er omdat het metablok
de enige plek is waar een resultaattitel vóór activatie leesbaar is. De mockup zet de titel
onder de kaart en laat het metablok weg. Dat is precies het besluit dat de correctieronde eist,
inclusief waar context en synopsis dan blijven. Vier tests in `search_screen_test.dart:370-390`
bewaken het huidige gedrag.
RECOMMENDATION: PRODUCT DECISION REQUIRED (SEARCH1) plus REVISE MOCKUP (secties, staten,
collecties als lijst).

### 14 Kijklijst

CURRENT PRODUCTION SCREEN: `lib/screens/watchlist_screen.dart` (659), `watchlist_card.dart`,
`watchlist_item_sheet.dart`, `watchlist_sort_sheet.dart`, `watchlist_entry.dart`.
CURRENT ROUTE: `TvMyPleyaSection.watchlist`, `restoreFocusKey` `tvMyPleya_watchlist`; tegel bij
`hasWatchlist`.
CURRENT TV PRIMITIVES: `TvCatalogGrid.forWidth` (`:466-468`), `WatchlistCard` als dispatcher naar
`FocusableMediaCard` of `WatchlistUnavailableCard`, `_FilterBar` met `FocusableFilterChip` op
inset 8, `CustomAppBar`.
CURRENT USER ACTIONS: SELECT afspeelbaar naar detail; SELECT niet-afspeelbaar naar de item-sheet
met Aanvragen, Uit kijklijst verwijderen, Annuleren; LONG SELECT alleen afspeelbaar; filterchips
Alles, Films, Series, Beschikbaar; sorteersheet Recent toegevoegd, Titel, Jaar.
CURRENT CONDITIONAL ACTIONS: "Beschikbaar" verdwijnt offline; Aanvragen volgt `requestability`
(unsupported, ready, resolvable); focusherstel na verwijderen (WL1, `b3a3e5d`, `:250-263`).
CURRENT STATES: laden; leeg met "Opnieuw proberen"; leeg door filter met "Alles"; per kaart
unknown, checking (spinner), available, notFound ("Niet beschikbaar", gedempt).
CURRENT FOCUS ENTRY: onthouden kaart, anders eerste kaart, anders filterbalk (`:266-278`).
CURRENT D-PAD CONTRACT (`:491-518`): UP eerste rij naar eerste chip; DOWN per kolom, laatste rij
blijft; LEFT kolom 0 naar bovenbalk; RIGHT laatste item blijft; MENU nested pop naar de tegel.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: de item-sheet (enige plek voor aanvragen en verwijderen); de drie
requestability-varianten; checking-spinner; twee lege staten; offline-gedrag.
ADDS: geen meer na correctie.
ARCHITECTURAL CONFLICT: de kijklijst is geen unified surface. `memberships` zijn
kijklijst-lidmaatschappen, geen bezittende bronnen; `WatchlistAvailability` kent geen
aanvraagstatus. Bronnen of aanvraagstatus op de kaart is nieuwe functionaliteit.
RECOMMENDATION: REVISE MOCKUP (item-sheet als tweede staat tekenen). Bronnen of aanvraagstatus
op kaarten: PRODUCT DECISION.

### 15 Aanvragen

Twee schermen, geen één: `lib/screens/seerr/seerr_discover_screen.dart` (952) en
`seerr_requests_screen.dart` (397), plus detail en row-grid. Route `TvMyPleyaSection.requests`
naar discover; Mijn aanvragen is een `Navigator.push` (`:330-332`).
CURRENT TV PRIMITIVES: `FocusedScrollScaffold` (app bar `ExcludeFocus` op TV), `FocusableTextField`
met TV-toetsenbordgedrag, inbox-knop naast het zoekveld als enige TV-route naar Mijn aanvragen
(`:568-585`), `LibraryHeaderBar` met typetabs en genre-actie, shelves met "Alles tonen",
`SeerrLoadMoreTile`, genrepaneel, `SegmentedTabGroup` op het aanvragenscherm.
CURRENT USER ACTIONS: zoeken (debounce 400 ms); typetab; genre-paneel; streamingdienst; Alles
tonen; Meer laden; poster naar detail; inbox. Detail: Aanvragen (uit bij beschikbaar) naar
`SeerrRequestSheet`. Aanvragen: filtertabs met tellingen; Goedkeuren en Afwijzen (manager,
pending); Aanvraag annuleren (eigen, met bevestiging).
CURRENT STATES: per shelf skeleton, geladen, leeg, gefaald; paginabreed fout met retry;
posterbadges "In afwachting", "Bezig", "Deels beschikbaar", "Beschikbaar".
CURRENT FOCUS ENTRY: zoekveld. D-pad: UP raster naar eerste typetab; LEFT eerste tab, kolom of
zoekveld naar bovenbalk; RIGHT tab naar tab naar genre-actie; LONG SELECT niets; MENU wist de
zoektekst, anders bovenbalk.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: zoekveld (mockup heeft een chip); inbox-knop; genre-actie; streamingdienstenrij; Alles
tonen; Meer laden; vier shelves ("Populair nu", "Populaire films", "Populaire series",
"Binnenkort"); acties op aanvragen; filtertabs met tellingen; manager-kop "Alle aanvragen".
ADDS: Mijn aanvragen op dezelfde pagina; chip "Filters 1"; posterbadge "Aangevraagd";
"Beschikbaar · 2 bronnen"; relatieve tijd en downloadpercentage; kop "Jellyseerr op NAS · 3 open".
LABEL DIFFERENCES: kop is "Ontdekken via Aanvragen"; "Alles" heet "Alle"; "Populair deze week"
heet "Populair nu"; "In behandeling" heet "Bezig".
ARCHITECTURAL CONFLICT: discover en aanvragen samensmelten geeft twee paginatiedomeinen, een
privacy-guard op `requestedBy` en per-rij mutaties op één surface. Seerr-status komt uit Seerr,
niet uit de unified resolver.
RECOMMENDATION: REVISE MOCKUP (twee schermen, bestaande labels, bestaande elementen).

### 16 Activiteit

CURRENT PRODUCTION SCREEN: `lib/screens/now_watching_screen.dart` (86 regels),
`now_watching_panel.dart`, `now_watching_row.dart`. Route `TvMyPleyaSection.activity`.
CURRENT TV PRIMITIVES: `CustomAppBar` plus één `NowWatchingPanel(large: true)`; rijen zijn
`_Tappable`. Geen `TvPageSurface`.
CURRENT USER ACTIONS: exact één: SELECT op een rij met `ratingKey` opent de titel. Geen stop of
terminate.
CURRENT CONDITIONAL ACTIONS: tegel zichtbaar bij `hasOnlinePlexServers`
(`tv_my_pleya_screen.dart:280`), wat een concrete `PlexClient` vereist (ACT1); de data komt
van Tautulli (`profile_session_screen.dart:212-222`); rijen zonder `ratingKey` zijn niet
focusbaar; de pagina popt zichzelf bij `!hasOthers` (`:63-70`), en `Navigator.pop` werkt niet in
een `TvNestedRoute`.
CURRENT STATES: sessies of niets. Geen lege, fout- of laadstaat.
CURRENT FOCUS ENTRY: eerste rij met `ratingKey`. D-pad: UP/DOWN default; LEFT naar bovenbalk
niet bedraad (afwijkend van elk ander TV-scherm); MENU nested pop.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: kop met totalen en amber bij transcoderen; bandbreedte, LAN/WAN; zelfsluiten.
ADDS (na correctie nog open): servertaken met voortgang. `ServerActivitiesButton` is op TV
bewust uitgesloten omdat het paneel een hover-popover is die de remote niet kan focussen
(`lib/screens/discover_screen.dart:1174-1186`). Drie-koloms kaartraster (code: verticale lijst).
LABEL DIFFERENCES: de schermkop is "Nu aan het kijken", de tegel "Activiteit"; de
tegelondertitel "Nu kijken, samen kijken, remote" belooft wat het scherm niet doet (bestaand
defect, los van de mockup).
ARCHITECTURAL CONFLICT: Samen Kijken is een eigen sectie met eigen route, tegel,
`restoreFocusKey` en Pleya Verify-scenario; Pleya Remote bestaat op TV niet (DEC-070). Beide
zijn uit de candidate gehaald. ACT1 blijft: zichtbaarheid aan Plex, inhoud aan Tautulli.
RECOMMENDATION: PRODUCT DECISION REQUIRED: (a) Activiteit is alleen Nu aan het kijken, of krijgt
scope erbij en welke naam; (b) servertaken terug op TV met focuscontract; (c) ACT1.

### 17 Live TV

CURRENT PRODUCTION SCREEN: `lib/screens/livetv/live_tv_screen.dart` (tabs Gids, Nu op TV,
Opnames), `tabs/guide_tab.dart` (1668; één `Focus`-node met handmatige toetsafhandeling
`:640-678`), `whats_on_tab.dart`, `recordings_tab.dart` (Gepland en Opnameregels in één tab),
`program_details_sheet.dart` (gedeeld door gids, Nu op TV en showschema).
CURRENT ROUTE: tab in de hoofdshell (`main_screen.dart:1291`); programmadetail is een sheet,
geen route. `useSideNav` is op TV nog waar (`platform_detector.dart:169-171`), dus de tabchips
staan in een eigen app bar onder de topnav: twee navigatiebalken.
CURRENT USER ACTIONS: kanaal afspelen; programma (lopend op TV: direct afspelen, anders sheet);
long-press 500 ms naar sheet; F togglet favoriet; sterknop favorietenfilter; herordenen;
tijdvenster plus of min 2 uur; dagkeuze en tijdslot; Gids herladen; Opnames annuleren, regel
bewerken of verwijderen, Regels opnieuw evalueren; Opnemen of Opname beheren (na async
`fetchSubscriptionMapping`).
CURRENT STATES: skeletons; geen DVR; geen zenders; "Geen programmagegevens beschikbaar";
admin vereist; nu-lijn 2 px `kAccent`; verstreken programma's 50%; opname-dot met tooltip.
CURRENT FOCUS ENTRY: grid rij 0, kanaalkolom (`:137-157`).
CURRENT D-PAD CONTRACT (`:680-799`): UP tijdnav naar tabbalk, grid rij 0 naar tijdnav; DOWN
tijdnav naar grid; LEFT tijdnav index 0 en grid kolom 0 naar `onBack`; RIGHT kolom 0 springt naar
het nu lopende programma; SELECT tijdnav min 2 uur, dagpicker, plus 2 uur; LONG SELECT sheet;
MENU grid naar tijdnav, tijdnav naar shell.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: tab Nu op TV en het showschema; dag- en tijdnavigatie (drie van vijf focusposities);
Gids herladen, Favorieten herordenen, Regels opnieuw evalueren; bron-headerrijen bij meerdere
bronnen; LIVE-badge en uitklapbare samenvatting; foutstaten.
ADDS: "Favorieten" als tab (code: filter); "Regels" als tab (code: sectiekop); badge 4; kopregel
met kanaalteller; voortgang in de programmatile; "start over 15 min"; regelnaam in detail;
permanente detailbalk zonder focus.
LABEL DIFFERENCES: "Regels" heet "Opnameregels"; "Kijken" heet "Kanaal bekijken"; "Opname
bewerken" heet "Opname beheren".
ARCHITECTURAL CONFLICT: de sheet blijft nodig voor Nu op TV en showschema; knopstaat is
asynchroon; SELECT op een lopend programma speelt direct af, een balk met "Kijken" maakt een
tweede pad en raakt het D-pad-contract.
RECOMMENDATION: PRODUCT DECISION REQUIRED: (a) Nu op TV en showschema; (b) sheet naast balk en
wat SELECT doet; (c) waar dag- en tijdnavigatie en de drie acties landen.

### 18 Speler-OSD

CURRENT PRODUCTION SCREEN: TV gebruikt `desktop_video_controls.dart` (`video_controls.dart:800`).
Knoppenrij VOD (`:963-1170`): Vorige aflevering, Vorig hoofdstuk, Terugspoelen, Afspelen of
Pauzeren, Vooruitspoelen, Volgend hoofdstuk, Volgende aflevering, "Eindigt om", Afspeelinstellingen,
Audio en ondertitels, Hoofdstukken en Wachtrij (op TV verborgen zodra de content-strip inhoud
heeft), Beeldverhouding. Niet op TV: PiP, AirPlay, vergrendelen, volledig scherm.
CURRENT CONDITIONAL ACTIONS: live zonder aflevering- en hoofdstukknoppen, met `LiveTimelineBar`
en "Ga naar live"; skip-knop niet bij filmintro's; auto-skip alleen bij afleveringen;
`canControl` false maakt alles inert (Watch Together).
CURRENT STATES: auto-hide 5 s op TV; holds; buffering; toast-pills; init-foutscherm met
Opnieuw, Terug, Probeer lagere kwaliteit; einde zonder auto-hide.
CURRENT FOCUS ENTRY: verborgen naar root `Focus`; UP/DOWN naar play/pause; LEFT/RIGHT naar tijdlijn;
marker naar skip-knop.
CURRENT D-PAD CONTRACT (`key_events.dart:299-350`, `desktop_video_controls.dart:458-788`):
verborgen: UP skip-knop of controls; DOWN op Apple TV veeg naar infopaneel, druk naar
wachtrij-strip; LEFT/RIGHT controls plus tijdlijn plus sprong; SELECT skip of play/pause; MENU
verlaat. Zichtbaar: UP naar tijdlijn, dan verbergen; DOWN naar play/pause, dan content-strip;
tijdlijn met progressieve versnelling en scrub-modus; MENU annuleert scrub, sluit strip, verbergt
controls en verlaat pas daarna; LONG SELECT is dubbele snelheid.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: aflevering- en hoofdstukknoppen (vier); Afspeelinstellingen (enige TV-ingang voor
slaaptimer, zoom, shaders, versie en kwaliteit, sync); Beeldverhouding; live-varianten;
content-strip; Kijk-je-nog en volgende-aflevering-kaarten; scrub-modus; skip-aftelling; fout- en
noticestaten.
ADDS: twee icoonknoppen rechtsboven; snelheid en slaaptimer top-level; hoofdstuknaam in de
tijdregel; permanente thumbnail; technische regel met "Direct play" (bestaat nergens);
gecombineerde resttijd en eindtijd.
LABEL DIFFERENCES: `videoControls.skipIntro`, `skipCredits` en `nextEpisode` ontbreken in
`nl.i18n.json` en vallen terug op "Skip Intro", "Skip Credits", "Next Episode". Productiebug.
ARCHITECTURAL CONFLICT: zes vaste knoppen tegenover negen tot twaalf conditionele met een
index-gebaseerde buurzoeker (`:489-512`); zonder settings-ingang worden vijf functies op TV
onbereikbaar.
RECOMMENDATION: REVISE MOCKUP.

### 19 Speler-infopaneel

CURRENT PRODUCTION SCREEN: `lib/widgets/video_controls/tv_info_panel.dart` (391),
`tv_information_tab.dart`, `tv_video_tab.dart`, `tv_audio_subtitle_tabs.dart`,
`tv_panel_widgets.dart` (`TvPanelTheme.accent` hardcoded `0xFFF42B1F`, `:16`). Ondertitelstijl
leeft in `lib/screens/settings/subtitle_styling_screen.dart`.
Tabs: Informatie, Video (hardcoded string `:265`), Geluid, Ondertitels. Video: Beeldverhouding,
Hoofdstukken (SELECT springt naar het volgende), Afspeelsnelheid, Omgevingsverlichting,
Prestatie-overlay. Geluid: SPOREN plus OPTIES (Maximaal volume, Audio synchronisatie met
sub-view, Audio-uitvoermodus, Prioriteit, Volume gelijkmaken, Verminder harde geluiden).
Ondertitels: SPOREN ("Uit" plus tracks) plus OPTIES ("Meer…" voor online zoeken, Plex-only,
sluit het paneel; Ondertitel synchronisatie).
CURRENT FOCUS ENTRY: pill van de actieve tab. D-pad: UP pill sluit, eerste rij naar pill; DOWN
pill naar rij; LEFT/RIGHT op de pillbalk wisselt tab, in rijen niets; SELECT past direct toe;
MENU sub-view naar tab, anders sluiten.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: Informatie-inhoud; de hele Video-tab; alle audio-opties behalve sync; sectiekoppen
Sporen en Opties; sync-sub-view; inert-staat bij Dolby-doorvoer.
ADDS: tab Wachtrij (zit in `ContentStrip` en `QueueSheet`); tab Hoofdstukken als lijst; audio en
ondertitels in één tab met drie kolommen; tweeregelige spooridentiteit (code toont alleen
`label.primary`, de secondary uit `TrackLabelBuilder` wordt weggegooid `:103, :375, :407`);
"geforceerd" als subregel (code: "(Forced)" hardcoded Engels, `track_label_builder.dart:203-205`);
ondertitelstijl-rijen; "Onthouden voor deze titel" per titel (alleen globaal in Instellingen,
`playback_settings_screen.dart:159-165`); statusregels; kopregel in de tabbalk.
LABEL DIFFERENCES: "Audio en ondertitels" zijn twee tabs "Geluid" en "Ondertitels"; "Info" heet
"Informatie"; "Weergave" heet "Video"; "Audio-synchronisatie" heet "Audio synchronisatie";
"Ondertitelvertraging" heet "Ondertitel synchronisatie"; "Online zoeken" heet "Meer…".
ARCHITECTURAL CONFLICT: `#F42B1F` tegenover `kAccent #E5140F` (R11, hoofdstuk 34.2); drie
kolommen vragen een herschrijving van de focusnavigatie; wachtrij in het paneel overlapt het
veeg-versus-druk-contract op Apple TV; ondertitelstijl in de speler is een nieuwe feature.
RECOMMENDATION: PRODUCT DECISION REQUIRED: (a) tabindeling; (b) ondertitelstijl in de speler;
(c) onthouden per titel of globaal; (d) waar de wachtrij leeft. Code-actiepunten los van de
mockup: weggegooide spoorlabels, onvertaald "Video" en "(Forced)".

### 20 Instellingen, Uiterlijk

CURRENT PRODUCTION SCREEN: `lib/screens/settings/appearance_settings_screen.dart` (414), frame
`settings_page.dart`, rijen `settings_section.dart` (`kSettingsMaxWidth 880` `:14`, focusbalk 3 px
`:28`). Ingang `settings_tv_page.dart:122-130`. Gewone push, geen nested route.
CURRENT TV PRIMITIVES: `FocusedScrollScaffold`, `SettingsWidthLimit`, `SettingsGroup`,
`SettingRowFocus`, `SwitchListTile`, `SegmentedButton`, `showSelectionDialog`, `FocusableSlider`.
Geen `TvPageSurface`, geen `TvMenuGrid`.
CURRENT USER ACTIONS (24 rijen in vijf secties): Weergave: Thema (Systeem, Licht, Donker,
OLED; default OLED), Taal (16 talen, herstart), Bibliotheek dichtheid (slider 1 tot 5, Compact
tot Comfortabel), Weergavemodus, Aflevering poster stijl, Volledige tv-kaarten (TV), Focusgloed
(TV), Afleveringsnummer op kaarten. Startscherm: Persoonlijke aanbevelingen, Actie voor Doorgaan
met kijken, Startlayout gebruiken, Servernaam tonen bij hubs. Navigatie: Opstartsectie, Aantal
ongekeken tonen. Inhoud: Standaard favoriete zenders, Spoilers verbergen, Afleveringsactie, Vraag
om profiel bij openen, Prestatie-overlay automatisch verbergen.
CURRENT STATES: alleen geladen; geen preview.
CURRENT FOCUS ENTRY: eerste focusbare descendant, het segment "Systeem" (`focused_scroll_scaffold.dart:65-74`).
CURRENT D-PAD CONTRACT: UP/DOWN rijen; LEFT/RIGHT alleen op segmenten en slider; SELECT togglet,
opent dialoog of pusht; LONG SELECT niet; MENU pop naar de index.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO. Zeven van 24 rijen getekend.
MISSING: Weergavemodus, Aflevering poster stijl, Volledige tv-kaarten, Focusgloed en de overige
zestien; de secties Startscherm, Navigatie, Inhoud.
ADDS: Titels onder posters (geen pref); Clearlogo op de hero (onvoorwaardelijk gedrag, geen pref);
Hero automatisch wisselen (hard 8 s, `TvHomeLayout.heroAutoAdvance`, `tv_unified_layout.dart:1163`,
afgeleid van context); Sfeerverlichting (pref bestaat, zit in het speler-instellingenpaneel en is
mpv-only); Verminder beweging als instelling (bestaat niet; alleen `visualEffects` op Android,
en die sleutel ontbreekt in `nl.i18n.json`); thema-omschrijvingen; live voorbeeldrail; breadcrumb.
ARCHITECTURAL CONFLICT: de index kreeg de tegeltaal, de subpagina staat nog op de 880-cap en de
3 px-balk; vier van acht getoonde controls hebben geen leespunt; sfeerverlichting hier zou een
tweede schrijfpad naast `shader.dart:148` zijn.
RECOMMENDATION: PRODUCT DECISION REQUIRED (bestaan van de vier instellingen; verhuizing van
sfeerverlichting), daarna REVISE met de volledige rijlijst.

### 21 Profiel kiezen

CURRENT PRODUCTION SCREEN: `lib/screens/profile/profile_switch_screen.dart` (841): selectiepoort
(`_buildSelectionGate` `:336-384`) en beheerlijst (`_profileList` `:390-446`);
`pin_entry_dialog.dart` (TV-dialoog `:123-157`); `profile_activation.dart:30-58`.
CURRENT ROUTE: root-push; poort vanuit koude start, app-resume, de topnav-profielchip en na de
eerste Plex-login; beheerlijst vanuit Instellingen en vanuit de poort zelf.
CURRENT TV PRIMITIVES: `Wrap` met `_GateTile` 120 pt, ronde `ProfileAvatar` (`ClipOval`), witte
3 px rand bij focus, `OutlinedButton`. Geen TV-primitieven.
CURRENT USER ACTIONS: poort: profiel kiezen (PIN bij `isPinProtected`), "Profielen beheren".
Beheerlijst: wisselen, Beheren, Verwijderen (alleen lokaal), Afmelden bij Plex (alleen Plex
Home), "Pleya-profiel toevoegen".
CURRENT STATES: laden; fout met retry na 5 s; leeg; poort; beheerlijst; wissel-overlay met
annuleren; PIN-fout met shake (melding hardcoded Engels, `profile_activation.dart:57`).
CURRENT FOCUS ENTRY: eerste tegel (`:364`).
CURRENT D-PAD CONTRACT: directional focus in de `Wrap`; SELECT wisselt; LONG SELECT alleen in de
beheerlijst; MENU in de poort sluit de app (`PopScope(canPop: false)` plus
`AppExitService.requestExit`, `:150-156`), in de lijst pop.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: het onderscheid poort en beheerlijst; verbindingschips; "Actief"-badge; laad-, fout- en
lege staat; wissel-overlay; het feit dat Menu de app sluit.
ADDS (na correctie nog open): vaste 260-tegels met gap 56 (code `Wrap` 26); initiaal op
accent-gradient (code `colorForName`); backdrop-crop als avatar (alleen Plex-thumb of initiaal).
ARCHITECTURAL CONFLICT: Jellyfin-gebruikers worden geen profielen; een Jellyfin-only installatie
toont de poort niet eens (`main_screen.dart:889-891`). Slot-badge wordt in de poort deels
weggeknipt door `ClipRRect(4)` (`:626-630`).
RECOMMENDATION: REVISE MOCKUP (poort en beheerlijst als twee beelden).

### 22 Inloggen

CURRENT PRODUCTION SCREEN: `lib/screens/auth_screen.dart` (642), `lib/screens/auth/plex_pin_auth_flow.dart`
(438), `add_jellyfin_screen.dart`. De vijfkeuze-picker (`add_connection_screen.dart`) is alleen
na inloggen bereikbaar en hangt aan een profiel.
CURRENT TV PRIMITIVES: gecentreerd blok tot 800 pt, twee kolommen boven 700 pt breed, `PleyaLogo`
met wordmark en de hardcoded tagline "Your media. Your way." (`:341`), `FocusableButton`,
`QrImageView`.
CURRENT USER ACTIONS: "Inloggen met Plex" (TV: QR direct), "Verbinden met Jellyfin", "Gebruik
browser" (niet op Apple TV, `:437`); in de flow "Opnieuw proberen" en de Jellyfin-uitweg
tijdens het wachten (`plex_pin_auth_flow.dart:270-285`, gebouwd voor App Review).
CURRENT STATES: keuze; QR met "Scan deze QR-code om in te loggen"; spinner "Wachten op
authenticatie..."; time-out na 5 minuten polling; PIN verlopen; herstelstaten "Geen mediaservers
gevonden" en "Kan de server niet bereiken"; Jellyfin: Quick Connect verlopen, inloggen mislukt.
CURRENT FOCUS ENTRY: Plex-knop (`:396`); de QR start niet automatisch (`autoStartQrOnTV: false`, `:320`).
CURRENT D-PAD CONTRACT: verticale kolom; LEFT/RIGHT niets; SELECT start de flow; MENU pop.
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: browser-route; herstelstaten; Jellyfins "Server zoeken" en meerdere URL's; het merkblok.
ADDS (na correctie nog open): Pleya Server, Pleya Share en Lokale map op de eerste start; de code
als tekst (de app stopt de URL `app.plex.tv/auth#?code=` in de QR en rendert de code nergens);
aftelklok (er is geen vervaldatum in de client).
ARCHITECTURAL CONFLICT: eerste start en verbinding toevoegen zijn twee schermen met twee
contracten; Pleya Share scant met de camera, die een Apple TV niet heeft.
RECOMMENDATION: PRODUCT DECISION REQUIRED (bronnen op de eerste start; code als tekst;
verloopteller). Daarna is de gecorrigeerde mockup dicht bij de code.

### 23 Offline

Er is geen offline Home. Offline is een navigatiemodus: `main_screen.dart` (`_isOffline` `:387`,
`_buildScreens` `:1260-1315`), `offline_mode_provider.dart` (zes redenen, twee tellen als
offline), `navigation_tabs.dart:187` (Home, Films, Series, Bibliotheken, Live TV, Zoeken en
Aanvragen zijn `onlineOnly`). Offline blijven Kijklijst, Downloads (niet op Apple TV),
Instellingen en Mijn Pleya; de app springt naar Downloads.
CURRENT USER ACTIONS: "Opnieuw verbinden" bestaat alleen in de zijbalk en de mobiele balk
(`:2568`, `:2603-2643`); `_buildTvShell` geeft geen reconnect door. Op TV kan niemand met de
remote een reconnect starten. Servers beheren via Mijn Pleya, Afmelden via de tegel.
CURRENT STATES: `noNetworkConnection`, `noServerConnection` (offline); `waitingForServerStatus`,
`noKnownVisibleServers`, `onlyAuthErrorServers` (niet offline). De getekende mix (offline plus
opnieuw aanmelden plus verbinden) is geen bereikbare `offlineReason`.
CURRENT D-PAD CONTRACT: `buildTvDestinations` kent geen offline-conditie; de topnav toont
Home, Series, Films, Zoeken als focusbare pills waarvan SELECT niets doet (`_selectTab` `:1890`).
MOCKUP PRESERVES ALL FUNCTIONALITY: NO.
MISSING: Downloads en Kijklijst als offline-bestemmingen; de inkrimpende topnav; de niet-offline
staten; terug-online-semantiek; het onderscheid tussen gequeude kijkvoortgang en geweigerde
kijklijstmutaties.
ADDS: offline Home met "Home" actief; momentopname-rail (`DiscoverSnapshot` bestaat alleen als
koude-start-versneller zonder tijdstempel, `discover_provider.dart:344-366`); serverlijst met
bibliotheektelling voor Plex en Jellyfin (bestaat alleen voor Pleya Servers); reconnect-knop op TV.
LABEL DIFFERENCES: "Geen server bereikbaar" tegenover `states.offlineTitle` "Je bent offline";
TV-formulering voor auth is "Sessie verlopen voor ${name}".
ARCHITECTURAL CONFLICT: de mockup volgt hoofdstuk 21.2 en 21.5, die als spec zijn goedgekeurd
maar niet gebouwd: geen offline Home, geen snapshot-pad, geen reconnect op TV, geen serverlijst
met Plex en Jellyfin. Implementatiegat, geen mockupfout.
RECOMMENDATION: PRODUCT DECISION REQUIRED: (a) Home offline als route; (b) snapshot met
tijdstempel; (c) reconnect op TV; (d) serverlijst met alle backends.

### 24 Collectie

Concreet backend-item (`collection_detail_screen.dart`, één server). Geen TV-primitieven:
`CustomAppBar` plus `SliverGrid` via `buildSparseFocusableGrid`, `FocusableActionBar` in de app
bar. Acties: Afspelen, Willekeurig, Downloaden en sync-regel (niet op Apple TV), Verwijderen; per
kaart contextmenu met "Verwijderen uit collectie". States: error met retry, laden, "Collectie is
leeg", skeletons met paginering per 200. Focus entry eerste kaart; MENU gaat eerst naar de app
bar, een tweede Back popt (`focusable_detail_screen_mixin.dart:70-77`).
MOCKUP PRESERVES ALL FUNCTIONALITY: NO. MISSING: Willekeurig; download; Verwijderen; lege en
foutstaat; verwijderen uit collectie; het grid. ADDS: hero met backdrop, synopsis en
aggregaat-meta; "Vanaf het begin"; bekeken-toggle op collectieniveau (bestaat niet);
sorteerchips (sorteren bestaat alleen op `HubDetailScreen` als sheet); volgnummer-badge;
placeholder "nog niet op je servers" met Aanvragen (geen externe metadatabron, geen aanvraagpad);
bron in de kop; rail in plaats van grid.
LABEL DIFFERENCES: "Alles afspelen" heet "Afspelen"; "Collectievolgorde" bestaat niet.
RECOMMENDATION: PRODUCT DECISION REQUIRED (TV-native collectie met hero en rails; ontbrekende
titels tonen).

### 25 Persoon

`actor_media_screen.dart` (204): `personId` plus `serverId`, één server, één entrypoint (de
Acteurs-rail op detail, `media_detail_screen.dart:1301-1319`); Zoeken heeft geen personenrij.
`getAppBarActions()` is leeg: nul acties. Grid zonder groepering; rolnaam alleen van de
instaptitel in de kop; avatar 80 pt met icoon-fallback. MENU popt direct.
MOCKUP PRESERVES ALL FUNCTIONALITY: YES, maar ADDS: cross-server persoonsidentiteit ("over alle
servers", "9 titels op je servers"); "2 bronnen"; Films en Series als secties; rol per kaart;
Willekeurig afspelen; Volgen (bestaat nergens); biografie, geboortedatum, beroep; known-for en
dedupe; initiaal-fallback; rails.
Bug gevonden: `actor_media_screen.dart:174` telt in hardcoded Engels ("titles").
ARCHITECTURAL CONFLICT: er is geen `CanonicalPersonIdentity`; nieuwe datavelden; Volgen is een
nieuwe feature; twee hero-knoppen veranderen het Back-gedrag (eerst naar de knoppenrij).
RECOMMENDATION: PRODUCT DECISION REQUIRED.

## Visuele tokenaudit (tv.css tegen code)

Conversie: type en dichtheid met k = 1,5725 (base × 0,85 × 1,85); boxcompositie als fractie van
1920. PASS: achtergrond `#141414`, surface, elevated, accent, amber, pagina-inset 75,5,
grid-inset 56, topnav y 44 en hoogte 51,9, chip 44, wordmark 51,9, itemfont 23,6, ringkleur wit
gepind, ringdikte 3,93, ring-gap kaarten 7,86, tegels zonder scale, tegelradius 15,7, billboard
18,9, sheet-radius 22, paginakoppen 42,5 en 47,2, grid 283×424 met gutter 22, knop 62,9 als
capsule, primaire CTA wit, chips 51 hoog.

Divergentie tussen HTML-baseline en code (code wint tenzij een besluit anders zegt):

1. Nav-itemafstand: mockup 40 label-naar-label; code telt `itemGap` 39,3 bovenop pill-padding
   26,7 per zijde en ring-gap 4,7, samen ongeveer 102 (`tv_unified_layout.dart:898-918`).
2. Kaartradius 12 tegenover `cardRadius` 10 → 15,7 (`:230`, `:677`).
3. Groepslabel: northstar 26, w500, inkt 0,72, zinshoofdletters; code 22, w600, inkt 0,50,
   HOOFDLETTERS met tracking (`:984`, `tv_page_surface.dart:164-169`). De code volgt de
   september-mockup die zelf van de code is afgeleid.
4. Vinkje: mockup witte schijf met donkere tick; code donkere capsule met witte tick
   (`tv_unified_media_card.dart:408-426`); 33.5 zegt "wit vinkje".
5. Nieuw-markering: mockup amber punt; code tekstpil "NEW" met rood-amber gradient
   (`new_content_badge.dart:51-57`), tegen hoofdstuk 34 en 33.6.
6. Raillabel 31,5 tegenover mockup 27 en de 8.3-band 25 tot 28.
7. Scrim `#141414` op 0,72 tegenover zwart op 0,50 of 0,34 (`overlay_sheet.dart:326, 164`).
8. Progress-track wit 0,25 tegenover zwart 0,45 (`tv_unified_media_card.dart:456`).
9. Ring-gap op chips en knoppen 8 tegenover 4,7 (`actionFocusRingGap` 3, `:221`).
10. Standaardthema is OLED (`theme_provider.dart:12`), dus alle alpha-fills landen donkerder
    dan op de northstar gemeten.
11. Eén inktladder in de mockup, vijf in de code (0,62 tot 0,78 voor de tweede tier); de tier
    0,30 bestaat niet als token.
12. Drie groenen voor één statuskleur, waarvan `Color(0xFF3FBF5F)` hardcoded in
    `tv_my_pleya_screen.dart:829` (R11-patroon).
13. Topnav-dim bij een overlay heeft geen implementatie.

Kleine REVISE-punten: pill-hoogte, focusschaal 1,06 om het midden tegenover 1,05 vanuit de
onderrand, focusduur 120 ms onder de 8.4-band, kaarttitel zonder weight-shift, knoplabel 25,2
boven de band, tegeltitel en tegelhoogte, rail-itemgap effectief 40,9, secundaire CTA-fill 0,26.

DEC-087 autoriseert de railband 346, de 16:9-kaart 615 en de buren 231; `_src/tv.css` presenteert
267×400 en 400×225 nog als bindend. De HTML loopt daar achter op het besluit.

## Eindmatrix

| Nr | Scherm | CODE PARITY | VISUAL CONTRACT | PRODUCT DECISION | FUNCTIONALITY MISSING | LABEL DRIFT | APPROVAL |
|----|--------|-------------|-----------------|------------------|------------------------|-------------|----------|
| 09 | Filmdetail | FAIL | REVISE | REQUIRED (topnav, terugknop, coverage) | trailer, aanvragen, acteurs, related, kijkers, staten | gecorrigeerd | NOT READY |
| 10 | Seriedetail | FAIL | REVISE | REQUIRED (seizoenkiezer) | shuffle, rails, paginering, spoilers | "S2E4" zonder Hervatten | NOT READY |
| 11 | Bronkeuze | FAIL | REVISE | REQUIRED (icoonwel) | progressbalk, Huidige bron, niets-bereikbaar | gecorrigeerd | NOT READY |
| 12 | Contextmenu | FAIL | REVISE | REQUIRED (vier acties, posterkop, breedte) | offline-varianten, meldingen | gecorrigeerd | NOT READY |
| 13 | Zoeken | FAIL | REVISE | REQUIRED (SEARCH1) | vier secties, recent, Seerr, metablok | hint, titel | NOT READY |
| 14 | Kijklijst | PASS na correctie | REVISE | NONE (tenzij bronnen op kaart) | item-sheet, requestability, lege staten | gecorrigeerd | NOT READY |
| 15 | Aanvragen | FAIL | REVISE | NONE | zoekveld, inbox, genre, shelves, acties | vijf labels | NOT READY |
| 16 | Activiteit | FAIL | REVISE | REQUIRED (scope, servertaken, ACT1) | totalen, LAN/WAN | ondertitel tegel | NOT READY |
| 17 | Live TV | FAIL | REVISE | REQUIRED (Nu op TV, sheet, tijdnav) | tab, tijdnav, drie acties, bronrijen | drie labels | NOT READY |
| 18 | Speler-OSD | FAIL | REVISE | NONE | vier knoppen, instellingen, beeldverhouding, strip, prompts | nl-vertaling skip ontbreekt | NOT READY |
| 19 | Infopaneel | FAIL | REVISE | REQUIRED (tabs, stijl, onthouden, wachtrij) | Video-tab, audio-opties, sub-view | zes labels | NOT READY |
| 20 | Uiterlijk | FAIL | REVISE | REQUIRED (vier instellingen, sfeerverlichting) | zeventien rijen, drie secties | gecorrigeerd | NOT READY |
| 21 | Profiel kiezen | PASS na correctie | REVISE | NONE | beheerlijst, chips, staten, Menu sluit app | gecorrigeerd | NOT READY |
| 22 | Inloggen | PASS na correctie | PASS | REQUIRED (bronnen op start, code als tekst, teller) | browser-route, herstelstaten | gecorrigeerd | NOT READY |
| 23 | Offline | FAIL | REVISE | REQUIRED (Home offline, snapshot, reconnect, serverlijst) | Downloads, Kijklijst, topnav-krimp | "Je bent offline" | NOT READY |
| 24 | Collectie | FAIL | REVISE | REQUIRED (hero en rails, ontbrekende titels) | shuffle, verwijderen, grid, staten | "Afspelen" | NOT READY |
| 25 | Persoon | PASS | REVISE | REQUIRED (persoonsidentiteit, Volgen, bio) | staten, focusherstel | "titles" hardcoded | NOT READY |

MOCKUPS READY FOR MICHEL APPROVAL: geen. Het dichtst bij: 22 (na correctie alleen nog het
besluit over bronnen op de eerste start), 21 (poort en beheerlijst splitsen), 14 (item-sheet
tekenen).

MOCKUPS REQUIRING REVISION: 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23, 24, 25.

PRODUCT DECISIONS REQUIRED:
1. Topnav op gepushte routes (09, 10, 24, 25 en alle subpagina's) tegenover het routecontract
   van hoofdstuk 6.2.
2. BACK1: zichtbare terugknop weghalen of focusbaar maken.
3. Broncoverage buiten de bronkiezer (09, 10, 13, 14, 15, 25).
4. Seizoenkiezer: chips (horizontaal) of seizoen-per-rail (verticaal) (10).
5. Contextmenu: de vier acties uit hoofdstuk 23 bouwen of het hoofdstuk bijstellen; posterkop;
   paneelbreedte pas na OVR1-diagnose (12).
6. SEARCH1: waar staat de resultaattitel permanent, en blijven context en synopsis (13).
7. Activiteit: scope en naam; servertaken op TV; ACT1 (16).
8. Live TV: Nu op TV en showschema, sheet naast balk, plaats van tijdnavigatie en acties (17).
9. Infopaneel: tabindeling, ondertitelstijl in de speler, onthouden per titel, wachtrij (19).
10. Uiterlijk: bestaan van hero-rotatie, titels onder posters, clearlogo en verminder beweging als
    instelling; verhuizing van sfeerverlichting (20).
11. Eerste start: Pleya Server, Pleya Share en Lokale map zonder profiel; Plex-code als tekst;
    verloopteller (22).
12. Offline: Home als route, snapshot met tijdstempel, reconnect op TV, serverlijst met alle
    backends (23).
13. Collectie als TV-native surface; ontbrekende titels met aanvraagpad (24).
14. Persoonspagina: cross-server identiteit, Volgen, biografiedata, rol per credit (25).
15. Backend-icoonwel in de bronkiezer (11).

CODE/MOCKUP CONFLICTS (bestaand in code, los van de mockups):
- `nl.i18n.json` mist `videoControls.skipIntro`, `skipCredits`, `nextEpisode`,
  `search.voiceSearch`, `settings.visualEffects*`, `addServer.connectToPleyaServerCard*`,
  `addLocalFolder.*`: Engelse fallback in productie.
- Hardcoded strings: "Video" (`tv_info_panel.dart:265`), "(Forced)"
  (`track_label_builder.dart:203-205`), "titles" (`actor_media_screen.dart:174`), "Your media.
  Your way." (`auth_screen.dart:341`), "Incorrect PIN" (`profile_activation.dart:57`).
- `TvPanelTheme.accent #F42B1F` en de serverstip `#3FBF5F` naast `kAccent` en `kSuccess` (R11).
- Het infopaneel gooit de technische spoorlabels weg (`tv_audio_subtitle_tabs.dart:103, 375, 407`).
- `PlatformDetector.shouldUseSideNavigation` is waar op TV: Live TV tekent twee navigatiebalken.
- `now_watching_screen.dart:63-70` popt via `Navigator` in een `TvNestedRoute`.
- Geen reconnect-affordance op TV; offline topnav toont dode pills.
- Legacy `MediaContextMenu` valt op tvOS in het 400×400 bottom sheet; ook de rating-sheet,
  de kijklijst-item-sheet en de Live TV-sheets.
- `StateView` en `EmptyStateWidget` schalen niet op TV.
- Zoeken: `people` wordt nooit meegegeven aan `searchProjection`.
- `tvMyPleya.activitySubtitle` belooft samen kijken en remote die de tegel niet levert.

STOP. Geen implementatie vóór Michel de gecorrigeerde set expliciet goedkeurt.

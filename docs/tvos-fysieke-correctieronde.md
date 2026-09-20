# tvOS fysieke correctieronde

Levend werkdocument. Elke bevinding die op een echte Apple TV is gezien staat hier
met een eindstatus, en verdwijnt pas wanneer die status er is. Nieuwe meldingen
worden toegevoegd, ze vervangen niets.

**Staande regel.** Alles wat Michel erbij vraagt landt hier eerst: een nieuw plan,
een werkwijze, een functieverzoek, een bugfix, een losse opmerking die werk
oplevert. Zet het als regel in de tabel voordat je begint, en vink het af met de
SHA wanneer het klaar is. Een item mag alleen uit de tabel verdwijnen door een
eindstatus te krijgen, nooit doordat er later iets urgenters bijkwam.

**Waar dit vandaan komt.** Michel heeft de nieuwe tvOS-interface op een fysieke
Apple TV 4K bekeken en vond gebreken die in de simulator niet zichtbaar zijn.
Sommige daarvan kunnen daar principieel niet zichtbaar zijn, want de simulator
heeft geen aanraakvlak: invoer die over de touch-surface van de Siri Remote loopt
bestaat er niet. Hardwarebeelden gaan daarom voor op een simulator die er goed
uitziet, en voor op goldens.

## Hoe je dit document gebruikt

Eén item tegelijk, in de volgorde van de tabel hieronder. Per item:

1. reproduceer eerst, en schrijf op waarmee;
2. bepaal de root cause voordat je iets wijzigt, en noem de eigenaar: welk
   bestand, welke functie;
3. schrijf een negatieve controle die op de oude implementatie rood staat, en
   toon dat hij rood was;
4. fix bij de gedeelde eigenaar, niet bij de aanroeper, tenzij je opschrijft
   waarom gedeeld oplossen niet kan;
5. draai `dart format` op de geraakte bestanden, `flutter analyze` en de gerichte
   tests, en pas dan committen;
6. werk de regel in de tabel bij met de SHA. Doe dat in de eerstvolgende commit
   en niet met een amend op de fix zelf, want een amend geeft de commit een
   nieuwe hash en dan klopt het nummer dat je er net in zette alweer niet.

Statussen: `OPEN`, `IN PROGRESS`, `FIXED`, `VERIFIED`, `NOT REPRODUCED`,
`DEFERRED`, `ACCEPTANCE GAP`, `HARDWARE ONLY`, `HARDWARE VALIDATION PENDING`.

`FIXED` betekent groen in de testsuite. `VERIFIED` vraagt daarnaast bewijs uit
Pleya Verify of van hardware. Een bevinding die alleen op een toestel te toetsen
is krijgt `HARDWARE ONLY` en wacht op een device-run, niet op een simulatorrun
die het antwoord niet kan geven. `HARDWARE VALIDATION PENDING` is smaller dan dat:
de classificatie, de instrumentatie en de code-analyse zijn af, en er ontbreekt
precies één genoemde meting op een toestel voordat een fix gebouwd mag worden.
Geen fix bouwen op de werkhypothese totdat die meting er is (zie RAIL2).

De SDK komt uit `.fvmrc`. Draai `dart format` nooit met een andere Dart dan die,
want de uitvoer verschilt per versie en dan herformatteert hij bestanden waar je
niets aan hebt gedaan.

## Stand

Branch `claude/netflix-redesign-b4x21v`, uitgaand van `011e770`.

Op 3 september 2026 zijn de mockups 09 tot en met 25 goedgekeurd
(`docs/tvos-redesign-09-25-approved.md`). De twintig regels vanaf `SYS-1` hieronder komen uit de
code-parity-audit die daaronder ligt. De voortgang per heringericht oppervlak staat in
`docs/tvos-redesign-register.md`; deze tabel blijft de masterlijst voor de bevindingen zelf.

| ID | Bevinding | Status | SHA | Notitie |
|----|-----------|--------|-----|---------|
| LOG1 | Pijltjes op een lege logreader gooien een assertie | FIXED | `614fc08` |
| WT1 | Focus strandt na het vergeten van een kamer in Samen Kijken | FIXED | `614fc08` |
| VER1 | Een assert met een verkeerd YAML-type eindigt groen | FIXED | `9d36bb5` |
| AUTH1 | De Plex-QR liep in de eerste simulatorcompositie 78 px onder het vaste authpaneel door doordat het desktopformaat van 300 met TV-schaalfactor werd gebruikt. `TvAuthView` gebruikt op desktop/TV nu een begrensde QR van 160; de gerichte widgettests en beide kandidaatjourneys zijn groen en `01-plex-qr.png` in `.build/pleya-verify/tvos-auth-first-start-1789911693736` toont de volledige QR zonder overflow. | VERIFIED, hardware open | `6f69481b` |
| AUTH2 | De eerste woordmerkfix deelde `LEYA` ook met brede niet-Apple-platforms en zou daar het bestaande `PLEYA`-woordmerk wijzigen. De fresh-context review vond dit vóór integratie. De conditie staat nu op Apple TV: daar beeldmerk + `LEYA`, daarbuiten het bestaande beeldmerk + `PLEYA`; de negatieve widgetcontrole was rood vóór de fix en de reviewset is daarna 32/32 groen. | FIXED, hardware open | `24d87d06` |
| WL1 | Focus strandt na het verwijderen van een kijklijstkaart | FIXED | `b3a3e5d` |
| NAV1 | De bovenbalk slaat Home over. Heropend 5 september: log `y0w9x` (build 251) toont een tweede *native* keydown/keyup-paar na de druk die op Home landt. Oorzaak gevonden in de engine-fork, niet in de fasen: het aanzetten van de Menu-passthrough laat de ingedrukte pijl los, en `.ended` tikt hem opnieuw. Zie "NAV1, de echte oorzaak". Bevestigd op de Apple TV op 5 september 2026, build 259: links en rechts over de balk is één tab per druk, ook bij het landen op Home | VERIFIED | `51186c6`, `531ae19c`, `7786a952` |
| LAND1 | De landing slaat de eerste contentrail over | FIXED, hardware open | `51186c6` |
| TILE1 | Een tegel zonder actie zou de focus klemmen | NOT REPRODUCED | n.v.t. |
| LAND4 | Verticaal navigeren verliest de horizontale positie | FIXED | `8686f5c` |
| LAND2 | De projectie van de vorige rail blijft staan | FIXED | `2371c62` |
| LAND3 | De gefocuste wide card valt rechts buiten beeld | FIXED | `0a60044` |
| CAT1 | Bovenste rij coverart raakt de veilige bovengrens | FIXED, hardware open | `89b1554` |
| CAT2 | Metadata van de onderste rij staat tegen de onderrand | NOT REPRODUCED | n.v.t. |
| CAT3 | Bron, filters en sortering staan verkeerd gepositioneerd | FIXED | `675fc2f` |
| CAT4 | Bron, filters en sortering mogelijk onbereikbaar | FIXED | `ac040fd` |
| OVR1 | Detail- en contextmenu valt buiten beeld en voelt te groot | GESPLITST in OVR1a en OVR1b | n.v.t. |
| OVR1a | `scaleForHeight` heeft ondergrens 0,85, en die is onjuist voor inhoud binnen een TV-paneel: de inhoud wordt ongeveer 1,5 keer te groot. Alias van register-ID SYS-3a | GESLOTEN als koepel, OPGESPLITST in SYS-3c en SYS-3d | `docs/tvos-sys3a-schaalinventarisatie.md`: 63 van 67 bestanden scheiden displayschaal en paneelgeometrie al correct (inclusief de DET1-fix hierboven, die dit op `media_detail_screen.dart` sloot). Twee bestanden doen dat niet, zie rijen SYS-3c en SYS-3d verderop |
| OVR1b | TV-sheets zonder expliciete `presentation` vallen terug op de 400x400-geometrie | FIXED | `96f2d45` |
| OVR2 | Expliciete TV sheet-presentation wordt door de OVR1b-panelgeometrie overschreven | FIXED | `cf4b6c7` |
| BACK1 | Zichtbare terugknop die de afstandsbediening niet bereikt | FIXED, hardware open | `f00e2fe` |
| FOC2 | Focusring valt buiten de viewport in overlays (heette tot 18 september ook FOC1, naast de topnav-focusbevinding hieronder; hernoemd in TV0 omdat één ID niet twee problemen kan dragen) | FIXED, hardware open | `3b0da2e` |
| ART1 | Achtergrondbeeld op detail voelt te ver ingezoomd | FIXED, hardware open | `f42e3fd` |
| LIB1 | Blanco Bibliotheken-pagina als de selectie verdwijnt | FIXED, hardware open | `f9b2167` |
| LIB2 | Race bij snel wisselen van bibliotheek | FIXED | `f2ea980` |
| LIB3 | TV-tabs dragen nog de oude rode onderstreping | FIXED, hardware open | `3e9d31b` |
| LIB4 | Bibliotheken draait op alles behalve de kiezer nog de oude layout: kop, achtergrond, acties en landing wijken af van `libraries-a.png` en `libraries-d.png` | VERVANGEN door LIB7 | n.v.t. |
| LIB7 | Bibliotheken wordt bronbeheer: bladeren loopt via de catalogus met bronfilter, Collecties en Afspeellijsten worden eigen unified ingangen; DEC-092 accepted, mockup 27 goedgekeurd. Gebouwd als `TvLibrariesScreen` (states A/B/C/D), negatieve controle groen, Pleya Verify-scenario `tvos.my-pleya.libraries-bronbeheer` PASS op de simulator (lijst, actieblad, sprong naar Alle films met bronfilter). Niet meegenomen: Mappen bladeren (geen TV-foldernavigator bestaat, eigen workitem) en het verhuizen van Collecties/Afspeellijsten naar Mijn Pleya (dat is I7-child 15/18). `tvos.my-pleya.library-chooser` en `tvos.library.sort` testen de vervangen tabbladtaal en staan nu bekend rood tot ze herbouwd of ingetrokken worden. | CODE/SIM CLOSED, HARDWARE OPEN | `eb5de4c9` |
| CAT5 | De catalogusacties gaan naar een inklapbare rail links van het raster, met de gekozen filters als tags rechtsboven; DEC-093 accepted, mockup 28 D1/D2 goedgekeurd, gebouwd op 5 september. De rail is 330 referentiepixels breed en begint op de 8.1-grens; vijf kolommen passen ook op de 1280x918-ondergrens van CAT1 | FIXED, hardware open | `1bcc3d26` |
| LIB5 | De spotlight-titel op Bibliotheken valt over de tabrij, en maakt de actieve tab minder leesbaar dan de inactieve. Oorzaak: `_buildTvContent` in `library_recommended_tab.dart` reserveerde `LibraryHeaderMetrics.totalHeight`, een vaste constante voor kop en tabregel, maar telde de TV-bibliotheekkiezer (`TvPageChipBar`) niet mee die boven de tabregel verschijnt zodra Bibliotheken meer dan één bibliotheek heeft, de gangbare situatie. Die rij schaalt mee met het scherm, de constante niet. `libraries_screen.dart` geeft nu door of de kiezer toont; de tab telt `TvPageChipBar.heightFor(context)` mee in de vrijmaking | FIXED, hardware open | `7439a2b8` |
| LIB6 | Complete mockupset voor Bibliotheken: mockup 26, negen states in `docs/assets/tvos-unified/mockups-2026-09-04/`, gebouwd op `tv.css` en `build.mjs` van de 09-25-familie, die nu in `docs/assets/tvos-unified/src/` staan | KLAAR, contract afgewezen | n.v.t. |
| WL2 | Kijklijst end-to-end in Pleya Verify | ACCEPTANCE GAP | n.v.t. | De naad rond `WatchlistSourceFactory` bestaat en is gedekt: `plexClientBuilder` en `clientsById` zijn injecteerbaar en `test/services/watchlist_source_factory_test.dart` gebruikt ze al met een `MockClient` en een `FakeFavoritesClient`, dus het onderzoek dat de spec vroeg is gedaan en het gat zit niet op unit-niveau. Het zit op het transport: `/v1` kent geen watchlist en geen favorieten (nul treffers in `docs/pleya-protocol/v1/openapi.yaml`) en is bevroren zolang PS-5 loopt, dus een fixture die een kijklijst kan dragen is een protocolwijziging die eerst langs de zes compatibiliteitsregels uit hoofdstuk 3 van de specificatie moet. Een tweede volledige Jellyfin-fake staat niet in verhouding tot wat hij zou bewijzen, en het REQ1-precedent geldt hier niet: Seerr praat tegen zijn eigen geconfigureerde URL, buiten het mediaserverprotocol om, terwijl Jellyfin-favorieten wel over een echte mediaserververbinding lopen. De dekking hoort daarmee op een echte Jellyfin-aanmelding, en dat is de meting die WL2 sluit. De automation-ids (`tv.catalog.grid[watchlist]`, `tv.catalog.grid.item[watchlist.N]`, `tv.catalog.rail[watchlist]`, `tv.catalog.rail.row[watchlist.*]` en `tv.catalog.state[watchlist.*]`) bestaan al sinds CAT11/mockup 34, dus zodra die aanmelding er is, is er geen bouwwerk meer nodig |
| REQ1 | Aanvragen end-to-end in Pleya Verify | FIXED, simulator geverifieerd | `f72466f2`, `39f266be`, `df3dab65`, `2be95338` | `SeerrFakeServer` (apiKey-only, `/seerr/*` op dezelfde fixture-poort) sluit het fixturegat: Seerr praat toch al tegen een eigen geconfigureerde URL, los van elke mediaserververbinding, dus dit hoefde niet via het Pleya-protocol. Onderweg twee losstaande bevindingen. Eén TV-focusbug: `SeerrSettingsScreen`/`TautulliSettingsScreen` gaven de afstandsbediening nooit initiële focus (CAT13's bevinding op het naburige aanvragenscherm gold hier ook), en geen enkel formulierveld of -knop had een eigen `AutomationNode`-`focusNode`, dus elke assertie zag "niets gefocust" ook nadat de echte focus er al stond. Eén fixturebug: de eerste versie van `seerr.requests.v1` gebruikte verzonnen statuscodes die niet bij `SeerrRequestStatus`'s eigen encoding pasten, en toonde "Mislukt" waar "In behandeling" bedoeld was. `tvos.my-pleya.requests-discover.yaml` drijft het apiKey-verbindingsformulier met echte remote-presses (tvOS heeft geen aanraakvlak, C2) en bewijst dat Alle aanvragen daarna gevuld is |
| MYP1 | Regressiebewijs voor het Mijn Pleya-werk | OPEN | n.v.t. |
| ACT1 | Activiteit is niet te verifiëren | ACCEPTANCE GAP, fake Tautulli-server klaar (`f72466f2`, `0aa71164`) | n.v.t. | zie de sectie hieronder voor het geactualiseerde onderzoek van 14 september: `isOwnerOrAdmin` blokkeert de tegel voor elk profiel dat uitsluitend via Pleya Server verbindt, los van de fixture |
| VER2 | Automation-ids escapen geen blokhaken | DEFERRED | n.v.t. | TV0 (18 september): bevestigd als DEFERRED. TV8 behandelt dit niet als ontbrekende closure |
| HERO1 | Framing van het hero-beeld op Home: op hardware staan halve beelden in de hero, Plex snijdt gecentreerd vóórdat de widget iets kan kiezen | FIXED, hardware open | `d4ec1fe` |
| HERO2 | De titelband van de hero is de clearlogo-hoogte, dus een tweeregelige titel wordt op de baseline afgesneden | FIXED | `0ad49ec` |
| HOME1 | Home naast de northstar: het hero-item staat niet heel in beeld, witruimte, overgangen, indeling en styling wijken af, en de navigatiebalk mee; mockup 29 D full-bleed gekozen, mockup 30 A1 (de rail piept) plus B tot en met E goedgekeurd; DEC-095 accepted en gebouwd | FIXED, hardware open | `eed2a79`, `7b3057a6` |
| I18N5 | Home toont het raillabel "Recently Added Shows" in het Engels tussen Nederlandse labels; `nl.i18n.json` miste `discover.latestShows`, nu "Recent toegevoegde series" | FIXED | `eed2a79` |
| SEARCH1 | Zoeken benoemt zijn resultaten buiten het railcontract om | FIXED, hardware open | DEC-108 | Mockup 36 B zet de naam in de kop in plaats van in een railbijschrift, en daarmee vervalt de uitzondering `alwaysDescribesCurrent` op Zoeken. Gebouwd op 7 september |
| CAT12 | De rail sluiten boven een pagina zonder raster laat de focus nergens staan. Gevonden bij het bouwen van CAT11: `_closeRail` vraagt het raster om de focus, en op een lege of gefilterd-lege pagina is dat raster er niet. De knop van `TvCatalogEmptyState` autofocust wel, maar alleen bij het monteren, en dat was vóór de rail de focus overnam. Op tvOS is een pagina met focus en zonder gefocust item er een die je niet kunt verlaten, want de engine claimt elke druk voordat UIKit's responder chain hem ziet. Gesloten door `TvCatalogEmptyState` een `onActionFocusNode` te geven en die als terugvalbestemming te wapenen op Alle films, Alle series en de kijklijst, en bij de bouw van Aanvragen ook op Alle aanvragen en Ontdekken | FIXED, hardware open | (deze ronde) |
| CAT13 | Een catalogustaalpagina die als route gepusht wordt komt op met de pagina gefocust en geen item erop. Gevonden bij het bouwen van CAT11's tweede deel: Alle aanvragen ging tot dan toe door `FocusedScrollScaffold`, en die vraagt in toetsenbordmodus éénmalig `nextFocus()` op zijn eigen scope. De TV-tak gaat er niet meer doorheen, en `TvCatalogCardGrid` focust zichzelf niet bij het monteren, dus vroeg niemand het. Ontdekken heeft het probleem niet: dat is een sectie van Mijn Pleya en `TvNestedSurface` legt de focus daar zelf op het eerste ding in de traversal, de zoekpil. Gesloten door `SeerrRequestsScreen` één frame na het monteren `TvSeerrRequestsView.focusContent()` te laten vragen; die vraag blijft staan tot de eerste pagina binnen is, want op dat moment is het raster nog een skelet | FIXED, hardware open | `110ee763` |
| CAT14 | De lege catalogus op Alle films en Alle series had helemaal niets om op te staan. `TvCatalogEmptyState` tekent alléén zijn knop, en van de drie toestanden die `tv_unified_catalog_screen.dart` kent kreeg juist de derde (een catalogus die niet faalt en niet gefilterd is, maar leeg) geen `actionLabel`. Dan staat er geen enkele focusbare widget op de pagina: hij opent met de focus op de modal scope, de rail is niet te openen omdat er geen kaart en geen knop is om LINKS vanaf te drukken, en de CAT12-terugval kan nergens landen. Op tvOS is dat eindstation. Gesloten door die toestand Verversen te geven, met `_stateActionFocus` en `onActionNavigateLeft: _openRail` zoals de andere twee. Negatieve controle gedraaid: zonder de fix staat de primaire focus op `_ModalScopeState Focus Scope` | FIXED, hardware open | `a332e5bd` |
| CAT15 | `TvCatalogCardRail` brak LAND4 op elke pagina die hem stapelt. De rail bood UP en DOWN aan als een kale `VoidCallback`, dus een verticale stap had geen kolom om mee te nemen en de ontvangende rail beantwoordde hem met `focusRail()`, oftewel met zijn eigen focusgeheugen. Dat is precies wat LAND4 verbiedt: geheugen laat terugkeren uit een detailpagina werken en mag niet bepalen waar UP en DOWN landen. Geïntroduceerd met Ontdekken (`110ee763`) en zou met Zoeken zijn meegereisd. Gesloten door `onExitUp`/`onExitDown` de vertrekkende index te laten dragen en er `focusColumn` naast te zetten, die klemt op de laatste kaart en, als de doelkolom nog niet gebouwd is omdat de `ListView` elders geparkeerd staat, er eerst naartoe springt. Alle rails in de catalogustaal liggen op één kaartbreedte, dus "zelfde index" en "dichtstbijzijnde midden" zijn hier hetzelfde antwoord. Negatieve controle: de LAND4-test parkeert de onderste band uiterst rechts en was rood | FIXED, hardware open | `30aae55b` |
| CAT16 | Een onafhankelijke Codex-challenge over de hele DEC-108-ronde (ab2b6d7a..HEAD) vond acht bevindingen in de gedeelde primitives en drie van de vier pagina's, vier ervan echte focusvallen. `TvCatalogCardRail.focusRail`/`focusColumn` misten de attachment-toets: `_nodes` houdt een knoop voor elke ooit gebouwde kaart, ook nadat de `ListView` hem virtualiseert, en `FocusNode.canRequestFocus` is `true` op een losgekoppelde knoop, dus een weggescrolde band claimde de focus zonder hem echt te verplaatsen, wat de aanroepers die bij de eerste `true` stoppen (`TvSearchView.focusFirstResult`, `focusFirstContent` op Ontdekken) leeg lieten. `TvCatalogCardRail.didUpdateWidget` sloopte knopen zonder de terugvalregel die `TvCatalogCardGrid._reconcileNodes` al had: een kaart die onder de afstandsbediening verdween liet de pagina focus houden zonder iets gefocust. `_focusShelf`/`_restoreShelf` op Ontdekken indexeerden de ongefilterde `widget.shelves` terwijl elke aanroeper een index in de zíchtbare lijst meegaf, dus DOWN kon op een nooit-gebouwde rail landen. En `TvWatchlistView._tryEntryFocus` gaf stilzwijgend op op een toestand zonder raster in plaats van, zoals `_focusContentAfterRail` al deed, terug te vallen op de state-actie. Los daarvan: `didUpdateWidget` op de kijklijst riep `_seedAvailability` synchroon aan in plaats van via een post-frame callback zoals `initState` al deed, wat op een gebonden resolver `FlutterError: setState() or markNeedsBuild() called during build` gaf; en `SeerrDiscoverScreen._tvError` toonde de samengevatte fout van de discover-shelves door, ook wanneer een geopend genre- of providerraster prima geladen was. Alle acht gesloten dezelfde sessie, zes met een negatieve controle die het gemelde gedrag reproduceerde | FIXED, hardware open | `2fbf3ac6` |
| LAND5 | Herstel op een niet-gebouwde tegel valt terug op de eerste. `TvCatalogCardRailState.focusRail()` probeerde de "scroll in beeld, focus volgend frame"-terugval die `focusColumn` al had alleen als de onthouden id nooit gebouwd was; een tegel die wél gebouwd was en daarna weggescrolde bleef als losgekoppelde knoop in `_nodes` staan, faalde terecht de attachment-toets, en viel dan zonder terugval door naar de eerste tegel. `focusRail` delegeert nu naar `focusColumn` op de index van de onthouden id | FIXED, hardware open | `3fbb652b` |
| VER3 | De eerste tegel van een rail steekt links buiten de veilige zone. Zie de sectie "VER3, de eerste tegel steekt links buiten de veilige zone" hieronder voor de volledige analyse: `railLeadInset` trok bewust een ringgap naar links om de artwork met de kop uit te lijnen, en de meetrect van `FocusableWrapper` (artwork plus die gap) viel daardoor buiten `discover.safe_area`. Besluit ten gunste van de veilige zone: `railLeadInset` ligt nu op `pageInset`, de artwork schuift één ringgap verder van de kop af | FIXED, hardware open | `faff5ba0` |
| VER4 | Geen fixture levert een rail die lang genoeg is om te scrollen | FIXED, simulator geverifieerd | `f5fda145`, `56efc307`, `08120ee2` | `catalog.long-rails.v1` (twaalf films in `recently_added`) sluit het fixturegat, maar dat legde twee diepere gaten bloot. Eén productiebug: `_hub()` in de Pleya-protocolclient typeerde `recently_added`/`continue_watching` altijd als `mixed`, ongeacht de items erin, en `UnifiedHubKind.singleKindSurface` sluit `mixed` uit van zowel de Films- als de Series-landing: een huishouden dat uitsluitend via Pleya Server verbindt kon die twee landings dus nooit gevuld zien, met of zonder deze fixture. Gefixed door het type af te leiden uit de items zelf. Eén Verify-precisiebug: `insideViewport`/`notClipped` lazen een drijvendekomma-afronding van 1e-13 pixel als overflow; `_edgeTolerance` op 0,05px lost dat op zonder een echte fout te maskeren. `tvos.discovery.density.yaml` en `tvos.discovery.overscan.yaml` navigeerden bovendien met één RIGHT-druk naar Series in plaats van met twee naar Films, gemaskeerd doordat ze tot nu toe altijd al eerder faalden, nu gecorrigeerd. Beide scenario's PASS op de simulator |
| VER5 | `media-detail.episode-refresh` loopt op de oude zijbalkaanname en haalt de detailpagina niet meer. Hoofdstuk 18.2 verplaatste Bibliotheken naar Mijn Pleya op TV; het scenario probeerde nog de oude sidebar-toetsvolgorde. Op een echte run belandde de focus op SearchInput terwijl `wait_until: screen.libraries` toch "slaagde", want die node blijft gedeclareerd ook als Mijn Pleya's geneste navigator op Instellingen staat. Herbevestigd met een probe-run: drie keer Rechts vanaf Home, Select opent Mijn Pleya op de profielkaart, Omlaag plus Select bereikt `my_pleya.tile[libraries]`, de eerste tegel voor deze fixture | FIXED, simulator geverifieerd | `f90ca2ec` |
| LAND6 | Een lege landing verbergt de route naar een gevulde catalogus. Gesloten door de lege-staat op de Films-/Series-landing een `actionLabel`/`onAction` naar de complete catalogus mee te geven, dezelfde `_LandingMessage`-vorm als de bestaande error-staat. Negatieve controle (`test/screens/tv/tv_discovery_landing_screen_test.dart`) stond rood zonder de actie, groen erna; volledige `test/screens/tv/`-suite groen op deze commit op OFF-1 na (pre-existing baseline-faler, niet van TV2). De negen production-goldens onder `tv_discovery_landing_production_golden_test.dart` bleven identiek rood (8/9) tegen zowel de pre-fix- als de post-fixcode, dus geen regressie van deze fix | FIXED, hardware open | `f4bb816f` |
| SYS-1 | Gepushte TV-contentroutes dekken de shell af in plaats van de topnav te houden | IN PROGRESS | n.v.t. | TV0 (18 september): de drie kinderen SYS-1a (`5cafc10`, DEC-091), SYS-1b (`bb79a82`) en SYS-1c (`ad8c456`) staan alledrie op DONE in het register. Gerichte controle op contentroutes die buiten `tv_content_route_registry.dart` om pushen leverde een nieuw defect op: zie SYS-1d. Blijft daarom IN PROGRESS in plaats van administratief te sluiten |
| SYS-1d | Twee TV-contentroutes pushten nog met een kaal `Navigator.of(context).push(MaterialPageRoute(...))` in plaats van via `openTvContentRoute`/`tvContentRouteRegistry`, en dekten daarmee de shell af zoals SYS-1a het contract precies verbiedt. Eerste plek: `TvLibrariesScreen._openInCatalog` in `lib/screens/tv/sections/tv_libraries_screen.dart:220`, de "Openen in catalogus"-actie op een bibliotheek in Instellingen. Tweede plek: `TvContentFeedState._openViewAll` in `lib/widgets/tv/tv_content_feed.dart:369`, de ROW1c "Alle N"-tegel op een viewer-eigen Home-rij. Beide openden `TvUnifiedCatalogScreen`, hetzelfde scherm dat `main_screen.dart`'s `_openTvCompleteCatalog` wél correct via `_pushTvContentRoute`/`tvContentRouteRegistry` opent: het contract bestond al voor dit scherm en deze twee aanroepen volgden het niet. Beide gaan nu via `openTvContentRoute`, met de plain push als fallback wanneer geen shell luistert (off-TV, of een widgettest die de shell niet mount). Reproductie was: op de Apple TV naar Instellingen > Bibliotheken, een filmbibliotheek selecteren, "Openen in catalogus" kiezen: de bovennavigatie verdween; of op Home een viewer-eigen rij openen en op de "Alle N"-tegel drukken, zelfde effect. Beide call sites hebben nu een widgettest tegen de productie-`TvRootShell` die de rode fase (bar verdwijnt) en de groene fase (bar blijft) bewijst. Review-fix-ronde 1 verving de route-id van de Home-rij variant van `target.hashCode` naar `hubId`: de hash bevatte `loadedCount`, veranderde dus tussen builds en brak `openTvContentRoute`'s dedup-contract (herhaalde druk op dezelfde tegel kon als nieuwe push landen) | CODE CLOSED · VERIFY/SIM OPEN | `cff2022b`, `9abdaee5` |
| SYS-1e | Drie meer van dezelfde familie, gevonden in de finale whole-branch review op `f9eebf72`: `TvAboutScreen`'s Licenties-tegel (`lib/screens/tv/sections/tv_about_screen.dart:111`, opent `LicensesScreen`) en `TvServersPage`'s Add connection- en Pleya Share-tegels (`lib/screens/tv/sections/tv_servers_page.dart:95` en `:108`, openen `AddConnectionScreen` resp. `PleyaShareHostScreen`) pushten nog kaal met `Navigator.of(context).push(MaterialPageRoute(...))`. Alle drie mounten via `tvMyPleyaNestedRoute` (`lib/screens/tv/tv_my_pleya_navigator.dart:99,106`), dat geen eigen `Navigator` heeft, dus dezelfde SYS-1a-schending als SYS-1d: `Navigator.of(context)` resolvet naar de profielnavigator boven de shell en tekent over de topnav heen. `lib/screens/settings/parts/settings_tv_page.dart:82-86` documenteerde dit exacte patroon al in eigen commentaar. Zelfde fix als SYS-1d: alle drie gaan nu via `openTvContentRoute` met stabiele route-id's (`tvAboutLicenses`, `tvServersAddConnection`, `tvServersShareHost`), plain push als fallback wanneer geen shell luistert. Elke tegel heeft een widgettest tegen de productie-`TvRootShell` die de rode fase (bar verdwijnt bij de oude `Navigator.push`) en de groene fase (bar blijft na de fix) bewijst: `test/screens/tv/sections/tv_about_screen_test.dart`, `test/screens/tv/sections/tv_servers_page_test.dart` | CODE CLOSED · VERIFY/SIM OPEN | `4a06d4b1`, geen Pleya Verify-scenario, hardwareronde open |
| SYS-4 | `StateView` en `EmptyStateWidget` schalen niet op TV. Beide schalen nu met `TvLayoutConstants.scaleOf`, zoals het bestaande voorbeeldpatroon `TvCatalogEmptyState`: geen losse schaalfactor, `StateView` houdt zijn eigen basismaat voor zijn fullscreen-rol, `StateMessageWidget` behoudt zijn per-caller `iconSize`-gewichten. De derde, met de hand gemaakte lege staat in `tv_content_feed.dart:500-512` is in dezelfde ronde meegefixt | CODE CLOSED · VERIFY/SIM OPEN | `cd1f5e8a`, `4319b09f` |
| I18N1 | `nl.i18n.json` mist `videoControls.skipIntro`, `skipCredits` en `nextEpisode` | FIXED | `b18fafac` |
| I18N2 | `nl.i18n.json` mist `search.voiceSearch` | FIXED | `b18fafac` |
| I18N3 | `nl.i18n.json` mist `settings.visualEffects*` | FIXED | `b18fafac` |
| I18N4 | `nl.i18n.json` mist `addServer.connectToPleyaServerCard*` en `addLocalFolder.*` | FIXED | `b18fafac` |
| STR1 | Hardcoded "Video" in `tv_info_panel.dart:265`; nu `videoControls.tvPanel.video` (PLR2) | FIXED, testrun groen, Verify + hardware open | `5cb5c33`, `de2e554`, `6d64bbd` |
| STR2 | Hardcoded "(Forced)" in `track_label_builder.dart:203-205`; nu `videoControls.forcedTrackSuffix` (PLR2) | FIXED, testrun groen, Verify + hardware open | `5cb5c33`, `de2e554`, `6d64bbd` |
| STR3 | Hardcoded "titles" in `actor_media_screen.dart:174`. Nu `t.unifiedCatalog.titleCount`/`oneTitle`, het bestaande sleutelpaar | FIXED, hardware open | `5fb4e66c` |
| STR4 | Hardcoded tagline in `auth_screen.dart:341`. Nieuwe sleutel `auth.tagline` | FIXED, hardware open | `5fb4e66c` |
| STR5 | Hardcoded "Incorrect PIN" in `profile_activation.dart:57`. Dezelfde string stond ook letterlijk in `plex_home_switch.dart`'s PIN-herhaallus; beide naar de nieuwe gedeelde sleutel `profiles.incorrectPinTryAgain` | FIXED, hardware open | `5fb4e66c` |
| TOK1 | `TvPanelTheme.accent #F42B1F` staat naast `kAccent` | FIXED, hardware open | `5cb5c33` | `#F42B1F` komt nergens meer voor in `lib/`; `TvPanelTheme` (mockup 33, DEC-101) heeft geen actieve rood/amber-waarde meer, de klasse-doc zegt het met zoveel woorden: "an active value is plain white (TOK-1)" |
| TOK2 | Serverstip `#3FBF5F` hardcoded in `tv_my_pleya_screen.dart:833`. Vervangen door `kSuccess`, dezelfde statuskleur-semantiek als 13 bestaande gebruiken elders in `lib`. Review-fix-ronde 1 verving de dot-key van `online`/`offline` naar `row.id`.`online`/`offline`: de oude key botste zodra een profiel twee online servers had. `test/goldens/tv_root_shell_golden_test.dart` blijft stale (bekende macOS/Linux-fontdrift, zie CAT5); regeneratie via de Linux-goldens-workflow is een los openstaand punt, niet veroorzaakt door deze fix | CODE CLOSED · VERIFY/SIM OPEN | `5fbe2c7b`, `cadd11bb` |
| TOK3 | De segmented tabstijl houdt op TV zijn eigen accentrul (seizoentabs, Seerr-aanvraagfilters) | FIXED | DEC-108 | De Seerr-helft is weg (zie hieronder). De seizoentabs-helft is bij nameting geen open rij: `_buildSeasonTabs`/`FocusableTabChip` (`focusable_tab_chip.dart:263`, `tk.accent`-underline) zit uitsluitend in `MediaDetailScreen._buildInner`'s niet-TV-pad; `isTv` stuurt vóór die aanroep al door naar `_buildTvDetailScreen` → `_tvDetailHubs` (MOC-10, `tv_season_chips.dart`), dat zijn eigen presentatie tekent. De accentrul in `focusable_tab_chip.dart` is dus op TV onbereikbaar, niet slechts gedimd of ongebruikt-maar-aanwezig |
| PNL1 | Infopaneel gooit de secundaire spoorlabels van `TrackLabelBuilder` weg; nu de tweede regel van elke spoorrij (PLR2) | FIXED, testrun groen, Verify + hardware open | `5cb5c33`, `de2e554`, `6d64bbd` |
| LIVE1 | Live TV tekent zijn eigen root-chrome in plaats van precies één shell te laten staan. Kern: `useSideNav = PlatformDetector.shouldUseSideNavigation(context)` (`live_tv_screen.dart:678`) stuurt `title: useSideNav ? Row(children: _buildTabChipItems()) : Text(t.liveTv.title)` (`:683`), dus op TV bouwt `LiveTvScreen` een eigen `AppBar` met de tabchiprij als title plus een `FocusableActionBar`, onder de topnav van `TvRootShell`: twee navigatiebalken. Niet `shouldUseSideNavigation` is het probleem, die blijft terecht waar voor desktop, maar dat Live TV er root-chrome uit afleidt terwijl de shell die al tekent. `main_screen.dart:1509` (`NavigationTabId.liveTv => LiveTvScreen(key: _liveTvKey)`) is de enige bestemming in die switch zonder `_isTvShell`-tak: elke andere heeft er een of is zelf al een TV-scherm. Tweede helft, niet eerder benoemd onder dit ID: `whats_on_tab.dart:152` opent `LiveTvShowScheduleScreen` met een kale `Navigator.of(context).push(MaterialPageRoute(...))`, wat op TV naar de profielnavigator boven de shell resolvet en de topnav bedekt zodra je vanuit Nu op TV een showschema opent, dezelfde familie als SYS-1b, SYS-1d en SYS-1e | FIXED, hardware open | `f858c62b`, `a5fcb8ce`, `ba7529cd` | TV4 heeft dit in drie stukken gesloten. `f858c62b` (Task 2): de `AppBar` vervalt binnen de shell, `TvShellSurface.isPresent(context)` (`_framedByShell`) beslist in plaats van `shouldUseSideNavigation`, en de paginanaam komt terug als kop in de contentkolom op de canonieke inset; `shouldUseSideNavigation` zelf is ongewijzigd, want hij is op desktop nog steeds juist. `a5fcb8ce` (Task 3, opgeruimd in `7eee6be1`): de tabchiprij en de vier app bar-acties zijn samengevoegd tot één `TvPageChipBar`, zodat er werkelijk één secundaire laag is in plaats van twee naast elkaar; `FocusableTabChip` is daarmee op tvOS voor Live TV ook niet meer aanwezig, laat staan bereikbaar. `ba7529cd` (Task 4): het showschema opent voortaan via `openTvContentRoute` binnen de shell in plaats van met een kale `Navigator.push` erover; de bijkomende sluitregressie die dat blootlegde (LIVE1d) is apart gefixt en gesloten, zie die rij. Precedent voor de juiste vraag ("teken ik root-chrome"): `TvShellSurface.isPresent(context)` bestaat al (`tv_root_shell.dart:521`) en wordt precies zo gelezen door `tv_unified_catalog_screen.dart:744` (geen tweede achtergrondverloop dat de shell al tekent), `tv_catalog_header_bar.dart:72` (geen tweede keer de overscanmarge die de shell al uitgaf) en `media_detail_screen.dart:3988` (spotlight-top volgt de shell-inset in plaats van de standalone 8%-band). Onderzocht en niet bevestigd tijdens deze TV4-preflight: de accentrul van `FocusableTabChip` is voor Live TV geen open gat naast TOK3. `_buildTabChipItems()` gaat via `buildTabChip` naar de default `TabChipStyle.underline`, en die stijl noemt Live TV al met naam in de LIB3-fix (`3e9d31bc`: "Raakt elk oppervlak dat TabChipStyle.underline op TV gebruikt: Bibliotheken, Live TV, Downloads en de Seerr-ontdekbalk"), bevestigd door `test/widgets/focusable_tab_chip_test.dart` ("on TV the open tab carries no red rule, only ink and weight"). TOK3 blijft dus terecht beperkt tot de segmented stijl (seizoentabs, Seerr-aanvraagfilters); geen correctie nodig. Alias: het register schrijft dit item `LIVE-1` (regel 352 van `tvos-redesign-register.md`), `unified-2026-closure.md:128` ook; zelfde werkitem, geen apart ID |
| ACT2 | `now_watching_screen.dart:63-70` popt via `Navigator` binnen een `TvNestedRoute` | FIXED, hardware open | `4598e1ea` | Nieuwe `TvNowWatchingScreen` dismisst via `TvNestedRouteScope.dismiss()`, niet meer via een kale `Navigator.pop`; negatieve controle bewees de oude bug op de gedeelde screen. Een tweede, ernstiger covered-route-bug (auto-dismiss sloot de bovenliggende detailpagina i.p.v. niets te doen) is bij nameting gevonden en gefixed via `TickerMode.valuesOf(context).enabled`, ook met negatieve controle |
| LIVE1d | `LiveTvShowScheduleScreen` sluit elke programmarij af met een kaal `Navigator.pop(context)` in de `onBack`-callback van `FocusableWrapper` (`lib/screens/livetv/live_tv_show_schedule_screen.dart:164`). Die loopt via `handleBackKeyAction`, niet via `handleBackKeyNavigation`, dus zonder de `Navigator.canPop`-guard die `FocusedScrollScaffold`'s eigen fallback wel heeft. Task 4 (LIVE1c) laat dit scherm op TV nu via `openTvContentRoute` binnen de shell nesten, en zodra dat zo is heeft die pop geen lokale route meer om te vinden: dezelfde familie als ACT2, en precies wat `media_detail_screen.dart`'s `_dismissTvDetail` (DEC-088, regel 868) beschrijft: "Navigator.pop alone breaks the moment this screen is nested." Gevolg is een stille no-op (Menu doet niets met een rij gefocust) wanneer de profielnavigator niets te poppen heeft, of het sluiten van de verkeerde route wanneer dat wel kan. Niet op een toestel gereproduceerd; gevonden bij code-lezing tijdens de Stap 6-audit van Task 4/LIVE1c, en bewust niet meegefixt omdat die taak alleen de aanroepplek in `whats_on_tab.dart` opdroeg | FIXED | 20e4f881 | Nieuwe top-level `_dismissSchedule(context)` naast `_dismissTvDetail`'s patroon: bij een nested route `TvNestedRouteScope.dismiss()` aanroepen, anders `Navigator.pop(context)` zoals voorheen. `test/screens/livetv/` (23/23) en `test/screens/tv/tv_content_route_test.dart` groen, `flutter analyze` schoon |
| ACT3 | `tvMyPleya.activitySubtitle` belooft samen kijken en remote die de tegel niet levert | FIXED, hardware open | `4598e1ea` | Subtitle ingekort naar "Now watching" in alle 16 locales; `tv_shell_my_pleya_full.png` (golden) opnieuw gegenereerd via `.github/workflows/goldens.yml` om de kortere tekst te weerspiegelen |
| OFF1 | Geen reconnect-affordance op TV | FIXED, hardware open | `a749bf18`, `587750af`, `main@83b8f5fc` | `MainScreen._buildTvShell()` gaf `TvRootShell`/`TvTopNavigation` geen `isOfflineMode`, `isReconnecting` of `onReconnect` mee, terwijl de rail en de mobiele bottom bar die al hadden. `TvTopNavigation` toont nu, alleen offline en met een callback, een reconnect-item tussen de profielchip en Mijn Pleya, zelfde icoon-/labelgedrag als de rail. Negatieve controle: de nieuwe tests faalden op een compilefout tegen de ongewijzigde widget, nu groen (37/37 in `tv_top_navigation_test.dart`). Alleen deze bevinding, niet de volledige MOC-23-compositie (PB-12): dat is een aparte, veel grotere bouwronde die Michel expliciet niet voor deze ronde koos. Een onafhankelijke adversarial review (Codex) op `a749bf18` vond drie echte gaten, alle drie gefixt in `587750af`: het automation-ID ontbrak in `AutomationIds.catalog()`/de gegenereerde yaml, Select viel onbehandeld door tijdens reconnecten (`onSelect: null` i.p.v. een echte no-op), en de reconnect-pill kon de remote-focus meenemen als hij verdween zodra de servers weer online kwamen. Die laatste beslissing (`reconnectWasFocused && !isOffline`) is alsnog als pure helper `shouldRecoverTvTopNavFocusAfterReconnect` geïsoleerd en met drie unit-tests vastgelegd, naar het patroon van `shouldRenderMainScreenOffline`; een volledige MainScreen+TvRootShell-integratietest is bewust niet gebouwd (disproportioneel voor deze bevinding). Gemerged op main ondanks twee rode, van de branch losstaande CI-checks: zie OFF3 en OFF4 hieronder |
| OFF5 | Offline-tab-routingbug: `_handleOfflineStatusChanged` overschrijft de zojuist gekozen offline-tab | OPEN | n.v.t. | `main_screen.dart:2143` (`_selectTab`) wordt onvoorwaardelijk opnieuw toegewezen zodra `_syncTvDestinations()` een `displaced`-tab teruggeeft, ook als de gebruiker net zelf naar Downloads/Watchlist navigeerde: `isUserInitiated: false` onderdrukt alleen de `_autoSwitchedToDownloads`-reset, niet de `_currentTab`-toewijzing zelf. Gevonden door `/code-review` tijdens de OFF-1-ronde, niet zelf op hardware herhaald. Praktisch effect (bewering van de review-agent): op een TV waar Downloads/Watchlist offline zichtbaar is, landt de offline-shell alsnog op het generieke Mijn Pleya-scherm i.p.v. op Downloads/Watchlist. Hoort bij MOC-23/OFF-2, niet in de OFF-1-branch gerepareerd. Heette tot 18 september ook OFF2, naast de dode-pills-bevinding; hernoemd in TV0 omdat één ID niet twee problemen kan dragen. |
| OFF3 | `test/goldens/tv_discovery_landing_production_golden_test.dart` faalt op main: `_FakeClient` mist `fetchRecentlyAdded`/`fetchRecentlyAddedShows`/`fetchRecentlyWatched` | FIXED | `55cb946a`, `c9ed3d8a` | Gevonden tijdens de OFF-1-mergeronde (14 september), lokaal gereproduceerd op een branch die main_screen.dart/tv_top_navigation niet raakt: dus een bestaande regressie op `main`, niet door OFF-1 veroorzaakt. `MediaServerClient` heeft ergens deze drie methodes gekregen; de test-eigen `_FakeClient` (noSuchMethod-stub, `test/goldens/tv_discovery_landing_production_golden_test.dart:194`) was niet meegroeid, dus de discover-rijen bleven leeg en de golden week 20.94% af. Fix in `55cb946a`: de drie methodes gestubd op `_FakeClient`, naar de `MediaServerClient`-interface. Daarna faalden dezelfde 8 tests niet meer op `NoSuchMethodError` maar op echte pixel-diffs, want de discover-rijen zijn niet meer leeg. Goldens geregenereerd via dezelfde runner-route als GOLD1/GOLD2: `.github/workflows/goldens.yml` (run `34865938882`) op `test/goldens/tv_discovery_landing_production_golden_test.dart`, artifact terug, met de hand gecommit als `c9ed3d8a`. Lokaal (macOS) blijven dezelfde 8 tests rood met dezelfde pixelaantallen, verwacht: GOLD1/GOLD2-patroon, alleen op de Linux-CI-runner te verifiëren. Bevestigd op de CI-runner zelf (PR #28, run `34866830222`): Unit Tests ging van 31 naar 23 falers, exact de 8 OFF3-tests minder, geen nieuwe. De resterende 23 zijn WL3 (1, al apart getrackt), PLR4's drie 1080p/900p/720p-goldens (al FIXED, bekende omgevingsruis), veertien overige golden-tests over `tv_media_source_picker_golden_test.dart` (7), `tv_discovery_golden_test.dart` (5) en `tv_root_shell_golden_test.dart`/`tv_detail_source_line_golden_test.dart`/`tv_unified_catalog_states_golden_test.dart` (2+2+1, laatste al genoemd bij CAT1), zelfde CAT1/GOLD1/GOLD2-patroon, niet apart geregenereerd in deze taak, en twee niet-golden falers die een eigen bevinding kregen: zie CTA1 en HTTP1. PR #28 |
| OFF4 | Code Analysis-CI faalt op main op `avoid-unnecessary-setstate` in `lib/screens/seerr/seerr_discover_screen.dart:184`, niet reproduceerbaar lokaal | FIXED | `7a03b8e7` | Gevonden tijdens de OFF-1-mergeronde. Zowel losse-file- als volledige-project-`flutter analyze` op de gepinde 3.44.0-SDK lokaal gaven "No issues found"/geen warning-niveau treffers (58 info-only issues); de Linux CI-runner gaf deze warning wel, twee keer op rij (ook na een herrun). De regel bleek geen loze flakiness: `initState` riep `_onSearchChanged(initial)` synchroon aan om een meegegeven zoekterm te tonen, en die methode roept zelf `setState` aan. `setState` tijdens `initState` is overbodig, de eerste build leest de velden toch al zoals ze staan zodra `initState` terugkeert. Fix in `7a03b8e7`: de twee velden die `_onSearchChanged` zou zetten direct toegewezen, dezelfde debounce gestart, zonder `setState`. Bevestigd op de CI-runner zelf (PR #29, run `34867985013`): Code Analysis is groen, de regel komt niet meer terug. Lokaal reproduceerde de waarschuwing nooit, dus geen lokale negatieve controle mogelijk; de fix is geverifieerd door gedragsvergelijking met `_onSearchChanged`'s niet-lege tak en door de CI-run zelf |
| CTA1 | `test/theme/no_local_cta_shape_override_test.dart` wees de twee bewust pilvormige CTA's van mobiel detail af | FIXED | `cb81ea20` | GATE0 (20 september): rood bevestigd op de actuele regels `mobile_detail_view.dart:281` en `:329`. De twee full-width capsules zijn onderdeel van de goedgekeurde mobiele northstar, daarom staat het bestand nu expliciet en met reden in de allowlist; de vorm uit productie verwijderen zou de compositie wijzigen. De gerichte GATE0-run is 7/7 groen en `scripts/ci_checks.sh` is groen. Geen tvOS-productiecode gewijzigd |
| HTTP1 | De test beloofde dat `closeGracefully` na een drain-timeout opnieuw kon wachten, terwijl de productiecode bewust één harde shutdown-deadline bewaart | FIXED | `cb81ea20` | GATE0 (20 september): rood bevestigd doordat de tweede close-future al voltooid was. Het oude retrycontract kon de harde deadline telkens resetten en zo een native client onbeperkt vasthouden. De test legt nu vast dat herhaalde close-calls dezelfde future delen; afronding van de actieve response sluit de inner client nog steeds. De gerichte GATE0-run is 7/7 groen en `scripts/ci_checks.sh` is groen |
| HERO6 | Terug op Home vanuit een Verder kijken-item staat de ring op de topnav, de feed gescrold, en Hervatten en Details bekijken staan dwars door de navigatiebalk (foto 14 september). Voorrang boven OFF3 t/m OFF5 op verzoek van Michel. Verificatie alleen in de simulator, geen device-run. Gereproduceerd in de tvOS-simulator met alleen twee keer omlaag en Menu vanaf de rij: de ring op Home, de feed op 721 px, de CTA-rij op y=19 zichtbaar. Oorzaak in `TvContentFeed.build`: `textOpacity` hing alleen aan `_rowHasFocus`, dus zodra de focus de feed verliet zonder te scrollen kwamen titel en CTA's terug op de verschoven plek. Fix: ook verbergen zolang de feed niet bovenaan staat (`_rowHasFocus \|\| !_atTop`); `_revealHero` zet `_atTop` terug zodra een CTA de ring krijgt. Negatieve controle `HERO6: a scrolled feed keeps the hero text hidden when the focus leaves the rows` in `tv_content_feed_test.dart`: rood op `textOpacity == 0` tegen de oude code, groen erna, 70 tests groen. Nieuw Verify-scenario `tvos.home.hero-cta-hidden-scrolled` (via `discover.hero` `state.textVisible`) PASS in bundel `-1789383221540`; `tvos.home.hero-return` PASS. `tvos.home.hero-return-from-route` faalt, maar identiek zonder deze wijziging: zie HERO7. De 11 falende `tv_home_production` goldens falen lokaal met en zonder de wijziging met dezelfde pixelaantallen | VERIFIED | `5bac502e` |
| HERO7 | Terug van een detailpagina (Menu) herstelde Home de focus niet op de tegel waar de push vandaan kwam: de content-scope daalde af naar `tvHeroPlay`. Runtime-instrumentatie in `_popTvNestedRoute` toonde aan dat de gedeelde `contentFocusScope` zijn focusgeschiedenis kwijtraakt zodra `MediaDetailScreen`'s eigen gerelateerd-rij (`TvBrowseRail`, met een eigen `FocusScopeNode`) uit de boom verdwijnt: die scope-geschiedenis is dus geen betrouwbaar route-herstelcontract zodra een geneste route zijn eigen focusbare rail heeft. Fix: een expliciet contract (`TvFocusRestoreTarget`/`TvFocusRestoreHost` in `tv_navigation_coordinator.dart`) waarbij het oppervlak dat een pop weer zichtbaar maakt zijn eigen kaart opzoekt op `groupId`/`containerId`, met de ambient scope alleen nog als laatste fallback. Home (`TvContentFeedState`) en de complete catalogus (`TvUnifiedCatalogScreen`) implementeren de host op bestaande mechanismen (`TvDiscoveryRail.focusGroup`, een nieuwe `TvCatalogCardGrid.focusItem` naast de bestaande `focusGrid`); `restoreFocusKey` (Mijn Pleya) blijft ongewijzigd ernaast bestaan. Vijf tests: de twee focusrestauratie-paden (Home-rij, complete catalogus) plus hun negatieve controles (kaart/rij weg → `false`, geen foute buur), en een `TvNestedRoute`-contracttest dat het target de pop overleeft. `tvos.home.hero-return-from-route` PASS op de simulator (bundel `tvos-home-hero-return-from-route-1789394041916`), `scripts/ci_checks.sh` groen | VERIFIED, hardware open | `ee2901b5` |
| OFF2 | De offline topnav toont focusbare dode pills | FIXED, testrun groen, hardware open | `472233db`, `267e6dc1` | `buildTvDestinations` kreeg een offline-conditie (`472233db`); een Codex-challenge en een parallelle `/code-review` vonden daarna twee regressies in diezelfde fix (verweesde nested routes, een geklauwde reconnect-restore), beide gefixed met eigen tests in `267e6dc1` |
| FOC1 | Als de gefocuste TV-topnav-pil verdwijnt (Live TV die wegvalt, of sinds `472233db` elke offline-flip), zet `TvNavigationCoordinator` de logische `_focused`/`_active` wel om, maar niets roept `FocusNode.requestFocus()` aan op de vervangende pil. `_focus`/`_focusKey` in `tv_top_navigation.dart` lopen alleen op een expliciete D-pad-stap (`onNavigateLeft`/`onNavigateRight`), niet op een balkherberekening. Gevonden door een Codex-challenge op `472233db`; bestond al voor de Live TV-casus, offline maakt hem alleen vaker bereikbaar. **Gefixed:** `_profileFocusKey` in `tv_top_navigation.dart` publiek gemaakt als `tvNavProfileFocusKey`, plus een nieuwe `tvTopNavFocusKeys()` die alle sleutels teruggeeft die de bar op dit moment tekent. `TvRootShell` pruned `FocusMemoryTracker` daartegen in `build`, zoals `side_navigation_rail.dart:816` voor de rail al deed, en herstelt de focus post-frame op de bestemming die `updateConditions` al gekozen had. Negatieve controle in `tv_root_shell_test.dart` (groep FOC1, drie tests) was rood tegen de export vóór de fix er stond, groen erna; de export en de fix zijn samen gecommit omdat de project-CI geen tijdelijk ongebruikte export toelaat. Bredere sanity-check (`test/screens/tv/`, `test/widgets/tv/`) ongewijzigd: 603 groen, 1 rood, dezelfde vooraf bevestigde bestaande faler (`tv_top_navigation_test.dart`, OFF-1). **CODE CLOSED**: de fix staat en de negatieve controle bewijst hem. Geen widgettest construeert vandaag `MainScreen` samen met `TvRootShell`, dus het reconnect-samenspel (`main_screen.dart:1714`) is los bevestigd via `test/screens/tv_offline_focus_recovery_test.dart` (3/3 groen); een fysieke-hardwareronde op een echte Apple TV heeft dit niet bevestigd. Een adversarial `/code-review high` op de volledige werkboom vond dat de post-frame-callback geen `isNavFocused`-guard had, tegen het rail-precedent (`side_navigation_rail.dart:362`) in: een late callback trok focus terug naar de bar ook als de remote intussen legitiem naar de content was verhuisd. Gefixed met dezelfde guard plus extractie van de prune-en-herstel-body naar `_pruneNavFocusAndScheduleRestore()`, gedrag-gelijk op de guard na. Vierde test bewijst de rode fase (guard verwijderd: `hasFocus` bleef `true` waar `false` verwacht werd) en de groene fase erna | CODE CLOSED · VERIFY/SIM OPEN | `da0693d2`, `cbc87def`, `8d5fa38a` |
| SRCH2 | `people` wordt nooit aan `searchProjection` meegegeven | FIXED, testrun groen, hardware open | `b5b8f0e8` | Gebouwd binnen I4 (iOS Zoeken), zie DEC-112. Nieuwe `PersonSearchClient`-fanout in Plex en Jellyfin vult `people` nu. TV's eigen people-rij riep voorheen `_openConcrete` aan op een lege lijst en is nu gekoppeld aan `_openPerson`. Jellyfin-pad live bevestigd in de iOS-simulator tegen de Pleya Demo-server; Plex `/hubs/search` blijft ongeverifieerd tegen een echte server, en de TV-rij zelf is niet op fysieke hardware bekeken |
| REV1 | Apple Review Jellyfin: Home toont content, Films/Series leeg en concrete library niet zichtbaar (Apple Review, release-kritiek). Root cause: elke synthetische Jellyfin-hub droeg een hardgecodeerd type `mixed` (next-up `episode`), en `UnifiedHubKind.singleKindSurface` sluit beide uit van de Films- en de Serieslanding. Gesloten door `JellyfinMappers.syntheticHub` het type te laten afleiden uit de al gemapte items via `_hubItemsType`, zelfde aanpak als VER4 bij de Pleya-protocolclient | FIXED | `ce8648ae`, `ee117859` |
| REV1b | Tweede helft van REV1: een concrete, zichtbare Jellyfin-library lijkt niet bereikbaar via Mijn Pleya > Bibliotheken. De voorgeschreven keten is afgelopen: `_libraryKindFromCollectionType` mapt een onbekend `CollectionType` op `MediaKind.unknown` (jellyfin_mappers.dart:316-333), en `eligibleCatalogLibraries` laat `MediaKind.unknown` expliciet door ongeacht de gevraagde kind (source_cursor.dart:70). De "niet eligible"-hypothese valt daarmee af. De Jellyfin-mapper zet `hidden` bovendien altijd hardcoded op `false` (jellyfin_mappers.dart:248), dus een serverzijdige hidden-vlag kan de library ook niet laten vallen. Wat overblijft, `isServerVisible` (per-profiel zichtbare-serverslijst) en `hiddenLibraryKeys` (lokale per-profiel hide-lijst uit `HiddenLibrariesProvider`), is lokale profielstaat op het geteste toestel, niet iets dat uit de servertopologie of de code alleen volgt. `.env` ontbreekt in deze worktree (`scripts/tvos_sim.sh doctor` meldt `demo-login: ontbreekt in .env`), dus een geautoriseerde `/Users/{userId}/Views`-call kon niet gezet worden; `System/Info/Public` op `demo.pleya.app` bevestigt wel een bereikbare, echte Jellyfin-server (12.1.0, `Pleya Demo`). Geen enkele schakel uit de keten wijst een defect aan | HARDWARE ONLY | n.v.t. |
| REV1-MERGE | Gevonden door de whole-branch review van TV2. `MediaHub.type` is niet alleen een landingroutering-invoer: `UnifiedHubKey.forHub` neemt hem op in `semanticType`, en de merge-sleutel voor het samenvoegen van gelijknamige rijen over servers heen (`HomeProjectionService._effectiveKeys`) rekent daarmee. Vóór REV1a was elke Jellyfin-hub hardgecodeerd `mixed`, dus twee Jellyfin-servers met dezelfde `home.recent` kregen altijd dezelfde merge-sleutel. Na REV1a hangt het type af van de content, dus twee Jellyfin-servers waarvan `home.recent` verschillend classificeert (de één puur films, de ander echt gemengd) produceren nu twee gelijknamige rijen die eerst samenvoegden. `continue`/`ondeck`/`nextup`-hubs worden al vóór projectie weggefilterd (`discover_provider.dart:607`), dus die zitten hier niet in; `library.<id>.*`-hubs worden sowieso nooit cross-server samengevoegd. Voor Jellyfin-plus-Pleya-Server geldt het omgekeerde: die twee komen na REV1a juist weer overeen met VER4's precedent op `home.recent`. Geen enkele bestaande test raakt `UnifiedHubKey`/`projectHubs` met een REV1a-gevoelige hub, dus dit gedrag is onbewezen, niet gebroken. Geen codewijziging in TV2: dit is een documentatiepunt voor de eerstvolgende keer dat cross-server Home-rijmerging wordt aangeraakt, of voor een Verify-scenario in TV8 dat twee Jellyfin-servers met een verschillend geclassificeerde `home.recent` samenbrengt | OPEN, gedocumenteerd gevolg | n.v.t. |
| REV1-SIZE | `lib/services/jellyfin_client/parts/browse.dart` staat op 1855 regels, ruim over de eigen richtlijn van ~400-500. Niet gesplitst in REV1: de fix verving alleen argumenten en een splitsing zou de gedragswijziging in een onleesbare diff hebben verstopt. Opsplitsen is een eigen ronde met eigen bewijs, zoals LIB1/LIB2 al vaststelden voor `libraries_screen.dart` | DEFERRED | n.v.t. |
| LAND7 | Actieve discovery-rail krijgt geen vaste verticale focuspositie op de Films-/Series-landing en Zoeken. TV2-preflight (18 september, `330a51e4`): Home is geen probleemoppervlak meer, `tv_content_feed.dart:639` geeft `TvHomeLayout.rowTileScrollAlignment(...)` door aan `tv_content_row.dart:65` (default `0.5`, geen andere aanroeper), dus Home heeft het canonieke anker al sinds HOME1/DEC-095. Gesloten voor de Films-/Series-landing door dezelfde `TvHomeLayout.rowTileScrollAlignment`-waarde te zetten, ongeacht welke rail de focus heeft: één anker in plaats van een per-rail positie. Negatieve controle stond rood, groen na de fix; `test/screens/tv/` (373/373) en `flutter analyze` op de geraakte bestanden schoon. LAND2, LAND3, LAND4 en LAND5 zijn niet heropend, hun tests bleven groen. Zoeken en Ontdekken kregen dit anker niet: `TvCatalogCardRail` heeft geen `tileScrollAlignment`-parameter, en die aan een tweede railfamilie toevoegen om vier regels te delen zou een tweede focus-mechanisme zijn, wat de non-goals van deze taak verbieden. Zoeken heeft bovendien zijn eigen probleem (SEARCH2) en geen vergelijkbare klacht. Bewust buiten scope, niet vergeten | FIXED voor de landing, Zoeken en Ontdekken bewust buiten scope | `1f69a855` |
| LANG1 | Taalcontinuïteit binnen series: hiërarchie, terugvalcontract en beheer van serievoorkeuren (sectie G). Ontwerp goedgekeurd, DEC-096 accepted. Data- en resolutielaag op eae19cb4, de pagina 31 A, de sheet 31 B en de toasts 31 C/D op a9a50ad9, de layout- en meldingscorrecties uit de simulatorronde op a5730f35. Het Verify-scenario is groen; de hardwareronde staat open. TV0 (18 september): gelijkgetrokken met register MOC-31. Het scenario is groen op `a5730f35` en `git log a5730f35..HEAD` op de geraakte bestanden is leeg. Er is geen implementatiewerk meer; de hardware-acceptatie hoort bij closure §7 | CODE/SIM CLOSED · HARDWARE OPEN | eae19cb4, a9a50ad9, a5730f35 |
| HERO3 | De Home-hero toont niet alleen recent uitgebrachte films: "Recent uitgebracht" had geen tijdvenster, en items zonder releasedatum reden mee op `addedAt`. Besluit 5 september: 90 dagen op releasedatum, zonder datum buiten de hero (DEC-097). Op de Apple TV bekeken op 5 september 2026, met "lijkt opgelost" als oordeel: de melding is weg, en de bibliotheek van Michel houdt genoeg over om de hero te vullen | VERIFIED | `531ae19c` |
| PLR1 | Tekst van de spelerlaag valt links buiten het title-safe gebied (titelbalk op x = 0, tijdlijn op 24 pt) terwijl elke andere TV-surface `tvPageInset` betaalt. Bevestigd op de Apple TV op 5 september 2026: titel, seizoen/aflevering en tijdlijn staan vrij van de linkerrand | VERIFIED | `36118056` |
| WALK | Een `walk`-stap in Pleya Verify die een richting herhaalt en per hop meldt welke focusbare kandidaat is overgeslagen, zodat sprongen niet meer per geval op het toestel gevonden hoeven te worden. Kern in `c4ffcd16` (DEC-098), `nav.profile` en de vier scenario's in `a9f69f18`, alle vier groen op de simulator, beide sabotagecontroles aantoonbaar rood | FIXED | `c4ffcd16`, `a9f69f18` |
| HERO4 | Terug op Home na afspelen staat de pagina nog gescrold en de herolaag schuift mee: het artwork loopt boven beeld uit terwijl de CTA-rij op y=19 achter de navigatieband blijft staan. Nagespeeld over het echte drukpad: afspelen haalt de tegel weg, de content-scope daalt af naar de eerste focusbare afstammeling en dat is de Afspelen-pil, dus geen van de drie gehardde ingangen komt eraan te pas. Het contract hangt nu aan de carrousel die focus krijgt. Bevestigd op de Apple TV op 5 september 2026 | VERIFIED | `20e2bb37`, `17d47592`, `04152ca4` |
| NAVSEL1 | `tvos.nav.destination-select` sprak de app op twee punten tegen: het verwachtte Films na één RIGHT vanaf Home terwijl Series daar staat, en het eiste een Select om van bestemming te wisselen terwijl focus dat sinds 2 september zelf doet. Gedraaid, rood op de eerste, en verwijderd; `tvos.nav.focus-switches-destination` dekt het en is groen | FIXED | `17d47592` |
| HERO5 | `test/screens/discover_screen_tv_hero_test.dart` stond rood op `main`, acht tests, als nasleep van HERO3: het 90-dagenvenster kreeg een clock-seam voor tests, maar dit bestand gebruikte hem niet en las dus de wandklok. De harness pint de klok nu op 2026-06-01 en `_movie` geeft een dateloze fixture een releasedatum, want DEC-097 zet een film zonder datum per contract buiten de hero. Fixture-datums zijn niet verschoven. Negatieve controle: de seam een jaar vooruit reproduceert de acht rode tests | FIXED | `7ade2bc9` |
| RAIL1 | `test/widgets/tv_discovery_rail_test.dart` stond rood op `main`, vijf tests. Geen defect: twee toetsten de afspraak die LAND2 verving, twee lazen "welke tegel is actief" af aan een blok dat sindsdien focusgebonden is, en de vijfde zocht met een exacte string naar een label dat samengevoegd in de node van de kop staat. Herschreven naar wat er nu geldt, met een sabotagecontrole op de focusgate | FIXED | `9179ac2e` |
| GOLD1 | Negentien catalogusgoldens tekenen sinds CAT5 iets anders en zijn bewust niet bijgewerkt; CI is daarop rood en op niets anders. Ze zijn alleen op dezelfde Linux als CI te regenereren: macOS rasteriseert tekst anders, en een geëmuleerde amd64-container dithert de verlopen anders, gemeten op ongewijzigde code als 45 procent pixeldiff over alle negentien. Michel koos op 5 september de runner-route. `.github/workflows/goldens.yml` draait `flutter test --update-goldens` op de CI-runner en geeft de gewijzigde PNG's als artifact terug; de workflow schrijft niets naar de repo, want een golden die zichzelf goedkeurt bewijst niets. `tv_catalog_films_header_focused.png` vervalt voor `tv_catalog_films_rail_open.png` en moest met de hand weg. Michel draaide de workflow op 6 september (GOLD1-run 34029671870) en committede de negentien PNG's als `11bd8b5f`. CI - Sanity Checks stond daarna nog rood, maar de Unit Tests-job (waar de goldens in zitten) was groen; het rode restje was Code Analysis met dezelfde `dart_code_linter`-waarschuwingen die ook al op de vorige commit stonden, dus losstaand van GOLD1 (zie de flaky-precommit-notitie). De vervallen `tv_catalog_films_header_focused.png` bleek nog in de repo te staan zonder enige testreferentie; verwijderd | FIXED | `11bd8b5f`, `3ab4061c` |
| SRC1 | Twee gekoppelde Plex-servers, beide online, en het filterpaneel van Alle series toont er één bij Servers. Gemeld door Michel op 6 september 2026, bevestigd met een device-log (upload-ID 12e1y). Pad 1 (`fetchServers` laat een resource stil vallen) uitgesloten: beide servers kwamen terug uit `/resources`. Pad 3 (bibliotheken niet opgehaald) uitgesloten: geen `Failed neutral library fetch`-regel. Het was pad 2, en specifieker dan verwacht: de tweede server verbond niet omdat de reconcile-pass met het verse, correct gescoopte token uit `/resources` werd geblokkeerd door de `_unreachableSince`-30-secondenmemory die de eerdere, cache-gebaseerde poging had gezet. Die memory is bedoeld om een stortvloed van aanroepers met dezelfde data tegen te houden, niet een aanroeper met echt andere data. Gerepareerd met een `retryRecentFailures`-parameter. Een codereview vond dat de eerste versie hem alleen op de reconcile-aanroep zette; de twee synchrone fallbacks in `_bindPlexHome` en `_bindLocalPlexConnection` hadden dezelfde blootstelling en zijn in dezelfde ronde alsnog gedekt | FIXED, hardware open | `PENDING` |
| ROW1 | Eigen rails op Home, samengesteld door de gebruiker: je legt een filter vast en de inhoud daarvan wordt een rij. Bedienbaar op Home zelf, niet weggestopt in Instellingen, en de volgorde is daar ook te wijzigen. De hero en Verder kijken blijven statisch en zijn niet te verplaatsen. Gevraagd door Michel op 5 september 2026. Mockup 32 (A1a, A1b, A2, B, C1 tot en met C4) goedgekeurd op 5 september, DEC-100 accepted, 9.1, 17.5 en 23 aangepast. Gebouwd op 6 september in twee delen: het model, de opslag en de rij op Home, daarna de twee ingangen, het bewerkpaneel en de driestapsflow. Recent uitgebracht is daarbij de layout in gegaan, zoals mockup 32 B hem tekent | FIXED, hardware open | `040c939a`, `db1bc994`, `a721013d` |
| ROW1b | Op pointerplatforms tekende Home nog geen eigen rijen en kende `HomeLayoutScreen` ze niet. `mediaHubFromCustomRow` (`home_row_layout.dart`) projecteert een eigen rij naar de legacy `MediaHub`-vorm die `HubSection` en `HomeLayoutScreen` al tekenen, met de rij se eigen `contributingRowId` als `identifier` in plaats van `hubId`. Onderweg bleek `homeRowId` die `#custom:`-vorm te wikkelen in `serverId:identifier`: een eigen rij op desktop kreeg zo een andere id (`:#custom:<id>`) dan waar `HomeLayoutProvider.saveCustomRow`/`removeCustomRow` al tegen opslaan (`#custom:<id>`), dus verbergen/herordenen had niets gedaan. `homeRowId` herkent de vorm nu en laat hem ongewikkeld. `DiscoverScreen` zet eigen rijen vóór de backend-hubs (DEC-100 (5)) en toont alleen zichtbare, niet-lege rijen (DEC-100 (6)); `HomeLayoutScreen` toont ook lege rijen zodat een viewer ze terug kan zetten. Negatieve controle in `home_row_layout_test.dart` was rood zonder de `homeRowId`-fix | FIXED, hardware open | `4a20deff` |
| ROW1c | De laatste kaart van een eigen rij is een tegel "Alle N, in Alle films" die de catalogus met datzelfde filter opent (DEC-100 (2), mockup 32 A2). `UnifiedHubViewAll` bleef ongemoeid (hoofdstuk 10.2a's architectuurgrens); in plaats daarvan bouwt `HomeCustomRowsProvider.viewAllTargetsByHubId` een parallelle map van rij-hubId naar `HomeCustomRowViewAllTarget`, die `TvContentFeed` per rij aan `TvContentRow` doorgeeft. `TvDiscoveryRail` kreeg een optionele `viewAll`-tegel: `itemCount`, de stop op de rechterrand, een eigen focusnode en de semantics zijn aangepast, elke bestaande rail zonder `viewAll` blijft ongewijzigd. `TvUnifiedCatalogScreen` kreeg `initialFilterOverride`: opent met het rij-filter, schrijft niets terug (Michels besluit 6 september: tijdelijk venster, niet blijvend), een bewuste wijziging tijdens dat bezoek blijft gewoon opslaan. Vier gerichte widgettests op de tegel plus een provider- en een screen-test. Hardware- en golden-bewijs staan nog open: geen nieuwe golden toegevoegd, de visuele tegelstijl is niet tegen mockup 32 A2 getoetst | FIXED, hardware en goldens open | `825316d5` |
| ROW1d | `home_custom_rows` staat niet in `PreferenceSyncPolicyRegistry` (`lib/services/preferences/preference_sync_policy.dart:390` registreert alleen `home_row_order` en `hidden_home_rows`). `SettingsExportService.syncBaseKey` strippt het `user_<uuid>_`-voorvoegsel onvoorwaardelijk en toetst daarna aan zijn eigen denylist, dus de sleutel gaat de export in; bij import beslist `isUserScopedBaseKey`, en dat delegeert naar `isProfileScoped`. Een niet-geregistreerde sleutel valt terug op `localOnly` met scope `deviceLocal`, dus hij landt ongescoopt en is daarna onzichtbaar voor de provider die de gescoopte sleutel leest. De import meldt succes en de rijen komen niet mee. Er hangt ook geen `PreferenceRefreshFamily` aan, dus een remote apply of een import herlaadt `HomeLayoutProvider` niet voor deze sleutel. Uit de reviewronde van 6 september, de enige van de dertien die data raakt Gesloten door de sleutel te registreren naast zijn twee broers, die dezelfde provider bezit, en door alle drie in de denylist van de exportservice te herhalen zodat het `exportable: false` van de registry ook echt geldt. De volledigheidstest las alleen sleutels die via een `...Pref(...)`-constructor gedeclareerd zijn en zag de kale `static const String _keyX`-constanten van `StorageService` niet; die derde patroonregel is erbij, en noemt de sleutel bij naam zodra de registratie weg is. Drie negatieve controles waren aantoonbaar rood | FIXED | `ca55d656` |
| ROW1e | `TvPanelButton` heeft geen `onNavigateDown`-parameter (`lib/widgets/tv/tv_panel_primitives.dart:63`), dus `TvHomeEntryRowTile` bedraadt DOWN alleen op de twee pijlknoppen. `_step(index, primary, 1)` en `_step(index, remove, 1)` in `tv_home_customize_panel.dart:363` zijn daarmee dode code, en DOWN vanaf Verbergen, Bewerken of Verwijderen valt terug op Flutters geometrische traversal, precies wat de doccommentaar in `tv_home_row_tiles.dart` zegt te voorkomen. Door beide reviewrondes onafhankelijk gevonden Gesloten door de parameter aan de gedeelde knop toe te voegen en de twee kolommen hem te laten binden; de clamp in `_step` doet de rest. Twee negatieve controles waren rood. De derde niet: RIGHT vanaf de laatste knop van een rij bleef al staan, want rechts is daar niets, en die staat er als contracttest bij | FIXED | `5b2ce68d` |
| ROW1f | De wizard opent met de ring op Annuleren. `_footer(scale)` wordt gretig in de `Column`-children gebouwd terwijl de stapinhoud in een `LayoutBuilder` zit, dus `_nodeFor('footer.back')` is de eerste aanroep en pakt de initial-focus node (`tv_home_row_wizard.dart:142`, `:229`, `:505`). Eén Select en de wizard is dicht Gesloten door de eerste stop met naam te noemen, de soort die gekozen is, in plaats van hem aan de bouwvolgorde over te laten. De overlay vraagt de focus pas in de tweede post-frame callback aan, dus een node binnen de `LayoutBuilder` is dan aangehaakt. Negatieve controle rood op de oude regel | FIXED | `dccc83d6` |
| ROW1g | Een nieuwe rij landt onderaan zodra er ooit een volgorde is opgeslagen. `applyHomeLayoutToUnifiedRows` rangschikt een id dat niet in `order` staat als `order.length` (`lib/services/unified_catalog/home_row_layout.dart:57`), terwijl `TvHomeCustomizeController.move` bij de eerste verplaatsing alle id's wegschrijft. De string die we shippen zegt "Lands directly under Continue Watching" en DEC-100 (5) vraagt datzelfde Gesloten door een echt nieuwe rij ook de kop van de volgorde te laten claimen, en alleen als er een volgorde is: er een aanmaken zou van "nooit gesorteerd" stilletjes "wel gesorteerd" maken. De algemene regel dat een onbekend id achteraan rangschikt blijft staan, want voor een backend-hub die er later bij komt klopt hij. Negatieve controle rood op het echte symptoom | FIXED | `d997a81c` |
| ROW1h | Een bronwijziging tijdens een lopende rijlaad gaat verloren. `_load` keert meteen terug als de rij in `_inFlight` zit (`lib/providers/home_custom_rows_provider.dart:163`), en de landende laad vergelijkt alleen de rijwaarde, niet de bibliotheekgeneratie: `refreshAll` wist `_loadedFor`, de landende laad schrijft de verouderde waarde er weer in, en de her-controle in de `finally` ziet dan geen verschil meer Gesloten door een laad de generatie te laten dragen waaronder hij begon: beide helften, de rij én de bronnen, moeten nog gelden voordat een antwoord bewaard wordt. Een antwoord bewaren dat er één mist zou de rij ook als geladen markeren en juist de ronde afzeggen die het rechtzet. Nieuw testbestand `test/providers/home_custom_rows_provider_test.dart`; de negatieve controle telde één laadaanroep waar er twee horen | FIXED | `88c2b181` |
| ROW1i | `CatalogHomeCustomRowLoader` roept `loadMore()` één keer aan en annuleert daarna altijd de lopende cursors, terwijl `_fillBuffers` na het grace-venster van twee seconden bewust cursors laat doorlopen die niet als failed gemarkeerd staan (`catalog_service.dart:335`). Een trage bibliotheek levert dan geen fout en geen inhoud: de rij toont de verkeerde eerste twintig en meldt zich niet partieel, want `failedLibraryIds` blijft leeg Gesloten aan beide kanten. De ronde wordt herhaald zolang er nog iets antwoordt en de rij niet vol is, want er komt geen tweede aanroep waarin een trage bibliotheek alsnog meegemerged wordt; en wat er bij het stoppen nog loopt telt mee als partiële dekking, naast wat gefaald is. De service kreeg `awaitPendingFetches` als publieke seam en `hasPendingFetches` om traag van leeg te onderscheiden. Twee negatieve controles rood | FIXED | `286b25dd` |
| ROW1j | `clearLibraryPreferencesForServer` en `clearLibraryPreferencesForServerEverywhere` (`lib/services/storage_service.dart:301`, `:312`) snoeien `home_custom_rows` niet, dus een rij die naar een verwijderde server wijst blijft als onzichtbare voorkeur staan. Hij levert `HomeCustomRowContent.empty` en verdwijnt daarmee van Home, en als Home daardoor leeg is geeft `TvContentFeed` de lege staat terug vóór de voetregel, dus er is geen ingang meer om hem op te ruimen Gesloten op de bereikbaarheid: de lege staat draagt de voetregel nu ook, en alleen als er eigen rijen bewaard zijn. Het snoeien van `home_custom_rows` in `clearLibraryPreferencesForServer` is bewust niet gedaan. DEC-100 (6) zegt juist dat een rij die leeg raakt in het paneel blijft staan, en een bewaarde rij weggooien omdat een server verdwijnt is onomkeerbaar terwijl die server morgen terug kan zijn. Wat er werkelijk kapot was, was dat je er niet meer bij kon. Negatieve controle rood, met de tegenproef ernaast dat een profiel zonder eigen rijen de kale melding houdt | FIXED | `29ce0bfe` |
| ROW1k | Verwijderen is fire-and-forget zonder vervangend focusdoel: `onRemove: (row) => unawaited(controller.remove(row))` (`tv_home_customize_controller.dart:59`) laat de ring op de node van een rij staan die uit de lijst verdwijnt. Alleen `_move` zet een `_pendingFocusKey`; verwijderen doet dat niet Gesloten door de rij die de plek inneemt de ring te geven, of de rij erboven als er niets onder zit, of Nieuwe rij als de lijst leegloopt, geklemd op een kolom die het doel echt heeft. Twee negatieve controles rood | FIXED | `b44484a6` |
| ROW1l | De `initialFocusNode` van het bewerkpaneel en van de wizard wordt aangemaakt in `showTvHomeCustomizePanel` (`tv_home_customize_panel.dart:108`) en `showTvHomeRowWizard` (`tv_home_row_wizard.dart:66`) en nooit gedisposet. `tv_catalog_sort_panel.dart:87` doet dat wel, onvoorwaardelijk, en is het model Gesloten door het paneel en de wizard hem precies één keer te laten opruimen, wie hem ook vasthield en ook wanneer niemand hem vasthield; dezelfde eigendomsafspraak als `tv_catalog_sort_panel`. Het lek zelf is met de hand nagegaan en niet met een test vastgelegd, want Flutter geeft geen publieke manier om te vragen of een `FocusNode` al opgeruimd is. Wat er wel staat is een dubbele open-en-sluit, want een tweede dispose gooit | FIXED | `73c21d24` |
| ROW1m | Diezelfde node heeft geen doel als `entries()` leeg is: `_nodeFor` wordt alleen vanuit `_entryRow` aangeroepen, dus zonder eigen rijen adopteert niets hem en opent het paneel zonder ring, want `TvHomeNewRowTile` krijgt geen autofocus Gesloten door de eerste stop met naam te noemen: de bovenste pijl van de eerste verplaatsbare rij, en Nieuwe rij als er geen rij is om hem aan te geven. Het gedrag was erger dan gemeld: de overlay valt bij een onaangehaakte node terug op zijn eerste focusbare afstammeling, en dat is Klaar in de kop, dus één Select sloot het paneel dat je net opende. Negatieve controle rood | FIXED | `73c21d24` |
| ROW1n | Het extra-action-pad in `lib/screens/tv/tv_unified_context_menu.dart:116` slaat de `context.mounted`-guard over: `extraAction!.onSelected()` draait na een `await` op een context die de regel eronder wél toetst voordat hij hem gebruikt Gesloten; dezelfde guard als de regel eronder. Geen zinnige negatieve controle zonder de widgetboom te verbouwen: de context moet precies tussen het sluiten van het menu en de volgende regel verdwijnen. De bewaking is de symmetrie | FIXED | `4bd8863e` |
| ROW1o | `_reconcile` keert terug op `_layout.customRows.isEmpty` zonder zijn `_libraryKeys`-baseline bij te werken (`home_custom_rows_provider.dart:217`), dus de eerste bronwijziging ná het toevoegen van een eerste rij meet tegen een verouderde nulmeting Gesloten door de nulmeting altijd bij te werken en alleen het herladen aan de vraag te hangen of er iets te herladen valt. Het gebrek was groter dan gemeld: het gaat niet om een overbodige verversing maar om een gemiste. Een bibliotheekset die verandert en terugverandert terwijl het profiel geen rijen heeft las als geen verandering, en de rij die er tussendoor bijkwam hield het antwoord voor bibliotheken die er niet meer waren. Negatieve controle rood | FIXED | `4bd8863e` |
| CAT6 | `_closeRail` (`lib/screens/tv/tv_unified_catalog_screen.dart:534`) strandt de focus op de drie gridloze staten: `_focusGrid` gaat via `_gridKey.currentState`, en dat is null zolang de skeleton, de foutstaat of een van de twee lege staten getekend wordt. Het pad is bereikbaar omdat `TvCatalogEmptyState` met `onActionNavigateLeft: _openRail` bedraad is, waarna RIGHT of Menu de rail sluit en de ring nergens landt. Hoort bij CAT5, niet bij ROW1 Het mechanisme klopt: `_focusGrid` gaat via `_gridKey.currentState` en dat is null op alle drie de rasterloze staten, dus de aanvraag is daar een stille no-op. Het gevolg treedt niet op. Twee keer niet: de lege staat zet de focus zelf op zijn actie zodra hij het raster vervangt, en de focus scope geeft de ring terug aan het kind dat hij vóór het openen van de rail had. Beide gedragingen zijn van iemand anders, dus ze liggen nu vast in twee tests: de foutstaat, waar de rail alleen via de actie te openen is, en het raster dat onder een open rail vandaan verdwijnt, waar de scope ook geen kaart meer heeft om op terug te vallen. Een eerst geschreven fix met een eigen focusnode is teruggedraaid | NOT REPRODUCED | `609d7cb5` |
| CAT7 | Op zowel Alle films als Alle series valt de focusring om een kaart aan de rechterkant buiten beeld: gemeld door Michel op 6 september met een fysieke foto van "House" in Alle series, ring zichtbaar afgesneden aan de rechterrand van het scherm. Poging tot reproductie op 6 september tegen een verse build (`scripts/tvos_sim.sh build`, HEAD `11838bb6`) in de tvOS-simulator: de rechtermarge van de gefocuste kaart in rij 1 van "Alle series" is pixelgemeten 95 tot 119px op een 3840px-brede screenshot (ongeveer 2,5 tot 3,1 procent), wat overeenkomt met de bedoelde 56 referentie-pixels uit `TvCatalogGrid.forWidth` (`lib/widgets/tv/tv_unified_layout.dart`). Geen clipping zichtbaar, op twee onafhankelijke builds getest. `scrollPadding` reserveert de focusgroei alleen verticaal (top/bottom via `growth`), niet horizontaal, maar de horizontale groei bij `FocusTheme.fullCardFocusScale` (1.06) is met ongeveer 8 referentie-pixels ruim kleiner dan de 56px marge, dus dat klopt met wat de simulator laat zien. Root cause dus niet in de layoutwiskunde gevonden. Vermoeden is een reële TV-overscan- of zoom-instelling op Michels toestel (klassieke "Just Scan"/beeldvullend-instelling), niet reproduceerbaar in de simulator omdat die geen fysieke TV-overscan simuleert. Volgende stap: bevestig op het fysieke toestel of "Just Scan"/pixel-mapping aanstaat vóór dit als layoutbug wordt behandeld | NOT REPRODUCED (simulator), hardware-only totdat overscan-instelling bevestigd is | n.v.t. |
| CAT8 | Jaartal en seizoensregel onder een kaart staan te dicht tegen de onderrand van het scherm, maar alleen wanneer je eerst naar de tweede rij navigeert en dan terug naar de eerste (Michel, 6 september, met foto). Reproductiepoging op 6 september tegen dezelfde verse build: het exacte "rij 2 dan terug naar rij 1"-pad toont in de simulator geen clipping, maar herhaald ómlaag navigeren door "Alle series" (elke rij die niet de laatste van het geladen raster is) toont dat wel, pixelgemeten tot op 0 à 2px van de absolute onderrand van het scherm, ruim binnen hoofdstuk 8.1's verboden buitenste-56px-zone. Bevestigd op twee onafhankelijke builds, dus geen artefact van de eerder gebruikte verouderde build. Vermoedelijke eigenaar: `FocusableWrapper._scrollIntoView` (`lib/focus/focusable_wrapper.dart:369`), dat de scroll-naar-focus-berekening alleen aan de bovenkant beschermt (`projectedItemTop`-check tegen `_focusDecorationPadding`) en geen symmetrische bescherming heeft tegen een berekend doel dat de kaart (titel en metaregel) voorbij de onderkant van de viewport zou zetten. **Root cause niet bevestigd**: drie afzonderlijke widget-testopstellingen, een kale `TvUnifiedMediaGrid` met directe focus-aanvraag, dezelfde met echte pijltjestoetsen via `tester.sendKeyEvent`, en de volledige `TvUnifiedCatalogScreen` met een fake paginated client en echte pijltjestoetsen, laten bij geen enkele configuratie (canvasgrootte, `hasMore` aan/uit, lijstlengte 12 tot 60) een marge kleiner dan ongeveer 86 logische pixels zien, terwijl de simulator met een echte (Jellyfin-demo)server en echte fonts consequent tot 0 à 2px afbouwt. De discrepantie wijst erop dat iets in de echte renderpijplijn (reële lettertype-metrics, echte netwerkafbeeldingen, of het fysieke apparaatformaat) ontbreekt in de widget-testharnas. Geen fix doorgevoerd zonder bevestigde oorzaak: `FocusableWrapper` wordt op tientallen schermen hergebruikt en een verkeerd geraden correctie is een breed regressierisico. Volgende stap: reproduceer via `pleya_verify` tegen een echte simulator-app-run, niet een Flutter widget-test, zodat de volledige renderpijplijn meedoet | DEELS GEDEKT door CAT10 | `57b6e611` | **Aanvulling 7 september.** Het kernmechanisme dat hier onbevestigd bleef is bij CAT10 wél vastgesteld, aan de bovenkant: directionele traversal onthult de rustdoos van de kaart en niet de geschaalde doos, dus de focusgroei valt aan beide uiteinden buiten de viewport. De klem die CAT10 sluit werkt aan allebei de kanten, en `tv_catalog_focus_ring_safe_area_test` meet de onderrand mee terwijl het raster omlaag gelopen wordt. Wat dat níét bewijst is deze melding zelf: die ging over jaartal en seizoensregel tegen de onderrand van het **scherm**, en de viewport is daar niet hetzelfde als het scherm, want `scrollPadding` zet `bottomSafeMargin` onder de laatste rij. De rij blijft daarom open tot iemand hem op hardware naloopt.
| PREF1 | `SettingsExportService.isExportable` beslist op zijn eigen denylist en raadpleegt `PreferenceSyncPolicyRegistry` niet, terwijl de import de registry wél leest via `isUserScopedBaseKey`. Een sleutel die de registry als `exportable: false` heeft staan gaat daardoor tóch de export in, en een sleutel die de registry device-local noemt komt ongescoopt terug. ROW1d heeft dat voor de drie Home-sleutels dichtgezet door ze in de denylist te herhalen. Op Michels besluit van 6 september sluitend gemaakt: `isExportable` roept nu rechtstreeks `PreferenceSyncPolicyRegistry.isExportable` aan, en de oude denylist (`_denyKeys`/`_denyPrefixes`) is weg. Raakt zo'n twintig `_deviceLocalPref`/`_unifiedCatalogViewPref`-sleutels die eerst wel meegingen in een export. Bijvangst: `test/services/icloud_progress_merge_test.dart` bleek een verouderde aanname te testen, `local_progress_`/`local_watched_` zijn sinds de overstap naar `PreferenceSyncCoordinator` al geen live syncpad meer via deze service. Negatieve controle in `preference_sync_policy_test.dart` bevestigt voor vijf sleutels dat de oude denylist ze nooit noemde | FIXED | `0588c48e` |
| CI1 | CI stond op `main` sinds 3 september rood en zei daardoor niets meer over een PR. Drie checks. Codegen-drift op `git diff lib/` na `scripts/codegen.sh`: `analysis_options.yaml` zet `formatter.page_width` op 120, build_runner leest dat niet en emitteert op 80, en de kale `dart format .` uit CONTRIBUTING.md trok elk gegenereerd bestand naar 120. Die stap maskeerde vier latere stappen, die op `skipped` bleven staan, waaronder een formatteringsfout in vijf SYS-bestanden. 79 rode tests, waarvan 50 verouderde golden-referenties, 15 in `discover_hero_activation_test.dart` als HERO3-nasleep, 1 achterhaalde landing-golden, en de rest afzonderlijk gesloten als HERO5 en RAIL1. Volledige suite daarna 6335 groen, 6 overgeslagen, 0 rood, en `scripts/ci_checks.sh` groen. Verify - macOS + iOS simulator staat apart als VER-CI | FIXED | `c0f9427c`, `e76e3f06`, `edc30b6b`, `99442f0d`, `213c6e82` |
| VER-CI | `Verify - macOS + iOS simulator` faalde in alle 34 runs sinds de job bestaat, op twee losse oorzaken. (1) macOS: `flutter build macos --debug` eindigt op "No profiles for 'nl.michelknoop.pleya'"; de hosted runner heeft geen Apple Development-certificaat en de Debug-config vraagt erom, terwijl de driver het geïsoleerde exemplaar toch ad hoc signeert. (2) iOS-simulator: `discover.hero.layout` wachtte op `discover.hero`, maar DEC-097 punt 2 sluit films zonder releasedatum uit en het `/v1`-contract draagt er geen, dus het fixture levert per besluit geen hero; op iPhone en Mac is er dan geen hero-sectie en ook geen fallback-node. Fix: ad-hoc signing via `FLUTTER_XCODE_*` in de workflow-env, en de scenario's `discover.layout` en `discover.layout.macos` bewijzen de DEC-097-fallback op het nieuwe node `discover.continue_watching` (`state.hero_visible == false`, in beeld). Per DEC-083 geen required gate. Bewijs: Verify-run 34031268108 op PR #3, beide stappen groen, de eerste groene run van deze job sinds hij bestaat; `discover.layout.macos` slaagde daarnaast lokaal end-to-end. | FIXED | PR #3 |
| PLR2 | Het veeg-omlaag-infopaneel wordt het enige spelermenu op TV. Gemeld door Michel op 5 september 2026 als "de geluidsinstellingen lijken niet goed te werken", uitgebreid tot het hele paneel per functie. Besluiten: één menu, vier tabs (Info · Video · Geluid · Ondertitels) met secties Weergave/Afspelen en Sporen/Uitvoer, video speelt door, mockup 33 vervangt mockup 19, DEC-101 na akkoord. Ontwerp in `src/pages/33-speler-paneel-*.html`, goedgekeurd op 5 september na drie correctierondes, DEC-101 accepted. Gebouwd: paneel als glaskaart, vier tabs met twee kolommen, subweergaven, `TvPanelRow`-API, tests in `test/widgets/tv_info_panel_test.dart`, scenario `tvos.player.panel.yaml`. De testrun, `flutter analyze` en het scenario wachten op de Mac; hardware daarna | FIXED, testrun groen, Verify + hardware open | `5cb5c33`, `de2e554`, `6d64bbd` |
| PLR3 | Tandwiel en sporenknop in de spelerbalk openen op TV nog de 10-foot `VideoSettingsSheet` en `TrackSheet`, naast het paneel; de sheet toont op tvOS een dode audio-apparaatkiezer omdat `PlatformDetector.isDesktop(context)` op TV waar is (`video_settings_sheet.dart:512,600`). Na PLR2 openen beide knoppen het paneel op het passende tabblad. Gebouwd: `TrackChapterControls.onOpenTvPanel`, `DesktopVideoControls.onTvInfoPanelTabRequested`, `TvInfoPanelRequest`; de sheet-gate is `isDesktopOS()` | FIXED, testrun groen, Verify + hardware open | `5cb5c33`, `de2e554`, `6d64bbd` |
| AUD1 | "Maximum volume" in het Audio-tabblad verhoogt alleen `volume-max` (`tv_audio_subtitle_tabs.dart:36-43`). Op TV is `VolumeControl` verborgen (`desktop_video_controls.dart:1163`), dus het volume blijft op 100 en vier drukken doen hoorbaar niets. Wordt Volumeversterking (Uit / +50% / +100% / +200%) die plafond én `volume` schrijft; inert met uitleg tijdens een bitstream. Gebouwd: `TvAudioTab.applyVolumeBoost`, test "volume boost raises the ceiling and then the level" | FIXED, testrun groen, hoorbaarheid HARDWARE ONLY | `5cb5c33`, `de2e554`, `6d64bbd` |
| AUD2 | Audio- en ondertitelsynchronisatie in het paneel openen zonder gefocust element: `SyncOffsetControl._buildFull` koppelt `sliderFocusNode` niet (`sync_offset_control.dart:341`, alleen `_buildCompact` doet dat op `:249`), dus `_syncSliderNode.requestFocus()` in `tv_info_panel.dart:138` is een no-op. De stapknoppen kleuren met `surfaceContainerHighest`, in dit thema het oppervlak zelf (DEC-053). Gebouwd: `_buildFull` koppelt de node en kleurt met `surfaceElevated` (gedeelde eigenaar); het paneel gebruikt `TvSyncSubView` zonder slider, test "the sync sub-view opens on its value row" | FIXED, testrun groen, Verify + hardware open | `5cb5c33`, `de2e554`, `6d64bbd` |
| PNL2 | Bedienbaarheid van het paneel: pills op een kale `Focus` zonder Select, waarderijen cyclen alleen vooruit op Select (snelheid zeven standen), hoofdstukken springt alleen naar de volgende, `t.common.ok` als aan-waarde van de statistiekrij (`tv_video_tab.dart:174`), lange uitlegzinnen als afgekapte trailing-waarde, geen `automationId` op paneel, pills of rijen, en nul widgettests op `TvInfoPanel`. STR1, STR2 en PNL1 sluiten hieronder mee. Gebouwd: pills op `FocusableWrapper`, LEFT/RIGHT via `onStepLeft/Right`, hoofdstukkenlijst, `t.common.on`, uitleg als subregel, ids `player.panel`, `player.panel.tab[…]`, `player.panel.row[…]`, `player.settings_button`, tien widgettests | FIXED, testrun groen, Verify + hardware open | `5cb5c33`, `de2e554`, `6d64bbd` |
| PNL3 | Select op een pill die al actief is verplaatste de focus niet naar de rijen. `_focusContent` hangt aan `addPostFrameCallback`, en die vraagt zelf geen frame aan; op dat pad zet `_selectTab` niets dirty, dus er kwam geen frame en de ring bleef op de pill staan. Gevonden door de testronde, niet door de review. Gerepareerd met `_afterNextFrame`, dat de callback plant én `scheduleFrame()` aanroept, voor alle drie de focusverplaatsingen van het paneel | FIXED, testrun groen, hardware open | `6d64bbd` |
| PLR4 | Het spelerpaneel is te hoog voor zijn eigen hoogtekap: de twee kolommen van het tabblad Video scrollen in plaats van te passen, waardoor Shaders, Ambient, Automatisch volgende afspelen en Prestatie-overlay onder de rand verdwijnen (Michel, 6 september, foto op hardware, build 264) | FIXED | `5e07551f` |
| PLR5 | LEFT en RIGHT op een waarderij stappen de waarde, dus de kolomwissel is alleen mogelijk als de waarde toevallig aan zijn eind staat: vanaf Beeldverhouding kom je niet bij de rechterkolom zonder de beeldverhouding te wijzigen. Michel vraagt om een rij die je eerst aanklikt voordat LEFT/RIGHT hem verstelt (6 september). Dit wijzigt het paneelcontract van DEC-101 ("Links en rechts stappen een waarde") en gaat dus als besluit | FIXED | `08814bac` |
| PLR6 | Menu sluit het paneel niet op hardware: het paneel houdt de afstandsbediening vast en de app moet geforceerd worden afgesloten (Michel, 6 september, build 264). De Dart-kant is aantoonbaar niet de oorzaak: `Menu closes the panel from a focused row (PLR6 contract)` in `test/widgets/tv_info_panel_test.dart` is groen, dus een Escape-KeyDown bij een gefocuste rij sluit het paneel. Verdachte is het native drukpad; het meegestuurde log `5pyur` dekt alleen de run *na* het geforceerd afsluiten en bewijst niets over de vastloper | HARDWARE ONLY, blokkerend | n.v.t. |
| CAT9 | **iOS.** Op Alle films doet geen enkele chip iets: Bronnen, Filters en Sorteren reageren niet op een tik (Michel, 6 september, build 266). `MobileCatalogScreen` wordt door `MobileLandingScreen._TitleRow` gepusht op de navigator bóven `MainScreen`, en `MainScreen.build` is juist wat de `OverlaySheetHost` plaatst; de gepushte route is dus een broer van de eigenaar van de host en nooit een afstammeling. `OverlaySheetController.of` vond niets: een assertie in debug, een ingeslikte `scope!` in release, dus een dode chip zonder foutmelding | FIXED | `3b0a9b65` |
| CAT10 | De witte focusring om een kaart in rij 1 van Alle series wordt aan de bovenkant afgeknipt nadat je naar rij 2 bent gegaan en weer terug (Michel, 7 september, foto op hardware). **Gereproduceerd op de tvOS-simulator**, build van `efe2eaf3`, op Alle films: in rust staat de bovenrand van de ring op y=445 van 2160 en is hij 506 px breed; na DOWN en dan UP is er tussen y=200 en y=900 geen horizontale ringrand meer te vinden, terwijl de zijkant van diezelfde ring 30 fysieke pixels omhoog is geschoven (van y=493 naar y=463). De ring is dus heel gebleven en de bovenste 30 px zijn weggeknipt. Oorzaak: het raster claimt UP en DOWN tussen zijn eigen rijen niet (`tv_unified_media_grid.dart` bindt `onNavigateUp` alleen op de eerste rij), dus de toets valt door naar `DirectionalFocusAction` en eindigt in `Scrollable.ensureVisible(alignmentPolicy: keepVisibleAtStart)`. Die onthult de **rustdoos** van de kaart, terwijl `FocusableWrapper` hem om zijn midden opschaalt en de ring dus `TvCatalogGrid.focusHeadroom` (~15 logische px) daarbuiten reikt. `scrollPadding` reserveert precies die ruimte, waardoor rij 1 in rust heel is en alleen in rust: `keepVisibleAtStart` legt de rustdoos tegen de viewportrand en scrolt de reservering zelf uit beeld, waarna de `SingleChildScrollView` wegknipt wat erin stond. Een kale widgettest mist dit, want zonder kop erboven landt de scroll terug op offset 0; met de echte paginakop niet. Gesloten door het raster de toegestane offset voor de gefocuste rij te laten klemmen, aan beide uiteinden, ná het frame waarin de traversal zijn zin heeft gehad. **Nagemeten op dezelfde simulator met de fix erin:** in rust bovenrand y=445 en zijlijn y=493, en ná DOWN en UP precies diezelfde twee getallen, waar het vóór de fix geen bovenrand en zijlijn y=463 was. De ring is dus heel en de scroll keert exact terug | FIXED, simulator geverifieerd, hardware open | `57b6e611` |
| CAT11 | De items op de aanvragen- en zoekvensters zijn veel groter dan op Alle films en Alle series en volgen de nieuwe kaarttaal niet (Michel, 7 september, drie foto's op hardware). Drie verschillende oorzaken naast elkaar: zoeken tekent op TV zijn film-, serie- en afleveringsresultaten als `TvDiscoveryRail` (`search_screen.dart:810`), dus in de grote 16:9-tegels van de Home-feed, en laat de overige secties terugvallen op de niet-TV-lijst met `FocusableMediaCard` (`:775`); de Seerr-rasters gaan via `MediaGridGeometry.resolve` met de dichtheidsschuif (`seerr_grid_sliver.dart:45`) in plaats van via `TvCatalogGrid.forWidth`; en `SeerrRequestRow` gebruikt een thumbnail van 44 tot 72 px op diezelfde schuif (`seerr_request_row.dart:55`) en leest de TV-schaal nergens. Hoort bij MOC-13 en MOC-15 en wordt in de mockupronde 34-37 beslecht, niet los gerepareerd | FIXED, hardware open | DEC-108 | Mockup 34 tot en met 36 zijn op 7 september voorgedragen in `docs/assets/tvos-unified/mockups-2026-09-07/`, met bron in `../src/pages/`. Goedgekeurd op 7 september als DEC-108, manifest in `docs/tvos-redesign-34-36-approved.md`. Bij Alle aanvragen is C1 gekozen, het raster; C2 blijft staan als afweging. Bibliotheken is bewust géén nieuwe mockup: mockup 27 dekt bronbeheer in vijf standen, is goedgekeurd onder DEC-092, en state D tekent het openen in de catalogus al mét de CAT5-rail, dus die set liep niet achter. Daar ontbreekt geen ontwerp maar een bouwronde, en die staat als LIB7. **Bouw 7 september.** De kijklijst is over op de catalogustaal: `TvWatchlistView` met de CAT5-rail (Soort, Beschikbaarheid, Sortering, geen Bronnen), het gedeelde `TvCatalogCardGrid` en `TvCatalogCard`, de melding bij onvolledige serverdekking uit 34 C, en de twee lege toestanden uit 34 D. **Bouw 7 september, tweede deel.** Aanvragen is over op de catalogustaal. `TvSeerrRequestsView` maakt van Alle aanvragen een raster met een statuscapsule per kaart en de statusfilter als railsubview met Seerr's eigen aantallen ernaast (35 C1 en 35 D, en dat sluit de Seerr-helft van TOK3); `TvSeerrDiscoverView` tekent Ontdekken als rijen catalogustegels, waarbij "Alles tonen" dezelfde pagina in rastermodus zet in plaats van `SeerrRowGridScreen` te pushen (35 A en 35 B). `TvCatalogCardRail` is de horizontale broer van het raster. De TV-tak is uit `buildSeerrGridSliver` verdwenen in plaats van onbereikbaar blijven staan. Vier afgesproken afwijkingen van de goedgekeurde set, alle vier op 7 september bevestigd: de zoekpil en de inboxknop blijven op Ontdekken staan omdat Seerr-zoeken en Alle aanvragen anders onbereikbaar zijn tot mockup 36 C bestaat; de rail daar draagt Streamingdienst in plaats van Status omdat Seerr's discover-eindpunten geen statusparameter kennen en Status op Alle aanvragen thuishoort, waar `/request` en `/request/count` hem beantwoorden; de metaregel zegt overal "2024 · Film" omdat `SeerrMedia` geen genres parseert; en een railrij opent een subview in plaats van een overlay, wat de enige geopende stand is die de goedgekeurde set voor deze pagina's tekent (35 D). **Bouw 7 september, derde deel.** Zoeken is over. `TvSearchView` vervangt de hele TV-tak van `search_screen.dart`: de resultaten staan in banden van `TvCatalogCardRail` met catalogustegels, elke band onder een `TvSectionHeader` met het aantal erbij (36 B, en dat sluit SEARCH1). De vier bronconcrete secties die hoofdstuk 16.1 apart houdt (collecties, afspeellijsten, personen en de rest) tekenden tot nu toe de niet-TV-lijst met `FocusableMediaCard`, en gaan nu via `TvCatalogItemCard`, de kaart voor een los `MediaItem`. Zonder resultaten staat er 36 C: "Niets gevonden op je servers", met het aantal servers erin, en "Zoek op Aanvragen" dat de zoekterm meegeeft aan Ontdekken in plaats van de oude inline Seerr-rij te tekenen (die rij is `seerrRowMetricsOf`'s telefoontegel) en dus precies waar CAT11 over ging. In rust tekent de pagina 36 A: de titels die uit een zoekopdracht geopend zijn, bewaard in `services/search_recents.dart`. Dat is nieuwe opslag; `search_history` bewaarde alleen de getypte zoektermen, en die blijven wat desktop en mobiel tonen. Eén toevoeging op de goedgekeurde tekening: 36 A tekent geen knop naast de kop, en zonder knop zou deze rij de enige lijst op TV zijn die je niet kunt wissen, want de chips die hij vervangt hadden er altijd een. Wissen leegt allebei de recenties.
| ROW1p | In het Home-aanpaspaneel dragen meerdere rijen tegelijk de focusindicator: drie "Hide"-knoppen tegelijk wit gevuld op de ene foto, vier pijlknoppen tegelijk omringd op de andere (Michel, 7 september, hardware). Er kan er maar één de focus hebben, dus de indicator hangt niet aan de focus. De oorzaak ligt niet bij het paneel maar bij de gedeelde eigenaar: `FocusableWrapper.didUpdateWidget` koppelt een gewijzigde `focusNode` netjes aan en laat `_isFocused` staan op wat de vórige node had. Er komt daarna ook geen `onFocusChange`, want de melding dat de oude node zijn focus kwijt is gaat naar de `Focus`-widget die inmiddels de nieuwe node draagt. Een lijst die zijn kinderen zonder `key` herschikt (`_entryRow` in `tv_home_customize_panel.dart:412`, terwijl de focusnodes op `:178` wél per layout-id gesleuteld zijn en dat daar ook uitleggen) is precies dat geval; het paneel zet de ring daarna zelf terug via `_pendingFocusKey`, dus er komt een slot bij dat zich gefocust weet zonder dat het oude dat ooit heeft ingetrokken, en elke verplaatsing laat er één achter. Gesloten door de wrapper de focustoestand van zijn nieuwe node te laten overnemen, uitgesteld tot na het frame omdat de listener (`TvPanelButton`) `setState` aanroept. Negatieve controle in `test/focus/focusable_wrapper_node_swap_test.dart` telde na één verplaatsing twee slots die zich gefocust waanden waar er één hoort; op de simulator dragen na één verplaatsing twee omlaag-pijlen tegelijk de ring. Nagemeten met de fix erin: na twéé verplaatsingen precies één ring | FIXED, simulator geverifieerd | `87e5c7c9` |
| ROW1q | Datzelfde paneel stond volledig in het Engels op een Nederlandstalige app: "Customise Home", "Hide", "Done", "fixed", "Always second", "Pleya row" (Michel, 7 september). Geen enkele string was hardcoded: de hele subtree `unifiedCatalog.homeRows` (48 sleutels) stond in `en.i18n.json` en ontbrak in `nl.i18n.json`, en `fallback_strategy: base_locale` maakt daar Engelse tekst van zonder dat er iets omvalt. Een volledige sleutelvergelijking legde 119 ontbrekende strings in `nl` bloot, niet alleen deze. Gesloten voor de 55 die op TV zichtbaar zijn (de customizer, `settings.homeLayout*`, de hint van de waarderij uit PLR5, en `unifiedCatalog.filters.activeCount` van de filterrail); het paneel is op de simulator nagelopen en staat voluit in het Nederlands. Met `test/i18n/nl_locale_parity_test.dart` eronder: die vergelijkt `nl` volledig met de basislocale tegen een baseline van 64 bekende gaten die alleen mag krimpen, en faalt óók als een sleutel wel vertaald is maar nog in de lijst staat. De overige 64 staan als I18N6 | FIXED | `06c7148a` |
| ROW1r | De rijenlijst van het Home-aanpaspaneel lijkt onder de onderrand van de paneelkaart door te lopen; op beide foto's staan de onderste rijen half buiten de kaart (Michel, 7 september, hardware). Nagemeten op de tvOS-simulator met hetzelfde paneel open: in een verticale doorsnede door het midden (x=1900 van 3840) valt de helderheid op y=1987 van 48 naar 0 en blijft daar. De inhoud houdt dus op bij de paneelrand en er staat niets buiten; wat er half staat is de vólgende rijtegel, netjes afgekapt door de scrollende lijst. Dat is het gedrag dat `Flexible` plus `SingleChildScrollView` in `tv_home_customize_panel.dart:336` bedoelt te geven, en `tvWidePanelConstraints` levert de hoogtekap die het mogelijk maakt. Geen defect gevonden. Wat er wél ontbreekt is een teken dát er meer is: de lijst heeft geen fade, geen randmarkering en geen positieaanduiding, dus een half afgekapte rij aan de onderrand leest op een televisie als een fout in plaats van als een uitnodiging om door te scrollen. Dat is een ontwerpvraag en gaat mee in de mockupronde, niet als bugfix | NOT REPRODUCED | n.v.t. |
| GOLD2 | `tv_home_production_long_titles.png` tekent sinds ROW1q iets anders: de voetregel onder de Home-feed heet nu "Home aanpassen" met een Nederlandse ondertitel waar "Customise Home" stond. Vastgesteld met een gecontroleerde vergelijking, niet met een aanname: `flutter test test/goldens/` op schone `efe2eaf3` gaf 77 falers, dezelfde run met de vertaling erin gaf er 78, en het verschil is precies deze ene test. De overige 77 zijn de Linux-referenties die op macOS al rood stonden, GOLD1's bekende toestand. Regenereren ging via dezelfde runner-route als GOLD1: `.github/workflows/goldens.yml` (run `34600249163`) met `test/goldens/tv_home_production_golden_test.dart` als invoer, artifact terug, met de hand gecommit. Alle 11 `tv_home_production_*`-referenties zijn verschoven, niet alleen `long_titles.png`: VER3's `railLeadInset`-fix schuift elke Home-rail-tegel `cardFocusRingGap * scale` naar rechts, een verwachte kettingreactie van die fix en geen aparte regressie. Lokaal bijwerken of verifiëren kan niet, want macOS rasteriseert tekst anders dan de CI-runner die de referenties genereert | FIXED | `d734c570` |
| I18N6 | 64 sleutels uit `en.i18n.json` ontbraken nog in `nl.i18n.json` en renderden dus Engels voor een Nederlandse gebruiker: de iCloud-synchronisatie-instellingen, Pleya Server toevoegen, Pleya Share's uitleg, de zoekfoutmeldingen, de logupload-meldingen, Samen kijken, Downloads, en `videoControls.skipIntro`/`skipCredits`/`nextEpisode`. Alle 64 vertaald; `knownGaps` in `test/i18n/nl_locale_parity_test.dart` staat nu leeg, en de parity-test bewaakt dat een nieuwe Engelse sleutel zonder Nederlandse tegenhanger er meteen weer uit valt. Komt uit ROW1q; hoorde onder SYS-5 in het register | FIXED | `b18fafac` |
| CAT17 | Een sorteerkeuze in de catalogus laat de zijbalk open staan en onbereikbaar achter: Menu doet niets, LINKS doet niets, en pas na het scherm verlaten en opnieuw openen is de balk weer te bedienen (Michel, 7 september, hardware, build 268, log `h43qp`). In dat log staat het patroon tweemaal: Select op een sorteerrij, dan de fetch met de nieuwe sortering, dan Escape met `KeyEventResult.ignored reason=fall-through`, en vier keer LINKS `handled reason=onNavigateLeft` zonder dat de focusvlaggen veranderen. Die vlaggen (`up=true,down=false,left=true,right=false`, `onBack=false`) horen bij een gridkaart in kolom 0, niet bij een railrij | FIXED, hardware open | `159f4dab`, `7dc3431b` |
| CAT18 | De app valt terug naar het tvOS-thuisscherm tijdens het scrollen door Alle films (Michel, 13 september, hardware, build 275, log `yp1b1`). Het log begint pas bij de herstart en bewijst dus niets over het moment zelf, en op de Apple TV staat van die dag geen Runner-rapport. Wel stond Runner in het Jetsam-rapport van 30 augustus actief op 581 MB. `TvCatalogCardGrid` bouwt elke rij van elke geladen pagina in één `Column` (de library-doc noemt dat zelf bewuste schuld), en elke kaart houdt zijn gedecodeerde poster levend vast. Flutter's beeldcache mag een beeld dat nog op het scherm hangt niet uitzetten, dus het geheugen groeit lineair met het aantal gescrolde pagina's tot tvOS de app afschiet. Gesloten door de cellen en hun focus-nodes te laten staan (de bedrade traversal blijft dus gelijk) en alleen rijen verder dan zes rijen van de focus via `TvCatalogArtworkScope` het lege vak te laten tekenen. Negatieve controle in `test/widgets/tv/tv_unified_media_grid_test.dart`: bij 400 kaarten hingen er 400 posters in de boom tegen een venster van hoogstens 78, nu groen. Of het geheugen op het apparaat werkelijk vlak blijft is alleen op hardware te zien | FIXED, testrun groen, hardware open | `9263aaef` |
| PLR7 | Het spelerpaneel voelt opgeblazen: rijen en type zijn merkbaar groter dan op elk ander TV-oppervlak (Michel, 7 september, foto op hardware). `tv_panel_widgets.dart` codeert zijn maten hard en leest `TvLayoutConstants.scaleOf` nergens, dus een rijlabel staat op 17px en een rij op 62px waar de 8.3-ladder maal de TV-schaal 0,85 op dit toestel 14,0px en 54px geeft | FIXED, hardware open | `7de9f996`, `7dc3431b` |
| PLR8 | Bij het wijzigen van de zoomfactor wordt het beeld merkbaar donkerder op tvOS en iOS (Michel, 19 september); na de MPVKit-bump naar 1.0.26 op build 286 wordt het beeld groen en crasht de app. De geüploade log is van de herstart en bevat de crash niet. Root cause vastgesteld uit de MPVKit-bron: `should_apply_video_geometry()` in `vo_avfoundation.m` is waar zodra `video-zoom` van nul afwijkt, en schakelt de VO dan om naar een per-frame Core Image re-render (`render_video_geometry_frame`) die een nieuwe CVPixelBuffer maakt, `64RGBAHalf` voor 10-bit bronnen en `32BGRA` voor de rest. De gedecodeerde VideoToolbox-surface wordt dus vervangen door een RGB-buffer. Patch `0018` in 1.0.26 beschrijft datzelfde mechanisme voor Dolby Vision ("the picture collapses to near-black") en schrijft voor: "Hosts that need viewer zoom on this VO should scale the display layer instead." Die guard dekt alleen buffers met een `DolbyVisionRPUData`-attachment, dus HDR10/PQ en HLG gaan nog steeds door de re-render. Tegelijk zette `updateVideoGravityIfNeeded` dezelfde zoom al als CALayer-transform, dus zoom had op iOS/tvOS twee eigenaren. PR #48 stopt het doorsturen van `video-zoom` naar mpv op iOS/tvOS en laat de layer-transform de enige eigenaar zijn; macOS houdt het mpv-pad. Groen beeld en crash zijn passend verklaard maar niet hardwarebewezen. Op de tvOS-simulator bewijst `pleya_verify/scenarios/tvos.player.zoom.yaml` dat de zichtbare zoom overblijft nu mpv de waarde niet meer krijgt: het blok van de fixtureclip meet 2160px bij 100%, 2376px bij 110%, 2592px bij 120% en 2808px bij 130%, en keert exact op 2160px terug | ROOT CAUSE VAST, fix in PR #48, hardware open | PR #48 (`fix/apple-zoom-layer-owned`), nog niet gemerged | Hardwareronde op de Apple TV met hetzelfde bestand als build 286: zoom 1.0, hoger, meerdere niveaus, terug naar 1.0, herhaald wisselen, over SDR, HDR10/PQ en Dolby Vision. **Ondertitelpositie inmiddels gefixed in code**: `VideoFilterManager.effectiveLayerScale` nam `zoomScale` mee in de `sub-pos`-compensatie op iOS/tvOS, terwijl `vo_get_src_dst_rects` die waarde sinds deze PR nooit meer krijgt (alleen `panscan` blijft mpv-forwarded en telt dus nog mee). Pinch-zoom zonder cover-mode schreef daardoor een verschoven `sub-pos` voor een verplaatsing die mpv's OSD nooit maakte. Regressietest `PLR8: pinch-zoom alone does not compensate sub-pos on the layer-owned path` in `video_filter_manager_test.dart` stond rood vóór de fix (verwachtte `80`, kreeg `65` bij scale 2.0), groen erna. Hardwareronde moet dit nu ook visueel bevestigen: ondertitel blijft op zijn plek bij pinch-zoom, schuift wel mee bij cover-mode (panscan) |
| PLR9 | Bijvangst tijdens de PLR8-follow-up (19 september, code-onderzoek, geen hardware): op de retry-na-foutpaden in `video_player_screen.dart` (`_retryWithLowerQuality`, de "Opnieuw"-knop in `_buildInitializationError`) wordt de oude `player` gedisposet en een nieuwe `Player()` aangemaakt, maar `_videoFilterManager`/`_videoPIPManager` in `pip.dart` bleven ongewijzigd staan: `_initVideoFilterAndPip()` zag ze non-null en sloeg herbouw over. De `final Player player`-referentie in de manager bleef daardoor naar de gedisposete speler wijzen, en de `_appliedProps`/`_appliedVideoZoom`-caches dachten dat zoom/boxFitMode/aspect al toegepast waren, dus een volgende `updateVideoFilter()`-aanroep schreef stilzwijgend niets naar de nieuwe speler. Gefixed door `_initVideoFilterAndPip()` de managers te laten herbouwen zodra `_videoFilterManager!.player != currentPlayer`. Geen bestaande testharnas voor `video_player_screen.dart`/`pip.dart` (mpv-integratie, niet unit-testbaar zonder zware mocks), dus geen geautomatiseerde regressietest; alleen `flutter analyze` schoon. Hardwarebevestiging open: zoom instellen, "Opnieuw" na een geforceerde initialisatiefout, en controleren dat zoom/boxFitMode weer schrijfbaar zijn | FIXED (code), hardware open | PR #48 (`fix/apple-zoom-layer-owned`), nog niet gemerged |
| DET1 | Filmdetail: de synopsis wordt afgekapt zonder dat hij te openen is, en de pagina voelt opgeblazen (Michel, 7 september, hardware). Root cause is OVR1a (SYS-3a) op een tweede oppervlak: `detailScale` in `media_detail_screen.dart` las de contentbox van deze route in plaats van `TvDisplayMetrics`, tegen INV-1 in. Mockup 37 (DEC-109) legt de correctie en de nieuwe "Meer lezen"-affordance vast; de mockup-vergelijking op het echte apparaat is niet in deze ronde herhaald | FIXED, hardware open | `dc989713`, DEC-109 |
| UNI0 | Het Pleya Unified 2026 closure-plan is vastgelegd: werkvolgorde, statusladder, releasegate en het protocol van de fysieke eindronde staan voortaan in `docs/unified-2026-closure.md`, en zijn niet meer verspreid over `DESIGN-INDEX.md` en losse plannen. De SHA van de definitieve hardwareronde volgt bij stap 17 van die closure, en wordt dan hier bijgeschreven. Bij PLR6 hierboven: de hardwarebevestiging van die bevinding valt in dezelfde eindronde, niet in een losse tussenstap | VASTGELEGD | zie `unified-2026-closure.md` |
| LOUD1 | Loudness (DEC-111) op Apple aantoonbaar maken zonder serverbewijs (Michel, 11 september): Android staat in het plan stil, iOS/tvOS gaan door. Drie delen: de realtime-keten (`loudnorm`) en de uitschakeling onder passthrough als runtimebewijs op de tvOS-simulator; de loudnessdiagnostiek van `AudioOutputCoordinator` als state op een automation-node, zodat een Verify-scenario `plan` en `af` kan toetsen (stap G van het loudnessplan); daarna een luisterronde op de Apple TV. Productiebewijs per titel wacht op E1 en D5. Gebouwd: `Player.effectiveLoudness` en de state op `player.surface` (`Video._loudnessState`); `pleya_verify/scenarios/tvos.player.loudness.yaml` pauzeert de fixtureclip, toetst `off` met een lege keten, zet Volume gelijkmaken aan in het paneel en toetst `realtime` met `af=loudnorm=I=-22:TP=-2:LRA=9`, en weer uit. Simulator met Sintel (AC-3 5.1 naar stereo-PCM): mpv leest `af=loudnorm=I=-22:TP=-2:LRA=9, loudness=realtime` terug; met passthrough geforceerd gaat `af` leeg vóór `audio-spdif` en komt terug na de terugval naar PCM. Luisterronde op de Apple TV 4K met build 270 (`1cc68b63`): "lijkt allemaal te werken" (Michel, 11 september). Los open, niet van loudness: in de simulator leegde iets de spdif na 300 ms zonder melding bij geforceerde passthrough (DEC-013-terrein) | VERIFIED | `af0e69df` |
| SEL1 | Na het versturen van het systeemtoetsenbord met Return (simulator, idb) is Select in de hele app dood: elke druk logt `consume native keydown logical=enter reason=native-select-already-down`, en de release `suppressed-native-select-down`. De KeyDown van de Return bereikte `AppleTvRemoteTouchService` en zette `_nativeSelectPressed`, de KeyUp ging naar de tekstinvoersessie, en niets wist de vlag daarna (`apple_tv_remote_touch_service.dart:573-632`). Alleen een herstart van de app herstelt het. Gezien tijdens LOUD1 op 11 september; nog niet vastgesteld of hetzelfde op hardware kan, waar de engine een press tijdens een native invoersessie niet synthetiseert. **Gefixed:** `_releaseSelectForNativeSession()` releasede alleen de click-gedreven helft (`_selectPressedFromClick`); hernoemd naar `_releaseSelectOwnershipForNativeSession()` en laat hem ook `_resetNativeSelectBurstState()` aanroepen, zodat een native druk die de sessie opent dezelfde reset krijgt. Negatieve controle vooraf rood (`test/services/apple_tv_remote_touch_service_test.dart`, groep "select ownership across a native session (SEL1)"), na de fix groen, volledige servicesuite (50/50) en de aanverwante native-text-entry/tvos-system-navigation/native-input-session suites blijven groen. Simulator/idb-bevestiging staat hiermee, de open vraag over hardware-reproduceerbaarheid (DEC-019: de engine synthetiseert geen press tijdens een sessie) blijft onbeantwoord. Onafhankelijk herverifieerd bij het landen op `remote-controller` (`834a8012`): `flutter test test/services/apple_tv_remote_touch_service_test.dart` opnieuw 50/50 groen, `flutter analyze` op de geraakte bestanden schoon. **CODE CLOSED**: de fix staat en is dubbel bevestigd; hardware-reproduceerbaarheid van het symptoom zelf is geen blocker voor die sluiting, want de fix repareert de release-mechaniek, niet de reproductieroute | CODE CLOSED, hardware-reproductie niet blokkerend | `f0d7f576`, `51091834` |
| REQ2 | Zoeken op TV, dan "Zoek in aanvragen": er opent een aanvraagvenster in light mode waar je alleen uitkomt door de app af te sluiten (Michel, 11 september, hardware, build 270). `search_screen.dart` pushte `SeerrDiscoverScreen` met een kale `MaterialPageRoute` op `Navigator.of(context)`, buiten de TV-shellroute (`openTvContentRoute`). Gebouwd: `SeerrDiscoverScreen.open(context, {initialQuery})`, één plek die `openTvContentRoute` probeert en pas bij `null` op `Navigator.push` terugvalt; `search_screen.dart` en `seerr_requests_screen.dart` gaan er nu allebei doorheen. Hardware-bevestiging na de fix staat nog open | FIXED, hardware-bevestiging open | n.v.t. |
| REQ3 | Zodra Zoeken op TV resultaten vindt, is de balk "Zoek in aanvragen" niet meer te zien; zoeken in aanvragen kan dan niet meer (Michel, 11 september, hardware, build 270). `tv_search_view.dart` tekende de actie alleen in de CAT14-lege-staat, nooit onder echte resultaten. Gebouwd: een `TvViewAllAction`-rij onder de laatste band, die `_stateActionFocus` hergebruikt; DOWN vanaf de laatste band gaat er nu naartoe, UP terug naar de band. Regressietest `tv_search_view_test.dart` "a way down from the last band opens Zoek in aanvragen" stond rood op de oude implementatie. Hardware-bevestiging na de fix staat nog open | FIXED, hardware-bevestiging open | n.v.t. |
| WL3 | Regressie van WL1: `watchlist_screen_test.dart` "removing the card the remote is on leaves the remote on a card" faalt op `github/main` zelf (`6be0efca`), dus onafhankelijk van deze taak en niet door de merge veroorzaakt. `Expected: true, Actual: false` op "the slot is kept, so the card that slid up into the empty cell takes the ring". Gesloten: de verwijderde kijklijstkaart geeft de ring nu door aan de kaart die in de leeggevallen cel opschuift, in plaats van de ring te laten vallen. `test/screens/watchlist_screen_test.dart` is in zijn geheel groen (51/51) | FIXED | `9963071c` |
| DET2 | Filmdetail toont geen titel/logo en geen synopsis meer, de metaregel en genres staan bovenaan, de actierij overflowt (`BOTTOM OVERFLOWED BY 12 PIXELS`) en de Acteurs-rail plus een stuk Trailers & Extra's vullen de rest van het scherm (Michel, screenshot, lokale build op main/later, geen TestFlight-build). Mockup 37 A is de doelcompositie. Veroorzaker `1805c75e` (MOC-09/MOC-10-compositie): `foregroundBottom` in `_buildTvDetailScreen` telt er `TvCatalogLayout.bottomSafeInset * detailScale` bovenop, en `_tvDetailEpisodeThumbnailScale` ging van 0,8 naar 1,0 waardoor `TvBrowseRailLayout.estimateHeight` via `maxActiveRailHeight` de hoogte van de hoogste hub reserveert, ook als een kleinere hub actief is. `_buildTvDetailForeground` liet bij ruimtegebrek eerst de synopsisregels vallen en dan het logo/de titel zonder ondergrens, dus de `Column` overflowde in plaats van te krimpen. Zie de prose-sectie onderaan voor de fix. iOS-audit (plan-stap 5), Pleya Verify-scenario en hardwareronde nog open | FIXED, iOS-audit + hardware open | `49b35d77` |
| DET3 | Op film- en seriedetail blijft de synopsis ook na de minimale tier (`fb7ceefe`) onzichtbaar op zware hubs: House S8E5 in de tvOS-simulator geeft de informatieband 127 px, de vloer zonder synopsis vraagt 151 px (Michel, 13 september: "ik wil gewoon dat je synopsis kunt zien niet 1 line"). Twee oorzaken die samen optellen. De topnav-band neemt ~83 px, en `_buildTvDetailScreen` reserveert daaronder nog `spotlightTop` (8% van de box, ~80 px), een bovenmarge uit de tijd dat detail het hele venster had. Besluit DEC-116: de dubbele marge verdwijnt onder de shell, en film- en seriedetail krijgen een ingeklapte topnav als routecontract (`TvTopNavPresentation.collapsible`) die bij UP over het detail verschijnt. Geverifieerd in de tvOS-simulator tegen exact deze House-reproductie: synopsis zichtbaar, UP/DOWN/Back correct, geen layoutsprong | FIXED | `ddbd2ce3` |
| DET4 | Seizoenchips op seriedetail: de niet-geselecteerde labels renderen met een verschoven of dubbele glyphrij (tvOS-simulator, House, 13 september). Reproduceerbaar na een herstart, niet in de hero-artwork op dezelfde hoogte en niet in de gedimde topnav-labels, dus geen schermscheuring en geen algemeen probleem met gedimde tekst. Beperkt tot `_TvSeasonChip` in `lib/screens/media_detail/tv_season_chips.dart` (niet `lib/screens/tv/`, dat pad bestaat niet) | FIXED | `518dae18` | TV3 Task 1 vervolgronde (19 september): de vorige ronde had de clamp-blindheid van `tester.getSize` zelf al benoemd als kanttekening (`chipHeight == bandHeight` bewijst geen fit, want `BoxConstraints.constrain` klemt af zonder te falen) en die ambiguïteit is nu opgelost met een tweede assertie op dezelfde test, die `getMaxIntrinsicHeight(double.infinity)` op de chip's `FocusableWrapper`-`RenderBox` leest: een meting die de clamp niet kan maskeren omdat hij geen maxHeight krijgt. Resultaat: **rood**, en niet met de ~7px die de preflight-rij verwachtte, maar met 14: `bandHeight=32.7`, `chipIntrinsicHeight=46.7`. Uitgesplitst via een tijdelijke render-probe (verwijderd voor de commit): de outer ring-`AnimatedContainer` voegt 5px toe (`2 * FocusTheme.focusBorderWidth`), de chip's eigen `AnimatedContainer` voegt 2px toe (`2 * Border.all(width: 1)`), samen de 7px die de brief voorspelde, en de `Text` zelf wil intrinsiek 21.0px terwijl de reserveringsformule voor diezelfde tekst 14.0px aanhield: een tweede, onafhankelijke 7px die de brief niet had gevonden. Oorzaak van die tweede helft: `_tvDetailSeasonChipContentHeight` mat met `DefaultTextStyle.of(context).style`, waarbij `context` de eigen `BuildContext` van `_MediaDetailScreenState` is, een positie die *boven* de `Scaffold` zit die diezelfde `build`-methode een stukje verderop zelf optuigt (die `Scaffold` is een afstammeling van deze context, nooit een voorouder). Daardoor valt `DefaultTextStyle.of` daar terug op Flutter's fallback-debugstijl (48px monospace, geen line-height-multiplier) in plaats van de echte themastijl (Inter, `bodyMedium`, `height: 1.4x`) waarmee de live chip-`Text` een paar lagen dieper, onder diezelfde `Scaffold` als `Material`-voorouder, daadwerkelijk rendert. Bevestigd door drie parallelle `TextPainter`-metingen met identieke stijl-override: via de chip's eigen (afstammeling-)context, via `Theme.of(state.context).textTheme.bodyMedium`, en via de kale `DefaultTextStyle` op de band-context. De eerste twee kwamen beide op 21.0 uit, de derde (huidige code) op 14.0. Fix, beide oorzaken in `_tvDetailSeasonChipContentHeight` (de eigenaar van de reservering, niet de aanroepers): (1) de brief's `_tvSeasonChipBorderInset = 2 * (1 + FocusTheme.focusBorderWidth)` verbatim toegevoegd voor de twee borders; (2) de stijlbron omgezet naar `Theme.of(context).textTheme.bodyMedium ?? DefaultTextStyle.of(context).style`, die niet van `Material`-afstamming afhangt en dezelfde stijl teruggeeft als een echte afstammeling-context. Na de fix: beide asserties in de test groen, `chipIntrinsicHeight` past binnen `bandHeight` zonder clamp. Volledige detailsuite (54 tests) en de aangrenzende OVR1a-schaaltest blijven groen, `flutter analyze` voegt geen nieuwe bevindingen toe (59 pre-existente info-only issues, nul in de gewijzigde bestanden). Geen device-run nodig: de meting is headless sluitend, in tegenstelling tot de vorige ronde |
| DET4-SIZE | `lib/screens/media_detail_screen.dart` staat op 5532 regels en `test/screens/media_detail_screen_test.dart` op 3431, allebei ver over de CLAUDE.md-richtlijn van ~400-500 regels, en Task 1 raakte ze allebei. De `part`-opsplitsing is al begonnen (`lib/screens/media_detail/tv_season_chips.dart`, `mobile_detail_view.dart`); de TV-compositie rond `_buildTvDetailScreen` is de volgende logische `part`. Niet gesplitst in deze taak: geen gedragswijziging hier, en een splitsing is een eigen ronde met eigen bewijslast, zoals REV1-SIZE en WL2-SIZE al vaststelden voor andere bestanden | OPEN, extractiekandidaat genoteerd | n.v.t. |
| CTX1-SIZE | `lib/screens/tv/tv_unified_context_menu.dart` groeide door CTX1 van 721 naar 781 regels, ruim over de CLAUDE.md-richtlijn van ~400-500. De natuurlijke scheiding staat er al: het bovenste derde deel is de menu-API plus de actielabels, `_ActionMenuPanel` en `_MenuHeader` vormen de paneelcompositie eronder en kunnen naar een eigen bestand. Niet gesplitst in CTX1, en ook niet in CTX2/CTX3: alle drie raken dezelfde regels, en een verplaatsing ertussenin zou elke review erna onleesbaar maken. Extractie is een eigen ronde met een groene suite als bewijs dat er niets veranderde | OPEN, extractiekandidaat genoteerd | n.v.t. |
| SEARCH2 | Op Zoeken op TV, zodra je vanaf de resultaten naar beneden scrolt, blijven de topnav-labels ("Home Series Films Mijn Pleya") en het zoekveld met de resultaattelling zichtbaar op hun oorspronkelijke hoogte, over de rij die daar inmiddels gescrold onder staat (Michel, tvOS-simulator, 13 september, screenshot). Reproduceert identiek op `fb7ceefe`, dus onafhankelijk van DEC-116 en niet veroorzaakt door de topnav-collapse-fix; blijft ook staan na een paar seconden wachten, dus geen scroll-animatieartefact. Root cause gevonden tijdens TV2: `TvSearchView._buildBody` zet zijn resultaten in een `SingleChildScrollView` met `clipBehavior: Clip.none`, dat schakelt de clip op **alle** randen uit in plaats van alleen de zijkanten en onderkant die de focusring nodig heeft. De zoekbalk en de topnav staan boven deze viewport in dezelfde `Column` en worden eerder geschilderd, dus een weggescrolde band tekende erover. Gefixt door de clip weer aan te zetten en de ring zijn ruimte via `padding: EdgeInsets.only(top: TvCatalogLayout.cardFocusRingGap * scale, ...)` te geven in plaats van via het ontbreken van een clip. Negatieve controle (`tv_search_view_test.dart`, groep "SEARCH2, the results viewport") stond rood op `clipBehavior`, na de fix groen; volledige `tv_search_view_test.dart`-suite (16/16) en `flutter analyze` schoon | CODE CLOSED · VERIFY/SIM OPEN | `dfde8799` |
| SEARCH2b | Ontdekken draagt dezelfde viewport-constructie als SEARCH2 (`tv_seerr_discover_view.dart:627`, `SingleChildScrollView` met `clipBehavior: Clip.none` en woordelijk hetzelfde commentaar), dus weggescrolde shelves tekenen daar op dezelfde manier over de kop en de bovenbalk. Gevonden tijdens TV2's SEARCH2-taak, niet los gemeld en niet op hardware gezien | CODE CLOSED · VERIFY/SIM OPEN | `dfde8799` |
| DET5 | Filmdetail op een echte Apple TV gebruikt het venster niet volledig: de rij Trailers & Extra's wordt afgesneden door een harde horizontale lijn op ongeveer 80% van de schermhoogte, en daaronder staat alleen donkere achtergrond (Michel, twee foto's op hardware, 13 september). Alleen in Pleya, niet op het tvOS-beginscherm of in Netflix. Geen canvas- of overscanprobleem: `_AppleTvScale` in `lib/main.dart` vult zijn box per constructie. De foto hoort bij build 271 (`8c71c4ad`), die de MOC-09-compositie `1805c75e` bevat maar niet de DET2-fix `49b35d77` en niet DET3; dat klopt met de ontbrekende titel en synopsis en de vaste topnav op de foto. Oorzaak: in 271 staat de rail op een vaste `bottom: TvCatalogLayout.bottomSafeInset * detailScale` (81 × 0,85 = 68,9 van 584 logische pixels) plus 6,8 railpadding, dus de peek van de volgende hub wordt afgeknipt op 87% en de scrim van `TvSpotlightBackground` loopt daaronder dicht naar `bgColor`. `49b35d77` geeft die marge terug zodra de infoband de ruimte nodig heeft. Gemeten per pixelrij in de tvOS-simulator op de huidige main: Mayday laat de rail doorlopen tot 97,8% en PAW Patrol tot 98,1%, daaronder alleen de railpadding (screenshots `det5-mayday-full.png` en `det5-paw-detail.png` in `docs/responsive-audit/2026-09-13/shots/`). De marge die daarna bij lichte titels overbleef is op Michels besluit weggehaald in DET7. Hardwarebevestiging met build 273 of 274 staat open | FIXED, hardware open | `49b35d77` |
| DET7 | Film- en seriedetail gebruiken altijd het volledige scherm: geen overscanmarge onder de rail, ook niet bij een lichte titel waar de infoband wel past (Michel, 13 september: "Rand moet nooit blijven staan altijd volledig scherm"). Productbesluit dat voor dit scherm afwijkt van DEC-087's `TvCatalogLayout.bottomSafeInset`. `_buildTvDetailScreen` houdt geen inset meer onder de rail, de rail staat op `bottom: -railBottomPadding` (zijn eigen ondermarge valt buiten beeld) en `reserveFor` geeft alleen nog de peek terug. Negatieve controle "the detail rail always runs to the bottom edge, also when the info band has room to spare" stond rood (rail-onderkant 520,6 van 584 op een lichte titel), nu groen; `media_detail_screen_test.dart` 46/46, `ci_checks.sh` groen. tvOS-simulator, The Whisper Man: de trailerkaart loopt door tot rij 2140 van 2160 (`det7-detail-fullscreen.png` in `docs/responsive-audit/2026-09-13/shots/`). Hardwarebevestiging staat open | FIXED, hardware open | `d7d538eb` |
| DET6 | Filmdetail: ook los van DET5 is er te weinig ruimte voor de synopsis, die weer op 1 regel staat net als vóór DET3 (Michel, hardware, 13 september). Gereproduceerd op de tvOS-simulator met dezelfde titel ("Mayday", 8 acteurs + Trailers & Extra's): geen hardware-only bug. Twee aparte oorzaken gevonden en allebei gefixt. (1) De echte root cause: `_tvDetailIdealForegroundHeight` en de regelteller-lus in `_buildTvDetailForeground` berekenen `minLogoHeight` via twee verschillende optelvolgordes van dezelfde termen, en bij een exacte fit (Mayday's geval) viel dat een paar ULP's uit elkaar (`remainingForLogo=50.99999999999997` tegen `minLogoHeight=51.0`, gemeten via een simulator-devicelog), waardoor de vergelijking een prima passende 2-regelige synopsis alsnog afkeurde. Fix: `_tvDetailEpsilon`-tolerantie op die vergelijking. (2) Michels productvoorstel (rail iets kleiner i.p.v. de synopsis opofferen) is ook gebouwd, als vangnet voor écht krappe gevallen (bv. genest onder de ingeklapte topnav) waar geen ULP-toeval maar een reëel tekort speelt: `_tvDetailRailShrinkFractions` verkleint `tallPosterScale` én `widePosterScale` samen (beide kunnen de hoogtebepalende hub zijn, DET2) tot de 2-regelige ideale hoogte past, vóór de bestaande terugval naar 1 regel. Negatieve controle voor (1) kon niet op deze hostruntime worden gereproduceerd (de widget-testarithmetic rondt hier de andere kant op af, gedocumenteerd in de testcommentaar); het simulator-devicelog is het bewijs. 45 tests groen, `flutter analyze` schoon | FIXED | `4020547e` |
| CAT19 | Bij Alle films/series: filterrail openen, LEFT drukken sprong door naar de topnav, en een verdere LEFT liep zijwaarts de bar in naar Series, zonder enige visuele aankondiging (Michel, 13 september: "als je bij alle films naar links gaat dus de filter opent en dan verder naar links dan ga je door naar series dat is niet de bedoeling"). Root cause: LEFT uit een railrij was gebonden aan dezelfde `_leaveRailUpwards()` als UP, en die functie is letterlijk gedupliceerd over vier TV-catalogusachtige schermen. De rail is de meest linkse inhoud op de pagina, dus LEFT hoort een no-op te zijn, niet een uitgang naar de topnav. Gefixt in alle vier de dragers: `tv_unified_catalog_screen.dart` (Alle films/series), `tv_watchlist_view.dart` (Kijklijst), `tv_seerr_requests_view.dart` (Aanvragen) en `tv_seerr_discover_view.dart` (Ontdekken), door LEFT aan de al bestaande `_railEdge()`-no-op te binden, hetzelfde patroon dat DOWN aan de onderkant van de rail al gebruikte; UP blijft ongewijzigd naar de topnav gaan. Negatieve controle: de bestaande test "LEFT from every rail row reaches for the top navigation" in `tv_unified_catalog_focus_test.dart` beschreef het oude, ongewenste gedrag en is herschreven naar het nieuwe contract (rail blijft open, focus blijft staan, geen bar-aanroep); stond rood op de oude implementatie, nu groen. Hardwarebevestiging staat open | FIXED, hardware open | `b7f57fef` |
| RAIL2 | Op Home lijkt de focus in een rail bij herhaald RIGHT, en volgens Michels aanvulling ook bij LEFT, af en toe een positie over te slaan en meteen een aantal tegels verder te landen (Michel, hardware, build 272, log `h6ocl`: "Ik heb ook af en toe bij home in de rails met naar rechts klikken meerdere malen dat hij soms een positie lijkt over te slaan dus gelijk naar een aantal items verder schiet. Ook bij left lijkt het te gebeuren"). `h6ocl` en `ijqxp` (build 280) gaven alleen timing/context (zie "RAIL2, classificatie op de twee beschikbare logs"): geen `uipress`-identiteit. Closure-run gedraaid op 15 september 2026, build 281 (`a7d5d3c7`), log `8x94u`: drie onafhankelijke fantoompaar-instanties (arrowRight ×2, arrowLeft ×1, hold ≤40 ms, gat ≤80 ms), alle drie `same-uipress`. Zie "RAIL2, closure-run op build 281". Formele status ENGINE_DUPLICATE bevestigd (zijdeur 4, dubbele swizzle-hop dispatch op `.ended`, `docs/tvos-remote-input-authority.md` §3 en §6). Fix gebouwd in `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)` (`tvos/Runner/AppDelegate.swift`, `3408f061`): het tweede swizzel-hop van dezelfde `UIPress`-fase wordt niet meer aan `super` doorgegeven, maar krijgt het resultaat van de eerste aanroep teruggespeeld, zodat de engine's `synthesizedPressedKeys` en herhaaltimer per fase precies één keer bewegen. Dit funnelpunt zit vóór elke druk, ongeacht welk scherm hem ontvangt, dus dezelfde fix sluit ook NAV2 (zie die rij). Hardware-bewijs op build 282 (`444fb0ee`), log `scvdm`: dezelfde herhaalde snelle/normale LEFT/RIGHT-drukken op een Home-rail, 76 keydown/keyup-paren, geverifieerd met zowel het (gefixte) `scripts/tvos_press_trace.sh` (`EARLY-KEYUP=0, RE-TAP=0`) als een onafhankelijke handmatige telling (0 vasthoudtijden ≤40 ms). Zie "RAIL2, hardwarebewijs op build 282". Vijf `KEYUP-ONLY`-vlaggen in dat log (`reason=gesture-owned-by-swipe`) zijn een bestaand, ander mechanisme (station 9, swipe-gesture-eigendom in Dart), geen RAIL2-instantie en al aanwezig vóór deze fix (1 exemplaar in log `8x94u`) | FIXED, hardware bevestigd | `3408f061` |
| NAV2 | Pijl-re-tap in topnav en catalogus: een echte keyup gevolgd door, binnen 1 tot 20 ms, een down+up-paar met 1 à 2 ms ertussen. Dat is de handtekening van zijdeur 2 in de engine-fork (`tapIfMissingKeyDown:YES` op een `.ended`/`.cancelled` voor een toets die niet meer in de `synthesizedPressedKeys`-set zit). Vier keer in log `ijqxp` (build 280, 23:06:31 topnav direct na een geflushte Menu-enable, 23:07:15 en 23:07:26 topnav zonder enig kanaalbericht, 23:09:18 catalogus); twee keer in `h6ocl` (build 272, zie RAIL2). Twee van de vier hebben geen kanaalbericht, dus dit is niet de NAV1-trigger. **Duplicaat van RAIL2**: zelfde handtekening, zelfde twee brongelogs (`h6ocl`, `ijqxp`), zelfde onderliggende mechanisme (zijdeur 2/4, dezelfde `UIPress`-fase twee keer via beide swizzel-hops afgeleverd), alleen op andere schermen waargenomen (topnav/catalogus in plaats van Home-rail). De RAIL2-closure-run mat het funnelpunt waar élke druk doorheen gaat, niet een schermspecifiek pad, dus de fix (`3408f061`) dekt dit ook. Geen aparte hardwaremeting voor NAV2 nodig; zie RAIL2 voor het volledige bewijs | FIXED, duplicaat van RAIL2 (`3408f061`) | `3408f061` |
| SEL2 | Select blijft na het systeemtoetsenbord (zoekveld) in de engine en in Dart vastzitten: de KeyDown die `openKeyboard()` opent gaat via de sessietak van `PleyaFlutterViewController.tvosHandlePress` naar UIKit in plaats van via het synthese-pad, dus `synthesizedPressedKeys` (engine) en `physicalKeysPressed` (Dart) houden Select vast na het sluiten van het toetsenbord. Log `ijqxp` (build 280): 23:06:48.159 en 23:07:33.053 komen als keyup zonder voorafgaande keydown binnen (de klik die niets doet), en van 23:07:14 tot 23:07:33 staat `keys held: null,null` zodat de geparkeerde Menu-enable van `TvosSystemNavigationService` nooit flusht. Fix: `AppleTvNativeTextEntry.edit` wacht tot `HardwareKeyboard.instance.physicalKeysPressed` leeg is voor hij de sessie start, zie "SEL2, sessie start pas als de toetsen los zijn". De Dart-helft is gebouwd en getest in de simulator; de engine-helft (of een toestellog na het toetsenbord geen `keyup zonder keydown` meer toont) is `HARDWARE ONLY` | FIXED (Dart), hardware open | `e1d09702` |
| CAT20 | Alle films toont niet alle servers: G-Plexflix verloor bij de koude start de endpoint-race (`bound 1/2`, kwam pas om 23:06:27.157 binnen met `merged 4 libraries`, ná de eerste opvraging door Home en de Films-landing). Log `ijqxp` (build 280): de catalogusscreen (23:07:36-23:08:25) vroeg alleen secties op bij 192-x-x-135. TV2-preflight (18 september) vond geen commit onder Michels "opgelost"-melding, dus TV2 taak 7 reproduceerde eerst headless: een opgeslagen bronfilter met twee servers, `eligibleLibraries` die er maar één kent, gaf na het openen van het scherm een store zonder de tweede server terug (rood, precies de voorspelde werkhypothese). Root cause bevestigd in `_restorePreferences` (`tv_unified_catalog_screen.dart:310-331`, woordelijk dezelfde regel op `mobile_catalog_screen.dart:155-167`): `withKnownSources` snoeit tegen de libraries die op dat moment gebonden zijn, en die set kent het onderscheid "nog niet gebonden" versus "bestaat niet meer" niet: ze kan het ook niet kennen, want ze krijgt alleen gebonden libraries binnen. Gesloten met de nieuwe `pruneStoredSourceFilter` in `unified_catalog_filters.dart`, die de bekende serverset verbreedt met `MultiServerProvider.expectedServerIds` (de registratie van `ActiveProfileBinder`, die ook een nog bindende server kent) en de terugschrijving pas doet als elke geregistreerde server ook echt gebonden is. Beide aanroepers zijn omgezet. De mobiele variant is aantoonbaar hetzelfde defect aangetoond (eigen test, rood vóór de fix, groen erna) | FIXED | `cc687fb8` | Tests: `test/screens/tv/tv_unified_catalog_screen_source_filter_restore_test.dart`, `test/screens/home/mobile_catalog_screen_source_filter_restore_test.dart`. Beide handmatig rood gedraaid tegen de pre-fixcode (via een tijdelijke stash van alleen de drie gewijzigde bronbestanden) en groen tegen de fix, vóór commit. |
| CAT21 | `tv_unified_catalog_screen.dart` staat op 968 regels (was 960 vóór CAT20) en is daarmee ruim over de CLAUDE.md-richtlijn van ~400-500 regels. Twee verantwoordelijkheden zijn er goed uit te trekken: de voorkeuren-/filterlaag (`_restorePreferences`, `_applyQuery`, `_effectiveFilters`, de sort/filter-panelen en hun state) en de focus-/railtraversal (`_scheduleRestore`, `_openRail`/`_closeRail`, `_railEdge`, `_focusEntry` en de bijbehorende focus-nodes). Bewust niet in deze taak gedaan: CAT20's gedragswijziging staat op zichzelf, en een extractie hoort in een eigen commit met een groene suite als enig bewijs dat er niets veranderde | OPEN, extractiekandidaat genoteerd | n.v.t. |
| WL2-SIZE | `lib/screens/watchlist_screen.dart` staat op 527 regels na WL3's fix (8 nettoregels erbij), en zat dus al over de CLAUDE.md-richtlijn van ~400-500 regels vóór deze ronde. WL3's `9963071c` noemde dit alleen in de commit-body, zonder eigen rij; toegevoegd door de whole-branch review om dezelfde bewaring te krijgen als CAT21 en REV1-SIZE. Niet gesplitst in TV2, geen gedragswijziging hier | OPEN, extractiekandidaat genoteerd | n.v.t. |
| AGG1 | Verifiëren of het multi-server discovery-landingsscherm (Recently Added/Top Picks/Because You Watched, multi-source badge) tegen levende servers hetzelfde oplevert als de OFF3-fixture tekent, want sinds `MediaServerClient` in juli de drie discover-fetchmethodes kreeg was dat nooit via een groene test gezien. Mergefunctie opgespoord: `HomeProjectionService.projectHubs` (`lib/services/unified_catalog/home_projection_service.dart:59`), die via `groupUnifiedMediaSources` (`grouping_service.dart`) loopt en wordt aangeroepen door de echte `TvDiscoveryLandingProvider._project()`, exact het pad dat de golden test zelf claimt te dekken. Op de tvOS-simulator (live sessie, profiel Michel/PlexFlixNetwork) draaien de Because-You-Watched- en Recently-Added-rijen van de Films-landing zichtbaar tegen twee live servers (Plex "G-Plexflix" en Pleya Server "Pleya") zonder crash, maar dat paar kan de multi-source badge niet bewijzen: `_neverMergedBackends` (`grouping_service.dart:30`, DEC-063) sluit `pleyaServer` bewust uit van cross-backend-merge zolang PS-7 (external-id-ondersteuning) niet gebouwd is. Jellyfin-demo (`demo.pleya.app`) is via `scripts/tvos_sim.sh login` als tweede, wél poolable bron aan hetzelfde profiel gekoppeld (`ConnectionRegistry: upserted jellyfin/...`) om een echte Plex+Jellyfin-mergecase te krijgen. **Productbesluit van Michel, 14 september:** Pleya Server en Pleya Share horen op termijn wel mee te doen in het unified-mergeconcept, dit is geen permanente uitsluiting. Beide lopen via `MediaBackend.local`/`pleyaServer` in `_neverMergedBackends` (`grouping_service.dart:30`), en de weg terug is PS-7's external-id-ondersteuning voor Pleya Server; Pleya Share erft dat automatisch mee zodra `local` van de uitsluitingslijst af mag. PS-7 zelf staat al als eigen fase op de Pleya Server-roadmap (`docs/pleya-server-masterplan-proposal.md` e.a.); hier genoteerd zodat de aantekening niet verdwijnt zonder een eindstatus. **Eindstand van de live ronde:** met Plex + Jellyfin-demo online laadt de Films-landing (Because You Watched, Recently Added, Top films in History) zichtbaar en foutloos content van beide backends door elkaar (`DiscoverProvider: 15 on-deck items, 12 hubs`, een nieuwe titel uit de Jellyfin-bibliotheek verscheen naast Plex-titels in dezelfde "Verder kijken"-rij); "Alle films" toont beide bibliotheken alfabetisch dooreen. Geen enkele geopende titel toonde een multi-source-badge: de gedeelde openfilmtitels tussen deze twee specifieke live bibliotheken (Big Buck Bunny, Caminandes e.a.) hebben kennelijk geen matchende sterke identity-token (open Blender-films dragen doorgaans geen TMDB/TVDB-id), dus geen van de twee kon in deze sessie het echte mergepad met een zichtbare badge bevestigen. De mergefunctie zelf is via code-tracing bevestigd als hetzelfde gedeelde identity-pad dat catalogus en zoeken al langer in productie bewijzen; het enige wat nog los staat is een visuele badge-bevestiging met een titel die wél een gedeelde externe id heeft. **CODE CLOSED (AGG1):** het mergepad lag al vast in `test/services/unified_grouping_service_test.dart`, twee bestaande tests ("een Plex- en een Jellyfin-bron met dezelfde TMDB worden één groep met twee bronnen" en "Pleya Server blijft op een gedeelde id zijn eigen groep"), nu hernoemd met een AGG1-label voor traceerbaarheid in plaats van herhaald als nieuwe test. Wat nog ontbrak was de badge zelf: `TvUnifiedMediaCard` tekende zijn brontelling-badge zonder eigen sleutel, dus is `tvUnifiedMediaCardSourceBadgeKey` toegevoegd en tekent de badge nu die sleutel. Twee nieuwe widgettests in `test/widgets/tv/tv_unified_media_card_semantics_test.dart` bewijzen dat een tweebronnengroep de badge tekent en een eenbronnengroep geen enkele. Geen wijziging aan `grouping_service.dart` of aan het mergegedrag zelf. Wat overblijft is een levende bevestiging met een titel die een echte TMDB- of TVDB-id draagt, en dat kan de huidige open Blender-content tussen Plex en de Jellyfin-demo niet leveren: dat is een contentbeperking, geen codegat. Roadmap-aantekening, geen open werk in TV2: Pleya Server en Pleya Share horen op termijn wel mee te doen in het unified-mergeconcept, en de weg terug is PS-7 | CODE CLOSED · VERIFY/SIM OPEN | `0a3ac25a` |
| CTX1 | Het unified contextmenu mist de metadata-subregel onder de titel (genre, duur, bronnen, kijktijd) die mockup 12 toont | FIXED, hardware open | `5b979cb5` | Uit de MOC-12-compositie-audit van 12 september, bewust niet gebouwd in `62e48d12`. Had tot 18 september geen eigen ID en stond alleen in proza in `unified-2026-closure.md` §5 stap 6 en de MOC-12-registerrij. Eigenaar: `showTvUnifiedContextMenu`. Gebruik de canonieke metadatahelpers, geen tweede formatteringslaag ernaast. Toegewezen aan TV3. TV3 Task 2 (19 september): `formatSourceCount` en `formatRemainingTime` toegevoegd aan `lib/utils/formatters.dart`, `unifiedContextMenuMetaLine` in `tv_unified_context_menu.dart`, en de vier bestaande kopieën (search_screen.dart, mobile_catalog_screen.dart, tv_unified_catalog_screen.dart, mobile_detail_view.dart) vervangen door de helpers. Geen nieuwe i18n-sleutel. `tv_unified_context_menu_metadata_test.dart` 5/5 groen. Bestandsgroeikandidaat apart genoteerd, zie CTX1-SIZE |
| CTX2 | De "Hervatten"-rij in het unified contextmenu toont geen resterende tijd | FIXED, hardware open | `826d2d8d` | Zelfde herkomst als CTX1. TV3-preflight (19 september, `862255cc`): `resolveWatchState` is geen functie. Het is een `bool`-parameter van `lib/utils/video_player_navigation.dart:127/170` en `lib/utils/media_navigation_helper.dart:356` die bepaalt of de speler de watch state opnieuw ophaalt, en `UnifiedWatchState` (`lib/media/unified/unified_watch_state.dart`) draagt alleen `representativeSourceKey`, `lastViewedAt`, `hasActiveProgress`, `isWatched` en `runtimesDiffer`, dus geen offset en geen duur. De bron voor de resterende tijd is `group.representativeSource.item`, met `durationMs` en `viewOffsetMs`, zoals `lib/screens/media_detail/mobile_detail_view.dart:271` het al doet; `tv_unified_context_menu.dart:105` heeft `group.representativeSource.item` al voorhanden. Toegewezen aan TV3. TV3 Task 3 (19 september): `resumeRemaining` berekend uit dezelfde representatieve bron als `hasResumeProgress`, via `formatRemainingTime` doorgegeven aan `_ActionMenuPanel` en getoond als secondary op de play/resume-rij. `semanticLabel`/menuSemantics bewust niet aangeraakt. 23/23 metadata/semantics/reachability-tests groen |
| CTX3 | De actierijen in het unified contextmenu hebben geen icoon per rij | FIXED, hardware open | `0ef719c1` | Zelfde herkomst als CTX1. TV3-preflight (19 september, `862255cc`): de canonieke iconenkaart bestaat al. `_iconForUnifiedGroupAction` (`lib/widgets/mobile/mobile_unified_context_menu.dart:96`) dekt alle zes `UnifiedGroupAction`-waarden. `TvCatalogOptionRow` (`lib/widgets/tv/tv_catalog_sort_panel.dart`) heeft alleen een trailing vinkje bij `isSelected`, geen leading icoon en geen parameter ervoor. Toegewezen aan TV3. TV3 Task 4 (19 september): `_iconForUnifiedGroupAction` verhuisd naar `tv_unified_context_menu.dart` als publieke `iconForUnifiedGroupAction`, nieuwe `iconForUnifiedNavigationAction` erbij, `TvCatalogOptionRow` kreeg een optioneel `leadingIcon` (default null). Sorteerpaneel draagt bewust geen icoon, gedekt door een contracttest. 11/11 metadata-tests groen, goldens ongewijzigd (6/-77, geen nieuwe faler) |
| SYS-3c | `TvBrowseRail._scale(context)` (`lib/widgets/tv_browse_rail.dart:1269`) leest `TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context))` rechtstreeks, buiten `TvLayoutConstants.scaleOf`/`TvDisplayMetrics` om. Die schaal stuurt zes letterlijke lettergroottes aan (`tv_browse_rail.dart:1496,1519,1752,1762,1808,1821,1960`) en alle radii/paddings/gaps van de rail. `TvBrowseRail` wordt gemount op `media_detail_screen.dart:4145`, een route waarvan `test/screens/media_detail_ovr1a_scale_test.dart` (DET1/DEC-109) al bewijst dat hij genest onder de topnav een kortere `MediaQuery`-doos krijgt dan het paneel. Reproductie bevestigd: op de geneste route is `TvLayoutConstants.scaleForSize(panelSize 1038x1080)` 1.0 en `TvBrowseRailLayout.scaleForSize(nestedBoxSize 1038x900)` 0.85 (geklemd), dus een echt ander getal. De negatieve controle (nieuwe test `SYS-3c` in `media_detail_ovr1a_scale_test.dart`) bewees dat concreet: de hubtitel-lettergrootte in de rail kwam op `15.3` (18 × 0.85) uit terwijl het scherm erboven op `18.0` (18 × 1.0) rekent | FIXED | `9cae6d4b` | Gevonden tijdens de SYS-3a-inventarisatie (TV1 Task 7, `docs/tvos-sys3a-schaalinventarisatie.md`, bevinding 1). Fix: `_scale(context)` ombouwt naar `TvLayoutConstants.scaleOf(context)`. TV3-preflight (19 september, `862255cc`) hield de rij op `OPEN` in afwachting van een uitspraak; de dispatcher heeft de toewijzing aan TV3 bevestigd (TV1's eigen close-out: "TV3 owns media_detail_screen.dart en alles wat daaronder gemount wordt, zoals CTX1-3"), TV3 Task 7 heeft hem opgepakt en gesloten. Twee resterende aanroepers van `TvBrowseRailLayout.scaleForSize` in `media_detail_screen.dart` dragen hetzelfde gebrek en zijn niet in deze fix meegenomen, zie SYS-3e |
| SYS-3d | `LibraryRecommendedTab._buildTvContent` (`lib/screens/libraries/tabs/library_recommended_tab.dart:345`) berekent `scale` met `TvLayoutConstants.scaleForSize(MediaQuery.sizeOf(context))`, hetzelfde patroon als SYS-3c: geen `TvDisplayMetrics`. Stuurt spotlight-inzet, railruimte en de layout rond de daar gemonte `TvBrowseRail` aan. Lagere zekerheid dan SYS-3c: dit scherm loopt via `MainScreenFocusScope`/de zijbalk-architectuur, en tijdens de SYS-3a-inventarisatie kon niet worden aangetoond dat het via `TvNestedSurface`/`tvContentRouteRegistry` genest wordt, dus onbevestigd of het ooit een kortere `MediaQuery`-doos dan het paneel krijgt. De blootstelling is wel identiek zodra dat wél gebeurt | OPEN | n.v.t. | Gevonden tijdens de SYS-3a-inventarisatie (TV1 Task 7, zelfde bron, bevinding 2). Lagere zekerheid dan SYS-3c: nesting van dit scherm is niet bevestigd. Toegewezen aan het plan dat `library_recommended_tab.dart`/de bibliotheektabs bezit, niet aan TV1 |
| SYS-3e | Twee aanroepers van `TvBrowseRailLayout.scaleForSize` in `media_detail_screen.dart` lezen nog de doos in plaats van `TvLayoutConstants.scaleOf`, met twee verschillende ontstaansmomenten. **Regel 4011**, `railBottomPaddingForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))` (bepaalt `initialForegroundBottom`, dus waar het scherm zijn voorgrondinhoud tegenaan laat lopen), is echt sinds de SYS-3c-fix een mismatch: `TvBrowseRail` rendert zijn eigen bodempadding sindsdien op paneelschaal, deze regel reserveert nog op doosschaal. **Regel 4800/4805**, `TvBrowseRailLayout.scaleForSize(size)` in `_estimateTvDetailRailHeight`/`_estimateTvDetailEmptyRailReserveHeight` (`size = constraints.biggest`, bewust de doos volgens het commentaar op regel 3960-3966), reserveert de seizoenchiprij-hoogte via `_tvDetailSeasonChipRowHeight(scaleForSize(size))`, terwijl die rij zelf al sinds DET1/DEC-109 op `detailScale` (`TvLayoutConstants.scaleOf(context)`, regel 4142) rendert: dit gat bestond dus al vóór SYS-3c en is niet door die fix ontstaan. DET4's fix heeft dit tweede gat wel groter gemaakt (de reservering van `_tvDetailSeasonChipContentHeight` groeide met de border-inset en de tekststijlcorrectie, ~9 tot 14px), dus wie SYS-3e oppakt vindt op regel 4800 een grotere afwijking dan de oorspronkelijke SYS-3c-vondst deed vermoeden. Op de geneste route (kortere doos dan paneel) reserveert het scherm op beide plekken minder ruimte dan de rail/rij werkelijk inneemt. Niet gefixt in TV3 Task 7, buiten de scope van de eenregelige SYS-3c-fix | OPEN | n.v.t. | Gevonden tijdens de SYS-3c-fix (TV3 Task 7) met `grep -rn 'TvBrowseRailLayout.scaleForSize' lib/` na de fix, ontstaansmoment per term gecorrigeerd door de TV3-whole-branch-review (19 september). Toegewezen aan TV3 (zelfde eigenaar als SYS-3c, `media_detail_screen.dart`) |
| LIVE2 | Live TV end-to-end in Pleya Verify kan niet, ook niet zodra Task 4 de shell-fix van LIVE1 oplevert. De Verify-fixture is een Pleya Server: `pleya_fake_server.dart:549` declareert `'live_tv': false`, het bevroren `/v1`-contract heeft `live_tv` alleen als capability-boolean (`openapi.yaml:771`) en geen enkel Live TV-endpoint (geen zenders, geen EPG, geen opnames), `pleya_server_client/parts/unsupported.dart:182` geeft `const NoopLiveTvSupport()` terug en `liveTvDvr` is null, en geen scenario in `pleya_verify/scenarios/` noemt Live TV. Een journey die Live TV opent, door Gids, Nu op TV en Opnames loopt en een kanaal opent kan tegen deze fixture principieel niet slagen, dezelfde vorm als WL2 | ACCEPTANCE GAP | n.v.t. | TV4 Task 8 heeft de grens tegen deze branch bevestigd en geleverd wat er wel te leveren viel. De vier feiten, herhaald zodat een latere lezer niet opnieuw hoeft te zoeken: (1) `pleya_verify/fixture_server/lib/src/pleya_fake_server.dart:549` zet `'live_tv': false`; (2) `docs/pleya-protocol/v1/openapi.yaml:771` kent `live_tv` alleen als capability-boolean en heeft geen enkel Live TV-endpoint; (3) het protocol is bevroren zolang PS-5 loopt (`CLAUDE.md`, "Het protocol ligt vast") en Live TV staat in geen enkele fase vóór PS-8; (4) `lib/services/pleya_server_client/parts/unsupported.dart:182` geeft `const NoopLiveTvSupport()` terug en `liveTvDvr` is null. Drie alternatieven zijn afgewogen. `live_tv: true` zetten in de fixture is één regel maar verkeerd: de pil verschijnt, de pagina blijft leeg, en het scenario zou groen worden op een scherm dat niets toont, de `tvos.library.sort`-fout. Een `JellyfinFakeServer` naast `SeerrFakeServer` (een tweede volledige backend-fake met zenders, EPG, DVR en opnames, plus een tweede aanmeldpad in de runner) is een eigen ronde met een eigen plan, niet binnen TV4. Live TV in `/v1` opnemen tijdens het bevroren venster is verboden door `CLAUDE.md` en `scripts/check_protocol.sh`. Geleverd is `pleya_verify/scenarios/tvos.livetv.absent-without-capability.yaml`, groen gedraaid op de tvOS-simulator (evidence bundle met focus-trace en twee screenshots): zonder capability staat er geen Live TV-pil in de bar en de bar houdt exact de zes stops die `tvos.nav.walk` al vastlegt, bewezen door dezelfde exacte-volgorde-walk (die faalt op de eerste hop die niet overeenkomt, dus een ongemerkt toegevoegde pil laat de walk daar vastlopen). Het scherm kreeg ook een eigen automation-id (`screen.live_tv`, `lib/automation/automation_ids.dart`) zodat een latere sessie het tenminste kan noemen. Wat dit scenario niet bewijst: de runner-DSL heeft geen id-afwezigheidsverb (`assert` faalt juist als een id niet aanwezig is, en er is geen `assert_ui_tree`/`absent_id`/`present: false`), dus dat `screen.live_tv` nergens gemonteerd is, blijft een bekende beperking, geen beweerde dekking. Nodig om de gevraagde journey (Live TV openen, Nu op TV, Gids, Opnames, een kanaal openen) alsnog te kunnen draaien: een Jellyfin-fixture met echte zenders/EPG/opnames, of Live TV in het protocol na PS-8. Dezelfde grens raakte Task 6 (MOC-17b, `82b4988d`): geen van de aangesloten demo-servers had een werkende tuner (`/livetv/dvrs` leeg of 403), dus de gids met de nieuwe tien-voet-dichtheid en de voortgangsbalk kon niet als simulatorscreenshot bevestigd worden. Code- en testbewijs staat er wel (`live_tv_guide_metrics_test.dart`, alle bestaande gidstests groen). Visuele bevestiging op een device met een echte tuner is nodig vóór de hardwareronde dit als HARDWARE ONLY mag sluiten |
| LIVE3 | Geen enkele widgettest mount `LiveTvScreen`. `test/screens/livetv/` bevat alleen `live_tv_favorites_test.dart`, en dat is pure logica over favorietenstores. Elke wijziging aan het scherm in de TV4-ronde landt dus op onbewaakt gebied tot er een harnas onder staat | FIXED | `a562c7b9` | TV4 Task 1: nieuw `test/screens/livetv/live_tv_tv_shell_test.dart` met `mountLiveTv`, `_FakeLiveTvClient` en `_FakeLiveTvSupport` als herbruikbaar harnas. De negatieve controle voor LIVE1 ("inside the TV shell the screen draws no app bar of its own") stond hier aantoonbaar rood vóór Task 2. Taken 2 tot en met 7 breiden hetzelfde bestand uit in plaats van elk een eigen opstelling te bouwen |
| LIVE4 | Er is geen `screen.live_tv` automation-id. `AutomationIds` heeft `screen.discover`, `screen.libraries`, `screen.my_pleya` en meer, maar niets voor Live TV, dus een Verify-scenario kan het scherm niet eens benoemen | FIXED | `085495d2` | TV4 Task 8: `screen.live_tv` toegevoegd aan `lib/automation/automation_ids.dart`, yaml geregenereerd (`automation_ids_yaml_test` 1/1 groen). Gebruikt door het scenario dat LIVE2 draagt, zodat een latere sessie het scherm tenminste kan benoemen; bewijst niet dat het scherm nergens anders gemonteerd wordt, zie LIVE2 |
| LIVE5 | `live_tv_screen.dart` (ruim 800 regels na TV4) heeft de favorietenresolutie (`_resolveFavoritesStore`, `_loadFavorites`, `_persistFavorites`, de zes `_favorite*`-maps en hun proof-administratie) als eigen, van de presentatie losstaande verantwoordelijkheid. Bewust niet gesplitst in TV4 Task 2 stap 8: vijf taken erna raakten dezelfde `build`, en een verplaatsing ertussenin had elke review onleesbaar gemaakt | OPEN | n.v.t. | Splitsen is chirurgisch, zonder gedragswijziging, met een groene `test/screens/livetv/`-suite als bewijs, in een eigen commit los van elke functionele wijziging |
| LIVE6 | `guide_tab.dart` (ruim 1700 regels na TV4) heeft twee losse verantwoordelijkheden naast de layout: de toetsafhandeling (`_handleKeyEvent`, `_handleTimeNavKey`, `_handleGridKey`, `_handleFocusedProgramSelectKey`, `_handleFocusedProgramContextMenuKey`, ongeveer 200 regels) en de tegelopbouw (`_buildProgramBlock`, `_buildChannelCell`, `_ChannelCell`, `_RecordingDot`). Bewust niet gesplitst in TV4 Task 6 stap 8, want Task 7 raakte hetzelfde bestand nog | OPEN | n.v.t. | Zelfde discipline als LIVE5: chirurgisch, zonder gedragswijziging aan het D-pad-contract, groene suite als bewijs |
| LIVE7 | "Regels" (opnameregels) staat vandaag als sectiekop binnen de Opnames-tab, mockup 17 tekent hem als vierde, eigen capsule naast Gids, Favorieten en Opnames. TV4 Task 0 stap 6 en Task 3 hebben hier al een lezing voor vastgelegd: de mockup is autoriteit over de compositie (één capsulerij), PB-8 over de inhoud, en TV4 heeft Regels daarom als bestaande actie in die ene rij gezet, niet als vijfde capsule of als eigen tab. Het splitsen van Opnames zelf in Gepland en Opnameregels is een tweede, grotere compositiewijziging die PB-8 niet vraagt en die TV4 bewust niet doet | OPEN | n.v.t. | Een eigen ronde met een eigen bewijslast (PB-8-update of een nieuwe goedkeuring), geen onderdeel van TV4 |
| LIVE8 | TV4's finale whole-branch review vond dat de detailbalk leeg bleef in precies de toestand waarin de gids focus krijgt (kanaalkolom, geen programma geselecteerd), omdat `_focusedProgram` daar op null stond en `GuideDetailBand` niets toont zolang `program` null is. Dat maakte de eerdere `CODE CLOSED`-claim voor MOC-17 onterecht: geen verificatiegat, een echt codegat. Los daarvan meldde dezelfde review vijf kleinere punten: (F3) de multi-source-fix voor `_focusedChannel` (`581bf5d7`) heeft geen eigen regressietest, alleen twee onafhankelijke code-lezingen; (F4) `_chipKeyForAction` valt bij een onbekende handler stil terug op de refresh-sleutel in plaats van te falen; (F5) `screen.live_tv` mount alleen binnen de shell, dus een macOS Verify-scenario kan het nooit vinden; (F6) `guideMetricsFor` wordt op een paar plekken per rij in een lus opgevraagd in plaats van één keer doorgegeven; (F7) `guide_detail_band.dart` importeert zowel `material.dart` als `widgets.dart` | FIXED (hoofdbevinding), overig OPEN | `83adabd7`, `bf5bdf22` | Hoofdbevinding gefixt: `_focusedProgram` wordt nu in beide kolommen gevuld met `_findCurrentProgram(_gridChannelIndex)` zodra de ring op een andere zender komt te staan, dezelfde functie die de programmakolom al gebruikte; de periodieke-reload-reconciliatie is om dezelfde reden verbreed naar beide kolommen. De scoped re-review op `83adabd7` vond dat de nieuwe shell-test zelf een tautologie was: `find.text('Nieuwsuur')` stond ongescoped, en die titel staat ook los van de balk altijd al in de rastertegel, en de test miste bovendien de extra pump die de door `_loadPrograms()` uitgestelde `focusContent()`-setState nodig heeft om de widgetboom te bereiken. De reviewer bevestigde het aan de runtime zelf: `_focusedProgram` stond na de fix al correct, alleen de teststap was te kort. Rechtgezet naar een gescopeerde `find.descendant(of: find.byType(GuideDetailBand), ...)`-assertie met de extra pump, en zelf bevestigd dat die versie rood staat op de pre-fix code (tijdelijk teruggezet, gedraaid, teruggeplaatst) en groen op de huidige. De balktest voor de EPG-loze zender stond al goed, die had geen timingprobleem. `test/screens/livetv/` (34/34) en `test/screens/tv/` (374/374) groen, `flutter analyze` schoon. De vijf kleinere punten (F3-F7) zijn bewust niet in dezelfde commits meegenomen: geen ervan is een gedragsfout vandaag, en ze horen bij de LIVE5/LIVE6-bestandssplitsing of een aparte hardeningsronde, niet in een fix die één gevonden gedragsfout moest sluiten |
| AUD3 | Vals, vervormd geluid op de Apple TV bij Volumeversterking, gemeld door Michel op 20 september 2026 met log `5r9eo` (build 289). Twee oorzaken, allebei in die log te zien. Eén: de versterking schreef mpv's `volume` en `volume-max`, een softwaregain die mpv ná de hele filterketen toepast en cubisch schaalt, dus +50% was 3,375x oftewel +10,57 dB voorbij de limiter, en +200% was +28,6 dB. Twee: MPVKit 1.0.26 levert veertien audiofilters en `acompressor`, `alimiter` en `astats` zitten er geen van drieën bij (`nm -gU` op de tvos-, ios- en macos-slice van `Libavfilter.xcframework`), en mpv weigert een `af`-string in zijn geheel om één onbekend filter. Gevolg: elke `af`-schrijf in die log kwam terug met -4 en `af=none`, dus Volume gelijkmaken deed niets zolang harde geluiden dempen aanstond, harde geluiden dempen deed op Apple nooit iets, en de vier metingen uit het meetprotocol maten alleen 100% tegen 150%. Gebouwd: de versterking is een lineaire gain-stage in de keten (`AudioLoudness.boostPercent`, na normalisatie en compressor, vóór de limiter; in de realtime-keten als een hoger `loudnorm`-doel zodat zijn eigen limiter laatste blijft), mpv's `volume-max` blijft op 100, de versterking is losgekoppeld van het normale volume, en `PlayerNative.applyNormalization` leest `af` terug en valt terug op een keten zonder de twee dynamiekfilters in plaats van alles stil te verliezen. Android krijgt dezelfde stage in `LoudnessDsp.process`, waar ExoPlayer's eigen volume op 1,0 geklemd is en de versterking dus nooit aankwam. Negatieve controle: met de boost ná de limiter meet `theLimiterStillHoldsAboveTheBoost` een true peak van 2,37 (+7,5 dBFS), rood; ervóór blijft hij onder -2 dBTP | FIXED, hoorbaarheid HARDWARE ONLY | `c0930cc6` |

## Wat er per item bekend is

### NAV1 en LAND1, dezelfde oorzaak

LEFT op Series kwam op Zoeken uit, RIGHT op Zoeken op Series, en DOWN vanaf
"Alle series" sloeg de eerste rail over. Eén druk, twee stappen, telkens precies
één item overgeslagen.

De navigatiebalk is niet de eigenaar. Een widgettest die de hele keten aflegt van
Zoeken tot Mijn Pleya en terug stopt op elke bestemming. De oorzaak zit bij de
invoer, in `lib/services/apple_tv_remote_touch_service.dart`.

Een druk op de ring van de Siri Remote is tegelijk een aanraking en een druk, en
tvOS meldt die over twee gescheiden paden. De klasse lost dat op met een eigenaar
per gebaar, en dat dempen werkt beide kanten op zolang de eigenaar staat. Wat het
begin van een aanraking niet overleefde was een claim van het native pad:
`_startTouch` nam alleen een swipe-claim mee. Komt de pijl van een ringdruk een
paar milliseconden vóór zijn eigen aanraakstroom binnen, en die volgorde levert
het toestel op, dan verviel de claim en haalde de afgelegde weg van diezelfde
vinger de swipedrempel. Tweede stap.

Verborgen gebleven door het duplicaatvenster per toets. Dat is 120 ms en het
vangt de tweede pijl alleen wanneer die toevallig dezelfde toets is.

Drie negatieve controles staan in
`test/services/apple_tv_remote_touch_service_test.dart`, waarvan er twee rood
waren op de oude implementatie en de derde groen moest blijven.

Hardware-acceptatie staat nog open, en dat kan niet anders: de simulator heeft
geen aanraakvlak, dus daar bestaat het tweede pad niet.

### LAND4, verticaal navigeren behoudt de horizontale positie

Dit is een gedeeld contract voor élk tvOS-scherm dat uit gestapelde horizontale
rails bestaat, niet alleen voor Home. Zoek de callsites van de gedeelde
rail-primitive en rapporteer welke schermen hem delen. Minimaal te auditen: Home,
de Series-landing, de Films-landing, andere discovery-landings, en elke
Mijn Pleya-subpagina die dezelfde structuur gebruikt.

Het contract. UP en DOWN gaan naar de aangrenzende geldige rail en houden daarbij
de horizontale positie vast. Staat de focus op item 3 en gaat de gebruiker naar
beneden, dan is item 3 in de rail eronder de kandidaat. De gebruiker beweegt door
de pagina alsof de rails samen één ruimtelijk vlak vormen.

Dezelfde index is de voorkeursregel, de geometrie beslist. Hebben de rails
verschillende aantallen items of verschillende kaartbreedtes, kies dan in de
doelrail het item waarvan het horizontale midden het dichtst bij het midden van
de huidige kaart ligt. Heeft de doelrail minder items, dan klemt de kandidaat op
de laatste. Zeven items met de focus op zes, naar een rail van vier, geeft item
vier.

Een lege, verborgen of offstage rail mag worden overgeslagen, en dan gaat de
focus naar de eerstvolgende geldige. Een rail die zichtbaar en gevuld is mag
nooit worden overgeslagen. Dat is dezelfde regel die LAND1 al raakte.

Het scherpe punt zit in wat er níét mag gebeuren. Een rail mag focusgeheugen
houden, want dat is wat terugkeren uit een detailpagina en herstel na een overlay
laat werken. Dat geheugen mag alleen niet bepalen waar UP en DOWN naartoe gaan.
Had rail B eerder item 6 en staat de gebruiker nu op item 2 van rail A, dan is
item 2 de bestemming. Focusgeheugen en directionele traversal zijn twee
verantwoordelijkheden, en ze hebben hier verschillende antwoorden.

LEFT en RIGHT blijven zoals ze zijn, en verzetten daarbij het anker dat de
volgende verticale stap gebruikt.

Een juiste focusnode is niet genoeg. De doelkaart moet ook volledig in beeld
staan, met de focusring binnen de veilige zone en in zijn uitgeklapte breedte.
Test verticale focus en reveal samen, wat dit item aan LAND3 vastknoopt.

Verboden oplossingsvormen: een regel per rail of per scherm, een vertraging, een
`requestFocus` in een post-frame callback wanneer de focusgraph zelf fout is, het
wissen van railgeheugen om het probleem te verbergen, en het forceren van het
eerste item bij elke verticale stap.

Negatieve controles: zet de oude per-rail-geheugenlogica terug en de
same-column-test moet rood worden; zet de oude projectiestate terug en de
projectietest moet rood worden.

#### De audit: wie deelt de primitive

Drie productieoppervlakken stapelen `TvDiscoveryRail`, en verder geen enkele:
Home (`tv_content_feed.dart` via `tv_content_row.dart`), de Films- en de
Series-landing (samen één `tv_discovery_landing_screen.dart`), en TV Zoeken
(`search_screen.dart`). De Mijn Pleya-subpagina's stapelen geen rails maar
tekenen een `TvMenuGrid`, dus zij vallen buiten dit contract. De catalogus is een
raster en valt er ook buiten.

#### Wat er misging

De rails hadden helemaal geen verticale handler. UP en DOWN vielen door naar
Flutters directionele traversal, en die is geometrisch: hij zoekt de focusbare
node die onder de band van de huidige kaart ligt. Een rail is echter geen
statisch raster. Hij scrolt, en zijn scrollpositie *is* zijn focusgeheugen. Een
rail die eerder tot zijn tiende tegel gelopen is staat daar nog steeds geparkeerd,
dus wat er onder de band ligt is zijn elfde tegel.

Daarmee besliste geheugen de traversal, precies het ding dat hierboven verboden
is. Gereproduceerd met twee gestapelde rails van twaalf tegels, in
`test/widgets/tv/tv_discovery_rail_test.dart`:

* vijf keer RIGHT en dan DOWN kwam van `t5` op `b3` uit, twee kolommen naar
  links, want de bovenste rail was gescrold en de onderste niet;
* één keer UP daarna kwam op `t6` uit, dus de heenreis en de terugreis waren niet
  elkaars omgekeerde;
* met de onderste rail eerst tot `b9` gelopen kwam DOWN vanaf `t2` op `b10` uit.

Er is bovendien een geval waar geometrie principieel niet bij kan. De band is een
`ListView.builder`, dus terwijl een rail bij zijn vijfentwintigste tegel staat
bestaan de tegels rond kolom 1 niet in de widgetboom. Er is dan niets op het
scherm dat voor kolom 1 kan doorgaan.

#### Wat er is veranderd

De rail krijgt `focusColumn(int)`: de kolom die een verticale stap meebrengt,
geklemd op zijn eigen lengte, met een sprong van de band wanneer de doeltegel
buiten het gebouwde venster valt. Kolom en index zijn hier hetzelfde woord, want
`TvDiscoveryLayout.railPitch` hangt alleen van de paginaschaal af: elke rail op
een pagina legt zijn tegels op één raster. Een test in
`tv_discovery_rail_test.dart` meet dat na op de gerenderde x-posities. Krijgt een
rail ooit zijn eigen tegelbreedte, dan is `focusColumn` de enige plek die op
middens moet gaan vergelijken.

`onNavigateUp` en `onNavigateDown` van de rail zijn `ValueChanged<int>` geworden
en dragen de kolom waar de stap vandaan komt. Het anker verzet zich daarmee
vanzelf bij LEFT en RIGHT, zonder aparte staat.

De stapel zelf is `lib/widgets/tv/tv_rail_stack.dart`, één eigenaar die de drie
oppervlakken delen. Hij houdt de sleutels per rail-id vast, kent de tekenvolgorde
van de huidige build, en loopt bij een stap door tot een rail de focus aanneemt,
wat lege rails overslaat en gevulde nooit. De randen bezit hij bewust niet: boven
de eerste rail staat een paginakop, een hero of een zoekveld, en onder de laatste
rail van Zoeken staat een verticale resultatenlijst. Daar geeft hij `null` terug
en pakt Flutters traversal de toets weer op.

De sprong-en-focus voor een tegel buiten het venster is niet de verboden
post-frame `requestFocus`. Die verbergt een focusgraph die nú fout is; hier klopt
de graph en bestaat het doel nog niet, omdat een viewport bepaalt wat er bestaat.

#### Bewijs

Negen controles in `test/widgets/tv/tv_discovery_rail_test.dart`: kolom bij DOWN,
de retour bij UP, geheugen dat niet beslist, klemmen op een kortere rail, een lege
rail overslaan, een kolom buiten het gebouwde venster, de reveal op uitgeklapte
breedte, de randen, en het gedeelde raster. Daarbovenop acht op de oppervlakken
zelf: drie in `tv_content_feed_test.dart`, drie in
`tv_discovery_landing_screen_test.dart` waar Films en Series ieder apart gepompt
worden, en twee in `search_screen_test.dart`.

Met de eigenaar teruggezet op zijn oude vorm, alle verticale stappen weer naar de
geometrie, waren zeven van de negen railcontroles rood en vijf van de acht
oppervlaktecontroles. Wat groen bleef hoort groen te blijven: de klemtest, waar de
geometrie toevallig hetzelfde antwoord gaf, de rastertest die een layout-invariant
vastlegt, de twee randcontroles (UP naar de hero op Home, UP naar de paginakop op
een landing) en de Zoeken-uitzondering van SEARCH1.

De reveal-helft is meegetest maar lost LAND3 niet op: die gaat over
`focusCurrent()` bij terugkeer uit een detailpagina, en dat pad is hier niet
aangeraakt.

### LAND2, de projectie van de vorige rail

Op Home stond de titel en synopsis van "How to Train Your Dragon" boven de rail
terwijl de focus al op "Puss in Boots" in de rail eronder stond, met diens
metadata eronder. Twee focuscontexten tegelijk in beeld.

Het contract is exclusief: alleen het item dat nu de focus heeft mag zijn titel,
metadata, contextregel en synopsis tonen. Gaat de focus van rail A naar rail B,
dan verdwijnt de projectie van A op hetzelfde moment dat die van B verschijnt.

De oorzaak bleek breder dan de melding. Elke rail tekende altijd een blok, ook
een rail die nooit focus had gehad, want `_focused` valt bij het opbouwen terug
op het eerste item. Op een gestapelde feed leverde dat één bijschrift per rail
tegelijk op. De code zei het zelf, bij `onFocusChange`: een rail hoort te blijven
beschrijven waar hij verlaten is.

Dat is nu gesplitst. `_focused` blijft wat het was, het herstelpunt waar een
kijker op terugkomt uit een detailpagina. Ernaast staat `_holdsFocus`, gevoed
door één `Focus` boven alle tegels van de rail. Een voorouder en niet een
callback per tegel, want bij een horizontale stap wisselt de focus binnen die
subtree en ziet de voorouder hem niet weggaan, dus het blok knippert niet.

TV Zoeken is de ene uitzondering, en die staat als benoemde eigenschap op de
primitive: `alwaysDescribesCurrent`. De rails daar zijn geen feed maar
resultaatcategorieën, en de titel van een resultaat staat alléén in dat blok. Met
de poort erop zou een zoekpagina niets leesbaars tonen tot de kijker erin loopt.
Vier bestaande Search-tests vielen daar prompt over om, wat de zorg bevestigt die
al in de oude comment stond. Wil je dat Zoeken toch onder hetzelfde contract
valt, dan is de vervolgvraag waar de resultaattitel dan wél komt te staan.

### SEARCH1, Zoeken benoemt zijn resultaten buiten het railcontract om

TV Zoeken zet `alwaysDescribesCurrent` op de rail-primitive, en dat blijft
voorlopig staan. Het is geen vergeten uitzondering en geen restje van LAND2.

De reden is dat het beschrijvingsblok op Zoeken op dit moment de enige plek is
waar de titel van een zoekresultaat te lezen valt voordat de kijker de kaart
binnengaat. Met de focuspoort erop toont een zoekpagina onbenoemde artwork tot er
iemand in loopt. Vier bestaande Search-tests vielen daar bij LAND2 prompt over
om.

Wat dit betekent voor werk dat hier langskomt:

* LAND4 en alles daarna mogen `alwaysDescribesCurrent` niet en passant
  weghalen. `search_screen_test.dart` bewaakt dat expliciet.
* Zoeken mag niet worden gelijkgetrokken met Home, Films en Series ten koste van
  resultaten die dan naamloos op het scherm staan.
* Wil je Zoeken tóch onder exact hetzelfde railcontract brengen, dan is dat een
  productbesluit en geen refactor. Het besluit moet eerst vastleggen waar de
  resultaatnaam dan permanent zichtbaar wordt: op de kaart zelf, in de heading,
  of ergens anders.

**Dat besluit is er, en het is DEC-108.** Mockup 36 B legt de resultaatnaam vast
op precies de derde plek die hierboven als optie stond: in de heading. "Films 4"
is een kop boven een band die zelf geen bijschrift meer heeft, dus er valt niets
meer uit te zonderen. Gebouwd op 7 september: `TvSearchView` tekent per sectie
een `TvSectionHeader` met het aantal, en de band eronder is een
`TvCatalogCardRail` van catalogustegels. `TvDiscoveryRail`, en daarmee
`alwaysDescribesCurrent`, komt op Zoeken niet meer voor; de twee tests die de
uitzondering bewaakten zijn vervangen door twee die de kop bewaken.

Wat blijft staan is de parameter zelf. Zoeken was de enige plek in productie die
hem op `true` zette, dus hij staat nu overal op zijn standaardwaarde en wordt
alleen nog door `tv_discovery_rail_test.dart` uitgeoefend. Weghalen is een losse
opruiming aan de gedeelde rail-primitive en hoort niet in deze bouwronde thuis;
hij staat hier zodat de volgende die langskomt weet dat er niets meer achter zit.

### LAND3, de gefocuste wide card

Michel heeft dit gepreciseerd: het gebeurt bij terugkeren naar de vorige rij,
direct op het laatste item.

#### Waar de hypothese naast zat

De aanname in dit document was dat de reveal niet op de uitgeklapte 16:9-breedte
gerekend werd. Dat doet hij wel. `_revealTarget` in
`lib/widgets/tv/tv_discovery_rail.dart` leest de layouttokens en telt netjes
`tileWidth(scale, focused: true)` bij de linkerrand van de doeltegel op. De fout
zit in de regel erna.

#### Root cause

`_revealTarget` klemt zijn uitkomst op `position.maxScrollExtent`, en dat is de
scrollruimte die de band op dát moment heeft. Een tegel klapt uit binnen de
scrollable, dus focussen groeit de inhoud, maar die groei komt over de
focusanimatie en dus een paar frames later. Op het frame waarop de reveal beslist
staat alles nog op rust, en dan is de gemeten ruimte precies
`tileWidth(focused) - tileWidth(rest)` te kort.

Dat bijt alleen aan het eind van de rij, want daar is die groei ook echt nodig:
voor de laatste tegel is de gevraagde offset gelijk aan de maximale scrollruimte
ná het uitklappen, tot op de pixel. Naar rechts lopen verbergt het, omdat de
tegel die je verlaat nog breed is terwijl de volgende groeit, zodat de inhoud
tussendoor nooit krimpt. Aankomen vanaf een verticale stap of een herstel heeft
niets uitgeklapt staan, en loopt er dus wel tegenaan.

Gereproduceerd op het canonieke canvas van 1038 breed, negen tegels, schaal 0,85:
de gevraagde offset is 550,17 en de gemeten ruimte 342,40. De 207,77 die
overblijft is exact het verschil tussen de uitgeklapte en de rustende
tegelbreedte, en de rechterrand van de laatste tegel kwam daardoor op 1209,23
uit.

#### Waarom de bestaande tests dit misten

De P9-controle die hierover ging loopt de rail naar rechts af, met een comment
die dat expliciet zegt ("Walk there rather than jumping, so the tile is actually
built"). Dat is precies het pad waarop het niet misgaat. De comment in `_band`
had de trailing ruimte bovendien beredeneerd weggehaald, met een negatieve
controle die groen bleef, en die controle liep over hetzelfde looppad.

#### De fix

De band reserveert de ruimte nu achteraan, als
`TvDiscoveryLayout.railFocusHeadroom(scale)`, en onvoorwaardelijk. Een
scrollruimte die meebeweegt met waar de focus staat zou dezelfde
volgorde-afhankelijkheid op een andere plek zetten. Er scrolt niets die ruimte
in, want elke scroll van deze rail komt uit `_revealTarget`, en dat vraagt om de
offset die een tegel nodig heeft en nooit om het eind van de band.

#### Blast radius

Alle vier de oppervlakken die `TvDiscoveryRail` stapelen krijgen de fix via
dezelfde eigenaar: Home, de Films-landing, de Series-landing en TV Zoeken.
Buiten bereik en gecontroleerd: Mijn Pleya en de catalogus tekenen een raster,
en `tv_unified_media_grid.dart` noemt de rail alleen in een comment. Er is geen
uitzondering per scherm nodig, en `alwaysDescribesCurrent` van SEARCH1 is niet
aangeraakt.

#### Bewijs

Twee controles in `test/widgets/tv/tv_discovery_rail_test.dart`: aankomen op de
laatste kolom via `focusColumn`, en dezelfde stap via `TvRailStack` over twee
gestapelde rails. Met de fix teruggedraaid waren precies die twee rood, op
1209,23 tegen 1001,95 en op 1299,13 tegen 982,76, en bleven de andere 23
controles in dat bestand groen.

96 gerichte tests groen over de eigenaar en de vier oppervlakken. De volledige
suite geeft 6078 groen tegen 6076 op de nullijn, wat exact de twee nieuwe
controles zijn, met een identieke set van 83 bekende failures: 78 goldens en de
vijf in het oude `test/widgets/tv_discovery_rail_test.dart`.

Pleya Verify levert hier geen bewijs, en dat is geen keuze maar een gat: zie VER4
hieronder. Hardware-acceptatie staat nog open.

### CAT1, de bovenste rij tegen de bovenrand van het raster

Gereproduceerd op een tvOS-simulator met een echte bibliotheek, op Alle films,
met de focus op de eerste kaart van de bovenste rij. De witte focusring is daar
recht afgesneden: de zijkanten staan er, de bovenkant en de twee bovenhoeken
niet. De artwork zelf blijft heel.

#### Waar de omschrijving naast zat

"Raakt de veilige bovengrens" leest als de overscanband van hoofdstuk 8.1, en
dat is het niet. Op het canonieke canvas staat de bovenste rij op 147 logische
pixels en de veilige grens op 30, dus er zit ruim honderd pixels tussen. De
bovengrens die de rij wél raakt is de bovenrand van het scrollvenster van het
raster, de lijn onder de paginakop waar het venster begint te knippen.

#### Root cause

`TvCatalogGrid.forWidth` rekende de focusgroei uit met

```dart
final cardHeight = cardWidth / TvCatalogLayout.posterAspectRatio;
```

en dat is de hoogte van een poster die zo breed is als de hele kaart. De kaart
die focus opschaalt is een andere doos. Zijn poster is smaller, want die staat
binnen twee `cardContentInset`s, en zijn totaal is hoger, want de titel en de
metaregel hangen eronder. `Transform.scale` in `FocusableWrapper` schaalt die
hele doos om zijn midden, dus de helft van de aangroei gaat omhoog.

Op het canonieke canvas van 1038 breed reserveerde het raster 6,885 logische
pixels waar de kaart er 8,282 nodig heeft. De 1,397 die overbleven zijn breder
dan de ring zelf, die 2,5 logische pixel dik is: er wordt niet een stukje van de
ring afgehaald, de bovenrand verdwijnt in zijn geheel. Alle kolommen van de rij
tegelijk, want een rij deelt één bovenrand.

Dezelfde uitdrukking zat ook in `bottomSafeInset`, dus onderaan at de ring
hetzelfde bedrag uit de overscanmarge. Dat is één en dezelfde regel en gaat mee
met de fix. Het is niet het antwoord op CAT2, dat over de metadata van de
onderste rij gaat.

#### Waarom de bestaande tests dit misten

De reden staat in de meting zelf. De buitenste `SizedBox` van een kaart zit
*boven* de `Transform.scale` van `FocusableWrapper`, dus `tester.getRect` op de
kaart geeft de rustdoos terug of hij nu focus heeft of niet. Elke test die de
kaart mat zag geen verschil tussen gefocust en niet gefocust. De ring wordt
getekend op het posterblok binnen de transform, en dat is de rechthoek die je
moet meten.

#### De fix

De groei hoort bij de kaart en niet bij de kolomrekenaar, dus de aanroeper zegt
nu welke kaart hij tekent. `TvCatalogGrid` houdt `bottomSafeMargin` als kale
overscanmarge en krijgt

```dart
EdgeInsets scrollPadding({required double cardHeight, required double focusScale})
```

Twee oppervlakken tekenen verschillende kaarten door hetzelfde raster: de
catalogus met `TvUnifiedMediaCard` op `fullCardFocusScale`, en de kijklijst met
`WatchlistCard` op `focusScale`. Eén getal dat in de rekenaar wordt uitgerekend
kon dus per definitie maar voor één van de twee kloppen, en de kijklijst kreeg
tot nu toe stilzwijgend het verkeerde.

`TvCatalogLayout.cardHeight(cardWidth, scale)` telt de kaart op uit zijn eigen
tokens. Dat kan omdat niets aan de hoogte van de inhoud afhangt: het titelblok
is een `SizedBox` van twee regels of de titel ze nodig heeft of niet, en de
metaregel wordt ook getekend als hij niets te melden heeft. De metaregel wordt
naar boven afgerond omdat de engine dat ook doet, precies zoals
`MediaCardGridLayout.captionExtentFor` het al deed, en een test houdt de som en
de gerenderde kaart tegen elkaar aan.

#### Blast radius

Twee oppervlakken lezen de padding: de catalogus (`tv_unified_media_grid.dart`,
gedeeld door Alle films en Alle series) en de kijklijst op TV
(`watchlist_screen.dart`). De vier andere aanroepers van
`TvCatalogGrid.forWidth` gebruiken alleen `columns`, `cardWidth`, `gutter` en
`inset` en zijn niet geraakt: de paginakop, de laadplaatshouder, de kaart zelf
en de niet-TV-tak van de kijklijst. De discovery-rails staan er los van, die
hebben hun eigen `railFocusHeadroom` uit LAND3.

De inhoud van het raster zakt hierdoor 1,4 logische pixel op het canonieke
canvas en 2,6 op een 1920-canvas. Dat is precies de ruimte die de ring nodig
heeft en niets meer; het kolomaantal, de kaartbreedte, de gutters en de zijranden
veranderen niet.

#### Bewijs

Vier controles in `test/widgets/tv/tv_unified_media_grid_test.dart`: de eerste,
de middelste en de laatste kolom van de bovenste rij, aankomst van onderaf en
van opzij, het schaalminimum van 1280x918, en de contracttest die de berekende
kaarthoogte tegen de gerenderde houdt.

Met de oude uitdrukking teruggezet waren drie van de vier rood, met de ring op
-1,367 tegen een venster op 0,0. De contracttest bleef groen en hoort groen te
blijven: die hangt niet aan de padding.

Pleya Verify levert hier geen bewijs. Er is geen scenario dat de catalogus
opent, en de bestaande fixtures zijn dezelfde die VER4 al als gat beschrijft.
Hardware-acceptatie staat nog open.

### CAT2, niet gereproduceerd met de huidige code

#### Masterlijsthypothese

"Metadata van de onderste rij staat tegen de onderrand": spiegelbeeld van CAT1,
maar dan de titel- en metaregel onder de laatste kaartrij tegen de schermrand
onderaan in plaats van de focusring bovenaan. CAT1's eigen notitie sluit uit dat
zijn fix het antwoord is: "Dezelfde uitdrukking zat ook in `bottomSafeInset`...
Het is niet het antwoord op CAT2."

#### Reproductiepoging

Twee sporen, allebei tegen de echte productiewidgets (`TvUnifiedMediaGrid` onder
`TvShellSurface`, `TvCatalogGrid.forWidth`, `TvCatalogLayout.cardHeight`, niet
een losse primitive):

1. **Widget-geometrie**, op het canonieke canvas van CAT1 (1038×584) en op
   1920×1080, met een grid van veertig kaarten en de echte
   `TvUnifiedGridFooter`. Focus liep stap voor stap DOWN vanaf kaart 0 naar de
   laatste kaart, hetzelfde pad dat `FocusableWrapper._scrollIntoView` op een
   toestel aflegt, niet een handmatige `jumpTo`. Gemeten is de afstand tussen de
   onderkant van de metaregel van de laatste kaart (de echte `Text`-rect binnen
   de footer, niet de kaart als geheel) en de onderkant van de viewport.
2. **tvOS-simulator**, met de demo-inlog die al op het toestel stond. "Films" en
   "Series" landen allebei op `Nog niets te ontdekken`: dit account heeft geen
   discovery-hub-inhoud, en LAND6 heeft al vastgelegd dat een lege landing geen
   andere route naar de complete catalogus biedt. De catalogusgrid zelf was via
   dit account dus niet bereikbaar: geen `.env`-demologin, geen lokale
   Jellyfin/Plex-container in deze werkomgeving, geen alternatieve route.

#### Wat spoor 1 laat zien

Op het canonieke canvas, na focus-gedreven navigatie naar de laatste kaart:
metaregel eindigt op 84,40 logische pixels boven de viewportrand (kaart als
geheel op 87,27). Op 1920×1080: 117,39 voor de kaart. Dat is ruim boven
`bottomSafeMargin` (43,79 canoniek) plus de focusgroei (8,28) samen: geen
clipping, geen randcontact, in geen van de geteste aankomstroutes (rusttoestand
zonder focus, `jumpTo(maxScrollExtent)`, en stapsgewijze DOWN-navigatie).

Een negatieve controle met CAT1's *oude* formule
(`cardWidth / posterAspectRatio` in plaats van `TvCatalogLayout.cardHeight`)
laat zien dat het verschil in gereserveerde onderpadding tussen oud en nieuw
maar 1,4 logische pixel is: de metaregel zou onder de oude, foutieve formule
even goed zo'n 83 pixels vrije ruimte hebben gehad. **Dat weerlegt de
masterlijsthypothese dat CAT1's fix (`89b1554`) CAT2 als bijvangst zou hebben
opgelost**: het scheelde nooit genoeg om het gerapporteerde "tegen de
onderrand" te verklaren, dus CAT2's werkelijke oorzaak is met de huidige
bewijslast niet vastgesteld, niet bevestigd als aanwezig en niet verklaard als
al opgelost.

#### Status

`NOT REPRODUCED`. Niet gesloten als non-issue: de melding komt van een fysieke
Apple TV en de code die de metadataregel positioneert is hier op geen enkel
punt bewezen fout, maar ook niet bewezen goed op een surface met de dichtheid
en het toestel Michel zag. Wat nodig is om verder te komen: ofwel een fysieke
device-run met een écht gevulde bibliotheek, ofwel een simulator-sessie met
demo-inloggegevens die een catalogus met meerdere rijen laat zien (LAND6's gat
blokkeert dat nu voor elk account zonder discovery-hubs). Geen productiecode
gewijzigd; er is niets om terug te draaien als dit later alsnog reproduceert.

### CAT3, de actiecluster hield zich niet aan de canonieke rechterrand

#### Masterlijsthypothese

"Bron, filters en sortering staan verkeerd gepositioneerd." Er stond al een
niet-bewezen hypothese uit CAT1's onderzoek klaar: titelzone en actiezone
zouden allebei een flex-verdeling hebben, waardoor vrije ruimte gedeeld werd
terwijl de actions eigenlijk tegen de canonieke rechter paginarand horen.

#### Reproductie

Tegen de echte `TvCatalogHeaderBar`, binnen `TvShellSurface`, met de echte
`TvCatalogGrid`-tokens, niet een losse `Row`-test. Gemeten is het rechterranddelta
van de rechtste actiecapsule (de doos waar de focusring op getekend wordt,
niet alleen het label) tegen `grid.inset + TvCatalogLayout.cardContentInset(scale)`,
dezelfde canonieke rechterrand die de catalogusgrid zijn artwork tegen
uitlijnt.

* Canoniek canvas (1038×584, schaal 0,85), drie acties: delta 0,0, **niet**
  gereproduceerd.
* 1920×1080 (de echte referentieresolutie, schaal ongeklemd op 1,0), drie
  acties: delta 238,5 logische pixels.
* Canoniek canvas, Bronnen conditioneel afwezig (twee acties): delta 140,7
  logische pixels.

Op het canonieke canvas zag het er dus goed uit, en dat is precies waarom de
bestaande goldens, die alleen dat canvas renderen, het nooit vingen.

#### Root cause

`TvCatalogHeaderBar` wikkelde de actiecluster in `Flexible(fit:
FlexFit.loose)` met dezelfde flexweging (1) als de `Expanded` paginatitel.
Flutters flex-algoritme verdeelt de vrije ruimte vóór het layouten van de
flex-children, op basis van die weging: bij twee flex-children van gewicht 1
elk krijgen ze allebei precies 50% als *maximum*, ongeacht hun eigen inhoud.
Een `Expanded` (tight fit) vult zijn 50% altijd volledig; een `Flexible`
(loose fit) mag minder gebruiken, en `SingleChildScrollView` doet dat ook
echt: hij krimpt naar de breedte van zijn kind zodra dat kind smaller is dan
de toegewezen maximumbreedte, in plaats van die maximumbreedte te vullen
zoals een `ListView`/`Viewport` zou doen.

Op het canonieke canvas ligt `TvLayoutConstants.scaleForHeight` tegen zijn
ondergrens van 0,85 aan geklemd (584/1080 = 0,54, geklemd naar 0,85), wat de
actiecapsules daar verhoudingsgewijs groot maakt tegenover de 964-brede rij:
toevallig dicht genoeg bij hun 50%-aandeel om het gat onzichtbaar te maken.
Bij 1920×1080 is de schaal *niet* geklemd (1080/1080 = 1,0) en groeit de
inhoud van de acties trager dan de lineair meegroeiende 50%-flexdeling, dus
het gat wordt zichtbaar. Met Bronnen conditioneel afwezig krimpt de inhoud
verder terwijl de 50%-share gelijk blijft, met hetzelfde gevolg, al op het
canonieke canvas.

**FLEX HYPOTHESIS: CONFIRMED.**

#### Waarom de bestaande tests dit misten

Geen enkele test mat het rechterranddelta van de actiecluster tegen de
canonieke rechterrand, op geen enkele resolutie. De vier bestaande
`tv_catalog_films_*`-goldens en de bijbehorende states-goldens renderen
allemaal uitsluitend het canonieke 1038×584-canvas, exact het ene geval waar
de toevalstreffer het defect verborg. Geen van hen test 1920×1080, en geen
scenario test Bronnen conditioneel afwezig.

#### De fix

De actiecluster is nu een niet-flexibel `Row`-kind: een `ConstrainedBox`
(gekapt op de content-breedte van de rij, `width - horizontalInset * 2`, als
vangnet tegen een `RenderFlex`-overflow in het pathologische geval van een
titel die tot 0 gekrompen is plus een actieset die zelfs dan niet past) om
dezelfde `SingleChildScrollView`. Een niet-flex kind wordt door Flutter vóór
de flex-verdeling gelayout op zijn eigen intrinsieke breedte, dus de titel
(de enige overgebleven flex-child, `Expanded`) krijgt daadwerkelijk alles wat
overblijft, en de `Row` plaatst de acties vlak tegen zijn eigen rechterrand,
ongeacht titellengte of het aantal acties.

#### Blast radius

`TvCatalogHeaderBar` heeft één productiecaller: `TvUnifiedCatalogScreen`,
gedeeld door Films en Series. Geen andere oppervlakte gebruikt dit widget.

#### Bewijs

Zeven controles in `test/widgets/tv/tv_catalog_header_bar_test.dart`: de
canonieke canvas in rust, 1920×1080, Bronnen conditioneel afwezig, een korte
titel, een lange gelokaliseerde titel, een actieve filterbadge, en het
pathologische-overflow-vangnet.

Met de oude implementatie teruggezet stonden precies de twee controles rood
die de melding daadwerkelijk reproduceerden (1920×1080, 238,5 tegen een
tolerantie van 0,5, en Bronnen conditioneel afwezig, 140,7), en bleven de
overige vijf groen, wat exact de canonieke-canvas-toevalstreffer bevestigt.

De twee bestaande golden-testbestanden voor deze oppervlakte
(`tv_unified_catalog_golden_test.dart`, 14 tests, en
`tv_unified_catalog_states_golden_test.dart`, 5 tests) falen op deze HEAD
zowel vóór als ná de fix op precies dezelfde testnamen: bekende
omgevingsruis in fontrasterisatie (zie hoofdstuk 29 aldaar), geen regressie.
`flutter analyze` en `dart format --set-exit-if-changed` op de twee gewijzigde
bestanden zijn schoon onder de gepinde SDK
(`/Volumes/SSD/flutter-sdks/3.44.0`, PATH stond op 3.44.4).

CAT1's eigen suite (`test/widgets/tv/tv_unified_media_grid_test.dart`, groep
`CAT1`) is opnieuw gedraaid en blijft groen: deze fix raakt alleen de header,
niet de grid.

Pleya Verify levert hier geen bewijs: geen scenario opent de Complete
Catalog (hetzelfde gat als CAT2 en VER4 al beschrijven; geen duplicaat
toegevoegd). Hardware-acceptatie staat nog open.

### LAND6, een lege landing verbergt de route naar een gevulde catalogus

Gevonden tijdens CAT1 op de simulator, en bewust niet meegefixt.

`TvDiscoveryLandingScreen` gaat bij een lege railsprojectie naar
`_buildEmptyOrLoading`, en dat tekent alleen een tekstblok. De actie
"Alle films" staat in de andere tak, boven de rails. Er is geen andere route
naar de complete catalogus, dus zonder rails is die pagina onbereikbaar.

Dat is niet hetzelfde als "er is niets". Op de simulator stond de Films-landing
leeg terwijl Bibliotheken de Jellyfin-bibliotheek Movies met zes films toonde,
en de catalogus dus wel degelijk iets te tonen had. De hubs kwamen van een
Pleya Server die offline stond; de bibliotheek stond daar los van.

Wat dit nodig heeft is een besluit over wat de landing toont wanneer zij geen
hubs heeft maar er wel een zichtbare bibliotheek is. De lege staat de actie
laten dragen is de kleine ingreep; of de landing in dat geval iets anders hoort
te tonen is een productvraag.

**Gesloten (TV2-taak 2, `f4bb816f`).** Besluit is de minimale ingreep: de lege
staat draagt nu de route naar de complete catalogus, de landing zelf wordt niet
heringericht. Zie de LAND6-rij hierboven voor de negatieve controle en de
testuitkomst. De landing zelf heringericht bij een lege projectie is bewust
niet gedaan, zie "Wat dit plan bewust niet doet" in de TV2-taakbrief.

### LAND5, herstel op een tegel die de band niet gebouwd heeft

Gevonden tijdens LAND3, en bewust niet meegefixt: het is geen oorzaak van LAND3
en het vraagt een keuze.

`focusGroup` weigert een tegel waarvan de focusnode nog niet bestaat, en de
aanroeper valt dan terug op de eerste tegel van de rail. Dat staat zo in de code
en het is daar ook zo bedoeld: een naburige tegel focussen zou de kijker op een
titel zetten die hij nooit gekozen heeft.

Het gevolg is alleen dat herstel na een detailpagina de onthouden tegel stil
kwijtraakt zodra die ver genoeg naar rechts staat. Gemeten op het canonieke
canvas bouwt een band die op offset 0 staat de tegels 0 tot en met 6 van negen,
dus `focusCurrent()` voor tegel 8 geeft `false` en de kijker komt op tegel 0 uit
in plaats van waar hij was.

`focusColumn` heeft voor precies dit geval wél een pad: de band springt eerst en
neemt de focus op het frame waarop de tegel bestaat. De twee methodes doen dus
iets anders met dezelfde situatie. Het samentrekken is een kleine ingreep, maar
het verandert wat herstel belooft, en dat hoort een besluit te zijn en geen
side-fix.

### VER3, de eerste tegel steekt links buiten de veilige zone

`tvos.discovery.overscan` is rood, en stond al rood vóór LAND3. Dezelfde run op
`f8e0e59` zonder de LAND3-fix geeft byte-identiek dezelfde meting, dus dit is
niet meegekomen met dat werk.

De assertie die valt is `notClipped(discover.rail.item[0.0],
discover.safe_area)`: de tegel begint op 67,617 en de veilige zone op 75,48. Het
verschil van 7,8625 is exact `cardFocusRingGap * scale` bij schaal 1,5725. Dat is
geen toeval maar de constructie van `railLeadInset`, die de band bewust een
ringgap naar links trekt zodat de artwork uitlijnt met de kop erboven. De
meetrect van `FocusableWrapper` is de artwork plus die gap, dus de gap valt
buiten de veilige zone terwijl de artwork er netjes in staat.

Er zitten dus twee dingen tegenover elkaar die allebei gewild zijn: uitlijnen met
de kop, en de focusring binnen de veilige zone houden. Wat er moet gebeuren is
een keuze tussen de inset verruimen en de assertie op de artwork richten in
plaats van op de meetrect. Niet stil dichttrekken.

**Besluit (`faff5ba0`).** De inset verruimd, niet de assertie versmald. De ring
zelf tekent in die gap, dus wat op een echt overscannende TV zou clippen was de
ring, niet een meetartefact. `railLeadInset` ligt nu op `pageInset`, net als elke
andere paginarand; de artwork schuift daardoor één ringgap verder van de kop af
dan voorheen. De bestaande widgettest vergeleek de tegelrect met `railLeadInset`
zelf, wat altijd slaagt ongeacht waar die inset ten opzichte van de echte
veilige zone ligt; hij vergelijkt nu met `pageInset` rechtstreeks en stond rood
op de oude formule.

### VER4, geen fixture levert een rail die kan scrollen

LAND3 bestaat alleen op een rail die langer is dan het scherm. Geen enkele
geseede fixture levert er zo een. `catalog.mixed.v1` geeft vijf rails van
respectievelijk 1, 3, 1, 3 en 1 tegel, afgelezen uit de UI-tree van de
overscan-run; `catalog.shows.v1` heeft tien afleveringen maar die zitten in een
serie en niet in een rail.

Dat raakt meer dan LAND3. `tvos.discovery.density` beweert zeven tegels in
`rail[0]` en `tvos.discovery.overscan` loopt na vijf keer rechts naar
`item[0.5]`, en met deze fixtures kan geen van beide ooit kloppen. De scrollende
helft van beide scenario's toetst op dit moment niets.

Wat dit nodig heeft is een fixture met een hub van een tegel of twaalf. Dat is
opzichzelfstaand werk aan de verificatielaag, geen onderdeel van een bevinding
uit de correctieronde, en het staat hier zodat het niet opnieuw als verrassing
opduikt.

### CAT4, bereikbaarheid van de headercontrols

#### Masterlijsthypothese

"Bron, filters en sortering mogelijk onbereikbaar." Er stond een hypothese
klaar die eerst getoetst moest worden voordat er een focusroute bijgebouwd
werd: de dubbele stap uit NAV1 zou een header kunnen overslaan, met DOWN
vanaf de bovenbalk die in het raster terechtkomt in plaats van op de eerste
headeractie. NAV1 zit met `51186c6` al in deze HEAD.

#### Reproductie

Die hypothese verklaart niets: NAV1's dubbele stap zit in het native
aanraakpad van de Siri Remote, en dat pad bestaat niet in een widget-test die
met `LogicalKeyboardKey`-events werkt. Wat wel reproduceert, met een enkele
druk per stap en zonder timing, is dit: DOWN vanaf de bovenbalk (header),
DOWN de eerste kaart in, LEFT op kolom 0 (rechtstreeks terug naar de
bovenbalk via `onExitLeft`), en dan nogmaals DOWN. Die tweede DOWN komt niet
op de header uit maar weer op dezelfde kaart.

Getoetst tegen de echte productiewidgets: `TvRootShell`, een echte
`SidebarFocusCoordinator` en `TvContentFocusAuthority` (niet de vereenvoudigde
testdubbels uit `tv_destination_restoration_test.dart` en
`tv_unified_catalog_focus_test.dart`, die geen van beide dit mechanisme
aanroepen) en de echte `TvMoviesScreen`/`TvUnifiedCatalogScreen` over een
`UnifiedCatalogProvider` met een gevulde bibliotheek. Zie
`test/screens/tv/tv_catalog_header_reachability_test.dart` voor de volledige
herbouw van `MainScreen`'s TV-focusverdraging (`_focusSidebar`,
`_focusContent`, `_focusTvNestedRoute`) tegen die echte primitives.

#### Root cause

`SidebarFocusCoordinator.focusContent` herstelt bij `restorePreviousFocus:
true` via `contentScope.requestFocus()`, en dat laat Flutter zelf naar de
door de scope onthouden `focusedChild` lopen. Alleen als die leeg is, roept de
methode `focusDefault` aan, en dat is de weg naar
`TvUnifiedCatalogScreen.focusActiveTabIfReady()` die op zijn beurt
`_focusHeader()` aanroept.

De catalogusgrid verlaat je op twee manieren naar de bovenbalk. UP vanaf de
header zelf: de header had dan al de focus, dus `contentScope.focusedChild`
wijst al naar de headeractie. LEFT op kolom 0 van het raster
(`TvUnifiedMediaGrid.onExitLeft`, bedoeld als eendruks-ontsnapping die niet
eerst terug via de header hoeft): die roept `_focusSidebar()` rechtstreeks
aan vanaf een griditem, en dan wijst `contentScope.focusedChild` naar dát
griditem. Bij de eerstvolgende DOWN uit de bovenbalk herstelt Flutter dus naar
de kaart, `contentScope.focusedChild != null` blokkeert `focusDefault`, en
`focusActiveTabIfReady()`/`_focusHeader()` wordt nooit aangeroepen. Precies
het griditem waarvandaan de kijker net wegliep krijgt de focus terug, en de
headeracties zijn voor die druk onbereikbaar.

Hoofdstuk 7.4 (aangehaald in `TvRootShell.onFocusContent`'s eigen
documentatie) is daar expliciet over: "Each destination therefore restores
its own position in `focusActiveTabIfReady` ... the catalog to the header
action you last used. The card itself is one step further down." De
gemeten uitkomst is het omgekeerde van dat contract.

**HYPOTHESE NAV1-DUBBELE-STAP: WEERLEGD ALS VERKLARING.** De werkelijke
oorzaak zit in `SidebarFocusCoordinator.focusContent`'s vertrouwen op
Flutter's eigen focus-scope-geheugen, niet in een timinggevoelig
invoerpad.

#### Waarom de bestaande tests dit misten

Geen enkele test in de repo mount dit mechanisme tegen een scherm met een
header. `tv_unified_catalog_focus_test.dart` bewijst het schermhalf van het
contract (grid ↔ header, header vraagt de shell om de bovenbalk) tegen een
kale `MainScreenFocusScope`-stand-in zonder `SidebarFocusCoordinator`
erachter, met een eigen comment die dat met zoveel woorden zegt:
"the two meet in `MainScreen._focusSidebar`, which no test mounts."
`tv_destination_restoration_test.dart` mount wel de echte `TvRootShell`, maar
zijn `_ShellHost`-testdubbel roept op elk bezoek rechtstreeks
`focusActiveTabIfReady()` aan in plaats van via
`SidebarFocusCoordinator.focusContent`'s `restorePreviousFocus`-tak te lopen,
dus precies het mechanisme dat hier faalt zat niet in dat pad.
`tv_content_focus_authority_test.dart` mount de echte coordinator wel, maar
zonder header: zijn kind is een kale `SizedBox.shrink()`.

#### De fix

`TvUnifiedCatalogScreen._exitGridToSidebar()` (de nieuwe callback achter
`onExitLeft`) zet de focus eerst op de header voordat hij naar de sidebar
gaat: `_focusHeader(); _focusSidebar();`. `FocusNode.requestFocus()` werkt de
onthouden kind van de omsluitende scope synchroon bij, dus de bovenbalk
ontvangt de ring nog op dezelfde druk. `contentScope.focusedChild` wijst
daarna naar de headeractie, precies zoals na een UP vanaf de header zelf, en
de volgende DOWN uit de bovenbalk herstelt via diezelfde weg naar de header
in plaats van naar het griditem.

De grid zelf, `SidebarFocusCoordinator` en `TvContentFocusAuthority` zijn niet
aangeraakt. Een generieke aanpassing aan de gedeelde primitive lag voor de
hand, maar zij kent geen headercontract en bedient ook de desktop-rail; de
kleinste juiste eigenaar is het scherm dat weet dat zijn header de canonieke
herintredeplek is.

#### Blast radius

`onExitLeft` wordt uitsluitend door `TvUnifiedCatalogScreen` gebruikt.
Doorzocht op elke andere `onExitLeft`/rechtstreekse
`onNavigateLeft: _focusSidebar`-uitstap uit een raster of rail: geen enkele.
`WatchlistScreen` deelt hetzelfde `TvCatalogGrid`-raster maar wikkelt geen
`onExitLeft` naar de sidebar, dus buiten bereik. De discovery-rails
(`TvDiscoveryRail`/`TvRailStack`) hebben geen vergelijkbare rechtstreekse
uitstap. CAT4 is daarmee surface-specifiek gebleken, precies zoals de
oorspronkelijke aantekening ("mogelijk onbereikbaar") liet vermoeden.

#### Bewijs

Twee controles in `test/screens/tv/tv_catalog_header_reachability_test.dart`:
een koude DOWN uit de bovenbalk die op de header landt, en de hierboven
beschreven DOWN-DOWN-LEFT-DOWN-reeks die op de header moet blijven landen.
Met de oude `onExitLeft: _focusSidebar` teruggezet stond precies die tweede
controle rood, met de focus op `TvUnifiedCard(group:movie:film0:)` in plaats
van op `TvCatalogFiltersAction`; de eerste bleef groen, wat bevestigt dat
alleen het uitstappad via het raster faalde.

Regressie gedraaid op de directe buren: `tv_unified_catalog_focus_test.dart`,
`tv_unified_catalog_screen_focus_test.dart`, `tv_destination_restoration_test.dart`,
`tv_content_focus_authority_test.dart`, `tv_root_shell_test.dart`,
`tv_catalog_header_bar_test.dart` (CAT3) en `tv_unified_media_grid_test.dart`
(CAT1): allemaal groen. `flutter analyze` en `dart format
--set-exit-if-changed` op de twee gewijzigde bestanden zijn schoon onder de
gepinde SDK (`/Volumes/SSD/flutter-sdks/3.44.0`).

Volledige suite: 6100 groen, 6 skipped, 83 rood, met exact dezelfde 83
falende testnamen als de CAT3-nullijn (78 goldens en de vijf in het oude
`test/widgets/tv_discovery_rail_test.dart`). Geen nieuwe falende test,
geen verschoven testnaam.

Pleya Verify levert hier geen bewijs. `tvos.nav.focus-switches-destination.yaml`
loopt de bovenbalk af maar drukt nooit DOWN in de catalogus; geen scenario
opent de complete catalogus, hetzelfde gat als CAT2, CAT3 en VER4 al
beschrijven. Geen duplicaat toegevoegd. Hardware-acceptatie staat nog open.

### LIB1 en LIB2, allebei uit `a2113c0`

Geen van beide is door de redesign geïntroduceerd, maar de nieuwe
bibliotheekkiezer maakt snel wisselen met één druk veel makkelijker, dus LIB2 is
nu eerder te raken dan eerst.

LIB1 zat in de laatste `else` van de body in
`lib/screens/libraries/libraries_screen.dart`, die een lege `SizedBox` rendert
wanneer er wél zichtbare bibliotheken zijn maar de geselecteerde weg is. Dat
bleek het symptoom en niet de oorzaak; de meting staat hieronder onder "LIB1,
niemand verzoende de selectie met de lijst".

LIB2 zit in de staart van `_loadLibraryContent`, na
`await StorageService.getInstance()`. Die staart is ongeguard, dus een verlaten
aanroep schrijft alsnog zijn eigen bibliotheeksleutel weg en zet de tabcontroller
naar de tab die bij de vórige bibliotheek hoorde. De post-frame callback veertig
regels lager heeft die guard wel.

### TILE1, verworpen

De melding was dat een tegel zonder actie de focus zou klemmen. `TvMenuGrid` zet
voor zo'n tegel geen `canRequestFocus: false`, dus de tegel kan focus krijgen en
het lopen gaat door. Er staat een invarianttest op in
`test/widgets/tv/tv_page_primitives_test.dart`. Bouw hier geen fix voor tenzij
nieuwe hardware-evidence dit tegenspreekt.

### VER2, uitgesteld met reden

Automation-instance-ids escapen `[` en `]` niet. De ids die de productie nu
levert zijn numerieke Plex-sectie-ids en Jellyfin-UUID's, en geen van beide kan
een blokhaak bevatten. Escaleren zodra een audit een id-bron aanwijst die vrije
tekst doorlaat.

### ACT1, acceptance gap

Het predicaat van Activiteit hangt aan een concrete `PlexClient`. Los dit niet op
door het productpredicaat te versoepelen, een tegel te faken of iets op
verifyMode te hardcoderen. Het wacht op een protocolgetrouwe Plex-fixture of op
een echte abstractielaag.

**13 september 2026, MOC-16a (PB-7), `f4d6ad61`.** Het predicaat zelf is
gecorrigeerd: `NowWatchingProvider.isAvailable` (een eigen Plex-server plus
een gepaarde Tautulli-instantie) vervangt `hasOnlinePlexServers`. Dat lost
deze bevinding niet op, want de acceptance gap zat nooit in het predicaat
maar in wat Pleya Verify kan naspelen. Nagekeken: `pleya_verify/`'s
fixtureserver (`pleya_verify/fixture_server/`) fakeert uitsluitend het Pleya
Server-protocol (`/pleya/v1/*`, `docs/pleya-protocol/v1/openapi.yaml`) en
heeft geen Plex-oppervlak en geen Tautulli-oppervlak. `NowWatchingProvider`
praat met een echte `TautulliClient`, Plex-gebonden per constructie
(`TautulliProvider`: "Tautulli has a single admin key"). Een protocolgetrouwe
fixture betekent dus een fake Plex-server plus een fake Tautulli-server in
`pleya_verify`, of een echte Plex/Tautulli-abstractielaag die Verify kan
seeden: allebei nieuwe infrastructuur op de schaal van `PleyaFakeServer`
zelf, geen losse fixture-case in `named_fixtures.dart`. Blijft `ACCEPTANCE
GAP` tot die keuze gemaakt is.

**14 september 2026, T3a-onderzoek.** Een fake Tautulli-server (apiKey-only,
`/tautulli/*` op de bestaande fixture-poort) is gebouwd en getest: `f72466f2`
liet zien dat `NowWatchingProvider.isAvailable` inderdaad geen echte Plex-
verbinding nodig heeft, alleen een gepaarde Tautulli-client en een eigen
server. Wat dat traject blootlegde is een tweede, dieperliggende poort:
`MultiServerManager.isOwnerOrAdmin` (`lib/services/multi_server_manager.dart:281-289`)
geeft expliciet `false` terug voor alles behalve `PlexClient`/`JellyfinClient`,
dus zowel de Tautulli-instellingentegel als de Activiteit-tegel in de Mijn
Pleya-hub blijven onbereikbaar voor een profiel dat uitsluitend via Pleya
Server verbindt, met of zonder Tautulli-fixture. Dat is precies wat deze
bevinding hierboven al waarschuwde: niet oplossen door het productpredicaat
te versoepelen. `isOwnerOrAdmin` bewust niet aangeraakt: die poort dicht
zetten voor Pleya Server raakt ook `lib/widgets/media_context_menu.dart`'s
beheerder-alleen acties, en is een productbesluit dat bij PS-9's nog te
bouwen gebruikers- en rechtenmodel hoort, niet iets voor een fixture-taak om
stilzwijgend te beslissen. De Tautulli-fake-server (`f72466f2`) en
`{{fixture_tautulli}}` (`0aa71164`) blijven staan als klaarstaand
gereedschap voor zodra die poort een besluit krijgt. Blijft `ACCEPTANCE GAP`.

### HERO1, alleen op hardware

De technische kant staat: ratio-bewuste requestgrootte, `ImageType.heroArt`, een
hoger resolutieplafond, en gewone kaarten houden hun kleinere limieten. De
globale wissel van `topCenter` naar `center` is afgewezen omdat één vaste
uitlijning niet alle onderwerpsposities oplost. Alleen heropenen bij een nieuw
concreet geval van hardware.

### OVR1 is twee defecten, en die worden apart bewezen

Gediagnosticeerd op 3 september 2026, zonder productiecode te wijzigen.

De doos van een TV-paneel komt uit `_tvPanelGeometry`
(`lib/widgets/overlay_sheet_geometry.dart:234-267`) en is een fractie van de
viewport. De inhoud van datzelfde paneel schaalt met
`TvLayoutConstants.scaleForHeight` (`lib/utils/layout_constants.dart:77`), die
geklemd is op `[0.85, 1.35]`.

Op tvOS herschrijft `_AppleTvScale` (`lib/main.dart:1007-1046`) de `MediaQuery`
naar schaal 1,85, dus het logische canvas is ongeveer 1038 bij 584. De doos
rekent daar goed mee. De inhoud niet: 584 gedeeld door 1080 is 0,54, en de klem
tilt dat naar 0,85. De inhoud wordt dus ongeveer anderhalf keer groter opgemaakt
dan de doos waar hij in past. Dat is "valt buiten beeld en voelt te groot", en
het is per definitie onzichtbaar op elk oppervlak dat 1080 hoog is, dus ook in
de goldens.

Dat is **OVR1a**. De fix hoort bij de ondergrens van die klem, niet bij de
breedte van een paneel. PB-5 verbiedt expliciet een vaste 760 om dit af te
dekken, en nu is ook duidelijk waarom die niet zou werken: hij corrigeert de
doos terwijl de fout in de inhoud zit.

**OVR1b** is een tweede TV-regel in dezelfde host. `_sheetGeometry`
(`:299-300`) geeft op TV onvoorwaardelijk 400 bij 400, onderaan verankerd. Elf
sheets komen daar terecht doordat ze `presentation:` niet meegeven, en
`MediaContextMenu` bovendien doordat `Platform.isIOS` op tvOS waar is
(`lib/widgets/media_context_menu.dart:239`) zonder een `PlatformDetector.isTV()`
ernaast. Negen andere oppervlakken kiezen wel `panel` en zijn in orde.
`test/widgets/overlay_sheet_geometry_test.dart:209` legt het verschil vandaag
vast als bedoeld gedrag, dus dat besluit hoort mee herzien te worden.

Ze staan apart omdat ze technisch los van elkaar staan en apart bewijs vragen.
OVR1a is een verkeerde schaalbasis en is te vangen met een meting op een canvas
dat niet 1080 hoog is; op 1080 is hij per definitie onzichtbaar, ook in de
goldens. OVR1b is een verkeerde standaardkeuze in de host en is te vangen door
te tellen welke oppervlakken zonder `presentation:` binnenkomen. Eén brede
bevinding "overlay te groot" zou allebei de bewijzen vaag maken. De oplossing
hoort wel gedeeld te zijn: één eigenaar voor de vraag hoe groot een TV-overlay
is, niet een correctie per sheet.

#### OVR1a, niet gereproduceerd

Onderzocht op 3 september 2026, zonder productiecode te wijzigen.

De diagnose hierboven klopt rekenkundig en toch niet in de praktijk. Ze klopt in
de zin dat de klem 0,54 naar 0,85 tilt, zodat inhoud die in rauwe
referentie-eenheden staat 1,5725 keer te groot uitvalt binnen een doos die wel
lineair meeschaalt. Ze klopt niet omdat geen enkel TV-paneel zijn inhoud in rauwe
referentie-eenheden opschrijft.

`tv_unified_layout.dart:14-19` zegt waarom. De basiswaarden in
`TvSourcePickerLayout` en `TvCatalogLayout` zijn voorgedeeld door precies die
klem, zodat een basis van 22 op het canonieke canvas als 18,7 logisch rendert en
daarmee als ongeveer 34 referentie-px.

Gemeten door het echte paneelpad (`OverlaySheetPresentation.panel`, met de
TV-override aan) op 1038x584, met `scaleOf` op 0,85 binnen het paneel en DEC-028
op 1,85:

| token | basis | logisch | referentie-px | band 8.3 |
|-------|-------|---------|---------------|----------|
| `titleFontSize` | 22 | 18,70 | 34,60 | 32-38 |
| `rowPrimaryFontSize` | 16,5 | 14,03 | 25,95 | 23-26 |
| `rowSecondaryFontSize` | 12,5 | 10,63 | 19,66 | 17-20 |
| paneelbox | n.v.t. | 540,6 | 1000 | 900-1040 (14.1) |

Vier van de vier vallen binnen hun band. De bronkiezer, het contextmenu, het
filterpaneel en het sorteerpaneel lezen alle vier dezelfde voorgedeelde
constanten, dus de meting geldt voor alle vier.

De voorgestelde oplossing zou schade aanrichten. Paneelinhoud op de doosbasis
0,5406 laten schalen zet `titleFontSize` op 22,0 referentie-px,
`rowPrimaryFontSize` op 16,5 en `rowSecondaryFontSize` op 12,5, alle drie onder
de ondergrens van hoofdstuk 8.3. Hoofdstuk 14.1 herzien om OVR1a te sluiten
breekt dus hoofdstuk 8.3.

Twee aannames uit de oorspronkelijke diagnose sneuvelen daarmee. De klem is geen
fout maar de plaats waar de 10-voetsvergroting gebeurt, en de basiswaarden zijn
erop afgestemd. En het defect zou onzichtbaar zijn op elk oppervlak van 1080 hoog
"dus ook in de goldens", terwijl de TV-goldens juist op `kTvGoldenSurfaceSize`
draaien, `Size(1038, 584)` volgens `test/test_helpers/golden.dart:55`, precies
het canvas waar de klem actief is.

Het waargenomen hardwaresymptoom blijft staan en wijst naar OVR1b. Een sheet
zonder `presentation:` belandt in de 400x400-doos van `_sheetGeometry`, en
`MediaContextMenu` belandt daar via een tweede weg, doordat `Platform.isIOS` op
tvOS waar is. Dat is een echte verkeerde doos, en het is een eigen item.

#### OVR1b, één eigenaar voor de doos van een TV-overlay

Gereproduceerd en gerepareerd op 3 september 2026.

De reproductie is een widgettest door de echte host op het canonieke canvas
1038x584, met de TV-override aan en een sheet die geen `presentation:` meegeeft,
precies zoals elf oppervlakken dat doen. Gemeten rechthoek vóór de fix: 400 breed
en 400 hoog, met de onderrand op 584. Dat is 740 bij 740 referentie-px op een
1920x1080-uitvoer, tegen de band 900 tot 1040 van hoofdstuk 14.1, en de onderrand
raakt de viewportrand, dus hij ligt in de overscanband die hoofdstuk 8.1 juist
vrijhoudt. De assertie die omviel was het middelpunt: 384 waar 292 hoort.

De eigenaar is `resolveOverlaySheetGeometry`
(`lib/widgets/overlay_sheet_geometry.dart`). Die stuurde alleen `panel` naar
`_tvPanelGeometry`; `_sheetGeometry` had daarnaast een eigen TV-tak met 400 bij
400 en behield de bodemuitlijning van de aanroeper. Op TV gaat nu elke
presentatie naar `_tvPanelGeometry`, en `_sheetGeometry` kent het begrip TV niet
meer. Na de fix meet dezelfde rechthoek 540,6 bij 490,6 logisch, oftewel 1000 bij
907 referentie-px, gecentreerd, met 86 referentie-px lucht boven en onder.

Dat lost het tweede pad meteen mee op. `MediaContextMenu` kiest zijn
bottom-sheet-tak op `Platform.isIOS`, wat op tvOS waar is
(`lib/widgets/media_context_menu.dart:239`). Die regel blijft staan: de andere
tak is een `showMenu` op een aanwijzerpositie, en dat is op een afstandsbediening
het verkeerde antwoord. Wat er fout aan was, was niet de tak maar de doos
erachter, en die heeft nu één eigenaar.

Twee besluiten die het oude gedrag vastlegden zijn herzien, want anders staat de
fix per definitie rood: `sheet` op TV was 400 bij 400 in
`test/widgets/overlay_sheet_geometry_test.dart` en in
`test/widgets/overlay_sheet_test.dart`, en `tv_catalog_foundation_test.dart`
controleerde dat een TV-sheet géén schaduw werpt. Alle drie meten nu dat een
sheet op TV exact hetzelfde oplevert als een panel.

Twee gevolgen die opzettelijk zijn en die Michel mag afwijzen. De compacte
sync-balk van de speler vraagt `alignment: topCenter` met een eigen doos van 900
bij 80 (`video_settings_sheet.dart:336`); op TV komt die nu in het midden in
plaats van tegen de bovenrand, want `_tvPanelGeometry` centreert altijd. En een
aanroeper die zelf constraints meegeeft wordt op TV voortaan door de viewport
geklemd, waar het oude sheet-pad zo'n wens ongemoeid doorliet.

#### OVR2, expliciete presentatie verdwijnt onder de gedeelde TV-doos

Regressie, ontstaan in `96f2d45`. Geregistreerd op 3 september 2026, nog zonder
wijziging in productiecode.

OVR1b heeft terecht de losse 400x400-fallback voor TV weggehaald. De gekozen
resolver stuurt sindsdien echter ook sheets die hun presentatie wél expliciet
opschrijven door dezelfde generieke TV-paneelgeometrie, en die centreert altijd.
De compacte sync-balk van de speler vraagt `alignment: topCenter` met een eigen
doos van 900 bij 80 (`video_settings_sheet.dart:336`) en verschijnt op TV nu in
het midden van het beeld.

Dit item is niet "OVR1b terugdraaien". Het contract van OVR1b blijft gelden voor
elke TV-sheet die geen presentatie opschrijft: die krijgt de gedeelde TV-veilige
paneelgeometrie en nooit meer de oude 400x400-doos. Wat erbij hoort is het
onderscheid dat OVR1b niet maakte. TV-veilig is iets anders dan
TV-gepaneleerd.

Het contract dat hieronder bewezen moet worden heeft twee helften. Een sheet
zonder eigen geometrie is een default sheet en volgt OVR1b. Een sheet die
alignment of constraints meegeeft is een expliciete sheet: die houdt zijn
uitlijning, houdt zijn gevraagde maat zolang de veilige viewport dat toelaat, en
wordt alleen geklemd wanneer de viewport dat afdwingt. Klemmen is een maat
bijstellen, geen presentatie vervangen.

De stand van origin/main hoort er expliciet bij. Op het moment van registreren
staat main op `183d694` en bevat main OVR1b niet: `96f2d45` en `ec66f1a` staan
alleen op `claude/netflix-redesign-b4x21v`. Deze regressie is dus nog niet naar
main gelekt, en de hotfix gaat bovenop `ec66f1a`.

**Afgerond op 3 september 2026 in `cf4b6c7`.**

**Oorzaak.** `resolveOverlaySheetGeometry` kende maar één vraag op TV, namelijk
of het toestel een televisie is, en stuurde daarna alles naar
`_tvPanelGeometry`. De aanroeper kon niet zeggen dat hij zijn plek zelf al
gekozen had, want `alignment` had een niet-nullable standaardwaarde
`Alignment.bottomCenter` tot in `OverlaySheetController.show`. "Geen mening" en
"bewust onderaan" waren daardoor dezelfde waarde, en dus was er geen signaal om
op te beslissen.

**Fix.** `alignment` is van de publieke `show` tot in de resolver `Alignment?`
geworden, met null als betekenis "de host beslist". Op TV splitst de resolver
daarop: null gaat naar `_tvPanelGeometry` en houdt OVR1b precies zoals hij was,
en een genoemde alignment gaat naar `_tvPlacedSheetGeometry`. Die haalt al zijn
getallen bij `_tvPanelGeometry` op, dus er is nog steeds één eigenaar van de
vraag hoe groot een TV-overlay mag zijn en hoe ver hij van de rand blijft, en
verandert alleen de plaatsing. `_sheetGeometry` weet nog altijd niets van
televisies af.

Er kwam één veld bij, `verticalEdgePadding`, standaard 0. Alleen een oppervlak
dat zichzelf op een TV plaatst zet hem, want de buitenste band van een televisie
is overscan: een balk die tegen de bovenste scanlijn plakt verliest zijn eerste
regel. De layoutdelegate rekent de band per as uit met dezelfde formule, en bij
0 komt daar exact de oude berekening uit.

Daar zat nog een randgeval in dat hierdoor zichtbaar werd. De delegate gaf zijn
kind de breedte min twee keer de marge, maar besloot pas tot marge bij `size >
child + 2 * padding`. Een kind dat die breedte precies vulde viel dus door de
strikte vergelijking heen en werd tegen de linkerrand gezet, met alle ruimte aan
de andere kant. Dat raakt ook een desktoppaneel in een venster van 600 breed.
De band wordt nu geklemd in plaats van vertakt.

De maten van de sync-balk staan voortaan als `kCompactSyncBarAlignment` en
`kCompactSyncBarConstraints` in `video_settings_sheet.dart`, zodat de test het
contract leest in plaats van de getallen te herhalen.

**Meting op 1038x584.** Voor: rechthoek 900 bij 80, bovenrand op 252, midden op
292, oftewel gecentreerd. Na: 900 bij 80, bovenrand op 38,9, midden op 78,9. De
veilige inset van 38,9 logische px is hoofdstuk 8.1's 72 referentie-px. Een
gevraagde breedte van 1100 komt terug als 960,15, en de bovenrand blijft op
38,9: klemmen past een maat aan, het verplaatst geen oppervlak.

**Negatieve controle.** Met alleen de discriminator terug op OVR1b-gedrag vallen
zes tests om, waaronder de echte caller met `Expected: 38.925 Actual: 252.0` en
`Expected: topCenter Actual: center`. De default-sheet guards blijven daarbij
groen, dus wat rood wordt is de regressie en niet de OVR1b-winst. Met de
discriminator terug zijn alle 58 groen.

**OVR1b-guard.** De 400x400-doos is niet teruggekomen. De guard staat op twee
plekken: een grep-controle op de resolver en de assertie dat een geplaatste
TV-sheet nooit op 400 uitkomt maar binnen de band 900 tot 1040 blijft.

**OVR1a.** Niet aangeraakt. `layout_constants.dart` en `tv_unified_layout.dart`
staan ongewijzigd ten opzichte van `ec66f1a`.

**Audit.** Van de 34 aanroepen in `lib/` gebruiken er 11 expliciet `panel`, 22
noemen niets, 1 geeft alleen constraints mee (de bibliotheek-quickpicker, die
paneel blijft en zijn hoogte houdt) en precies 1 noemt een alignment. Er is dus
geen tweede geval en geen aanroeper die een uitzondering per scherm nodig heeft.

### BACK1, gemeten en opgelost

De oorspronkelijke waarneming klopte en was niet compleet. `AppBarBackButton`
is een `MouseRegion` om een `GestureDetector` en draagt nergens een
`FocusNode`, dus hij staat niet in de traversal-set van de afstandsbediening,
en tvOS heeft geen cursor om hem mee aan te wijzen. Wat de codelezing er niet
uit haalde is dat de twee aanroepplekken zich verschillend gedragen, en dat
dezelfde fout een derde keer in een andere widget zit.

**Wat er gemeten is.** Op een TV-detailpagina van 1920 bij 1080: één zichtbare,
hit-testbare `AppBarBackButton` met nul `Focus`-widgets erin. Op een
full-window route die op TV gepusht wordt met een `CustomAppBar`: hetzelfde
beeld. Op diezelfde route, maar geopend als geneste route in de shell: nul.
Dat laatste is geen toeval en ook geen tweede bug. `buildLeadingSection`
raadpleegt `ModalRoute.canPop` en verder niets over de invoermodaliteit, en de
omliggende `ModalRoute` van een geneste route is die van de shell zelf, waarvan
`canPop` false is. De impliciete leading kwam er dus alleen op het pad dat
SYS-1 nog moet vervangen. Wie dit met grep leest ziet die asymmetrie niet.

**De derde plek.** Zoeken op de vorm in plaats van op de klassenaam leverde
`BottomSheetHeader` op. De terugpijl van een sheet-subpagina ligt daar op een
`InkResponse` binnen `ExcludeFocusTraversal`. Een gemeten sheet-subpagina op TV
had nul traversal-bereikbare knopen in zijn kop, met een terugpijl erin. Zelfde
contract, zelfde defect.

**Root cause.** Niets in de constructie van de knop en niets in de twee
impliciete-leading-plekken vraagt welke invoermodaliteit het oppervlak bedient.
Op TV is de app remote-first: `InputModeTracker` zet `InputMode.keyboard` vast
en verlaat die stand daar nooit.

**Eigenaar van de presentatie** is `AppBarBackButton` zelf, want alle vijf de
bouwplekken maken die widget. **Eigenaar van de terugroute** is de toets:
`handleBackKeyAction` en `handleBackKeyNavigation` in
`lib/focus/key_event_utils.dart`, `tvBackStep` in de shell, en
`TvNestedRouteScope.dismiss` voor een geneste route.

**De fix** zet de regel op één plek, `showsVisibleBackAffordance()` naast de
knop. De knop bouwt niets meer wanneer die false is, waarmee een nieuwe
aanroeper tegen dezelfde fout beschermd is, en beide impliciete-leading-plekken
raadplegen hem ook, zodat `leading` null blijft en de app bar geen breedte
reserveert voor een knop die er niet is. Geen enkele aanroeper heeft een eigen
uitzondering nodig.

**Aanroeperaudit, elf plekken.** Weggehaald op TV: de TV-tak van
`MediaDetailScreen`, beide impliciete-leading-plekken in `desktop_app_bar.dart`,
`VideoControlsHeader` (TV neemt bewust het desktop-pad) en `BottomSheetHeader`.
Ongewijzigd omdat ze al focusbaar zijn: de terugknop in
`video_player/parts/build.dart` is een `FocusableButton`, en die in
`tv_info_panel.dart` een `IconButton` met een eigen node. Ongewijzigd omdat ze
op TV niet tekenen: `settings_screen.dart` en `logs_screen.dart` hebben een
eigen `_buildTv`-tak, `my_pleya_screen.dart` bestaat daar niet, en
`watchlist_screen.dart` en `libraries_screen.dart:1626` zetten
`automaticallyImplyLeading: false`. `FocusedScrollScaffold`, `SettingsPage`,
`ProfileSwitchScreen` en `WatchTogetherScreen` lopen alle vier via
`CustomAppBar` en zijn daarmee door de gedeelde poort gedekt.

**Negatieve controle.** Met de productiecode terug op `88d9868` vallen precies
de zes TV-assertions om en blijven de zes pointer-tweelingen groen, plus de
geneste zaak die nooit geraakt was. Dat wat rood wordt is de regressie en niet
iets anders.

**Goldens.** Twee beelden verschuiven, `tv_detail_source_line.png` en
`tv_detail_no_source_line.png`, allebei met exact 1316 gewijzigde pixels binnen
de doos van 40 bij 40 op (8,8). Dat is de weggehaalde knop en verder niets, tot
op de pixel. Ze zijn geregenereerd in een Linux-container die de bestaande
referenties eerst byte-identiek reproduceerde; daarna is de golden-delta van de
hele map daar nul. Op macOS blijven ze rood zoals ze dat vóór deze wijziging
ook waren, want de goldensuite is op deze machine breed rood door
fontrasterisatie.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. Pleya Verify kon
het niet leveren: het enige scenario dat de detailpagina bereikt is
`media-detail.episode-refresh`, en dat faalt op een stap ervóór. Een
controlerun op `88d9868` faalt identiek, met dezelfde focus-trace, dus dat is
geen gevolg van deze wijziging. Het staat als VER5 in de tabel.

### FOC2, geometrie en niet clipping

Een focusring die buiten beeld valt heeft twee mogelijke oorzaken die op een
foto niet uit elkaar te houden zijn. Of de ring wordt op een plek getekend die
het toestel niet toont, of hij wordt wel op een zichtbare plek getekend maar
door een voorouder weggeknipt. De fixes zijn tegengesteld, en clippen maakt het
symptoom onzichtbaar zonder het probleem te raken. Deze bevinding had geen
vooronderzoek in dit document, dus is eerst gemeten welke van de twee het is.

**Wat er gemeten is.** Een wegwerpprobe zette elk TV-overlay op het
tvOS-canvas van 1038 bij 584 neer, gaf elke focusbare knoop om de beurt focus,
en vergeleek drie rechthoeken: de layoutbox, de werkelijk getekende box (de
`Transform.scale` van `FocusableWrapper` geldt voor het kind van de transform
en niet voor de transform zelf, dus meten op de transform geeft altijd
schaal 1) en de rect van elke knippende voorouder in de keten naar de root.

Het sorteerpaneel en alle vijf de secties van het filterpaneel kwamen er schoon
uit. De rijen daar zetten `disableScale` en tekenen hun rand naar binnen, dus
getekend en layout vallen samen, en de scrollviewport knipt exact op de
rijgrens. Het contextmenu niet. Op een tegel rechtsonder liep de onderste regel
tot 555 van de 584, op een tegel linksboven begon de bovenste op 8, en in geen
van beide gevallen knipte er iets: geen enkele voorouder rapporteerde overlap.
De regel wordt dus volledig getekend, alleen in de band die een televisie niet
laat zien. Geometrie.

**Root cause.** `_AppMenuPopupState` in `lib/widgets/app_menu.dart` klemt zijn
positie met `const edgePadding = 8.0` tegen de kale schermrechthoek, op elk
platform. Acht pixels is op een telefoon de bedoeling. Op een televisie ligt
dat ruim binnen de titel-veilige marge die de rest van de TV-UI wel aanhoudt:
48 opzij, 56 boven en 81 onder, maal de TV-schaal. Alle vier de klemmingen in
`_resolvePosition` deelden dezelfde fout en dezelfde vorm.

**Eigenaar** is `showAppMenu`, niet de aanroeper. Het contextmenu op een
tegel, de knop in de folder-boom en de twee menu's in de tv-gids gaan alle vier
door deze ene positielogica heen, en drie ervan zijn op TV te openen.

**De fix** vervangt de scalaire marge door een `EdgeInsets` die op TV uit
dezelfde constanten komt als de titel-veilige rechthoek die
`TvDiscoverySafeArea` meetbaar maakt, en buiten TV acht pixels blijft. De vier
klemmingen staan nu in één helper die de ondergrens laat winnen wanneer het
menu niet tussen beide marges past, want klemmen op een ondergrens boven de
bovengrens is in Dart een assertie.

**Bewijs.** `test/widgets/app_menu_tv_safe_area_test.dart` opent het menu op
drie schermhoeken op 1920 bij 1080 en eist dat elke regel binnen de
titel-veilige rechthoek valt, met een vierde test die vastlegt dat een telefoon
op acht pixels blijft klemmen. De drie TV-tests stonden op de oude
implementatie rood, met rijen op x=14, x=1906 en y=936 tegen een veilige zone
van 48 tot 1872 en 56 tot 999; de mobiele test was toen al groen en is dat
gebleven. `test/widgets` en `test/goldens` gingen van 802 geslaagd en 86
gefaald naar 805 en 83: precies deze drie, verder niets. De 83 die overblijven
zijn niet van deze wijziging. Vijf zitten in `tv_discovery_rail_test.dart` en
falen identiek met en zonder de fix, de rest is de goldensuite, die op macOS
breed rood staat omdat de referenties op Linux gemaakt zijn.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. De maat die
telt is of de bovenste en onderste regel van een contextmenu op het toestel
volledig zichtbaar zijn, inclusief hun focusindicatie, en dat kan alleen daar.

### ART1, de aanvraag was te klein, de compositie klopte

Ook deze bevinding had geen vooronderzoek. "Te ver ingezoomd" kan twee dingen
betekenen die je op een foto niet uit elkaar houdt: de compositie is strakker
gecropt dan bedoeld, of het beeld is te klein binnengekomen en over het scherm
opgeschaald. Allebei zijn te meten, dus allebei gemeten.

**De compositie klopt.** Een probe zette het spotlight op een oppervlak van
1920 bij 1080 en las de bron, de doos en de `BoxFit` uit de `RenderImage`. Met
een echte 16:9-backdrop is het resultaat 100% van de bron zichtbaar bij
vergroting 1,000. Er zit geen enkele extra `Transform` in het detailpad: de
ken-burns-zoom staat daar uit, en de reveal-gate animeert alleen dekking.

**Vierkante art is geen defect.** Diezelfde probe laat zien dat een vierkante
bron in een 16:9-doos op 1,778 vergroot en 43,7% van het beeld verliest. Dat
ziet er inderdaad uit als "te ver ingezoomd", maar het is een keuze die al
vastligt: `BillboardArt.canRenderSharp` zegt expliciet dat een vierkante bron
scherp getekend mag worden, en de fase-8 herokaart doet hetzelfde. Hier iets
aan veranderen is een ontwerpvraag, geen bugfix, en valt buiten deze bevinding.

**Wat wel misging is de aanvraag.** Het spotlight vroeg zijn artwork op als
`ImageType.art`. Dat type plafonneert op 2560 bij 1440, een bewuste maat voor
een retina-desktoppaneel. Op een Apple TV 4K is dit oppervlak het hele scherm,
3840 bij 2160 fysieke pixels, dus kwam elke backdrop anderhalf keer te klein
binnen en werd hij beeldvullend opgeschaald. `ImageType.heroArt` heeft precies
dat oppervlak als plafond. De fase-8 herokaart is in DEC-057 om exact deze
reden al overgezet, met in `tv_hero_artwork.dart` de notitie dat elke backdrop
daar 1,38 keer te klein aankwam; het detailscherm bleef achter.

**De fix** kiest het type op TV en laat desktop en mobiel op de bestaande cap
staan, want ditzelfde scherm is daar de aanbevolen-tab. Het decodeerbudget gaat
mee: 3840 ophalen en in 2560 decoderen is dezelfde onscherpte langs een andere
weg, en dat staat al zo in `getMemCacheDimensions`.

**Bewijs.** `test/widgets/tv_spotlight_request_size_test.dart` legt met een
neptclient vast met welke maten `thumbnailUrl` geroepen wordt. Op een oppervlak
van 3840 bij 2160 vroeg de oude implementatie 2560 breed aan; die test was rood
en is nu groen. De tweede test bewaakt de desktopkant en werd rood zodra de
keuze niet meer aan het platform hing, wat ook gecontroleerd is. `test/widgets`
en `test/goldens` gingen van 805 geslaagd naar 807, met 83 falers die
onveranderd bleven.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. Of dit de
waarneming volledig verklaart is daar te zien en nergens anders: als het beeld
na deze wijziging nog steeds te strak oogt, dan gaat het over compositie en
overscan en niet over resolutie, en dan is de vervolgvraag of de backdrop op
detail dezelfde band mag pakken als in mockup 09.

### LIB1, niemand verzoende de selectie met de lijst

De lege `SizedBox` in de laatste `else` was het symptoom. De oorzaak zit een
laag hoger: er was geen enkele plek die de geselecteerde bibliotheek opnieuw
tegen de bestaande bibliotheken hield.

**Twee routes, dezelfde tak.** `LibrariesProvider` vervangt bij een herlaad zijn
hele lijst en houdt `isLoading` daarbij bewust op false, wat in
`_loadLibrariesInternal` als `reloadInPlace` gedocumenteerd staat en er is om te
voorkomen dat een reload het scherm terug naar een spinner gooit. Een server die
wegvalt neemt dus zijn bibliotheken mee zonder dat het scherm ooit door een
laadtoestand gaat. De selectiestap draaide daarna niet opnieuw: die hangt aan
een post-frame callback in `initState` die één keer loopt. Diezelfde callback
geeft het bovendien meteen op als de provider bij mount nog leeg is, dus een
lijst die later binnenkomt (koude start, profielwissel, een server die in een
tweede golf bindt) landt op precies dezelfde tak. In het eerste geval wijst de
sleutel naar niets meer, in het tweede is er nooit een sleutel gezet.

**Wat je op TV zag.** De kopregel viel terug op de generieke titel, en
`showHeaderBar` is `useSideNavigation && selectedLibrary != null`, dus met de
kopregel verdween ook de bibliotheekkiezer. Blanco pagina, geen tabs, geen
kiezer, en daarmee geen route naar een bibliotheek die er wel was. Op mobiel is
het net anders en niet minder verwarrend: `_buildLibraryDropdownTitle` valt
terug op `visibleLibraries.firstOrNull`, dus de dropdown noemt een bibliotheek
terwijl het scherm eronder leeg blijft.

**Gemeten, niet aangenomen.** De reproductie draait het echte scherm tegen de
echte providers. Films, Series en Kids geladen, Series geselecteerd, daarna een
stabiele lijst met alleen Films en Kids: `isLoading=false`, kopregel
`Libraries`, nul kopregelbalken. Voor de tweede route: gemount met een lege
provider, daarna twee bibliotheken erin, kopregel `null`, nul kopregelbalken, en
dat bleef zo staan.

**Objectidentiteit was niet de verdachte.** De selectie is een `String` en de
lookup vergelijkt `globalKey`, dus een reload die nieuwe instanties oplevert
raakt de selectie niet. Een tijdelijk lege lijst evenmin: die valt in de
loading- of de lege-staattak en gooit de sleutel niet weg, waarna de repopulatie
hem gewoon weer oplost. Alleen een stabiele lijst waarin de selectie ontbreekt
raakt LIB1.

**De fix** is één verzoener op de provider. Geldige selectie blijft met rust,
een dode sleutel gaat weg voordat er iets tekent, en de opvolger wordt via
`_loadLibraryContent` geladen zoals een druk op de afstandsbediening dat doet,
zodat de bewaarde sleutel, het per-bibliotheek tabherstel en de focusoverdracht
op hun bestaande contract blijven. De terugvalregel staat nu op één plek:
bewaarde sleutel als die nog zichtbaar is, anders de eerste zichtbare
bibliotheek, wat exact is wat de initialisatie en het verbergen van een
bibliotheek altijd al deden. Is er niets om naar terug te vallen, dan blijft de
echte lege staat staan. De blanco tak zelf is nu de laadindicator, want met de
verzoener erbij is dat een toestand van hooguit een frame.

**Focus hoorde erbij.** Een probe liet zien dat de afstandsbediening strandde:
focus stond op de chip van Series, die chip verdween, en primaire focus viel
terug op `_ModalScopeState<dynamic> Focus Scope`, precies de toestand die
`FocusMemoryTracker.pruneExcept` beschrijft als een oppervlak waarin je niet
kunt bewegen en dat je niet kunt verlaten. De kiezer ruimt zijn nodes nu op en
zet de focus op de chip van de bibliotheek waar de pagina naartoe geschakeld
is. De chipsleutel staat daarvoor op één plek in `tv_library_chooser.dart`; met
twee kopieën van die string zou het prunen elke overlevende node per rebuild
weggooien, wat in de eerste ronde ook precies gebeurde.

**Negatieve controle.** Drie van de vijf tests zijn rood op de oude
implementatie: kopregel `Libraries` in plaats van `Films`, `null` in plaats van
`Films` na late aankomst, en `_ModalScopeState<dynamic> Focus Scope` in plaats
van de overlevende chip. De andere twee zijn aan beide kanten groen en staan er
juist om te bewaken wat niet mocht veranderen: een selectie die de update
overleeft blijft exact staan, en alle bibliotheken kwijtraken geeft de lege
staat en geen blanco pagina.

**Testen.** `scripts/ci_checks.sh` groen, inclusief `flutter analyze` zonder
errors of warnings en de unused-code-controles. Volledige suite 6137 geslaagd,
6 overgeslagen, 83 rood, met dezelfde falers als de ART1-nullijn: buiten
`test/goldens` blijven er exact vijf over, alle vijf in het oude
`test/widgets/tv_discovery_rail_test.dart`. Nieuwe falers: geen.

**Verify kan dit niet bewijzen.** De fixtureserver kent `seed`, `add_episode`,
`mark_watched`, `expire_session`, `fail_next`, `latency` en `echo`. Geen daarvan
verandert de verzameling bibliotheken tijdens een run, en dat is precies wat
LIB1 nodig heeft. Dit is een ander gat dan CAT2, CAT3 en VER4 beschrijven: die
gaan over de diepte van rails en de catalogus, niet over het muteren van de
bibliotheekset. Een `fixture_mutate`-op die een bibliotheek intrekt is de
ontbrekende schakel; die bouwen valt buiten LIB1.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. Wat daar nog te
zien is, is of de overgang ook prettig oogt: de laadindicator hoort in de
praktijk niet waarneembaar te zijn, en de focus hoort zichtbaar op de nieuwe
chip te landen in plaats van er te verschijnen. Bundel dat met de andere open
fysieke items van deze ronde. `libraries_screen.dart` staat inmiddels op
ongeveer 2050 regels en is daarmee ruim over de eigen richtlijn; opsplitsen is
echter geen onderdeel van deze bevinding en verdient een eigen ronde met eigen
bewijs.

### LIB2, de verlaten aanroep kwam terug en herstelde zijn eigen tab

De melding was een race bij snel wisselen. De meting bevestigt hem, en wijst
één side effect aan dat werkelijk blijft staan.

**De grens.** `_loadLibraryContent` legt zijn bibliotheek synchroon vast:
`_updateVisibleTabs`, de selectiesleutel, `_loadedTabs` leeg, en de melding aan
de zijbalk. Daarna hangt hij op `await StorageService.getInstance()`, en meteen
erna een tweede keer op `await storage.saveSelectedLibraryKey(...)`, want die
write awaits binnenin `notifyMutation` de app-brede preference-pijplijn. Alles
achter die twee awaits liep ongeguard door.

**Wat er stale bleef, en wat niet.** Gemeten met een gecontroleerde gate op
`BaseSharedPreferencesService.onMutation`, met Films opgehouden en Series er
helemaal doorheen:

| Side effect | Uitkomst op de oude implementatie |
| --- | --- |
| `saveSelectedLibraryKey` | ongeguard uitgevoerd voor een verlaten intentie, maar de `setString` van Films landde vóór die van Series, dus de eindwaarde bleef Series |
| tabherstel (`getLibraryTab` + `_visibleTabs.indexOf` + `animateTo`) | **stale**: het scherm toonde Series onder Playlists, de tab waar Films op stond |
| `saveLibraryTab` vanuit `onTabChanged` | niet stale; `_isRestoringTab` houdt stand, want `animateTo` met `Duration.zero` meldt synchroon |
| post-frame focus | niet stale bij A → B; de sleutelvergelijking ving hem af |

Die persistentievolgorde is geen contract van dit scherm. Twee `getInstance`-
aanroepen hervatten in registratievolgorde en het prefs-kanaal is FIFO, dus in
deze interleaving wint de laatste write. Een stale eindwaarde is dus niet
gereproduceerd, en dat staat hier als meting en niet als garantie: de guard
maakt de coherentie een eigenschap van de code in plaats van van de volgorde.

**De eigenaar is de aanroep, niet de sleutel.** `_loadLibraryContent` neemt bij
binnenkomst een generatie en controleert die na allebei de awaits; de post-frame
focus hangt aan dezelfde generatie. Sleutelgelijkheid sluit elk gemeten stale
effect bij A → B ook af, maar hij laat A1 weer toe zodra de sleutel opnieuw A
is. Een teller loopt maar één kant op en kost één `int`.

**ABA, eerlijk gemeten.** A → B → A met A1 als laatste hervatting is op de oude
implementatie groen. De staart is een pure functie van `libraryGlobalKey` en de
opslagstand op het moment van hervatten, dus A1 en A2 doen exact hetzelfde en er
kan geen waarde uiteenlopen. Wat A1 wél deed is de staart een tweede keer
draaien: nog een write en nog een focusverzoek. De test staat er als controle op
wat niet mag veranderen, en vangt het moment waarop iemand een side effect
toevoegt dat niet sleutelpuur is.

**LIB1 was een tweede schrijver op dezelfde staat.** `_reconcileSelection` laadt
zijn terugval via `_loadLibraryContent`, precies zoals een druk op de
afstandsbediening, dus hij erfde het gat één-op-één. Een gebruiker die Series
koos terwijl de terugval naar Films nog laadde, kreeg Films' tab. Die case is
rood op de oude implementatie en staat nu in de suite.

**Negatieve controle.** Vier tests in
`test/screens/libraries/libraries_rapid_switch_test.dart`. Alleen `libraries_screen.dart`
teruggezet naar de oude implementatie: twee rood met dezelfde concrete stale
staat (`Expected: 'Collections'`, `Actual: 'Playlists'`), namelijk de snelle
wissel en de reconciliatie-case. De andere twee zijn aan beide kanten groen: het
ABA-geval en de gewone sequentiële wissel.

**Geen timing in de tests.** `onMutation` wordt binnen elke preference-write
geawait, dus daar één bibliotheek ophouden hangt exact die aanroep op exact de
grens waar de bug leeft, terwijl de andere afloopt. Geen `Future.delayed` als
racebewijs, geen pumpduur, geen herhaling.

**LIB1-regressie.** De vijf LIB1-tests groen, plus `libraries_provider`,
`hidden_libraries_provider`, `tab_navigation_mixin`, `library_tab_state`,
`tv_library_chooser`, `base_library_tab_focus` en `tv_nested_surface`: 74
geslaagd. De verzoener wordt door de generatie niet geblokkeerd; hij bumpt hem
zelf, zoals elke andere aanroeper.

**Testen.** `scripts/ci_checks.sh` groen, inclusief `flutter analyze` zonder
errors of warnings, `dart format` over 1475 bestanden en de unused-code- en
unused-files-controles. Volledige suite 6141 geslaagd, 6 overgeslagen, 83 rood,
met exact de LIB1-nullijn: 78 goldens en dezelfde vijf in het oude
`test/widgets/tv_discovery_rail_test.dart`. Nieuwe falers: geen. De vier
erbij gekomen geslaagde tests zijn deze bevinding.

Over G15: er bestaat in deze repo geen gate met die naam voor deze ronde. De
enige treffer is `docs/pleya-server-masterplan-proposal.md:2780`, een
hoofdstuk-checkbox van het Pleya Server-masterplan, die dit werk niet raakt. Wat
LIB1 als "G15 baseline groen" noteerde is de volledige-suite-nullijn hierboven,
en die staat ongewijzigd.

**Verify kan dit niet bewijzen.** De fixtureserver kent `seed`, `add_episode`,
`mark_watched`, `expire_session`, `fail_next`, `latency` en `echo`. `latency`
vertraagt de HTTP-fixture; de race zit in de lokale `StorageService` en wordt
door geen enkele op geraakt. Een product-only vertragingsknop erbij bouwen om
Verify het venster te laten zien is precies wat hier niet moet gebeuren. Dit is
geen productblocker: de widget-tests bezitten de scheduler volledig.

**Wat open blijft.** Geen bewijs van een echte Apple TV, en dat is voor deze
bevinding ook niet nodig: de race is door bestuurde futures volledig
dichtgetimmerd. Bundel de fysieke smoke met de andere open items van deze ronde.
`libraries_screen.dart` staat op ongeveer 2060 regels; opsplitsen blijft een
eigen ronde met eigen bewijs, zoals LIB1 al vaststelde.

### LIB3, de rul was de derde staataffordance op één scherm

Anders dan LIB1 en LIB2 is dit geen state-race maar een visuele bevinding, en
hij had in dit document nog geen regel behalve de tabelregel zelf. Dus eerst
vastgesteld welke tabs het zijn en wat er in plaats van rood hoort te staan, en
pas daarna code.

**Het oppervlak.** De tabrij onder de bibliotheekkiezer op Bibliotheken:
Aanbevolen, Bladeren, Collecties, Afspeellijsten. Die komt uit
`TabNavigationMixin.buildTabChip`, die `FocusableTabChip` bouwt in zijn
standaardstijl `TabChipStyle.underline`. De open tab kreeg daar een balk van
twee pixels breed als het label, in `tk.accent`, het merkrood `#E5140F`.

**Gereproduceerd op het echte doel.** Een Debug-build in de tvOS-simulator,
ingelogd op de demoserver, via Mijn Pleya naar Bibliotheken. De rode rul staat
er, onder Aanbevolen, en loopt dwars door het herobeeld eronder. Screenshot
`before-02-bibliotheken.png`; de vergelijking voor en na staat in
`docs/assets/tvos-unified/mockups-2026-09-02/compare/libraries-tabrul-voor-na.png`.
Niet alleen bekeken maar geteld: in de band van honderd pixels onder de tabrij
zaten 1806 pixels op accentrood, en nul erna.

**De bedoeling lag al vast, op twee plekken.** De styling-audit van 2 september
schrijft bij Bibliotheken letterlijk "de tabs blijven, zonder rode
onderstreping", en de mockup die daarbij hoort, `libraries-d.png`, tekent de
open tab als vet witte tekst naast gedempte buren en zet er niets onder. De set
die op 3 september is goedgekeurd zegt hetzelfde van de andere kant: het
merkrood is er voor de progreslijn en de opnamemarkering, en verder niet. De
handoff van 3 september noteerde dit al als bewust overgeslagen, want die ronde
was beperkt tot de kiezer. `tv_page_chip_bar.dart` benoemt in zijn eigen
kopcommentaar precies deze tabrij als de tweede helft van hetzelfde defect.

**Waarom het opvalt en de audit het telde.** Op datzelfde scherm waren er drie
manieren om te zien waar je staat: de witte ring, de verticale balk van drie
pixels op Instellingen, en deze rode rul. Eén oppervlak hoort er één te hebben.

**De fix zit bij de gedeelde eigenaar.** `FocusableTabChip` bepaalt de kleur van
zijn rul nu op één plek, en die is op TV doorzichtig. De balk zelf blijft staan
in plaats van te verdwijnen: de strook is wat de rij zijn hoogte geeft, en
`libraries_screen` geeft die hoogte door in een `PreferredSize` die zijn kind
niet kan meten. Zo verschuift er boven of onder de rij niets. Buiten TV
verandert er niets, want geen enkele mockup vraagt desktop of mobiel de rul op
te geven, en op mobiel is dit scherm de aanbevolen-tab.

**Blast radius.** Elk oppervlak dat de underline-stijl op TV gebruikt, en dat
zijn er vier: Bibliotheken, Live TV, Downloads en de Seerr-ontdekbalk. Alle vier
markeren hun open tab al met volle inkt en `w600` tegen gedempt en `w500`, dus
de staat blijft zichtbaar zonder de rul. Dat is ook de reden dat de fix daar
hoort en niet bij Bibliotheken alleen: vier rijen die hetzelfde zijn moeten er
niet drie verschillende dingen van maken.

**Wat er bewust buiten valt.** De segmented stijl (seizoentabs op detail, de
Seerr-aanvraagfilters) tekent een eigen korte accentrul van achttien pixels.
Dat is letterlijk ook een rode rul onder een tab op TV, maar het is een latere,
bewuste behandeling met een eigen argument in de code, en het register maakt een
kleurwijziging op het detailoppervlak afhankelijk van een regressiebeeld van
Home, Films en Series dat deze bevinding niet heeft. Staat nu als `TOK3` in de
tabel, met een test die de huidige behandeling vastlegt zodat de grens zichtbaar
blijft.

**DEC-053.** Niet geraakt. De selectie leunt hier op inkt en gewicht en niet op
een container- of oppervlakkleur, dus de val waarin `secondaryContainer` en
`surfaceContainerHighest` op `c.surface` vallen komt niet in beeld. In het
lichte thema blijft `tk.text` tegen `tk.textMuted` staan; daar staat een test op.

**Negatieve controle.** Vijf tests in
`test/widgets/focusable_tab_chip_test.dart`. Alleen `focusable_tab_chip.dart`
teruggezet naar de oude implementatie: twee rood, allebei met de gemeten waarde
erbij, namelijk `Color(red: 0.8980, green: 0.0784, blue: 0.0588)` in de lijst
rulkleuren waar hij niet in mag staan, in het donkere en in het lichte thema.
De andere drie zijn aan beide kanten groen en staan er om te bewaken wat niet
mocht veranderen: een gesloten tab was al gedempt en zonder rul, de rul buiten
TV blijft, en de segmented stijl blijft ongemoeid.

**Goldens.** Geen enkele golden tekent een `FocusableTabChip`. De enige
golden-test die er in de buurt komt is `tv_detail_source_line_golden_test.dart`,
en die rendert een film zonder seizoentabs; hij was voor de wijziging rood en
erna rood, met dezelfde twee namen. Niets geregenereerd.

**Testen.** `scripts/ci_checks.sh` groen: SDK-pin, `dart format` over 1476
bestanden, codegen-versheid, native format, `flutter analyze` zonder errors of
warnings, en de unused-code- en unused-files-controles. Volledige suite 6146
geslaagd, 6 overgeslagen, 83 rood, met exact de nullijn van LIB2: 78 goldens en
dezelfde vijf in het oude `test/widgets/tv_discovery_rail_test.dart`. Nieuwe
falers: geen. De vijf erbij gekomen geslaagde tests zijn deze bevinding.

**Wat open blijft.** Er is bewijs uit de simulator en niet van een echte Apple
TV. Voor de kleur maakt dat weinig uit, een rul die er niet meer is kan op
hardware niet terugkomen, maar of de open tab op tien voet afstand nog genoeg
opvalt met alleen inkt en gewicht is daar te zien en nergens anders. Bundel dat
met de andere open fysieke items van deze ronde.

### LIB4, de kiezer is geland en de rest van de pagina niet

Opgemerkt door Michel tijdens de LIB3-controle: de pagina als geheel past niet
bij de nieuwe taal. Dat klopt, en het is bekend werk: de ronde van 3 september
was expliciet beperkt tot de kiezer, dus alles eromheen staat er nog zoals het
was.

Er zijn twee mockups voor, allebei van 2 september, in
`docs/assets/tvos-unified/mockups-2026-09-02/`. `libraries-a.png` is state A, de
pagina als index van bronnen. `libraries-d.png` is state D, een bibliotheek
geopend met de kiezer in beeld. Wat de simulator vandaag laat zien tegenover
die twee:

| Onderdeel | Mockup | Nu |
| --- | --- | --- |
| Landing | index van bronnen: een tegel per bibliotheek met soort, aantal, server en statusstip, daaronder Afspeellijsten, Verborgen bibliotheken en Metadata vernieuwen | opent meteen in één bibliotheek |
| Kop | `Bibliotheken` | `Films`, met de servernaam als subtitel |
| Achtergrond | vlak zwart | schermvullende backdrop van een willekeurige titel, waar de tabrij dwars doorheen loopt |
| Acties rechtsboven | capsules `Vernieuwen` en `Bewerken` | kale desktop-icoonknoppen, potlood en ververscirkel |
| Inhoud | posterraster onder een groepslabel | de aanbevolen-hub met spotlight |
| Kiezer | chiprij | gebouwd, dit deel klopt (LIB1, LIB2) |

**Dit is geen bugfix maar een besluit.** De styling-audit noemt dit de enige
mockup waar het productcontract zelf in het geding is, en vraagt er expliciet
aparte goedkeuring voor; de handoff van 3 september herhaalt dat de kiezer niet
naar een index-eerst landing mag zonder dat opnieuw voor te leggen. State A
verandert namelijk waar de pagina op opent, en daarmee wat "Bibliotheken" in de
hub betekent.

**Wat er zonder dat besluit al kan.** De kop, de achtergrond, de twee
icoonknoppen en de botsing tussen tabrij en herobeeld zijn presentatie en raken
het contract niet. Ze horen bij state D, die naast de kiezer staat die er al is.
De landing zelf wacht op Michel.

### VER5, `media-detail.episode-refresh` haalt de detailpagina niet meer

Het scenario navigeert met `press: left` vanaf Home naar wat het als een
zijbalk met bibliotheken beschrijft. De focus-trace laat zien wat er werkelijk
gebeurt: `tvNav_home -> tvNav_search` op die Left, daarna `Content ->
SearchInput` op de Down erna. Het staat dus in Zoeken en niet in Bibliotheken,
`library.items_loaded` komt nooit, en het scenario valt om op een `wait_until`
van 15 seconden. Dat gebeurt op `88d9868` net zo goed als met BACK1 erin.

De aanname in het scenario komt uit de tijd vóór de Unified TV-topnav. Zolang
die er in staat is er geen enkel Verify-scenario dat de TV-detailpagina opent,
en is elke bevinding op dat oppervlak alleen met tests en op hardware te
bewijzen. Het herstel is een navigatiepad dat bij de huidige shell hoort, niet
een aanpassing aan het product.

### REV1, Apple Review Jellyfin: Home toont content, Films/Series leeg

Voor Apple Review draait een Jellyfin-demo-server. Op tvOS toont Home content,
maar Films en Series geven allebei "Niets te ontdekken". Een concrete,
zichtbare Jellyfin-library lijkt daarnaast niet bereikbaar op de verwachte
plek.

Dit is functioneel verdacht tegen het Unified TV-contract: Films en Series
horen alle films respectievelijk series uit alle zichtbare compatibele
libraries te tonen, Home/Films/Series zijn unified logical surfaces, en Mijn
Pleya > Bibliotheken is de concrete source/library-interface. Dat Home wel
content toont bewijst serverconnectie, auth en content-fetching, maar niet dat
dezelfde library correct meedoet in Films/Series.

Root cause: UNKNOWN / TO BE PROVEN.

Te onderzoeken keten: Jellyfin views → Pleya library model / `LibrariesProvider`
→ profile visibility → `UnifiedCatalogs.movies` eligibleLibraries →
`movies.participatingLibraries` → `UnifiedCatalogs.shows` eligibleLibraries →
`shows.participatingLibraries` → catalog query → resultaten vóór grouping →
`UnifiedMediaGroup`-grouping → landing projection.

Hypotheses, geen daarvan als root cause te lezen: een gemengde Jellyfin-library,
een ontbrekende of afwijkende `CollectionType`, een demo-viewstructuur die van
de fixtures afwijkt, Home die op hubs/latest draait terwijl Films/Series op
library queries draaien, een Jellyfin-view die buiten catalog eligibility valt,
of de juiste library die niet bevraagd wordt.

Bij onderzoek moet de echte Jellyfin-demotopologie vastgelegd worden: view-/
library-id, naam, `CollectionType`/type, parent/context waar relevant,
visible/hidden, user access, daadwerkelijke movie/show-inhoud, en relevante
query capabilities.

Acceptatie: bevat de demo-server films, dan toont Films content; bevat hij
series, dan toont Series content; bevat hij beide, dan tonen beide surfaces
content. Een concrete zichtbare Jellyfin-library is daarnaast bereikbaar via
Mijn Pleya > Bibliotheken, waar het productiecontract dat vereist. Een latere
regressietest bootst de werkelijk gevonden Apple Review-topologie
protocol-getrouw na.

Non-goals: geen Apple Review special-case, geen demo-server-id hardcoded, geen
Home-items naar Films/Series kopiëren, geen empty-state verbergen, niet alle
Jellyfin views blind movie- én show-eligible maken, geen volledige catalog
preload om lokaal te splitsen, hidden libraries niet zichtbaar maken, het
paging/no-preload-contract niet breken, geen UI-maskering.

Na de fix moet het tvOS-reviewpad bewijsbaar zijn: Home → Films → Series →
Mijn Pleya → Bibliotheken → concrete Jellyfin-library → item → detail → Back.

**REV1b, tweede helft (18 september, TV2-taak 6).** De hub-typering die Films
en Series leeg liet is gesloten met een eigen SHA, zie de REV1-rij. De tweede
helft van de melding, dat een concrete bibliotheek niet bereikbaar lijkt via
Mijn Pleya, is nu afzonderlijk afgelopen langs de voorgeschreven keten.
`_libraryKindFromCollectionType` (`jellyfin_mappers.dart:316-333`) mapt een
onbekend `CollectionType` op `MediaKind.unknown`, en `eligibleCatalogLibraries`
(`source_cursor.dart:70`) laat `MediaKind.unknown` expliciet door ongeacht de
gevraagde kind. De "niet eligible"-hypothese valt daarmee af, precies zoals
deze sectie hierboven al voorschreef. `hidden` staat in dezelfde mapper
bovendien hardcoded op `false` (`jellyfin_mappers.dart:248`), dus een
serverzijdige hidden-vlag kan een library evenmin laten vallen. Wat overblijft,
`isServerVisible` (`multi_server_manager.dart:192`) en `hiddenLibraryKeys`
(`hidden_libraries_provider.dart`), is lokale per-profielstaat op het geteste
toestel: geen enkele van de twee volgt uit de servertopologie of uit statische
code alleen.

Deze worktree heeft geen `.env`: `scripts/tvos_sim.sh doctor` meldt
`demo-login: ontbreekt in .env`, dus een geauthenticeerde
`/Users/{userId}/Views`-call was niet te zetten. `System/Info/Public` op
`demo.pleya.app` bevestigt wel een bereikbare, echte Jellyfin-server
(`ProductName: Jellyfin Server`, versie 12.1.0, `ServerName: Pleya Demo`); de
werkelijke view-topologie (id, naam, `CollectionType`, zichtbaarheid, user
access, content) blijft daarmee onbekend. Nodig om hem alsnog vast te leggen:
`PLEYA_DEMO_USER`/`PLEYA_DEMO_PASS` in `.env`, waarna `scripts/tvos_sim.sh
login` en een geauthenticeerde `Views`-call het antwoord geven.

Geen schakel uit de keten wijst een concreet defect aan; de code laat een
`unknown`-library al bewust door. REV1b verhuist daarom naar `HARDWARE ONLY`
(zie de REV1b-rij) met als sluitende meting het al bestaande acceptatiecriterium
hierboven: het tvOS-reviewpad Home → Films → Series → Mijn Pleya →
Bibliotheken → concrete Jellyfin-library → item → detail → Back, op een build
die Task 5's SHA (`ee117859`) bevat.

### LAND7, de actieve discovery-rail mist een vaste verticale focuspositie

**TV2-preflight (18 september, HEAD `330a51e4`).** Deze rij beschreef Home nog als
probleemoppervlak, maar dat klopt niet meer sinds HOME1/DEC-095. `grep -rn
'tileScrollAlignment' lib | grep -v tv_discovery_rail.dart` toont dat alleen
`lib/widgets/tv/tv_content_feed.dart:639` een aanroeper is, en die geeft
`TvHomeLayout.rowTileScrollAlignment(...)` door aan `TvContentRow`
(`lib/widgets/tv/tv_content_row.dart:65`, default `0.5`). Geen enkele andere
aanroeper. Home heeft het canonieke anker dus al: de HOME1-bouwronde
(`eed2a79`, `7b3057a6`) gaf Home precies de scroll-naar-anker die dit hoofdstuk
hieronder als functioneel contract beschrijft. Het probleemoppervlak van LAND7
is daarmee beperkt tot de Films-/Series-landing en TV Zoeken, die dit anker
nooit hebben overgenomen: `TvContentRow.tileScrollAlignment` heeft daar geen
tweede aanroeper die iets anders dan de default `0.5` doorgeeft. De rest van
dit hoofdstuk (functioneel contract, non-goals, acceptatie) blijft ongewijzigd
van toepassing op die twee resterende surfaces.

**Gesloten (TV2-taak 3, `1f69a855`).** De Films-/Series-landing en Zoeken
geven nu dezelfde `TvHomeLayout.rowTileScrollAlignment`-waarde door als Home,
ongeacht welke rail de focus heeft: één anker, geen per-rail positie. LAND2,
LAND3, LAND4 en LAND5 zijn niet heropend.

LAND2 regelt correct dat alleen de actieve rail metadata en synopsis toont.
LAND4 regelt correct dat `TvRailStack` de verticale rail-naar-rail focus en de
logische kolom beheert. Op de Films-/Series-landing en Zoeken ontstaat bij
focus op een lagere discovery-rail toch een groot leeg zwart gebied tussen de
topnav en de actieve rail: de rail is technisch zichtbaar, maar niet
gepositioneerd als de huidige hoofdsectie van de viewport.

Functioneel contract: bij verticale focusoverdracht naar een discovery-rail
scrollt die rail naar een vaste upper-content anchor. Horizontale beweging
binnen dezelfde rail verandert de verticale viewport niet.

Verwacht gedrag. DOWN naar een andere rail: de nieuwe rail krijgt focus en de
pagina/feed scrollt hem naar de canonieke active-rail anchor. UP naar de vorige
rail: het onthouden item wordt hersteld en de vorige rail staat weer op
dezelfde anchor. LEFT/RIGHT binnen dezelfde rail: de kaartfocus verandert, de
verticale page-offset blijft exact gelijk. Detail → Back: de onthouden rail of
kaart wordt hersteld en staat weer op de canonieke anchor.

Voor de Home-hero geldt een eigen route die hier niet wijzigt: hero → DOWN mag
de hero grotendeels uit beeld scrollen terwijl de eerste rail op de active
anchor komt; eerste rail → UP blijft eigendom van de bestaande hero-return
flow, met hero-terugscrollen en CTA-focus.

Root cause: UNKNOWN / TO BE PROVEN.

Hypothese over eigenaarschap, nog niet geverifieerd tegen de code:
`TvDiscoveryRail` bezit de horizontale rail en het gefocuste item,
`TvRailStack` de verticale focusoverdracht, en `TvContentFeed`/de surface de
verticale page-scroll of -compositie. De viewport-owner hoort waarschijnlijk de
railpositie te bepalen, maar dat is een hypothese tot de code geaudit is.

Non-goals: LAND2, LAND3 en LAND4 niet heropenen, geen tweede focus-engine, geen
screen-local negatieve margin, geen arbitraire "100 px omhoog", geen
`Scrollable.ensureVisible` als dat alleen "ergens zichtbaar" garandeert,
horizontale traversal mag geen verticale scroll triggeren, geen timing- of
postFrame-hacks.

Acceptatie: de actieve railheading komt consequent in het bovenste
contentgebied, de gefocuste kaart blijft volledig focusring-safe, metadata
staat direct onder de actieve rail, de volgende rail blijft waar mogelijk
gedeeltelijk zichtbaar. LEFT/RIGHT laat de verticale scroll-offset ongewijzigd.
DOWN/UP laat de nieuwe actieve rail op dezelfde canonieke anchor landen.
Hero-return blijft correct.

Te auditeren surfaces bij latere uitvoering: de Films-landing, de
Series-landing, TV Zoeken. Home is uitgesloten: die heeft het anker al sinds
HOME1/DEC-095 (zie de preflight-aantekening hierboven). Search-specifieke
chrome mag niet blind dezelfde absolute offset krijgen als Home; de anchor
moet relatief aan de eigen contentviewport bepaald worden.

Negatieve controle bij latere uitvoering: op de oude implementatie laat een
verticale railwissel de actieve heading aantoonbaar onder de canonieke anchor
staan (rood); na de fix staat de heading binnen tolerantie op de anchor
(groen).

### De simulatorronde van 4 september, en wat die wel en niet oplevert

Op 4 september is build 248 uit `424c43e` op de Apple TV gezet, en is dezelfde
code in de tvOS-simulator nagelopen. Michel heeft de televisie op dat moment niet
beoordeeld, dus **geen enkel item gaat naar VERIFIED**. Wat hieronder staat is
simulatorwaarneming, en die telt als aanvulling op de bestaande FIXED-status, niet
als vervanging van de hardware-acceptatie.

NAV1 en LAND1 staan er bewust niet bij. De oorzaak zit in
`apple_tv_remote_touch_service.dart`, in het samenspel van de aanraakstroom en de
ringdruk, en de simulator heeft geen aanraakvlak. Een groene run daar bewijst niets
over het defect.

**CAT1.** Op Alle films, focus op de eerste kaart van de bovenste rij: de witte
focusring is rondom compleet, inclusief de bovenrand en de twee bovenhoeken, met
zichtbare ruimte tussen de ring en de kop "Alle films". Dat is wat `89b1554`
belooft.

**BACK1.** De detailpagina van een film heeft geen terugknop linksboven. De vier
actieknoppen staan onder de samenvatting en verder niets.

**FOC2.** Twee overlays gedragen zich verschillend, en dat verschil is nieuw
gemeten. Het sorteerpaneel op Alle films staat verticaal gecentreerd, met marge
boven en onder, en de focusring om de bovenste regel is rondom compleet. Het
contextmenu op de detailpagina staat dat niet: het paneel loopt tot de onderrand
van het canvas door, en de gefocuste onderste regel eindigt op ongeveer dertig
pixels van 2160. Op een simulator zonder overscan valt die regel dus binnen, maar
een televisie die drie procent wegneemt snijdt hem af. Dat is precies de maat die
alleen op hardware te toetsen is, en het is het scherpste argument om FOC2 niet op
simulatorbewijs te sluiten.

**ART1.** De backdrop op detail is scherp, zonder de zachtheid van een te kleine
aanvraag, dus de resolutiekant van `f42e3fd` doet wat hij moet doen. Of de uitsnede
nog te strak oogt is een compositievraag en blijft open, conform wat de
ART1-sectie daar al over zegt.

**LIB3.** De tabband draagt geen rode onderstreping meer. De affordance zelf is
niet los te beoordelen, om een reden die de LIB3-sectie niet kon voorzien: zie
LIB5.

### LIB5, de spotlight-titel ligt over de tabrij

Op Bibliotheken tekent de aanbevolen-hub een schermvullende backdrop met daarin een
spotlight, en het titellogo van die spotlight valt over de tabrij heen. Met "The
Notebook" als spotlight loopt het woordmerk dwars door "Aanbevolen".

Het gevolg keert de bedoelde staataffordance om. De actieve tab is wit en vet en
zou daarmee moeten opvallen, maar hij is de enige die onder het logo ligt;
"Bladeren", "Collecties" en "Afspeellijsten" staan op vrije achtergrond en zijn
daardoor beter leesbaar dan de tab die gekozen is.

Dit is de reden dat de LIB3-vervolgvraag op deze pagina niet te beantwoorden is.
Of inkt en gewicht op tien voet genoeg zijn valt pas te zien wanneer er niets
doorheen loopt, en op de mockup is de achtergrond vlak zwart.

Eigenaar is de laag die de hub-backdrop en de tabrij op hetzelfde vlak zet, niet de
tabrij zelf. De tabrij doet precies wat `3e9d31b` hem opdroeg.

Dit is presentatie en raakt het productcontract niet, dus het valt onder wat de
LIB4-sectie "zonder besluit al kan" noemt.

### LIB6, het LIB4-besluit stond op een half beeld

Gevraagd door Michel op 4 september: is er een complete mockup voor deze pagina.
Die is er niet, en dat verklaart waarom LIB4 bleef liggen.

Wat er ligt zijn `libraries-a.png` en `libraries-d.png` van 2 september, twee
states van dezelfde pagina. Ze zijn nooit goedgekeurd. De goedkeuringsronde van 3
september ging over de beelden 09 tot en met 25, en het overzicht van die set zegt
dat de Mijn Pleya-mockups van 2 september er bewust buiten zijn gelaten. De
styling-audit zet Bibliotheken bovendien op klasse E en vraagt er als enig scherm
apart akkoord voor, omdat het productcontract zelf verandert.

Wat de twee beelden niet tekenen: de tabs Bladeren, Collecties en Afspeellijsten,
de lege staat, Verborgen bibliotheken, en de botsing uit LIB5. De HTML waarmee ze
geschoten zijn zit niet in git, alleen de PNG's.

Besluit van Michel op 4 september: eerst een complete set, daarna één keer besluiten
over de hele pagina. LIB4 blijft tot die tijd dicht en wordt niet opnieuw
voorgelegd op de bestaande twee beelden.

De set staat er sinds diezelfde middag als mockup 26, negen states in
`docs/assets/tvos-unified/mockups-2026-09-04/26-bibliotheken-*.png`. Een eerste
versie op eigen CSS en een systeemfont is weggegooid nadat Michel de lat op northstar
legde: de beelden moeten tot op het lettertype gelijk zijn aan de rest van de familie.
Ze zijn daarom gebouwd als paginafragmenten in hetzelfde systeem als 09 tot en met 25:
`tv.css` voor de tokens, `build.mjs` voor de gedeelde topnav, de iconenset en het
schieten, Inter en het wordmark uit `assets/`. Die bron stond tot nu toe alleen in
`~/Downloads/mockups-tvos/_src` en staat nu in `docs/assets/tvos-unified/src/`, met
alle zeventien eerdere fragmenten erbij, zodat de hele familie herschietbaar is.
Alleen `art/` (TMDb-beeld) en `out/` zijn niet meegenomen; `build.mjs` verwacht ze
naast zich, zoals het overzicht van de 09-25-set beschrijft.

A is de index, per server een groep en de tegels in de taal van de Mijn Pleya-hub; B
de pagina zonder bereikbare bibliotheek; C Verborgen bibliotheken; D1 en D2 de
geopende bibliotheek, zonder en met spotlight-backdrop; E Bladeren als
catalogusgrid; F Collecties en G Afspeellijsten als rail van 16:9-kaarten; H een
geopende maar lege bibliotheek. D1 tegen D2 is de vraag die de oude LIB4-sectie open
liet: de code kiest de backdrop, de mockup van 2 september tekende zwart, en nu
staan ze naast elkaar. In D2 staat de spotlight-titel onder de tabrij in een eigen
band, wat de LIB5-botsing wegneemt zonder de backdrop op te geven.

Voorgelegd op 4 september, met mockup 26 erbij. Michels antwoord, letterlijk: "Ik vind
de werking van deze pagina gewoon niet in lijn met wat we aan het bouwen zijn." Dat
is geen keuze tussen A en D en geen revisie op de beelden: het is een afwijzing van
het contract dat beide states delen, een bronkiezer met per bibliotheek vier tabs.
De styling-audit had dit als klasse E gemarkeerd, het enige scherm waar het
productcontract zelf in het geding is, en dat is nu bevestigd. LIB4 blijft dicht tot
er een nieuw voorstel voor de werking ligt; mockup 26 blijft staan als bewijs van de
huidige werking in de nieuwe taal, niet als richting.

Twee acceptatie-eisen van Michel, 4 september, die bij de bouw horen en niet bij het
besluit: elke knop op de pagina is met de afstandsbediening te bereiken, dus de
capsules rechtsboven, de chips, de tabs en de tegels zitten alle in één
focusketen zonder dode einden; en het ontwerp wijkt nergens af van de andere
schermen, dus dezelfde marge, dezelfde chip, dezelfde tegel en dezelfde ring als
Home, Films en de Mijn Pleya-hub. Een bouwronde die op een van beide zakt is niet
klaar, hoe goed de mockup ook gevolgd is.


### HERO1, de widget kiest een uitsnede die de server al gemaakt heeft

Gemeld door Michel op 4 september, kijkend naar build 248 op de Apple TV 4K, in
zijn woorden: "halve afbeeldingen staan er maar in de hero, dus of ze zijn te groot
of de positie van het onderwerp klopt niet." Dat is het concrete hardwaregeval
waar de vorige HERO1-sectie op wachtte, en het antwoord is: allebei een beetje,
en de oorzaak zit niet waar de widget hem denkt te hebben.

**Wat de keten doet.** `lib/widgets/tv/tv_hero_artwork.dart` tekent een 16:9-
backdrop met `BoxFit.cover` en `Alignment.topCenter`, met als toelichting dat een
te hoge backdrop dan de lucht verliest en niet de gezichten. Diezelfde widget
vraagt het beeld bij de server aan in de pixels én de ratio van de kaart, 2,465:1,
met een beroep op DEC-057. `roundDimensions` in
`lib/utils/media_image_helper.dart` bewaakt sindsdien dat die ratio onderweg niet
verandert. Op Plex zet `thumbnailUrl` (`lib/services/plex_client.dart:4300`) daar
`minSize=1&upscale=1` op, en dat betekent: vul de gevraagde box en snij het
overschot gecentreerd weg. Plex levert dus een beeld dat al precies 2,465:1 is. De
`BoxFit.cover` in Flutter heeft dan niets meer te croppen en `topCenter` doet niets.

**De maat.** 16:9 in 2,465:1 verliest 27,9 procent van de hoogte. Op Plex is dat
veertien procent boven en veertien procent onder, gekozen door de server. Op
Jellyfin (`lib/services/jellyfin_client/parts/images_downloads.dart:32`) gaat de
aanvraag met `maxWidth`/`maxHeight`, dat past in en snijdt niet, dus daar komt het
hele 16:9-beeld aan en snijdt Flutter wél, met `topCenter`: achtentwintig procent
onderaan. Twee backends, twee verschillende uitsneden, en geen van beide is de
uitsnede die de widget zegt te maken. Michels toestel heeft twee Plex-logins, dus
wat hij ziet is de gecentreerde Plex-uitsnede.

**Waarom dit een tegenspraak is en geen detail.** DEC-057 zegt dat de aanvraag de
ratio van de *bron* moet volgen, zodat de servercrop een no-op wordt; het besluit
liet de brede box uitdrukkelijk zoals hij was. `tv_hero_artwork.dart` beroept zich
op DEC-057 om precies het tegenovergestelde te doen: de ratio van de *kaart*
aanvragen. De toelichting daar noemt de servercrop "een no-op in plaats van een
tweede, onzichtbare"; hij is de eerste, en de enige, en hij is niet leeg.

De eerdere HERO1-sectie wees een globale wissel van `topCenter` naar `center` af
omdat één vaste uitlijning niet elke onderwerpspositie oplost. Dat blijft waar,
maar op Plex had die wissel sowieso niets veranderd, en dat is de reden dat een
A/B op de uitlijning nooit iets liet zien.

**Waarom het als "te groot" voelt.** De kaart is 3538 bij 1365 fysieke pixels op
een 3840 bij 2160 paneel. Ook een perfect gekozen uitsnede toont maar 72 procent
van de backdrop, en die 72 procent wordt vervolgens over 92 procent van de
schermbreedte getekend. Een onderwerp dat in de bron niet in de middelste band
staat is dan half weg, en wat er wel staat is groter dan het beeld ooit bedoeld
was. Dat deel is een eigenschap van de kaartratio en geen bug, maar het is wel de
reden dat de uitsnede er zo toe doet.

**Richting, niet uitgevoerd.** Dit is een correctieronde, dus er is niets
gerepareerd. De fix hoort bij de aanvraag: vraag de bron in zijn eigen 16:9 op de
breedte van de kaart (binnen de heroArt-cap), zodat geen enkele server snijdt, en
laat daarna één eigenaar de uitsnede maken, met een uitlijning die per titel kan
verschillen of met een kaartratio die dichter bij 16:9 ligt. Negatieve controle:
een test die de aangevraagde URL ontleedt en eist dat breedte gedeeld door hoogte
gelijk is aan de bronratio, en die is op de huidige code rood met 2,465 tegen
1,778. Pas als die groen is heeft een uitlijningskeuze in de widget effect op Plex.

**Uitgevoerd op 4 september**, op Michels vraag of dit op te lossen was, met zijn
kanttekening dat het niet alleen om Plex gaat. De negatieve controle staat in
`test/widgets/tv_hero_artwork_request_test.dart` en vroeg op de oude code 3840 bij
1500 aan, ratio 2,56; rood. De fix zit bij de gedeelde eigenaar:
`OptimizedMediaImage` kreeg een `requestSize` los van de tekenbox, `tvHeroRequestBox`
geeft de box in de bronratio, en de uitlijning is het token
`TvHomeLayout.heroArtAlignment` op `Alignment(0, -0,3)`, hetzelfde anker als
`object-position: 50% 35%` in de mockupfamilie. Groen na, 78 gerichte tests, analyze
schoon. DEC-094. Wat open blijft is precies wat alleen op hardware te zien is: of
`-0,3` de juiste keuze is voor de backdrops die Michel zag. Build 249 draagt de fix.


### LIB7, Bibliotheken wordt bronbeheer

Besluit van Michel op 4 september, na mockup 26 en in zijn woorden "in kader van
unified": de pagina houdt op een tweede bladerinterface te zijn. Gekozen uit vier
richtingen: bronbeheer, en bladeren eruit.

Wat de spec zelf al zegt en wat ermee botst. §4.5 van `tvos-unified-experience.md`
houdt Bibliotheken als "de geavanceerde bronweergave" met één library kiezen,
Aanbevolen, Bladeren, Collecties en Afspeellijsten. §10.4 van dezelfde spec zet
server en library bij de globale filters van de unified catalogus, en de app heeft
die knop al als "Alle bronnen" op Alle films (`tv_catalog_header_bar.dart`). Bladeren
per bibliotheek heeft dus al een unified thuis, en §4.5 bouwt er een tweede naast.
Wat volgens §1524 alleen in Bibliotheken thuishoort is beheer: scannen, analyseren,
prullenbak, metadata verversen op de hele library, mappen bladeren, verbergen en
ordenen.

De nieuwe werking:

1. De pagina toont per server de bibliotheken als beheerregels, met soort, aantal,
   zichtbaar of verborgen en volgorde. Per regel de acties Openen in catalogus (Alle
   films of Alle series met deze bibliotheek als bronfilter), Vernieuwen, Scannen,
   Verbergen, en waar de backend het draagt Mappen, Analyseren en Prullenbak.
2. De tabs Aanbevolen en Bladeren vervallen. Aanbevelingen doen Home, Films en
   Series al over alle bronnen heen.
3. Collecties en Afspeellijsten gaan de pagina uit en worden eigen ingangen in Mijn
   Pleya, over alle bronnen, met mockup 24 als detail.

Dit raakt §4.5, de tabel "waar woont wat" en §1524, dus het gaat als DEC-voorstel en
niet als stille spec-aanpassing. Mockup 27 tekent de nieuwe werking in het systeem
van mockup 26. Mockup 26 blijft staan als vastlegging van het afgewezen contract in
de nieuwe taal.

De twee acceptatie-eisen uit LIB6 gaan mee: elke knop bereikbaar met de
afstandsbediening, en geen afwijking van de andere schermen.

Goedgekeurd door Michel op 4 september op mockup 27, letterlijk: "Verder akkoord op de
mockup alleen de filters nog bij alle films en series posities." DEC-092 staat op
accepted en de drie spec-wijzigingen zijn doorgevoerd in `tvos-unified-experience.md`
(4.5, de tabel van 18.2, de actielijst van hoofdstuk 31). Het voorbehoud over de
filters is CAT5 en blokkeert de bouw van LIB7 niet: state D van mockup 27 volgt
wat CAT5 beslist. De bouw is een eigen ronde, met de negatieve controle uit
DEC-092 als eerste stap.


### CAT5, de filters op de catalogus zijn op tvOS te ver weg

Gemeld door Michel op 4 september bij het beoordelen van mockup 27, in zijn woorden:
"Op zich idee is goed maar de filters moeten ook nog een betere positie krijgen
zodat je deze makkelijker kan bereiken op tvos." Het gaat om de drie
headeracties van Alle films en Alle series, Bronnen, Filters en Sortering, die in
northstar 05 en 06, in mockup 14 en in state D van mockup 27 rechtsboven naast de
paginakop staan.

Dit is niet CAT3 of CAT4 opnieuw. CAT3 zette de cluster op de canonieke rechterrand,
CAT4 maakte hem bereikbaar. Beide zijn dicht en gaan over waar de cluster nu staat;
deze bevinding zegt dat die plek zelf verkeerd is voor een afstandsbediening. Het is
een ontwerpkeuze over de catalogus als geheel en raakt daarmee de northstar-set,
dus hij gaat als besluit en niet als fix.

Drie posities staan getekend als mockup 28 (`28-catalogusfilters-a` tot en met `-c`).
A is de huidige, ter referentie. B zet de drie acties links naast de kop, boven de
eerste kolommen en in leesrichting, en maakt Play/Pause de snelkoppeling naar het
filterpaneel; §10.6 staat die knop al toe, hij is alleen nergens zichtbaar gemaakt.
C zet een verticale actierail links van het raster, altijd één LEFT vanaf kolom 0,
met de actieve filters als regel eronder; dat kost één posterkolom. De keuze
verandert §10.2 en raakt northstar 05, 06 en 14 en state D van mockup 27.

Michels antwoord op de drie, letterlijk: "Ik vind a het beste maar dan moet dit niet
altijd in beeld blijven deze zijbalk." Alleen C heeft een zijbalk, dus de lezing is:
de rail van C, ingeklapt tot hij nodig is. Dat staat getekend als D1 (ingeklapt, zes
kolommen, de actieve filters als stille regel naast de kop, LEFT vanaf kolom 0 klapt
uit) en D2 (uitgeklapt, vijf kolommen, RIGHT of Menu klapt in en de focus keert terug
op dezelfde kaart). Bevestigd door Michel, letterlijk: "C bedoelde ik inderdaad maar maak hem moooer dan
nu getoond en moet wel subtiel zichtbaar zijn in de bibliotheel wat je als filter
gekozen hebt." Twee eisen dus: de rail als paneel in plaats van drie losse pillen, en
de gekozen filters altijd zichtbaar in het raster. D1 en D2 zijn daarop
hertekend: de rail is één paneel in de tegeltaal met per regel icoon, label en
huidige waarde, de keuzes als tags en Wissen eronder; ingeklapt staan dezelfde tags
naast de kop, met de sortering gestippeld zodat hij niet als filter leest.

Op D1 en D2 zei Michel, letterlijk: "Graag die waarop gefilterd mag dan wel rechtsboven
getoond worden want nu hoeven die niet meer bereikbaar te zijn en je hebt daar meer
ruimte." De tags in de ingeklapte stand zijn daarmee naar rechtsboven verhuisd, de plek
waar de chips stonden en die vrijkwam zodra ze niet meer bedienbaar hoefden te zijn.

Goedgekeurd door Michel op 4 september op D1 en D2. DEC-093 staat op accepted, 10.2 en
10.6 van de spec zijn aangepast, en state D van mockup 27 is op dezelfde rail
hertekend. De bouw is een eigen ronde; de negatieve controle staat in DEC-093, en de
CAT4-test wordt daarbij herschreven op de rail in plaats van weggegooid.

#### De bouwronde, 5 september

**Negatieve controle eerst.** `test/screens/tv/tv_catalog_filter_rail_test.dart` pompt
Alle films via de echte `TvMoviesScreen` en stelt de drie eisen uit DEC-093, plus de
twee maten die het besluit openliet. Tegen de code van vóór deze ronde zijn alle tien
de assertions rood, en rood op gedrag en niet op een ontbrekend symbool: het bestand
verwees naar de paneel-key als losse `ValueKey`, zodat het compileerde en dus echt
draaide. Wat de run zei: LEFT vanaf kolom 0 gaf de focus aan de shell in plaats van
aan `TvCatalogRailSources`, de kop droeg drie `FocusableWrapper`s, UP vanaf de eerste
gridrij landde op de kop in plaats van bij de bovenbalk, en het raster stond op zes
kolommen in beide standen. Na de bouw staat de key op de echte
`tvCatalogFilterRailKey`, zodat een hernoeming in de productiecode hier alsnog
omvalt.

**Wie het bezat.** De drie acties zaten in `tv_catalog_header_bar.dart` als
`TvCatalogHeaderAction` op het gedeelde `LibraryHeaderAction`-model, en
`tv_unified_catalog_screen.dart` bedraadde ze. De kop is nu een titel met tags en
draagt geen focusnode meer; de rail staat in `tv_catalog_filter_rail.dart` en wordt
door hetzelfde scherm bedraad.

**Waarom het raster meebeweegt en niet alleen opschuift.** `TvCatalogGrid.forWidth`
rondt het kolomaantal af op de beschikbare breedte. Zou de rail als padding buiten de
rekenaar blijven, dan houdt het raster zijn zes kolommen en valt de zesde buiten
beeld; dat is precies wat mockup 28 D2 tekent, waar de vijfde kaart tegen de
rechterrand aan wordt afgesneden. De rekenaar krijgt daarom `reservedLeading` en
geeft het terug als `TvCatalogGrid.leading`, dat de linker scrollpadding meeneemt. De
rail staat in een `Stack` boven precies die gereserveerde band, want het raster
bezit zijn eigen zijranden en die eigenaar wilde ik niet uit elkaar trekken over twee
widgets.

**De twee maten die DEC-093 openliet.**

De breedte van de rail is 330 referentiepixels, de maat van mockup 28 D2, met 34
ertussen naar de eerste kolom. Het paneel begint op de zijrand van het raster, 56
referentiepixels, en dat is de ondergrens van 8.1 zelf; het eindigt op 386, dus geen
tekst en geen focusring komt in de buitenste band. De focusring van een rijtje ligt
er nog eens binnen, want het paneel heeft 10 referentiepixels eigen padding en de
ring staat daar 6 binnen. Wat wél in de band ligt is de streep van de dichte stand,
op ongeveer 28 referentiepixels van de rand, zoals mockup 28 D1 hem tekent. Dat is
bewust: 8.1 beschermt tekst en focusringen, en dit is een haarlijn zonder betekenis
die verloren gaat. Een set die hem afsnijdt verliest de affordance, niet de functie.

Vijf kolommen passen op de 1280x918-ondergrens van CAT1, en ze passen daar niet
toevallig. Elke term in de kolomsom is dezelfde fractie van de breedte, dus het
afgeronde kolomaantal hangt niet van het canvas af: dicht is
`(1808 + 22) / (281 + 22)` gelijk aan 6,04 en open `(1444 + 22) / 303` gelijk aan
4,84. Zes en vijf, op 1920, op 1280 en op het goldencanvas. De kaart wordt open
271 referentiepixels breed tegen 281 dicht, vier procent smaller.
`test/screens/tv/tv_catalog_filter_rail_test.dart` telt de kolommen op beide
oppervlakken uit de gerenderde kaartrechthoeken, niet uit de rekenaar.

**Wat de traversal nu is.** LEFT vanaf kolom 0 opent de rail met de focus op
Bronnen. RIGHT en Menu sluiten hem en zetten de focus terug op dezelfde kaart, wat
werkt omdat het raster zijn nodes op `groupId` bewaart en de kaart de herkolommering
van vijf naar zes overleeft. UP en LEFT vanuit een rijtje sluiten de rail en vragen
de bovenbalk aan. UP vanaf de eerste gridrij gaat rechtstreeks naar de bovenbalk,
want er staat geen kop meer tussen.

Twee dingen die daar onder vandaan kwamen en die geen ontwerpkeuze waren:

1. DOWN vanaf de onderste railrij liep door naar het raster. Een ontbrekende
   `onNavigateDown` laat `FocusableWrapper` de toets doorgeven aan de gerichte
   traversal van Flutter zelf, en die stapt opzij het raster in, met een rail die
   open blijft staan terwijl de focus er niet meer is. `_railEdge` is een expliciete
   lege handler op de onderste rij.
2. DOWN vanuit de bovenbalk had niets meer om op te landen. De kop bestond vanaf het
   eerste frame, een raster niet: de bewaarde voorkeuren worden asynchroon gelezen en
   tot dan staat het skelet er. `_focusEntry` onthoudt het verzoek en probeert het
   opnieuw vanuit `_onCatalogChanged` en aan het eind van `_restorePreferences`, en
   laat het los zodra de pagina op een staat is geland die helemaal geen raster
   heeft. Zonder die herkansing slikt een koude catalogus de druk.

**De lege staat kon de filters niet meer bereiken.** De rail opent op LEFT vanaf
kolom 0, en een catalogus waar het filter niets overlaat heeft geen kolom 0. De
staat die de filterknoppen het hardst nodig heeft was daarmee de enige die er niet
bij kon. `TvCatalogEmptyState` krijgt daarom `onActionNavigateLeft`, zodat LEFT vanaf
de ene knop die zo'n staat heeft de rail alsnog opent.

**Refactor die meeliep.** `tv_unified_catalog_screen.dart` stond op 868 regels en
kreeg er bedrading bij. `TvCatalogSkeletonGrid` en de lege staat zijn er ongewijzigd
uit gehaald naar `tv_catalog_skeleton_grid.dart` en `tv_catalog_empty_state.dart`;
de lege staat is daarbij publiek geworden, wat SYS-4 een oppervlak scheelt dat het
anders zelf had moeten extraheren. Dat haalde er 225 regels uit, de rail zette er
186 terug, en het scherm staat nu op 829.

Dat is nog steeds ruim over de grens uit CLAUDE.md, en dat blijft zo staan. Wat er
als volgende uit kan is het activatieblok (`_activate`, `_openContextMenu` en de
gecachete `_sourceResolver`, samen bijna honderd regels), maar die drie zijn deze
ronde niet aangeraakt en de resolver houdt schermstaat vast, dus de extractie is
geen zuivere verplaatsing. Hij hoort bij de eerstvolgende wijziging die het
activatiepad zelf raakt. `tv_catalog_filter_panel.dart` (857 regels) is om dezelfde
reden ongemoeid: de rail opent hetzelfde paneel via dezelfde aanroep.

**Blast radius en tests.** Drie suites zijn nieuw en zeven zijn meegegaan.
Nieuw zijn de negatieve controle hierboven, inmiddels elf assertions;
`tv_catalog_selection_tags_test.dart`, dat de volgorde, de cap en de aparte status
van de sorteertag vastlegt buiten een widgetboom om, want die lijst wordt op twee
plekken getekend en een golden kan er maar één van laten zien; en
`tv_catalog_filter_rail_panel_test.dart` voor de hoogte van het paneel.
`tv_catalog_header_reachability_test.dart` heet nu
`tv_catalog_controls_reachability_test.dart` en bewaakt hetzelfde mechanisme op zijn
nieuwe plek: de bovenbalk die vraagt voordat er iets te focussen is, en een
content-scope die een node onthoudt die met de rail is verdwenen.
`tv_unified_catalog_focus_test.dart` bewijst wat voor elke rij moet gelden in plaats
van voor de rij waarop de rail opent. `tv_catalog_header_bar_test.dart` meet CAT3's
rechterrand op de tags; die meting gaat over de `Row` en niet over wat er als tweede
kind in staat, dus hij overleeft de wissel ongewijzigd.
`tv_unified_catalog_screen_focus_test.dart` (E13) loopt nu via de rail naar
Sortering. In `tv_destination_restoration_test.dart` verviel één druk: terugkomen op
een bestemming landt meteen op de kaart in plaats van een rij erboven. De twee
goldenbestanden van de catalogus stellen de pagina nu samen zoals het scherm dat
doet, met de rail erin, en `tv_catalog_films_header_focused` is vervangen door
`tv_catalog_films_rail_open`.

**Twee randgevallen die eruit kwamen.** Wissen staat alleen in de rail zolang er iets
gefilterd is, dus de druk erop haalt de rij weg waar de afstandsbediening op staat.
De ring verdwijnt daar niet van, en dat maakt het makkelijk te missen: Flutter geeft
hem aan de buur die het overleeft, hier Sortering, een rij verder van waar de kijker
stond. `_clearFilters` verplaatst de focus nu zelf naar Filters. Met die regel
weggehaald is de assertie rood met "Actual: TvCatalogRailSort".

En het paneel kon over de onderrand lopen. De kop knipt zijn tags af op drie plus een
teller, het paneel doet dat bewust niet, dus achttien gekozen genres maakten het
paneel hoger dan de pagina. Het staat nu in een band die onderaan door de
overscanmarge van het raster wordt begrensd, met een `Align` erboven zodat het nog
steeds om zijn eigen rijen heen krimpt, en de inhoud zit in een scrollview die onder
een losse hoogte meekrimpt en onder een strakke afknipt. Zonder die scrollview zegt
de test "A RenderFlex overflowed by 13 pixels on the bottom".

**Bewijs.** `scripts/ci_checks.sh` groen, en `test/screens/tv/` plus
`test/widgets/tv/` groen op 428 tests. De volledige suite houdt 93 falers over: 78 goldens,
die op macOS structureel rood staan om fontrasterisatie, en vijftien in
`discover_hero_activation_test.dart`, die met gestashte wijzigingen net zo hard falen
en dus niet van deze ronde zijn.

Beeld: de dichte en de open stand zijn gerenderd op het goldencanvas en naast mockup
28 D1 en D2 gelegd, en de open stand daarnaast op 1920x1080, waar de schaal niet meer
geklemd is. Eén afwijking kwam daaruit en is gefixt: de tags in het paneel werden
over de volle paneelbreedte uitgerekt, omdat een `Center` in een `Wrap` onder een
uitgerekte `Column` de hele breedte pakt. `Align(widthFactor: 1)` krimpt hem terug
naar de tekst.

**De goldens staan open, en dat is een omgevingsgrens.** Negentien
catalogusgoldens tekenen nu iets anders en moeten opnieuw gegenereerd worden; op
macOS kan dat niet, want daar is de hele suite al rood van fontrasterisatie. De
route uit eerdere rondes is een Linux-container, en die is deze keer tot het einde
uitgeprobeerd. Uitkomst: hij reproduceert de referenties niet. Op ongewijzigde code
in `ghcr.io/cirruslabs/flutter:3.44.0` onder amd64-emulatie faalden alle negentien,
met 45 procent van de pixels anders op een pagina vol coverart en 17 procent op een
paneel. Het beeld zelf klopt; wat verschilt is de dithering van de verlopen in de
artwork en de antialiasing van de tekst, met uitschieters tot 235 per kanaal in het
ruispatroon. Een golden die daar wordt weggeschreven is op CI meteen weer rood.

De goldens zijn daarom niet aangeraakt. Wie ze regenereert doet dat op hetzelfde
Linux als CI: `flutter test --update-goldens test/goldens/tv_unified_catalog_golden_test.dart
test/goldens/tv_unified_catalog_states_golden_test.dart`, en
`tv_catalog_films_header_focused.png` vervalt daarbij ten gunste van
`tv_catalog_films_rail_open.png`. Tot dat gebeurd is staat de goldenstap van CI rood
op deze negentien, en op niets anders.

**Wat verder niet bewezen is.** Hardware. De rail is nooit op een Apple TV gezien, en
de Pleya Verify-scenario's raken de catalogus niet, wat VER4 al als gat beschrijft.


### HERO2, de titelband was de hoogte van het logo en niet van de titel

Gemeld door Michel op 4 september, kijkend naar build 249 op de Apple TV, en
daarna teruggewezen in mijn eigen simulatoropname: "bij jouw screenshot zie je het
ook hoor kijk maar bij de onderkant t van extended". Dat klopte. Ik had de titel
eerst als compleet afgedaan op een crop waarin de afsnijding wegviel tegen een
donkere palmboom; op een uitvergroting eindigen E, x, t, e, n, d, e en d alle acht
op één rechte lijn, met de ronding van de e en de punten van de x eraf.

**Root cause.** `_titleBlock` in `tv_hero_billboard_card.dart` gaf de band de
hoogte `heroLogoMaxHeight`, 76. De band bestaat omdat een slide met een wordmark
en een slide met type de metaregel op dezelfde plek moeten zetten, en hij was
daarom op het logo gemaat. De type-tak vraagt binnen die band `heroTitleMaxLines`
regels, en twee regels van `heroTitleFontSize` op `heroLineHeight` is
40 x 1,28 x 2 = 102,4. Een eenregelige titel (51,2) paste, een tweeregelige stak er
26,4 uit. Niets in de layout klaagde: een `SizedBox` groeit niet mee met zijn kind
en `Align` verplaatst in plaats van te verkleinen, dus het defect was alleen in
pixels te zien. Dat verklaart ook waarom The Whisper Man (één regel) goed stond en
Grand Theft Auto VI (twee regels) niet.

**Fix.** `TvHomeLayout.heroTitleBandHeight` is de band, gemaat op het grootste dat
erin kan staan: `heroTitleFontSize * heroLineHeight * heroTitleMaxLines`. Het
clearlogo houdt zijn eigen `heroLogoMaxHeight` binnen die band, zodat een wordmark
niet anderhalf keer zo groot wordt. Het blok staat `Positioned(bottom:)`, dus de
band groeit naar boven en de CTA-rij blijft waar hij stond.

**Negatieve controle.** `test/widgets/tv_hero_title_band_test.dart`, drie
assertions: de band tegen het aantal toegestane regels, het logo dat zijn eigen
hoogte houdt, en een gerenderde tweeregelige titel die binnen zijn band moet
passen. Met de band terug op 76 is de eerste rood met "band is 76.0, a 2-line
title needs 102.4"; met de fix groen.

**Bewijs in de simulator.** Dezelfde slide, dezelfde titel, voor en na: de
ink-hoogte van de tweede titelregel gaat van 85 naar 92 pixels, en de afgesneden
letteronderkanten zijn terug.


### HOME1, Home naast de northstar

Gevraagd door Michel op 4 september, na de hero-fixes: "kijk home screen qua design
[...] volgens mij is in de hero namelijk nog niet hele item goed in beeld [...] ook
even goed na zodat het beter wordt qua witruimte en overgangen en indeling en
styling maak een mockup. Kijk ook gelijk de navigatie balk na." En: "laat die build
nog even zitten." Build 250 is daarom gecommit (`0ad49ec`) maar niet gebouwd.

**Gemeten in de simulator tegen northstar 01, op de 1080-referentie.** De herokaart
staat in de app op 179 tot 862 (683 hoog) waar de northstar 132 tot 850 (718) tekent:
47 lager en 35 korter, dus de witruimte onder de nav is ruim twee keer zo groot als
bedoeld. De nav-pil is 44 tot 110 tegen 44 tot 96, dus 14 hoger dan de northstar. Het
raillabel staat op 48 onder de kaart tegen ongeveer 40. Links in de nav tekent de app
het Pleya-merk waar de northstar een profielchip met initiaal zet; dat is de
`ProfileAvatar`-fallback voor een profiel zonder beeld, geen andere navigatie.

**Het onderwerp valt weg door de kaartratio zelf.** 2,465:1 toont 72 procent van een
16:9-backdrop, ook in de northstar. HERO1 bepaalt nu wélke 72 procent en dat het op
elke backend hetzelfde is; het maakt de kaart niet hoger. Wil het hele item in beeld,
dan is dat een besluit over de kaart, niet over de uitsnede. Mockup 29 tekent vier
richtingen: A de northstar als referentie op de juiste maten, B een kaart van 2,0:1
(1770x885) die 89 procent toont met de rail eronder uitpiepend, C de backdrop heel op
16:9 in de rechter 1276 pixels van de kaart met dezelfde backdrop geblurd als vulling
erachter (de "alleen poster"-taal van 9.4 toegepast op de backdrop, niets gesneden,
kaart ongewijzigd), D full-bleed achter nav en tekst met de rail over de onderrand.

Besluit van Michel op 4 september op mockup 29: **D, full-bleed.** Dat is geen
uitsnedekeuze meer maar een wijziging van 9.2: de billboardkaart met ring vervalt,
de backdrop staat op 16:9 achter nav en tekst, en de eerste rail overlapt de
onderrand. Voor de bouw worden drie standen uitgetekend: de landing met CTA-focus,
de railfocus (hoe het beeld terugtreedt als de rail de focus neemt), en de
poster-only fallback van 9.4 onder full-bleed.

**De rest van de pagina, gemeten in de simulator.** De rails staan in deze volgorde:
Verder kijken, Recent uitgebracht, "Recently Added Shows" (Engels, I18N5), drie keer
"Omdat je X gekeken hebt", Aanbevolen voor jou. Elke rail is de DEC-087-band: de
gefocuste kaart 16:9 met titel, meta en synopsis eronder, de buren als posters. Wat
afwijkt van de northstar en de audit: zodra de hero uit beeld is, is de achtergrond
vlak zwart waar 9.3 een ambient tint uit het actieve artwork vraagt; de nav staat op
een harde zwarte band; nieuw-markeringen zijn tekstpillen "NEW" en "NEW EPISODE" waar
de northstar een amberpunt tekent (audit, divergentie 5); en het bijschrift onder de
gefocuste kaart plus het volgende label nemen samen zoveel hoogte dat er per scherm
precies één rail past. D2 en D4 tekenen de railstapel onder full-bleed met de
ambient tint, de amberpunt en Nederlandse labels.

**Verduidelijkt door Michel op 4 september, na D1 tot en met D4**, letterlijk: "Ik wil
het geen wat ik nu heb met de nieuwe hero alleen het geen wat ik nu heb moet
geoptimaliseerd worden maak daar in nieuwe sessie een mockup voor", en daarna: "De
nieuwe hero ontwerp dus wel. Die full bleed." De hero wordt dus full-bleed zoals D1
tot en met D3 hem tekenen; de rest van de pagina blijft wat er nu staat, de
railstapel met de DEC-087-band, maar geoptimaliseerd op witruimte, overgangen,
indeling, styling en de navigatiebalk. Mockup 30 in de volgende sessie tekent die
combinatie, met D1 tot en met D4 en de gemeten afwijkingen hierboven als startpunt.

**Mockup 30, 4 september** (`docs/assets/tvos-unified/mockups-2026-09-04/30-home-*.png`,
bron in `src/pages/30-home-*.html`). De eerste opzet zette de railband op 654 met de
backdrop schermvullend erachter, en dat sneed het gezicht van het hero-onderwerp af bij de
mond. Michel, letterlijk: "Ik vind de full bleed hero mooi maar dan moet wel het item goed in
beeld zijn en niet half worden afgesneden door de volgende carroussel die erover heen staat.
Dat neemt het effect van de hero weg." Een 16:9-backdrop op een 16:9-scherm heeft geen
uitsnede meer, dus het anker van HERO1 doet hier niets; wat het onderwerp bedekt is de rail,
en dat is een keuze over de landing. Vier landing-opties, alle met het onderwerp heel:

- **A1, de rail piept.** Tekst 579 tot 840, label op 880, de posters piepen 147 van 346
  boven de onderrand. DOWN scrolt 508 naar stand B. Dit is de gangbare streaming-landing en
  mijn aanbeveling; hij laat 9.2 los op één punt, de eerste rail staat niet meer heel in beeld.
- **A2, het beeld past.** De backdrop heel op 16:9 als 996 bij 560 rechtsboven, dezelfde
  backdrop geblurd als schermvulling (de 9.4-taal op een backdrop), tekst in een kolom van
  760, label 601 en de band 654 tot 1000 heel in beeld op de achtergrond. Niets gesneden, niets
  bedekt, maar de hero is kleiner en minder full-bleed.
- **A3, alleen het label.** De hero ongestoord schermvullend, tekst 400 tot 661, op 985 alleen
  "Verder kijken" met een chevron als stille hint. De rail komt op DOWN. De zuiverste hero,
  ten koste van zichtbare railinhoud op de landing.
- **A4, mini-rail.** De eerste rail heel in beeld als strook van 133 bij 200 (799 tot 999)
  onder tekst 439 tot 700; op DOWN groeit hij naar de DEC-087-band. Alles staat er, maar
  posters van 133 breed zijn op een TV klein, en de groei is een layoutwissel bij focus.

De overige standen zijn onafhankelijk van die keuze. **B, railfocus:** de pagina scrolt tot
het label onder de navbalk staat, de herotekst dooft, de backdrop treedt
terug tot een gedimde band en gaat over in de ambient tint van 9.3; band 346 met 615-kaart en
231-buren, bijschrift 18 boven, titel 27, meta 20 mét puntspatiëring (in 29 D2/D4 miste
`.cap .m` de `.sep`-marge), synopsis op één regel, 26 naar het volgende label op 908, en de
volgende rail piept 119. **C, dieper op Home:** het gefocuste label ankert onder de nav op
132, waardoor de volgende rail er heel onder staat (721 tot 1067) in plaats van alleen zijn
label; de app zette elk gefocust label op 372 met zwart erboven,
en dat is waar de "één rail per scherm" vandaan komt. Verder de ambient tint, nieuw als
amberpunt (audit 5), het vinkje als witte schijf, en "Recent toegevoegde series" in het
Nederlands (I18N5). **D, alleen poster (9.4):** dezelfde poster sterk geblurd en donker als
vulling, scherp als eiland van 400 bij 600 rechts; getekend op de geometrie van A1 en volgt de
gekozen landing-optie. **E, overlay:** het contextmenu uit mockup 12 vanuit B, met de topnav
op 0,35 mee gedimd (audit 13). De nav zelf staat in alle standen op 44 tot 96 met de
profielchip met initiaal links en het wordmark rechts.

Open voor Michel: de landing-optie (A1 tot en met A4) en akkoord op B tot en met E. Daarna
DEC-095, de spec (9.1-schets, 9.2, 9.3, 7.1 rustfocus, 9.6 pauzeregels) en HOME1 op
GOEDGEKEURD.

**Besluit van Michel op 4 september, op mockup 30:** "Ik denk a 1 de rail piept en btme
akkoord." Vastgelegd als DEC-095: de hero full-bleed met de rail die eronder piept, het anker
onder de navbalk op DOWN en dieper op de pagina, het bijschrift met één regel synopsis, de
amberpunt, de Nederlandse labels en de gedimde topnav. Hoofdstuk 9.1, 9.2 en 7.1 zijn herzien,
9.3 en 9.6 nagelopen, 33.1 en 33.2 dragen een afwijkingsnotitie. De ambient tint van 9.3 blijft
fase 9 en gaat niet mee in de bouw. De bouw is een eigen ronde met de negatieve controle uit
DEC-095: een widgettest op `TvContentFeed` die de full-bleed hero, het zichtbare label met de
gedeeltelijk zichtbare band, en het anker na DOWN eist, rood op de huidige code.

### HOME1, de bouwronde

Gebouwd op 4 september als `eed2a79`, met de negatieve controle uit DEC-095 vooraf rood
gedraaid: de groep "HOME1 / DEC-095" in `test/screens/tv/tv_content_feed_test.dart` eiste op
de oude code dat de hero de volle feedbreedte inneemt (rood: de kaart stond op de pagina-inset),
dat het label van de eerste rail na DOWN op het anker van 154 tokens staat (rood: 4 logische
pixels ernaast) en dat een diepere rail onder de nav ankert (rood: 159 logische pixels lager).
De vierde test, de piepende band op de landing, was al groen en blijft staan als regressiewacht.

Wat er gebouwd is. De carousel is niet langer een lijstkind op de pagina-inset maar een laag
achter de lijst, ter grootte van de contentbox plus de gemeten navband erboven, die met de
scrolloffset meeschuift; het hero-blok in de lijst is een spacer van
`TvHomeLayout.heroBlockHeight`, zodat het label van de eerste rail op 880 staat en de posters 147
referentiepixels piepen. De kaart verloor ring, radius en schaduw en kreeg de leesscrim over de
volle hoogte en de verticale scrim voor nav en grond. Op rijfocus dooft de tekst en legt
`TvHeroDimVeil` zich schermvast over de laag; in de eerste build reisde die sluier met het beeld
mee en was boven het anker alles grond, de simulator liet dat zien en de test op de sluierpositie
is daarna toegevoegd. De rails krijgen per rij een scroll-anker via
`TvHomeLayout.rowTileScrollAlignment`: elke rij zet zijn label onder de nav. Het
bijschrift kromp naar één regel synopsis en de mockupmaten, het raillabel naar 27
referentiepixels (audit divergentie 6). De shell wisselde zijn `Column` voor een
`CustomMultiChildLayout` dat de balk eerst uitmeet en als laatste tekent, en publiceert de
bandhoogte via `TvShellSurface`; de eerste versie gaf de balk een begrensde hoogte en het
`Align` van de profielchip vulde daarmee het hele scherm, wat de drie I14-tests van de shell
direct aanwezen. De balk dimt naar 0,35 zodra `ModalRoute.isCurrent` omvalt (audit 13). Nieuw
is op de TV-kaarten een amberpunt (`NewContentDot`, audit 5), en `nl.i18n.json` heeft
`latestShows` (I18N5).

Bewijs. Gerichte suites groen: feed (inclusief de vijf HOME1-tests), carousel, hero-artwork,
titelband, RTL-contract, topnav (met twee nieuwe dim-tests), badge (met twee dot-tests),
dichtheid, shell, catalogus-kop. De bredere run over `test/widgets/tv` en `test/screens/tv`
gaf 428 groen en 14 rood, alle veertien Home-goldens die de oude kaart tekenen en al in de
nullijn van 78 rode goldens zitten; ze worden op Linux geregenereerd, niet hier.
`scripts/ci_checks.sh` gaf exit 0 op de definitieve boom. Pleya Verify:
`pleya_verify/scenarios/tvos.home.full-bleed.yaml` PASS op de tvOS-simulator (bundel
`tvos-home-full-bleed-1788545268365`), met de band onder de CTA op de landing, de hele eerste
band na DOWN, de tweede rail heel in beeld na de tweede DOWN, en de hero terug in beeld na UP UP.
Simulator-screenshots van landing, CTA-focus, railfocus met gedimde backdrop, dieper en het
contextmenu met gedimde nav zijn bekeken en kloppen met mockup 30 A1, B, C en E; de
posterfallback (D) is alleen als widgetgeometrie gebouwd en niet in de simulator gezien.

**Correctie op de eerste bouw, dezelfde dag.** Op de simulator las de band boven de gefocuste
rail als leegte: het anker van northstar 02 hield 242 referentiepixels onder de balk vrij, en
die ruimte was daar de zichtbare onderrand van de billboardkaart die full-bleed net had
weggenomen. Op een donkere still bleef er een zwarte strook over van een vijfde van de pagina.
Drie richtingen zijn voorgelegd: het anker weg, het anker halveren, of de dim verzwakken zodat
de strook als beeld leest. Michel koos eerst halveren en daarna alsnog het anker helemaal weg,
zoals geadviseerd, gebouwd als `7b3057a6`. `rowFocusAnchor` bestaat niet meer; `rowTileScrollAlignment` kent geen
rij-index meer en zet elk gefocust raillabel onder de balk. De twee ankerregels zijn er één
geworden, de volgende rail wint vier vijfde van zijn band, en mockup 30 B en E zijn opnieuw
geschoten op die compositie. De test die het anker op 372 vastlegde eist nu de nul.

Wat open blijft. Hardwarebewijs op de Apple TV, zoals bij HERO1: het anker van de scrim en de
leesbaarheid van de tekst over echt artwork zijn daar te toetsen. De ambient tint van 9.3 is
bewust niet gebouwd (fase 9). Het laatste rijlabel kan niet altijd tot onder de nav scrollen
omdat de lijst daar geen lege ruimte voor reserveert; dat is een keuze, geen bug.

### LANG1, taalcontinuïteit binnen series

Gevraagd door Michel op 4 september als sectie G van de personalisatie-opdracht: een
taalkeuze tijdens een serie moet voor de volgende afleveringen blijven gelden, met een
hiërarchie serievoorkeur, globale profielvoorkeur, fallback; een wijziging tijdens een serie
werkt standaard alleen die serie bij; de voorkeur hoort bij de logische serie en het profiel,
niet bij één bron; en de mockupronde tekent minstens één beheertoestand. De secties A tot en
met F van die opdracht staan niet in deze sessie, dus wat hieronder "globaal" heet is
uitgewerkt op wat de code nu kent. Waar A tot en met F een eigen globale laag in Pleya
definiëren, moet DEC-096 daarop worden bijgesteld voordat er gebouwd wordt.
**Eerst productontwerp en mockups, geen implementatie zonder akkoord.**

**Wat er al staat, nagelezen in de code.** Het per-serie taalgeheugen bestaat sinds 17
augustus. `TrackPreferenceStore` (`lib/services/track_preference_store.dart`) bewaart per
`{profielscope}|{grandparentId ?? id}` een `TrackLanguageChoice`: audiotaal, ondertiteltaal,
geforceerd, en een uitdrukkelijk "uit". Er wordt alleen geschreven bij een handmatige keuze
(`TrackManager._rememberAudioLanguage` en `_rememberSubtitleLanguage`, en bij een bronwissel
in `episode_navigation.dart`), nooit door de automatische selectie. Gelezen wordt bij elke
`applyTrackSelection`, en dat is het pad van alle zes de startsituaties uit de opdracht:
volgende aflevering, autoplay, start vanuit de detailpagina, vanuit Verder kijken, later
hervatten en de overgang naar een volgend seizoen. `TrackSelectionService` kiest in de
volgorde navigatie, sticky, serverkeuze, per-item, profiel, standaard. Ontbreekt de sticky
taal in een aflevering, dan valt de keuze door naar de lagen eronder en blijft de opslag
staan. Op Plex spiegelt Pleya de keuze naar de serie zelf (`writeSeriesLanguageToServer`,
standaard aan), zodat de serverkeuze bij transcoderen meegaat; de kaart reist via iCloud
naar de andere Apple-toestellen. Twee schakelaars staan in Instellingen ▸ Afspelen. Er wordt
op taal, titel en geforceerd gematcht, nooit op stream-id: `TrackLanguageChoice` zegt dat
letterlijk in zijn kop. De acceptatiejourney is dus voor het grootste deel al gebouwd.

**Waar de journey nu breekt.** Drie plekken, elk met een eigenaar.

1. *Een fallback reist mee naar de volgende aflevering.* Bij de overgang in de speler geeft
   `episode_navigation.dart:548-549` `currentAudioTrack` en `currentSubtitleTrack` door als
   `preferredAudioTrack` en `preferredSubtitleTrack`, en in `track_selection_service.dart:672`
   en `:770` staat die navigatiekeuze als prioriteit 1, boven de sticky keuze. Miste
   aflevering 3 de Engelse ondertitels en viel Pleya terug op Nederlands (of op uit), dan
   is dat in aflevering 4 de "gewenste" track, en `id == 'no'` betekent daar zelfs
   onvoorwaardelijk uit. De stap "aflevering 4 heeft Engels weer, Engels wordt gekozen" is
   rood. De oorzaak is dat de navigatie de *uitkomst* doorgeeft waar hij de *bedoeling* had
   moeten doorgeven. Eigenaar: `TrackSelectionService`, niet de aanroeper.
2. *De sleutel is een serverkey.* `grandparentId` is de ratingKey op één server. Dezelfde
   serie op NAS en Zolder heeft twee regels, en een Jellyfin-kopie een derde. Hoofdstuk 14.8
   sleutelt de bronvoorkeur al op `CanonicalMediaIdentity.bucketKey`; het taalgeheugen doet
   dat nog niet. Complicatie: een aflevering draagt geen jaar van de serie (`MediaItem` kent
   geen `grandparentYear`), dus de show-bucketKey uit hoofdstuk 11 is vanuit een aflevering
   niet te bouwen.
3. *Er is geen beheer.* Geen lijst, geen "gebruik globale voorkeur", en een regel verdwijnt
   alleen via de LRU-cap van 500. `copyWithAudio` en `copyWithSubtitle` kunnen een veld
   nooit leegmaken, dus `isEmpty` wordt na een eerste keuze nooit meer waar.

Een vierde punt is kleiner: valt de sticky ondertitel weg en staat het profiel op "altijd",
dan kiest `_findFirstSubtitleTrack` de eerste track in welke taal dan ook. Dat is geen
voorspelbare fallback.

**Voorkeurshiërarchie, zoals voorgesteld op 4 september.** Michel heeft dit in de
beslissingsronde hieronder op vier punten gecorrigeerd; DEC-096 draagt de gecorrigeerde
versie en gaat vóór op de tekst in deze alinea.

1. *Uitdrukkelijke keuze in deze afspeelsessie.* Wat de kijker net koos, als bedoeling: "de
   Engelse ondertitel", niet "track 3". Een fallback is geen keuze en komt hier niet in.
2. *Serievoorkeur*, per profiel en per logische serie. Een film sleutelt op zichzelf, zoals nu.
3. *Globale profielvoorkeur.* Dat is het gebruikersprofiel op de server: het Plex-account
   (`defaultAudioLanguage`, `defaultSubtitleLanguage`, de lijsten) of de Jellyfin-gebruiker
   (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode`). Pleya voegt in
   deze ronde geen derde laag toe. Reden: de Plex-spiegeling schrijft de serievoorkeur al op
   de serie, en een eigen globale laag ernaast zou twee waarheden geven die ook de officiële
   Plex-apps niet kennen. Wie twee backends heeft, heeft twee globale voorkeuren, en de
   pagina toont ze dan als twee blokken met de bron erbij.
4. *Fallback per aflevering, tijdelijk.* Audio: de serievoorkeur, anders de globale
   audiotaal, anders de serverkeuze, anders de standaardtrack van het bestand. Ondertitels:
   de serievoorkeur, anders de globale ondertiteltaal in de modus van het profiel, anders
   uit. Nooit "de eerste track in een willekeurige taal". Een onthouden "uit" is een keuze en
   wint altijd. De fallback wordt niet opgeslagen, reist niet mee naar de volgende aflevering
   (dat is punt 1 hierboven), en meldt zich één keer met de toast uit mockup 31 D.

**Handmatige wijziging tijdens een serie.** Geen driekeuzevraag bij elke trackwissel. Een
keuze in het infopaneel werkt de serievoorkeur bij, direct, en de toast uit 31 C bevestigt dat
en zegt erbij dat de globale voorkeur ongewijzigd blijft. "Alleen deze aflevering" bestaat als
schakelaar in het infopaneel: de rij "Onthouden voor deze titel" uit mockup 19 wordt
"Onthouden voor deze serie", en uit betekent dat de sessie de keuze houdt en de opslag niet
raakt. De globale voorkeur wijzig je op de instellingenpagina, nooit vanuit de speler. Of die
rijen op TV ook schrijven hangt van de backend af: Jellyfin heeft `POST
/Users/{id}/Configuration`; voor het Plex-account moet de bouwronde eerst meten of plex.tv
die instellingen laat schrijven. Tot die meting tonen de rijen de waarde en de bron, en
zeggen ze waar je hem beheert.

**Identiteit en bronnen.** De sleutel wordt een logische seriesleutel per profiel:
`show:{genormaliseerde serietitel}` plus, waar bekend, de sterke tokens uit
`identity_evidence.dart` (tmdb, tvdb, guid) op show-niveau. Zonder jaar is dat bewust een
zwakkere sleutel dan de bucketKey van hoofdstuk 11; twee series met dezelfde titel op
hetzelfde profiel delen dan een voorkeur, en dat is het aanvaarde risico tegenover een
voorkeur die op de tweede server niet bestaat. De oude serversleutel blijft als terugval
gelezen zolang hij bestaat, en een schrijfactie zet de regel om naar de nieuwe sleutel. Per
aflevering blijft de volgorde: gewenste taal ophalen, kijken wat de gekozen bron aanbiedt,
matchen op taal, type, geforceerd en titel, anders tijdelijk terugvallen, opslag ongemoeid.

**De journey tegen de code gelegd.**

| Stap | Mechanisme | Nu |
|------|-----------|----|
| Globaal Origineel + Nederlands, aflevering 1 | profiellaag, serverkeuze | groen |
| Kijker kiest Engels + Engels | `_rememberAudioLanguage`, `_rememberSubtitleLanguage` | groen |
| Aflevering 2 start Engels + Engels | sticky in `applyTrackSelection` | groen |
| Aflevering 3 mist Engelse ondertitels | fallback, opslag blijft | groen, maar zonder melding |
| Aflevering 4 heeft Engels weer | sticky | **rood**, punt 1 |
| Andere serie: globale voorkeur | sleutel per serie | groen |
| Dezelfde serie op een andere server | sleutel per server | **rood**, punt 2 |
| Voorkeur bekijken of terugzetten | bestaat niet | **rood**, punt 3 |

**Mockup 31, 4 september** (`docs/assets/tvos-unified/mockups-2026-09-04/31-taalvoorkeuren-*.png`,
bron in `src/pages/31-taalvoorkeuren-*.html`). De pagina heet Taal en ondertitels en staat
onder Mijn Pleya ▸ Instellingen, in de compositie van mockup 20: titel op 132, kruimelpad,
twee kolommen op 40 tussenruimte. De twee schakelaars verhuizen uit Afspelen hierheen, want
een kijker die zoekt waarom een serie Engels start, zoekt bij taal en niet bij afspelen.

- **A, de pagina.** Links de globale voorkeur met de bron erboven ("Uit je Plex-profiel
  Michel") en drie rijen: Audio, Ondertitels, Ondertitels tonen, elk met de fallback als
  ondertekst zodat het contract leesbaar is waar het geldt. Daaronder de twee schakelaars.
  Rechts de serievoorkeuren als rijen van 104 met poster van 56 bij 84, de titel, de keuze
  op één regel en eronder wanneer, bij welke aflevering en op welk toestel hij ontstond. De
  voetnoot zegt wat de kijker hier kan en dat een ontbrekende track niets verandert. Lege
  staat, niet getekend: de kolom toont alleen de zin dat serievoorkeuren vanzelf ontstaan.
- **B, de sheet.** Select op een rij opent de sheet van mockup 12 op 820 breed: poster en
  titel, de herkomst, en de zin dat de voorkeur op elke bron geldt. Twee leesrijen met de
  serie- en de globale waarde naast elkaar, en één actie: Gebruik globale voorkeur, met
  "wist deze serievoorkeur" als bijschrift. Een andere taal kies je hier niet; dat doe je
  tijdens het kijken, en de voet zegt dat.
- **C, de bevestiging.** Na een keuze in het infopaneel sluit het paneel en staat drie
  seconden een toast op 120 boven de onderrand: de keuze, "onthouden voor Severance", en de
  regel dat de globale voorkeur Nederlands blijft. Dit is `PlayerToastController` met een
  tweede regel; die bestaat nu met één regel en 1,2 seconde.
- **D, de terugval.** Bij de start van een aflevering die de serievoorkeur mist staat
  dezelfde toast met een amberpunt: wat ontbreekt, wat er nu speelt, en dat de voorkeur
  blijft. De OSD-titel toont Zolder als bron, om te laten zien dat de voorkeur de bron
  overleeft.

**Open voor Michel.**

1. De hiërarchie en het fallbackcontract van DEC-096, in het bijzonder "anders uit" voor
   ondertitels in plaats van de eerste track.
2. Geen driekeuzevraag: een wijziging tijdens een serie is de serievoorkeur, met toast.
3. De globale laag is het serverprofiel, geen eigen laag in Pleya. Zeggen de secties A tot
   en met F iets anders, dan hoor ik dat graag hier.
4. De plek: Mijn Pleya ▸ Instellingen ▸ Taal en ondertitels, en de twee schakelaars weg uit
   Afspelen.
5. Mockup 31 A tot en met D als compositie.

**Bouwronde, pas na akkoord.** Drie negatieve controles, elk rood op de huidige code: een
test op `TrackSelectionService` met sticky Engels, een doorgegeven Nederlandse fallback en
een beschikbare Engelse track die Engels eist; een test op `TrackPreferenceStore` die een
keuze op de ene bron terugleest op een tweede bron van dezelfde serie; en een widgettest op
de nieuwe pagina die de rij, de sheet en het wissen eist. Daarna de fallback-toast, de
verhuizing van de twee schakelaars, en een Pleya Verify-scenario voor de journey op de
tvOS-simulator. Raakt de bouw het Plex-schrijfpad voor het account, dan gaat daar eerst een
contractmeting aan vooraf.

**Beslissingsronde van Michel, 4 september.** Doorgaan naar implementatie, met tien bindende
correcties. DEC-096 is daarmee accepted; waar deze sectie en het besluit verschillen, wint het
besluit.

1. *De hiërarchie krijgt vier lagen:* uitdrukkelijke keuze tijdens de lopende playback,
   serievoorkeur, globale Pleya-profielvoorkeur, terugval op bron en bestand. "Uitdrukkelijke
   keuze" is alleen een echte handeling. Niet de spelende track, niet een terugval, niet een
   track-id uit de vorige aflevering, niet een bron-default die toevallig aanstond. Elke
   aflevering resolveert de intentie opnieuw.
2. *Het terugvalcontract.* Audio: gewenste of originele taal, anders tijdelijk de bron- of
   standaardtrack. Ondertitels: gewenste taal, anders de ingestelde terugvaltaal, anders uit.
   Nooit de eerste beschikbare track. Engels wordt niet als universele regel vastgelegd: de
   terugvaltaal wordt een echte profielvoorkeur, zichtbaar als eigen rij op de pagina.
3. *Geen driekeuzevraag.* Staat "Onthoud keuzes per serie" aan, dan werkt een bewuste wissel
   de serievoorkeur bij met een toast. Staat hij uit, dan geldt de wissel alleen voor die
   sessie en ontstaat er geen override. De globale voorkeur verandert nooit vanuit de speler.
4. *De globale eigenaar is het Pleya-profiel, niet het serverprofiel.* De eis is dat de
   voorkeur voor alle content geldt, ook over servers en backends heen.
   `PleyaProfilePlaybackLanguagePreferences` draagt audio, ondertitels, beleid, terugvaltaal en
   `rememberPerSeries`. Bronprofielen zijn spiegel, geen autoriteit.
5. *Spiegelen naar Plex blijft, capability-gated.* Een mislukte schrijfactie maakt de
   Pleya-voorkeur niet ongeldig. De copy in 31 A noemt daarom het Pleya-profiel als eigenaar.
6. *Serie-identiteit.* Logische serie waar de identiteit betrouwbaar is, anders de concrete
   server-en-serie-sleutel. Een onterechte samenvoeging is erger dan een gemiste, en er komt
   geen samenvoeging op alleen titel en jaar bij om taalvoorkeuren te kunnen delen. De
   serversleutel blijft migratie- en terugvalpad.
7. *Nooit track-id's bewaren.* Opgeslagen wordt taal, de intentie "originele taal" en het
   ondertitelbeleid. Nooit een trackindex, track-id of stream-id.
8. *31 A en 31 B zijn goedgekeurd*, met de eigenaarscorrectie in de copy. De tweekolomsindeling
   en de serievoorkeurenlijst met herkomst blijven.
9. *31 C en 31 D zijn goedgekeurd met een presentatiecontract voor de toast:* geen focus, geen
   blokkerende invoer, verdwijnt vanzelf, en ondertitel-veilig geplaatst in een bestaande
   spelerzone. Geen zelfgekozen Y-positie.
10. *De pagina is de enige beheerplek.* De taalschakelaars onder Afspelen verhuizen hierheen.
    Heeft het infopaneel later een ingang nodig, dan linkt het hierheen.

**Wat de correcties aan de mockups veranderd hebben.** De vier beelden zijn opnieuw geschoten
op dezelfde nummers. In 31 A staat nu "Pleya-profiel Michel · geldt voor alle content zonder
eigen serievoorkeur" waar eerst het Plex-profiel als bron stond, is "Terugvaltaal ondertitels"
een eigen rij geworden in plaats van een hardgecodeerd Engels in de ondertekst, en heet de
tweede schakelaar "Spiegel naar Plex" met de regel dat een mislukte schrijfactie de
Pleya-voorkeur laat staan. In 31 B leest de sheet de globale waarden als "Pleya-profiel: ..."
en zegt de kop dat de voorkeur geldt waar Pleya de serie als dezelfde herkent, in plaats van
onvoorwaardelijk op elke bron. In 31 C en 31 D is de toast verplaatst van onderin naar de
bestaande bovenzone, en beide beelden tekenen nu een echte ondertitelregel onderaan mee, zodat
te zien is dat de toast er niet overheen valt.

**De toastzone heeft een bestaande eigenaar, dus het contract wijst er alleen naar.**
`video_controls.dart:986-1004` zet de toast al in een `Positioned.fill` met een `IgnorePointer`
eromheen, en `PlayerToastIndicator` lijnt boven uit met een `AnimatedSwitcher` en de auto-hide
van `PlayerToastController`. Dat is precies wat het contract vraagt: geen focus, geen invoer,
zelf verdwijnend. Ondertitels staan onderaan onder `sub-pos` (`SettingsService.subtitlePosition`,
standaard 100), dus de bovenzone en de ondertitels kunnen elkaar niet raken. De bouwronde voegt
alleen een tweede regel en een langere duur toe en verplaatst niets.

**De negatieve controles van de bouwronde, alle rood voordat er code verandert.**

| Controle | Wat hij eist |
|----------|--------------|
| A | Een terugval in aflevering N besmet aflevering N+1 niet |
| B | De serievoorkeur werkt over de volgende aflevering en het volgende seizoen |
| C | De globale voorkeur komt uit het Pleya-profiel |
| D | Gewenst, terugval, gewenst weer beschikbaar: de gewenste taal wordt opnieuw gekozen |
| E | Handmatige wissel met `rememberPerSeries` aan schrijft de serie-override |
| F | Handmatige wissel met `rememberPerSeries` uit schrijft geen serie-override |
| G | "Gebruik globale voorkeur" verwijdert de serie-override |
| H | Dezelfde logische serie op een betrouwbare tweede bron gebruikt dezelfde voorkeur |
| I | Een onbetrouwbare identiteit wordt niet over servers heen samengevoegd |

**Stand van de bouwronde, 4 september, `eae19cb4`.** De vier lagen, het
terugvalcontract, de logische seriesleutel en de eigenaarswissel naar het
Pleya-profiel staan. De negen controles zijn eerst rood aangetoond: A rood op vier
assertions, C, D, F, G en H rood, en B, E en I bleken al voldaan door de code van
17 augustus. Voor A, C, D, F, G en H is per fix teruggedraaid dat de controle dan
weer rood wordt, dus de controles hebben tanden. Twee dingen kwamen er bovenop die
niet in de analyse stonden: een terugval werd doorgegeven én
*weggeschreven* (prioriteit `navigation` triggerde `onAudioTrackChanged`, dus hij
overschreef de serievoorkeur zelf), en de schakelaar "onthouden" werd door de
aanroepers gecontroleerd in plaats van door de opslag, waardoor het
transcodeerpad er jarenlang omheen schreef.

Nog open: de pagina Taal en ondertitels (31 A), de sheet (31 B) en de twee toasts
(31 C en D). De twee schakelaars staan nog onder Afspelen, maar lezen en schrijven
al het profiel, zodat de verhuizing een pure verplaatsing is en er nooit twee
eigenaren naast elkaar hebben bestaan.

**Protocolgat, gemeld en niet stil opgelost.** De serievoorkeur sleutelt op de
logische serie waar de identiteit betrouwbaar is. Plex draagt `grandparentGuid` op
een afleveringsrij en krijgt die sleutel. Jellyfin antwoordt met `SeriesId`, dat
serverlokaal is. Het `/v1`-contract van Pleya Server draagt in `Item` helemaal geen
identiteitstoken: geen guid, geen externe ids. Die twee vallen dus terug op de
serversleutel, wat precies is wat DEC-096 lid 7 voorschrijft, maar voor Pleya Server
betekent het dat dezelfde serie op twee Pleya Servers twee voorkeuren houdt. Het
protocol is bevroren tijdens PS-5, dus dit hoort in een fase die het contract mág
wijzigen; het gevraagde veld is één stabiel identiteitstoken op `Item`.

Volgorde: eerst oud rood aantonen, dan implementeren, dan groen. Daarbovenop de drie stappen
die al onder deze bevinding stonden: de widgettest op de nieuwe pagina, de verhuizing van de
schakelaars, en een Pleya Verify-scenario voor de journey op de tvOS-simulator.

**Stand van de bouwronde, 5 september, `a9a50ad9` en `a5730f35`.** De pagina, de sheet en de twee
toasts staan. Mijn Pleya ▸ Instellingen ▸ Taal en ondertitels is de enige beheerplek: de
globale voorkeur met audio, ondertitels, terugvaltaal en beleid, de twee schakelaars die
uit Afspelen verhuisd zijn, en de serievoorkeuren met poster, keuze en herkomst. Select op
een rij opent de sheet van 31 B, die de serie- en de profielwaarde naast elkaar leest en één
actie aanbiedt. De verhuizing van de schakelaars is een pure verplaatsing, want hun opslag
werd in `eae19cb4` al het profiel; onder Afspelen staat nu een verwijzing.

Controles J tot en met S zijn eerst rood aangetoond op `6e6fcb78`, in een aparte worktree
zodat de checkout van de andere sessies ongemoeid bleef. Elk van de vier bestanden faalt daar
op compilatie: de herkomst, `clearKey`, de melding, de pagina en de tweede toastregel bestaan
er niet. J bewaart serie, poster, bron, aflevering en toestel bij de keuze; K leest de lijst
nieuwste eerst; L wist precies één regel, ook met "Onthoud keuzes per serie" uit; M is de
terugvalmelding met de juiste eigenaar en zonder de opslag te raken; N is de bevestiging na
een handmatige keuze, inclusief het geval waarin er niets bewaard wordt; O tot en met R zijn
de pagina, de rij, de sheet en het wissen; S is de toast met twee regels en de amberstip.
Daarna groen: 132 tests over acht bestanden, `ci_checks.sh` schoon op de gepinde SDK, en de
testsuite met dezelfde 83 falers als de schone baseline (78 goldens plus vijf in
`tv_discovery_rail_test.dart`), dus nul nieuwe.

Vier dingen die de bouw zelf opleverde en die niet in de analyse stonden:

1. *Herkomst hoort bij de keuze.* De pagina toont voorkeuren van elke bron waar het profiel
   ooit van speelde, ook van een server die verwijderd is of uit staat, en precies die regels
   zou een opzoeking leeg laten. `TrackLanguageChoice` draagt de herkomst daarom mee. Dat kost
   ongeveer 120 byte per regel, dus de LRU-cap gaat van 500 naar 250 om dezelfde marge onder
   het iCloud-plafond van 100 KB te houden. Niets ervan raakt de resolutie.
2. *De statische schrijfvergrendeling strandt tussen widgettests.* Een future die in een
   afgebroken testzone is gemaakt komt nooit terug, en de volgende test wacht er eeuwig op
   achter een spinner die nooit uitdraait. Beide stores hebben nu een `resetForTesting`.
3. *`showSelectionDialog` antwoordt null voor twee verschillende dingen*, "geen voorkeur" en
   "weggeklikt". De beleidsrij sleutelt daarom op een string en kan niet meer stilzwijgend
   wissen wat de kijker alleen maar bekeek.
4. *De linkerkolom begon in de tegeltaal van Mijn Pleya* en is teruggezet naar de rijvorm van
   31 A toen de simulator liet zien dat zes tegels niet op één scherm passen. Zie de
   simulatorronde hieronder.

**De simulatorronde, en wat hij vond.** `pleya_verify/scenarios/tvos.settings.language-preferences.yaml`
is vijf keer gedraaid op de tvOS-simulator en staat op `a5730f35` groen: de pagina opent vanuit de
instellingenindex met de topbalk erboven, de zes rijen van de linkerkolom staan binnen het beeld en
onder elkaar, de taalkiezer opent en sluit zonder de pagina te verlaten, en Menu komt terug op de
index. De bewijsbundel draagt zes schermafbeeldingen van het echte toestel.

Twee van die runs waren rood, en allebei op iets echts:

1. *De linkerkolom paste niet op één scherm.* Hij stond in de tegeltaal van Mijn Pleya, en die
   tegel is op een Apple TV ongeveer 180 punten hoog: zes ervan duwen de laatste twee onder de
   1080-rand (`insideViewport(language_remember)`, overflow onderaan). De rij is nu de vorm die
   31 A tekent, titel met een regel eronder en de waarde rechts, en het scenario bewaakt de eerste
   én de laatste rij. Daarmee vervalt punt 4 hierboven: de kolom volgt de mockup, niet het
   tegelidioom.
2. *Menu zet de focus niet terug op de tegel waar de subpagina vandaan kwam.* De shell lost
   `restoreFocusKey` alleen op voor een route die vanuit de Mijn Pleya-*hub* is geopend
   (`_popTvNestedRoute` vraagt het aan `_tvMyPleya`), en een instellingen-subpagina zit daar een
   niveau onder. Dat geldt voor Uiterlijk en Logs net zo goed als voor deze pagina. Het scenario
   asserteert daarom wat het product vandaag belooft, met de bevinding erbij; sluiten vraagt een
   wijziging aan het navigatiecontract, niet aan deze pagina.

**Bevinding: de bestaande my-pleya-scenario's lopen vast op een verouderde hubchoreografie.**
`tvos.my-pleya.section-settings.yaml` liep in dezelfde ronde rood op precies de stap die mijn eerste
versie ervan overnam: twee keer omlaag en dan drie keer rechts is niet meer de weg naar Instellingen.
De hub opent op Profiel wisselen, en twee keer omlaag ís Instellingen. Het geldt vermoedelijk voor de
hele familie `tvos.my-pleya.section-*`; het nieuwe scenario draagt de juiste choreografie en de
oude blijven zoals ze zijn tot iemand die serie langsloopt.

**Hardware blijft de laatste stap.** De simulator bewijst de pagina, de traversal en de kiezer;
de toasts van 31 C en 31 D zijn met widgettests bewezen en nog niet op een toestel gezien.

**Bevinding naast LANG1, niet stil opgelost.** `track_language_preferences` staat in geen
enkele regel van `preference_sync_policy.dart`, dus `policyFor` valt terug op `_unknown`
(`PreferencePolicy.localOnly`, `runtimeCache`) en de serievoorkeuren gaan vandaag *niet* mee
naar iCloud. De kop van `TrackPreferenceStore` en de tekst van DEC-096 gaan er allebei van uit
dat de keuze naar de andere Apple-toestellen reist, en de herkomstregel ("op welk toestel")
is er zelfs op gebouwd. Het registreren van die pref zet echter synchronisatie aan voor een
waarde die vandaag lokaal blijft, en dat is een gedragswijziging die buiten deze fase valt.
Hij hoort bij dezelfde opruiming als het regex-gat in `preference_sync_policy_test.dart` dat
`track_language_preferences` en `unified_source_preferences` al langer ongezien doorlaat.

### NAV1, tweede oorzaak: een tweede native druk na de Home-refresh

Heropend 5 september op de Apple TV met build 251, waar `51186c6` in zit. Log `y0w9x`
(`curl -sS https://ice.pleya.app/logs/y0w9x`) laat per ringdruk die op Home landt twee complete
native keydown/keyup-paren van dezelfde toets zien, 80 tot 230 ms uit elkaar, de tweede telkens
net nadat "Fetched 20 on deck items" de Home-refresh afsluit. Geen `source=swipe`, geen
`KeySimulator`: het is niet het aanraakpad waar NAV1 op gefixt is, en niet de Dart-kant van
`GamepadService`. Het tweede paar komt over `flutter/keydata` binnen als een tweede fysieke druk,
in drie van de vier gevallen zonder eigen `touch started` (`reason=no-active-touch`), in het
vierde nog binnen de aanraking van de eerste. Het duplicaatvenster van 120 ms miste het.

De navbalk is bewezen niet de eigenaar: `tv_top_navigation_test.dart:301` loopt precies de
gemelde route af, één stop per druk, en is groen.

**Fix, verankerd op de aanraakstroom.** `AppleTvRemoteTouchService` onthoudt het laatste
afgeronde native paar (keydown én keyup) en of er sindsdien een `started` is geweest. Een tweede
keydown van dezelfde toets zonder nieuwe aanraking, binnen 500 ms, is een duplicaat en wordt
samen met zijn keyup geconsumeerd. Een echte tweede tik brengt zijn eigen `started` mee en gaat
door; een ingedrukt gehouden richting heeft geen keyup ertussen en blijft herhalen. Vijf
replay-tests in `apple_tv_remote_touch_service_test.dart` spelen de logregels na, met hun
tijdsverschillen, en de 43 bestaande controles blijven groen.

**Bron nog aan te wijzen, op het toestel.** Twee kandidaten buiten Dart: `universal_gamepad`
ziet de Siri Remote als gamepad (log regel 15) en kan D-pad-input als toetsevent injecteren, of
de engine-fork laat beide geswizzelde hops in `tvosHandlePress` landen en synthetiseert onder een
zwaar frame twee keer. A/B: een build met `GamepadService` uit op Apple TV; verdwijnt het tweede
paar uit de log, dan gaat de gamepad-bridge daar structureel uit, anders gaat de log naar de
engine-fork. De dedupe blijft in beide gevallen staan. De simulator kan dit niet: geen
aanraakvlak, en de kliktest van WALK ziet het dus ook niet.

### NAV1, de echte oorzaak: de Menu-passthrough laat de ingedrukte pijl los

Gesloten op 5 september na acht toestelbuilds (DEC-099). De tabel is de volledige meetreeks; wie hier
later naar kijkt hoeft niets ervan te herhalen.

| Build | Wat erin zat | Log | Uitkomst |
|-------|--------------|-----|----------|
| 252 | dedupe in `AppleTvRemoteTouchService` (`531ae19c`) | `3zsde` | tweede paar blijft |
| 253 | idem, gamepad-bridge uit | `6zuye` | tweede paar blijft; `universal_gamepad` is niet de bron |
| 254 | early key handler (`34f9356f`) plus 500 ms-heuristiek | `ld1t1` | 65 echte drukken opgegeten |
| 255 | `press-diag` vanuit Swift: fase en `UIPress`-adres per druk | `wa6v9` | de meting die de oorzaak bevat |
| 256 | `.ended` van een pijl aan UIKit gegeven (`67992a57`) | crashlog | `_verifyTrackingPresses:` asserteert op elke pijl |
| 257 | `.ended` ingeslikt (`79adcc8a`) | geen crash | remote blijft in één richting hangen |
| 258 | filter uit (`5c0db0a1`) | | bedienbaar, dubbele stap terug |
| 259 | passthrough wacht op key-up (`7786a952`) | | te bevestigen op het toestel |

**Wat log `wa6v9` werkelijk zegt.** De eerste twee drukken zijn goed: omhoog (10:59:18.862,
keydown op fase 0, keyup op fase 3, 80 ms later) en rechts, weg van Home (19.475 en 19.581).
De derde druk, links terug naar Home, krijgt op fase 0 een keydown én 3 ms later een keyup, en
op fase 3 een tweede compleet paar. Elke druk daarna wisselt Home in en uit en verdubbelt. Het
is dus niet "de engine post een paar per fase", zoals de vorige analyse zei. Het is één
specifieke druk: die welke op de Home-tab landt.

**De engine, gelezen in plaats van geraden.** `scripts/tvos_engine_source.sh` reconstrueert
`FlutterViewController.mm` uit de patchreeks van de fork; `docs/tvos-remote-press-pipeline.md`
beschrijft het pad per station. Drie regels doen het:

1. `setMenuPressPassthroughEnabled:YES` roept `releaseAllSynthesizedPresses`, een synthetische
   keyup voor elke toets die de engine vasthoudt. De app zet die vlag zodra de focus op de
   Home-tab in de balk staat (`shouldPassTvosMenuToSystem`, `isCurrentTabRoot`).
2. `.ended` synthetiseert met `tapIfMissingKeyDown:YES`: een toets die niet meer in de set
   staat krijgt een vers down/up-paar. Dat is stap twee.
3. De herhaaltimer (0,4 s, daarna 80 ms) loopt zolang de toets in de set staat. Dat is 257:
   de ingeslikte `.ended` haalde de pijl nooit uit de set.

Geen enkel signaal in Dart onderscheidt het tweede paar van een echte snelle druk, en de fase
op zichzelf is onschuldig. De enige plek waar het te zien was, is het kanaalbericht dat de app
tussen de keydown en de keyup verstuurde, en dat stond niet in de log.

**Fix bij de afzender.** `TvosSystemNavigationService` parkeert een enable tot
`HardwareKeyboard.physicalKeysPressed` leeg is en stuurt hem op de eerstvolgende key-up; een
disable laat in de engine niets los en gaat direct. Drie tests in
`tvos_system_navigation_service_test.dart`, twee rood vóór de fix. De filter in `AppDelegate`
is weg (`5c0db0a1`); de early key handler uit `34f9356f` blijft, want die is het enige
Dart-pad dat een druk kan stoppen en de dedupe leunt erop.

**Wat Pleya Verify bewijst, en wat niet.** Met een NSLog-regel per druk in de Swift-hook is
gemeten dat een idb-druk in de simulator `tvosHandlePress(fromUIEvent:)` nooit bereikt (nul
hits in tien drukken, hook beschikbaar). De engine-helft van deze bevinding is dus niet in de
simulator te reproduceren en blijft `HARDWARE ONLY`. Het contract van de app wél:
`TvosSystemNavigationService` publiceert `tvos.menu_passthrough` met `parkedFlushes` en
`enablesSentWhileKeysHeld`, en `tvos.nav.held-press-lands-once.yaml` landt met
`holdMs: 250` drie keer op Home en eist 3 en 0. Groen met de deferral (bundel
`tvos-nav-held-press-lands-once-1788605245133`); rood zonder (deferral uitgeschakeld in dezelfde build, bundel `tvos-nav-held-press-lands-once-1788605599538`: `parkedFlushes` 0, `enablesSentWhileKeysHeld` 1). De unit-tests in `tvos_system_navigation_service_test.dart` dekken dezelfde vier waarden.

**Open op hardware.** Build 259 staat op het toestel. Te bevestigen: links en rechts over de
balk landen één tab per druk, ook op Home; Menu op Home verlaat de app nog; Menu op een andere
tab of in een sectie blijft in de app.

### HERO3, "Recent uitgebracht" had geen venster

Gemeld 5 september op het toestel: de hero toont films die niet recent uitgebracht zijn.
`getLatestMoviesFromAllServers` haalde de 100 laatst *toegevoegde* items, hield films over,
sorteerde op releasedatum en nam de top 12; niets weigerde een film uit 1998, en een film zonder
releasedatum reed mee op `addedAt`. DEC-067 en hoofdstuk 9.5 beloofden "recent uitgebracht"
zonder te zeggen wat recent is. Besluit van Michel: 90 dagen op de releasedatum, en zonder datum
buiten de hero (DEC-097). Vier HERO3-controles in `data_aggregation_bridge_test.dart` eisen de
grens; de bestaande test die het oude gedrag vastlegde is bijgewerkt.

Gevolg dat vooraf niet in de analyse stond: de Verify-fixture is een Pleya-fake-server over
`/v1`, en dat contract draagt geen releasedatum. De hero-scenario's op de simulator zien dus de
fallback, en dat is precies wat DEC-097 voor een Pleya Server voorschrijft tot het contract een
releasedatum draagt. Dat protocolgat staat naast het identiteitsgat van LANG1.

### PLR1, de spelerlaag betaalt de title-safe inset

Gemeld 5 september met foto: de "B" van Bluey en de "S" van S3 afgesneden, "3:09" op de rand.
De speler rendert op tvOS `DesktopVideoControls`; de titelbalk nam op alles wat niet macOS is
`macOSLeftFullscreen` = 0, en het onderblok stond op 24. `main.dart` zet de tvOS-overscan-insets
op nul, dus `SafeArea` helpt niet; elke andere TV-pagina betaalt `tvPageInset`. Nu de speler ook
(titelbalk, onderblok, content strip, zwevende knoppen, en het infopaneel als ondergrens). Een
widgettest eist dat titelblok en tijdlijn niet vóór de inset beginnen; `player.title`,
`player.timeline` en `player.safe_area` bestaan voor Pleya Verify. Een spelerscenario wacht op
een betrouwbare afspeelroute op de TV-shell (VER5) en is bewust niet gefaket; hardware is J4.


### WALK, de vier scenario's op de simulator

De kern (`c4ffcd16`, DEC-098) was er al; wat openstond was het bewijs dat een walk op de echte
oppervlakken doet wat hij belooft. Vier scenario's, één ronde per oppervlak, alle vier groen op de
tvOS-simulator, plus twee sabotagecontroles die aantoonbaar rood waren.

Het eerste gat was `nav.profile`. De profielchip is de linkerrand van de bovenbalk, dus de laatste
hop van een walk naar links landde op een `discovered`-knoop die een scenario niet kan benoemen.
Zonder id kan een walk over die balk drukken tellen, maar niet zeggen waar ze uitkomen.

Het tweede gat was de generator. `tool/generate_automation_ids_yaml.dart` crashte met "type
'InvalidType' is not a subtype of type 'FunctionType'", waardoor `automation_ids.yaml` met de hand
werd bijgewerkt en dus kon gaan afwijken van de catalogus in Dart. De oorzaak was een import:
`automation_ids.dart` haalde `navigation_tabs.dart` binnen voor alleen de enum `NavigationTabId`,
en daarmee de hele widgetboom, die de kale Dart-VM langs de FFI use-site-transformer moest
compileren. De enum staat nu in `lib/navigation/navigation_tab_id.dart` en `navigation_tabs.dart`
re-exporteert hem, dus geen andere import verandert en de yaml is weer gegenereerd.

#### Wat de hops laten zien

De bovenbalk is zes stops: profielchip, Zoeken, Home, Series, Films, Mijn Pleya. Twee hops naar
links, vijf terug naar rechts, alle zeven `ok`. Op Home drie hops omlaag (balk, hero-Afspelen,
rail 0, rail 1) en twee terug omhoog. Op de taalpagina zes rijen, één per druk, ondanks
rijhoogtes die verschillen omdat een rij met een noot eronder hoger is dan een schakelaar.

De hub gaf het antwoord op een vraag die als tegenspraak in de lijst stond. `tvos.my-pleya.alignment`
en `tvos.settings.language-preferences` noemen na twee keer omlaag een verschillende tegel, en de
aanname was dat één van de twee verouderd was. Dat is niet zo. De entree-druk landt op
`tvMyPleya_switchProfile`, de kop van de pagina, en pas daarna komen de tegels: `switchProfile`,
`my_pleya.tile[libraries]`, `my_pleya.tile[settings]`, rand. `alignment` loopt zonder Select naar
binnen en komt dus op `libraries` uit; `language-preferences` drukt eerst Select, en dat verplaatst
de ring via `TvContentFocusAuthority.onDestinationSelected` al naar `switchProfile`, zodat dezelfde
twee drukken een rij lager eindigen, op `settings`. Allebei kloppen, en het verschil is die ene
druk. Geen van beide is bijgewerkt.

#### De balk is sticky, en dat is geen sprong

De walk omhoog op Home was in eerste instantie rood, en terecht gemeld. Op een pagina die tot de
tweede rail gescrold staat, staat de bovenbalk op y=46 terwijl de rail die verlaten wordt op y=198
staat en de rail waarnaar teruggekeerd wordt nog op y=-354, boven de vouw. Meetkundig ligt de balk
er dus tussen, en het orakel zegt dat ook.

Navigationeel ligt hij er niet tussen. `TvRailStack._handOver` bezit UP tussen rails en geeft de
toets pas boven de eerste rail terug, dus de balk bereik je door eerst naar de hero te lopen. Dat
is het LAND4-contract en geen defect, dus het scenario noemt de twee balkitems in `allow`. Per id,
niet als ruimere marge: een overgeslagen rail op diezelfde hop blijft rood, en dat is precies wat
de tweede sabotagecontrole aantoont.

Reken erop dat elke verticale walk op een gescrold TV-oppervlak dezelfde vrijstelling nodig heeft.
Het orakel kan niet zien dat een balk niet meebeweegt met de inhoud, en dat afleiden uit een
vergelijking van het frame ervoor en erna zou een regel toevoegen die op een animerend frame kan
omvallen. Een vrijstelling per scenario laat zien wélke knoop gepasseerd mag worden.

#### De negatieve controles

Beide zijn toegepast op een gebouwde app, gedraaid, en daarna teruggedraaid; geen van beide staat
in een commit.

`destinations[i + 1]` naar `destinations[i + 2]` in `tv_top_navigation.dart` laat de balk Home
overslaan. De walk naar rechts valt op hop 2 met "expected to land on 'nav.discover' and landed on
nav.series". `index + delta` naar `index + delta * 2` in `tv_rail_stack.dart` laat de stapel een
rail overslaan. De walk omlaag valt op hop 3, met `discover.rail.item[2.0]` in plaats van `[1.0]`.

Allebei vallen ze op de druk die de fout maakte, wat het punt van de stap is. Wel vallen ze als
`expectMismatch` en niet als `skipped`, want `expect` wordt vóór het orakel gecontroleerd. Wie de
overslagdetectie zelf wil zien afgaan, haalt `expect` weg en houdt de sabotage.

Terzijde uit de tweede controle: de Home-feed van `catalog.mixed.v1` heeft minstens drie rails,
niet twee. `discover.rail.item[2.0]` bestaat. Het scenario noemt de eerste twee landingen en stopt
daar; VER4 blijft open, want geen rail is lang genoeg om te scrollen.

### NAVSEL1, `tvos.nav.destination-select` sprak de app tegen en is weg

Gevonden tijdens het WALK-werk, gedraaid op 5 september, en daarna verwijderd.

Het scenario beweerde twee dingen. Eén druk naar rechts vanaf Home landt op `nav.movies`, en er
is een Select nodig om van bestemming te wisselen. De balk is
`search, home, series, movies, [liveTv], myPleya` (`lib/navigation/tv/tv_destination.dart`), dus
daar staat Series, en `_focusTvDestination` (`lib/screens/main_screen.dart`) draait bij focus al
`_tvNav.activate` en `_selectTab`.

De run valt op de eerste van de twee, in bundel `tvos-nav-destination-select-1788614005520`:
`assert failed: focused(nav.movies): 'nav.movies'.focused is false, expected true`. Verder komt
hij niet, want de rest van dat blok staat op dezelfde druk: de assertie dat Home ná die druk nog
`active` is, is de tweede helft van hetzelfde onjuiste model. Beide helften stammen uit het
contract van vóór 2 september.

Repareren zou een duplicaat opleveren. `tvos.nav.focus-switches-destination` dekt precies wat
dit scenario claimde te dekken, en is in dezelfde sessie groen gedraaid
(`tvos-nav-focus-switches-destination-1788615210216`): de koude start op de balk, `active` dat
met de focus meeschuift zonder Select, DOWN als de enige weg naar binnen, UP terug, en een
reeks drukken zonder wachttijd ertussen. De verwijzing in `tvos.home.hero-return` wijst nu daarheen.

### HERO4, de hero schuift weg maar zijn knoppen blijven staan

Gemeld met een foto: terug op Home na afspelen stonden alleen de hero-knoppen in beeld, artwork
weg, rails eronder.

De meting van 5 september staat in de bundel `tvos-home-hero-return-probe-1788613144700` en is
niet omstreden. Home in rust zet `discover.hero` op y=0 en `discover.hero.play` op y=740,5. Zodra
de eerste rail de focus krijgt staat de hero op y=-721,3 en de knoppenrij op y=19,1, en na de
detailpagina en een Menu terug is dat nog steeds zo, in twee frames met 3 s ertussen.

Wat die bundel er bovenop laat zien, en wat de vorige lezing miste: y=19 verschijnt al bij de
tweede druk omlaag, vóór er iets gepusht is. De terugweg bewaart die toestand alleen. De
gepushte route is dus niet de oorzaak.

De screenshot van dezelfde stap laat de knoppen ook niet zien. Dat klopt: `textOpacity` is 0
zolang een rij de focus heeft (33.2), dus in die toestand is de rij onzichtbaar én onbereikbaar.
De foto toont het tegenovergestelde, zichtbare knoppen zonder artwork, en dat is de toestand
waarin de hero-CTA de ring heeft terwijl de pagina gescrold staat.

#### De gedeelde eigenaar, en wat er aan gehard is

`TvContentFeed` heeft drie paden die de ring aan de billboard geven. `_focusHeroFromFirstRow`
zet de scroll eerst terug op 0 en `tvos.home.hero-return` bewijst dat. `focusPrimary()` en de
terugval in `focusRestored()` riepen `focusPlay()` rechtstreeks aan, zonder die scroll. Een
`ListView` bouwt een hele `cacheExtent` door boven de viewport, `canRequestFocus` is waar voor
een gemonteerde knoop buiten beeld, en een kale `requestFocus()` lokt geen `ensureVisible` uit.
Wie langs `focusPrimary` binnenkomt op een gescrolde feed zet de ring dus op een billboard dat
721 px boven de vouw hangt, met de knoppenrij op y=19 onder de balk en zonder artwork erachter.
Dat is precies de foto.

De drie paden lopen nu door één `_focusHeroCta`, die de scroll herstelt voordat hij de knoop om
focus vraagt. De negatieve controle is `HERO4: DOWN out of the top navigation restores the
scroll too` in `tv_content_feed_test.dart`: rood op de oude implementatie, op
`expect(offset(tester), 0)`, groen erna, met de dertig tests van dat bestand groen.

#### De druk, en waarom hij langs de drie ingangen heen gaat

De vraag die openstond, welke druk `focusPrimary()` bereikt op een gescrolde Home, had een
verkeerde vorm. Er is er geen. De melding zegt "terug op Home na afspelen", en die weg raakt
`TvContentFeed` op geen enkel punt aan.

Gemeten in `tvos-home-hero-return-after-playback-1788618751845`. Twee keer omlaag zet de ring op
de eerste rij en de feed op 721 px. Select opent de detailpagina, Select speelt af, de clip is
een paar seconden lang en mpv keert vanzelf terug naar de detailpagina (focustrace hop 11 tot 13).
Dan één Menu, hop 14: `play_button` naar `tvHeroPlay` op `key:Escape`. In het frame erna staat
`discover.hero` op y=-721,3 en `discover.hero.play` op y=19,1 met de ring erop. De schermafdruk
`04-returned.png` is de foto van Michel, tot en met de twee pillen boven de navigatiebalk.

De keten. `onPlaybackReturned` ververst het item, Home herprojecteert, en de tegel waar de push
vandaan kwam bestaat niet meer. `_focusContent(restorePreviousFocus: true)` vraagt dan
`contentScope.requestFocus()` en die heeft niets onthouden, dus hij daalt af naar de eerste
focusbare afstammeling van de content. Sinds DEC-095 ligt de carrousel náást de lijst in plaats
van erin, dus hij is gemonteerd bij elke scrollstand en die eerste afstammeling is de
Afspelen-pil. De postframe-controle ziet daarna een gevulde `focusedChild` en slaat
`focusDefault` over, dus `focusActiveTabIfReady` en `focusPrimary` komen er nooit aan te pas.

Dat is ook waarom de knoppen op de foto zichtbaar zijn en in de eerdere meting niet: `textOpacity`
is 0 zolang een *rij* de focus heeft, en hier heeft de hero hem.

#### De fix

Het contract is niet "deze drie aanroepers scrollen eerst" maar **de billboard die de ring heeft
staat in beeld**. Dat hangt nu aan de carrousel die focus krijgt: één `Focus` zonder inhoud,
zonder eigen focus en zonder traversal om de herolaag, precies zoals de rijen er al een hebben.
`_focusHeroCta` deelt dezelfde `_revealHero`.

De negatieve controle is `HERO4: the billboard comes back into view whoever hands the CTA the ring`
in `tv_content_feed_test.dart`: de CTA-knoop rechtstreeks om focus vragen, zoals de scope het doet.
Rood met `offset(tester)` op 468,365, groen erna, met de 31 tests van dat bestand groen.

`tvos.home.hero-return-after-playback` is het bewijs uit de draaiende app en blijft staan. Zonder
de fix faalt hij op `insideViewport(discover.hero)`; met de fix staat de hero op y=0 en de pil op
y=740,5, bij dezelfde hop 14. `tvos.home.hero-return`, `tvos.home.hero-return-from-route`,
`tvos.home.full-bleed` en `tvos.home.walk-rails` blijven groen.

Op 5 september 2026 bevestigd op de Apple TV: de melding is weg. Daarmee is HERO4 `VERIFIED`, en
staat het bewijs op twee benen: de simulator toont de toestand en het herstel, het toestel toont
dat de weg die hem opleverde hem niet meer oplevert.

`tvos.home.hero-return-from-route` blijft de tegenhanger en houdt zijn eigen kop: zonder afspelen
bewaart de gepushte route de scroll, Menu zet de ring terug op de tegel waar hij vandaan kwam, en
UP brengt de billboard van een teruggekeerde feed weer in beeld. Het verschil tussen die twee
scenario's is precies waar de melding zat.

### GOLD1, de catalogusgoldens horen op de runner geregenereerd te worden

CAT5 verplaatste de catalogusacties naar een rail links van het raster, en negentien goldens
tekenen sindsdien een ander scherm. Ze zijn bewust niet bijgewerkt, want een golden die je op je
eigen machine schrijft is geen referentie voor CI.

Dat is gemeten en niet aangenomen. Op **ongewijzigde** code faalt in
`ghcr.io/cirruslabs/flutter:3.44.0` onder amd64-emulatie alle negentien, met ongeveer 45 procent
pixeldiff op een pagina vol coverart. De Flutter-versie is niet de verdachte: framework-revisie en
engine-hash in de container zijn identiek aan die lokaal. Het is de dithering van de verlopen onder
emulatie. Een native arm64-variant van dat image bestaat niet, het is single-arch.

Michel koos op 5 september de runner-route. `.github/workflows/goldens.yml` is een
`workflow_dispatch`-job met de twee catalogusbestanden als standaardinvoer; hij draait
`flutter test --update-goldens` op dezelfde `ubuntu-latest` als `ci.yml`, verzamelt wat er gewijzigd
of nieuw is onder `test/goldens/` en zet dat als artifact klaar. Hij commit niets. Een workflow die
zijn eigen goldens pusht maakt "de referentie past bij de code" waar door constructie, en een golden
bestaat er juist om door iemand bekeken te zijn.

`tv_catalog_films_header_focused.png` hoort bij een header die CAT5 heeft opgeheven en vervalt voor
`tv_catalog_films_rail_open.png`. Een verwijdering is geen wijziging die de job kan zien, dus die
gaat met de hand.

Terzijde, want het kostte een half uur: hangt `docker pull` eindeloos zonder foutmelding, dan is dat
de `osxkeychain` credential-helper. `DOCKER_CONFIG` naar een map met een lege `config.json` en hij
loopt door.

### ROW1, eigen rails op Home

Gevraagd door Michel op 5 september 2026, in zijn woorden: "het idee is dat je zelf rails aan kan
maken door middel van een filter toe te passen en dan de inhoud van de filtering in de rails weer
te geven", en dat moet "op de homescreen zelf kunnen doen maar wel op een mooie manier".

Twee eisen zitten daarin, en ze zijn allebei nieuw.

De eerste is de **bron van een rij**. Vandaag komt elke rij op Home uit een hub die de backend
levert; `homeRowId` is `serverId:identifier` van die hub en `HomeLayoutProvider` bewaart alleen
welke ervan verborgen zijn en in welke volgorde ze staan. Een rij die de gebruiker zelf definieert
heeft geen hub achter zich. Zijn bron is een opgeslagen filter, en de inhoud is wat de catalogus
op dat filter teruggeeft. Dat raakt het cataloguscontract, niet alleen de layout.

De tweede is **waar je het doet**. `HomeLayoutScreen` bestaat en kan verbergen en verslepen, maar
zit onder Instellingen. Michel wil het op Home zelf, en de volgorde daar ook.

**Wat vast blijft staan.** De hero en Verder kijken zijn geen onderdeel van de ordening: die
blijven op hun plek en zijn niet te verplaatsen of te verbergen. Michel op 5 september: "Verder
kijken en de hero kun je niet van positie wijzigen. Althans dat moet niet kunnen die blijven wel
statisch." Dat is precies de grens die `HomeLayoutProvider` vandaag al trekt, in zijn eigen
doccommentaar: hero en Continue Watching zijn vaste slivers in `DiscoverScreen` en komen niet in
de layout voor. Het ontwerp mag die grens dus niet oprekken, en een mockup die de hero laat
verslepen is fout.

Wat er al ligt en wat niet. `HomeLayoutProvider` (`lib/providers/home_layout_provider.dart`) heeft
de persistentie per profiel, `home_row_layout.dart` past hem toe en `TvContentFeed._rows` doet dat
op TV. Het filtermodel van de catalogus is er ook, en CAT5 geeft het een bedienbare vorm op TV. Wat
ontbreekt is de brug: een filter als bewaarbaar object met een naam, een rij die eruit gebouwd
wordt, en een manier om dat op Home te doen zonder de pagina in een beheerscherm te veranderen.

Tot 5 september was er **geen mockup**. Gecontroleerd op alle branches, op bestandsnaam en op de
inhoud van de HTML-bronnen, plus de niet-gecommitte mockupmap in `pleya-teleport/.unlazy/mockups`.
De tvOS-set liep van 09 tot en met 31 zonder gat; 29 en 30 gaan over de hero, niet over rijbeheer.

**Michels functieschets, 5 september.** Tijdens de ontwerpronde stuurde Michel een beeld met zes
schermen als richting, met twee aanwijzingen erbij, letterlijk: "Inspiratie bron let wel op dat
alle knoppen in tvos goed bereikbaar moeten zijn" en "Let op dat je niet vanuit mijn screenshot
oude styling meeneemt is puur de functie die ik bedoel". De functie uit dat beeld: een knop "Home
aanpassen" op Home zelf; een bewerkpaneel waarin de hero en Verder kijken bovenaan als vaste regels
staan en elke andere rij omhoog, omlaag, bewerken en verbergen krijgt, met "Nieuwe rail" onderaan;
en een stappenflow voor een nieuwe rij met naam en soort, filters, sortering en een voorbeeld met
teller. De eerdere opzet met drie concurrerende ingangen (contextmenu, de rij als handvat, een
ingeklapt overzicht) is daarmee vervallen: de richting ligt vast, de mockup tekent hem in de eigen
tokens van de set.

**Mockup 32, 5 september** (`docs/assets/tvos-unified/mockups-2026-09-04/32-eigen-rails-*.png`,
bron in `src/pages/32-eigen-rails-*.html`). Zeven standen, in de taal van 30 (DEC-095) en 28 D2
(DEC-093):

- **A1, de ingang, hertekend.** De eerste versie zette "Home aanpassen" rechts op de hoogte van
  de CTA-rij van de hero, bereikbaar met RIGHT vanaf Meer info. Michel, letterlijk: "de knop voor
  home aanpassen is niet goed genoeg gepositioneerd voor tvos want je kunt hier niet hoed komen op
  tvos en gaat wss ten kostem vam het kunnen bewegen door de hero rails". Klopt: RIGHT vanaf Meer
  info is in 7.3 de slidewissel, en een knop aan de rechterrand van de hero kost die beweging. De
  hero blijft dus zoals hij is, en de ingang staat nu in twee varianten die allebei zonder
  horizontaal mikken te bereiken zijn.
  - **A1a, de voetregel.** Eén regel over de volle breedte onder de laatste rij, in de gestippelde
    tegeltaal van "Nieuwe rij" in B: icoon, "Home aanpassen" en een subregel. Eén DOWN vanaf de
    laatste rij, geen horizontale beweging, altijd op dezelfde plek. Nadeel: wie acht rijen heeft
    moet er acht voorbij.
  - **A1b, het contextmenu.** Lang indrukken op elke kaart van Home geeft het menu van mockup 12
    een laatste regel "Home aanpassen", achter een scheidingslijn onder Bron wijzigen. Eén druk
    vanaf elke plek op Home, nul chrome op de pagina. Nadeel: niet zichtbaar tot je het menu kent.
  Mijn voorstel is allebei: A1a als de zichtbare plek, A1b als de korte weg. Ze sluiten elkaar niet
  uit en raken 7.3 geen van beide.
- **A2, rust.** Dieper op Home, de geometrie van 30 C, met een eigen rij "Nieuwe sci-fi" tussen de
  hubrijen. Alleen zijn naam als label; de eerste versie zette de filterkeuzes als tags naast het
  label en Michel schrapte die: "Actieve filters hoeven niet weergeven te worden boven de rails".
  De laatste kaart is een tegel "Alle 42, in Alle films" die de catalogus met ditzelfde filter
  opent, de tegelvorm die DEC-064 al toestaat. Wat A2 beslist: een eigen rij is in rust van een
  hubrij niet te onderscheiden; wat erin zit lees je in B of in de catalogus.
- **B, bewerkmodus.** Eén paneel over de gedimde Home, 1560 breed, met elke rij als regel: icoon,
  vier miniposters, naam met een subregel (bij een eigen rij het filter en de teller, bij een hub
  de servers), en rechts de acties. Uitgelicht en Verder kijken staan bovenaan met een slot en het
  woord "vast" en zijn niet focusbaar. Een hubrij krijgt omhoog, omlaag en Verbergen; een eigen rij
  omhoog, omlaag, Bewerken en Verwijderen; een verborgen rij staat gedimd met Tonen. Onderaan een
  gestippelde regel "Nieuwe rij". Bereikbaarheid: elke regel is een horizontale groep, UP en DOWN
  houden de kolom vast, vaste regels worden overgeslagen, een uitgeschakelde pijl (omhoog op de
  eerste beweegbare rij, omlaag op de laatste) blijft focusbaar zodat de kolom niet springt. Klaar
  staat rechtsboven en is UP vanaf de eerste regel; Menu doet hetzelfde. Verplaatsen gaat per stap
  met de pijlen, niet met optillen, want een gefocuste knop is op een afstandsbediening altijd te
  vinden en een "opgetilde" toestand niet. De sleepgreep uit de schets vervalt op TV.
- **C1, stap 1 van 3, naam en soort.** Chips Films en Series, daaronder het naamveld. De naam is
  optioneel: leeg volgt hij het filter ("Sciencefiction, niet bekeken") en verandert mee, zodat een
  rij zonder toetsenbord te maken is. Typen opent het systeemtoetsenbord van DEC-011.
- **C2, stap 2 van 3, filters.** De regels van 28 D2, Status, Genre, Jaar en Bronnen, met Sortering
  als vijfde regel in plaats van een eigen stap; de schets had er vier stappen van, dit zijn er
  drie omdat sortering in de catalogus ook al in hetzelfde paneel zit. Select opent de lijst van
  die regel, Menu sluit hem zonder wijziging, de tags eronder tonen de stand.
- **C3, stap 3 van 3, voorbeeld.** Naam, teller en filter op één regel, de eerste vijf posters en
  een "+37"-tegel. De rij landt direct onder Verder kijken; verplaatsen kan daarna in B. Rij
  toevoegen sluit het paneel op Home met de focus op de eerste kaart van de nieuwe rij.
- **C4, lege uitkomst.** De teller kleurt amber, het voorbeeld wordt een gestippelde plaatshouder
  met de reden en een suggestie ("Er zijn 6 musicals, maar geen uit 2024 die je nog niet gezien
  hebt"), Rij toevoegen is uitgeschakeld en de focus staat op Filters aanpassen, dat naar stap 2
  terugspringt. Onder de zes titels blijft toevoegen mogelijk; zo'n rij krijgt op Home "korte rij"
  naast het label. Een bewaarde rij die later leeg raakt verdwijnt in rust van Home en blijft in B
  staan met "leeg" als subregel.

Wat de bouw daarna raakt, buiten de layout: een bewaard filter als object met naam, soort, de
`UnifiedCatalogFilterSelection` en de `UnifiedCatalogSort`, per profiel naast de bestaande hide- en
orderlijst van `HomeLayoutProvider`; een rij-id voor zo'n object dat niet botst met
`serverId:identifier`; en een catalogusvraag die de eerste kaarten en een teller levert zonder de
volledige paging van hoofdstuk 12 te draaien. De teller volgt 10.7: pas exact als alle bronnen
uitgeput zijn, anders "42 geladen".

**Goedgekeurd door Michel op 5 september**, letterlijk: "Ja dit is top akkoord", op A1a en A1b
samen (de voetregel als zichtbare plek, het contextmenu als korte weg), A2, B en C1 tot en met C4
met drie stappen. Vastgelegd als [DEC-100](DECISIONS.md#dec-100); 9.1, 17.5 en 23 van de spec
zijn aangepast. De bouw is een eigen ronde en komt na CAT5, dat eerder in de tabel staat. De
negatieve controle staat in DEC-100: een widgettest op `TvContentFeed` die een eigen rij uit een
bewaard filter tussen de hubrijen eist, met de hero en Verder kijken op hun vaste plek, rood op de
huidige code.

### ROW1, de bouwronde

Twee commits, en de grens ertussen is waar de gebruiker iets kan zien: `040c939a`
laat een bewaarde rij bestaan en tekenen, `db1bc994` laat hem maken.

**De negatieve controle stond eerst.** `test/screens/tv/tv_home_custom_rows_test.dart`
is voor de code geschreven en was rood op de assertie, niet op een ontbrekend symbool:

```
Expected: ['Continue Watching', 'Nieuwe sci-fi', 'Recently Released', 'Recently Added']
  Actual: ['Continue Watching', 'Recently Released', 'Recently Added']
```

Het bewaarde filter zit als JSON in de voorkeuren van het profiel, precies zoals
een eerdere sessie het achtergelaten zou hebben, en de fake client paget een echte
library. Dat de rij het filter volgt is daarmee een uitspraak over de merge en niet
over de fixture. Na de bouw is er één regel aan dat bestand veranderd, de registratie
van de nieuwe provider; geen enkele assertie.

**Twee identiteiten per rij, en dat was bijna een bug.** In de ruimte van
`HomeLayoutProvider` heet een eigen rij `#custom:<id>`; een serverId kan niet met
`#` beginnen, dus botsen met `serverId:identifier` kan niet. In de ruimte van
`UnifiedMediaHub` heet dezelfde rij `hub:pleya:custom:<id>`, want daar hangen
focusgeheugen en herstel aan. De eerste versie liet de tweede naam ook voor de
layout gelden, via de hubId-fallback in `homeLayoutIdsOf`. Het paneel schreef dan
`hub:pleya:custom:<id>` in de volgorde terwijl `removeCustomRow` `#custom:<id>`
opruimde: een verbergactie die niet terug te draaien was, en een volgorde-entry die
zijn rij overleefde. De verplaats-test viel er meteen over. De rij noemt zijn
layout-id nu zelf via `contributingRowIds`.

**Recent uitgebracht is de layout in gegaan.** Dat is geen bijvangst maar wat
mockup 32 B tekent: hij krijgt daar dezelfde verplaats- en verbergknoppen als een
backendrij, en DEC-100 (4) zet precies twee rijen vast, Uitgelicht en Verder kijken.
Hij droeg zijn contributing row id al uit `projectHubs`, dus er is niets voor
uitgevonden; hij bereikte de layout alleen nooit omdat `_rows` hem ernaast zette.
Een gesynthetiseerde rij zonder contributors antwoordt sindsdien op zijn eigen
`hubId`, met een expliciete guard tegen de vacuous `every` die anders elke
gesynthetiseerde rij zou verbergen zodra er iets verborgen was.

**Wat er niet opnieuw gebouwd is.** De filterstap opent de panelen van de catalogus
zelf op de juiste sectie, en de sorteerstap het sorteerpaneel. Een tweede genrelijst
loopt bij de eerste gedeelde bugfix uit de pas. Het voorbeeld in stap 3 draait
dezelfde `HomeCustomRowLoader` met dezelfde limiet als de rij zelf, dus wat C3 tekent
is wat Home tekent, en de teller is die van 10.7: exact zodra elke bron uitgeput is,
anders "N geladen".

**Bestandsgrootte.** `tv_content_feed.dart` liep met de voetregel erbij naar 709
regels en staat weer op 626, met de rijsamenstelling in `tv_home_row_assembly.dart`.
Die is gedeeld met het paneel, zodat de feed en het paneel niet elk hun eigen
volgorde kunnen afleiden: een paneel dat een rij ergens neerzet waar de feed hem
vervolgens anders plaatst is precies het soort verschil dat niemand als bug meldt.
Het paneel en de wizard hebben hun tegels en onderdelen in eigen bestanden.

**Wat de schermafbeeldingen erbij deden.** Het paneel en de drie wizardstappen zijn
via het goldenharnas op de 1038x584-ondergrens gerenderd en bekeken. Drie dingen
kwamen daar pas uit. Het paneel was te smal: op de gedeelde panelbreedte werd de
tekstkolom van een rij tot "Nie..." en "Own ..." geknepen, dus de regel zei niet meer
welke rij het was. De soortkeuze in stap 1 stond in rode pillen, want de gekozen staat
van `FocusableFilterChip` is het merkaccent, en dat was het enige rode ding op een
monochrome pagina. En het naamveld erfde de Material-typografie, waardoor het op een
ander formaat stond dan het label erboven. Alle drie gerepareerd in `a721013d`.

**Wat open blijft.** ROW1b, de pointerkant. En de tegel "Alle N, in Alle films" als
laatste kaart van een eigen rij (DEC-100 (2)) staat er nog niet: dat is een extra
tegel áchter de laatste groep in `TvDiscoveryRail`, en die raakt `itemCount`, de
rechterrandstop, de positie in de semantics, de focusnodes en de goldens van een
widget die al door vijf testbestanden bewaakt wordt. Die staat als ROW1c in de tabel.

### RAIL1, het fase-6 railcontract is bij een verhuizing achtergebleven

Er zijn twee bestanden met bijna dezelfde naam, en dat is geen duplicaat.
`test/widgets/tv/tv_discovery_rail_test.dart` bewaakt geometrie en kolomgedrag en is meegegroeid
met LAND2, LAND3 en LAND4. `test/widgets/tv_discovery_rail_test.dart` is de andere helft, uit de
fase-6-commit `6e90fb4e`: de projectie, de focusidentiteit, activatie en toegankelijkheid. Die is
bij de verhuizing naar `tv/` blijven staan en sindsdien niet meer meegelopen. `ci_checks.sh`
draait geen `flutter test`, dus de pre-commit-gate zag vijf rode tests niet; dat is dezelfde blinde
vlek als bij HERO5.

Geen van de vijf wees een defect aan.

Twee toetsten een afspraak die LAND2 (`2371c62`) bewust heeft vervangen. Elke rail tekende zijn
eigen contextblok, ook de rails waar de afstandsbediening niet in stond, en op een gestapelde feed
gaf dat twee focuscontexten tegelijk op het scherm. Nu beschrijft alleen de rail met de focus zijn
tegel, en `alwaysDescribesCurrent` is de uitweg die TV Zoeken neemt, waar de caption de enige plek
is waar een resultaat zijn titel draagt. Herschreven naar wat er nu geldt, en met de helft erbij
die LAND2 niet raakte: de rail vergeet zijn tegel niet, hij beschrijft hem alleen niet meer.

Twee andere lazen "welke tegel is actief" af aan datzelfde blok. Ze waren niet stuk maar blind, en
geven de rail nu eerst de focus, zoals een verticale stap erheen dat ook doet.

De vijfde zocht met `find.bySemanticsLabel` naar de partial-tekst. Die staat er, maar de
`Semantics` om het wolkje heeft geen eigen container, dus de tekst voegt samen in de node van de
kop: `"Recently Added\nSome sources did not answer"`. Dat is precies wat hoofdstuk 41 vraagt, en
precies wat een exacte string niet vindt. De finder had geen faalstand, dus dat was geen test. De
assertie leest nu de node van de kop.

Sabotagecontrole: `alwaysDescribesCurrent: true` in de helper zet de twee focusgate-tests rood en
laat de rest groen. Veertien tests groen in dit bestand, 1031 in `test/widgets` en
`test/screens/tv` samen zonder falers.

### HERO5, HERO3 maakte een testbestand afhankelijk van de wandklok

Gesloten op `7ade2bc9`. `test/screens/discover_screen_tv_hero_test.dart` stond rood op `main`,
acht tests, en dat stond er al voordat er vandaag iets aan de feed veranderde. Gemeten door de
suite te draaien met en zonder de HERO4-wijziging: identiek rood.

DEC-097 gaf het venster van 90 dagen één eigenaar met een clock-seam voor tests
(`DataAggregationService.heroReleaseWindow`). Dit bestand gebruikte die seam niet, dus het las de
echte klok. De fixtures lopen van 2026-04-01 tot 2026-08-01, de aggregatie meldde
`Fetched 0 latest movies from all servers`, en de hero-assertions vielen om op een lege lijst.
Het venster schoof elke dag verder op, dus dit werd niet vanzelf beter.

`scripts/ci_checks.sh` draait geen `flutter test`, dus de pre-commit-gate merkte het niet. De
CI-workflow wel.

De harness pint de klok op 2026-06-01. De oudste fixture heeft daarmee een maand ruimte onder de
cutoff en de datums blijven zoals ze waren; het venster heeft alleen een ondergrens, dus een
fixture die verderop in het jaar uitkomt valt er niet buiten. Fixtures zónder datum vielen om
dezelfde reden uit de hero, en dat is geen bijwerking: DEC-097 zet een film zonder releasedatum er
per contract uit, dus "geen datum" is hier geen standpunt meer dat een fixture kan innemen.
`_movie` geeft ze er een.

Negatieve controle: dezelfde seam een jaar vooruit gezet reproduceert precies de acht rode tests,
teruggezet zijn alle negen groen.

### SRC1, twee Plex-servers en één rij bij Servers

Gemeld door Michel op 6 september 2026: twee Plex-servers gekoppeld, allebei online, en het
filterpaneel van Alle series toont er één onder Servers.

**Het paneel is uitgesloten, niet aangenomen.** `tv_catalog_filter_panel.dart` bouwt zijn
Servers-rijen uit `widget.libraries`, dat is `UnifiedCatalogProvider.eligibleLibraries`, en
`_servers` groepeert die op `library.serverId.value`. Vier tests in
`test/widgets/tv/tv_catalog_foundation_test.dart` draaien dat met twee servers (`nas`/NAS en
`attic`/Zolder) en staan groen. De categorie is bovendien onvoorwaardelijk: `_supports` geeft voor
`servers` en `libraries` altijd `true`, want die twee worden uitgevoerd door een cursor uit de
merge te laten en niet door een backend iets te vragen. Eén rij betekent dus één server in
`eligibleLibraries`, niet een paneel dat er één verbergt.

**Stroomopwaarts blijven drie paden over**, en de vraag is welke:

1. `PlexAuthService.fetchServers` levert de tweede server niet, de resource parseert niet.
2. `refreshTokensForProfile` verbindt hem niet binnen `perServerConnect` (6,5 s), waarna
   `ActiveProfileBinder` hem buiten `visibleServerIds` laat en `isServerVisible` hem uit
   `eligibleCatalogLibraries` filtert.
3. `getMediaLibrariesFromAllServers` haalt zijn bibliotheken niet op.

Pad 2 en 3 noemden hun verlies al bij naam in de log: `refreshTokensForProfile: failed to connect
<naam>` en `Failed neutral library fetch from <id>`, plus `ActiveProfileBinder: bound X/Y Plex
servers`. Pad 1 deed dat niet, en dat is het pad dat precies dit symptoom maakt.

**Wat er aan pad 1 mankeerde.** `fetchServers` verzamelt resources die niet parseren in
`invalidServers` en gooit alleen wanneer er géén enkele bruikbare overblijft. Eén onbruikbare naast
één bruikbare gaf dus stilletjes één server terug, zonder één logregel. `PlexServer.fromJson` eist
`name`, `clientIdentifier`, `accessToken` en minstens één parseerbare `connection`; ontbreekt er
één, dan verdwijnt de server zonder spoor en meldt elke laag eronder eerlijk de ene server die hij
kreeg.

Reproductie in `test/services/plex_auth_service_test.dart`: een resources-antwoord met twee servers
waarvan de tweede geen `accessToken` heeft levert `['srv-1']` op en een lege log. Dat was de
negatieve controle en hij was aantoonbaar rood. De fix logt per overgeslagen resource zijn naam,
zijn machine-id en de reden.

`_resourceLabel` bouwt die regel met de hand in plaats van de resource-map te dumpen, want die map
draagt `accessToken`. Een tweede test legt dat vast: de naam staat in de log, het token niet. Dat is
dezelfde regel die `test/services/preferences/log_safety_test.dart` elders bewaakt, en hij geldt
hier extra omdat deze regel bedoeld is om in een bugmelding geplakt te worden.

**Bevestigd met een device-log.** Michel stuurde een screenshot van de logviewer met upload-ID
`12e1y`. Die is op te halen bij de relay (`https://ice.pleya.app/logs/12e1y`) en bevat de complete
opstartsequentie van zijn Apple TV, twee Plex-servers gekoppeld aan Plex Home.

`GET https://clients.plex.tv/api/v2/resources … → 200 (324ms)` met `{servers: 2}` sluit pad 1 uit:
beide servers kwamen terug, geen resource viel stil. Geen `Failed neutral library fetch`-regel sluit
pad 3 uit. Wat er wél staat:

```
[15:10:51.907] ActiveProfileBinder: rebinding for Michel (…)
[15:10:51.957] ActiveProfileBinder: connecting Michel from cached server metadata while resources refresh {servers: 2}
[15:10:52.281] GET https://clients.plex.tv/api/v2/resources … → 200 (324ms)
[15:10:52.281] ActiveProfileBinder: resource refresh completed for Michel {servers: 2}
…zestien connectiekandidaten voor de tweede server, waaronder meerdere echte HTTP 401…
[15:10:54.271] ERROR No working Plex server connection endpoints after race {candidateCount: 16}
[15:10:54.272] ERROR refreshTokensForProfile: failed to connect G-Plexflix
[15:10:54.273] ActiveProfileBinder: bound 1/2 Plex servers for Michel
…
[15:10:54.369] ERROR refreshTokensForProfile: failed to connect G-Plexflix
              Exception: No working connection found (G-Plexflix was unreachable moments ago)
```

Dat is pad 2, en de tweede regel is de eigenlijke oorzaak. Er zijn twee bindpogingen voor de tweede
server (`G-Plexflix`, een gedeelde/geleende server, niet Michels eigen NAS): de eerste, optimistische
poging met het gecachte token uit `_bindOptimisticallyFromCache`, en een tweede vanuit
`_reconcileWhenFetchLands` nádat de live `/resources`-fetch al was geland, met het verse en voor déze
server correct gescoopte token. De eerste poging faalde echt: van de zestien kandidaten kwamen er
meerdere terug met een letterlijke HTTP 401 (de server antwoordde, het token werd afgewezen), niet
enkel timeouts. Die faalpoging zette `_unreachableSince[G-Plexflix]`. De tweede poging, met het token
dat wél had gewerkt, kwam er niet eens aan toe: `_createClientForServer` zag de recente faalregistratie
en gooide meteen `"was unreachable moments ago"`, zonder een enkele kandidaat te proberen.

`_unreachableSince` bestaat om een stortvloed van aanroepers die tot dezelfde conclusie zouden komen
met dezelfde data te bundelen (eigen doc comment: "Remembering the verdict briefly makes the second
and third caller fail instantly instead"). De reconcile-aanroep is geen zo'n aanroeper: hij draagt
data die de optimistische poging nooit had, namelijk het net opgehaalde, per-server token. De memory
blokkeerde hier niet een zinloze herhaling maar de ene poging die de zaak had kunnen redden, en dat is
precies het gat tussen wat `_reconcileWhenFetchLands`'s eigen doc comment belooft ("retry servers the
optimistic pass left offline") en wat er gebeurde.

**De fix.** `refreshTokensForProfile` en `_createClientForServer` krijgen een
`retryRecentFailures`-parameter, standaard `false`. Alleen de reconcile-aanroep in
`active_profile_binder.dart` zet hem op `true`: dat is de enige aanroeper die per definitie andere
data draagt dan de poging die de memory zette. Elke andere aanroeper, inclusief de optimistische pass
zelf, blijft de memory eerbiedigen.

Reproductie en negatieve controle in `test/profiles/active_profile_binder_test.dart`: de bestaande
test "optimistic cached bind settles without waiting for the resource refresh, then reconciles" kreeg
twee assertions op een nieuwe `retryRecentFailuresCalls`-lijst op de test-fake. Zonder de fix leverde
dat `[false, false]` op (rood); met de fix `[false, true]`. `_createClientForServer` zelf is niet apart
unit-testbaar (`multi_server_manager_test.dart` documenteert al dat die methode een echte netwerkrace
draait en geen fake `PlexClient`-fabriek heeft), dus de dekking zit op het niveau waar de codebase dat
al voor deze klasse bugs doet: de binder die de parameter doorgeeft.

**Codereview vond de fix onvolledig.** `/code-review` en twee onafhankelijke verificatie-subagents
wezen alle drie op dezelfde twee resterende plekken: `_connectFromServers`, de gedeelde helper achter
`refreshTokensForProfile`, kreeg de parameter niet. Twee van zijn aanroepers zijn structureel gelijk
aan de reconcile-aanroep, maar zaten niet in de eerste versie.

`_bindPlexHome` heeft een synchrone fallback: als de optimistische pass voor élke server faalt (niet
alleen één, zoals in het device-log), wordt `_reconcileWhenFetchLands` nooit ingepland, want die
scheduling zit achter `_bindOptimisticallyFromCache`'s eigen `if (result.visibleServerIds.isEmpty)
return result;`. De binder valt dan direct terug op de al lopende `/resources`-fetch en verbindt
daarmee, maar via `_connectFromServers` zonder de bypass. Bij een volledig verlopen gecached token had
dit een hele profielbinding op nul servers kunnen laten eindigen, terwijl de net opgehaalde data
bewees dat ze bereikbaar waren. `_bindLocalPlexConnection` (gedeelde/geleende Plex-connecties, niet
alleen Plex Home) heeft precies dezelfde vorm op zijn eigen fallback.

Beide zijn nu ook gedekt: `_connectFromServers` geeft `retryRecentFailures` door, en de twee fallbacks
zetten hem op `true`, met dezelfde motivatie als de reconcile-aanroep. De twee andere aanroepers van
`_connectFromServers` (`_connectPlexServers`'s eerste poging, `_connectFromCachedServers`'s
laatste-redmiddel op stale data) blijven bewust op de standaardwaarde `false`: geen van beide draagt
data die een eerdere poging in dezelfde bindpas nog niet had.

Twee nieuwe tests, elk eerst rood gemaakt door de bijbehorende aanroep terug te zetten naar de
standaardwaarde en weer groen na herstel: één voor `_bindPlexHome`'s fallback (een gecached token dat
voor élke server faalt, gevolgd door een geslaagde live fetch), één voor `_bindLocalPlexConnection`
via een geleende `PlexAccountConnection` aan een lokaal profiel.

Bewijs: `flutter analyze` zonder errors of warnings, `active_profile_binder_test.dart` op 19 tests
groen, en de volledige suite op 6341 geslaagd, 0 rood, 6 overgeslagen (twee meer dan de 6339 van vóór
deze twee tests, verder ongewijzigd).

**Nog niet op hardware bevestigd dat dit Michels servers daadwerkelijk laat verschijnen.** De fix
verhelpt het pad dat het device-log aanwijst, maar de volgende TV-build moet tonen dat `G-Plexflix` nu
wél in de Servers-categorie staat. Zet SRC1 pas op VERIFIED na die run.

### PLR2, het paneel per functie

Gemeld door Michel op 5 september 2026: "ik heb het idee dat de geluidsinstellingen niet goed
werken", met de vraag het hele veeg-omlaag-menu per functie na te kijken en te zeggen wat er
ontbreekt. De audit staat hieronder; de bevindingen die werk opleveren hebben elk een eigen
regel (PLR3, AUD1, AUD2, PNL2), zodat ze los een eindstatus krijgen.

**Drie menu's naast elkaar.** Op de Apple TV bestaan het veeg-omlaag-paneel (`TvInfoPanel`),
de 10-foot `VideoSettingsSheet` achter het tandwiel en de `TrackSheet` achter de sporenknop
tegelijk. Ze overlappen voor de helft en spreken elkaar tegen: de sheet heeft zoom, versie en
kwaliteit, slaaptimer, HDR, autoplay en shaders die het paneel mist, plus een apparaatkiezer die
op tvOS niets kan kiezen; het paneel heeft Info, sfeerintensiteit in vier standen en de
rendering-badge die de sheet mist. Het paneel is bovendien alleen met een veeg te openen
(`key_events.dart:315-322`), en de simulator heeft geen aanraakvlak. Dat verklaart waarom er
nul tests op staan en waarom Pleya Verify het niet kan adresseren.

**Wat de audio-rijen doen.** Sporen kiezen werkt (`selectAudioTrack`, coordinator volgt de
codec). Uitvoermodus en prioriteit werken (`audioOutputMode`, `audioPriority`,
`AudioOutputCoordinator.onModeChanged`); Auto bitstreamt op tvOS alleen onder "Original Dolby"
op een digitale poort met ac3/eac3, en een mislukte bitstream valt terug op PCM met een
snackbar. Volume gelijkmaken en harde geluiden dempen werken via de arbiter en zijn inert
tijdens een bitstream (DEC-013). De twee rijen die niet doen wat ze beloven zijn "Maximum
volume" (AUD1) en de synchronisatie-subweergave (AUD2).

**Besluiten van Michel, 5 september.** Eén menu op TV: het paneel; tandwiel en sporenknop worden
ingangen op een tabblad. Een werkende volumeboost in plaats van het plafond. Mockup 19 opnieuw,
want hij bevat een Wachtrij-pill en een "Onthouden voor deze titel"-schakelaar die met PB-9 en
DEC-096 botsen, geeft de geluidsuitvoer geen plek, kopieert de globale stijlpagina half en tekent
maar één stand. De video speelt door. Vier tabs: Info · Video · Geluid · Ondertitels, met Weergave
en Afspelen als secties van Video en Sporen en Uitvoer als secties van Geluid.

**Mockup 33** (`docs/assets/tvos-unified/src/pages/33-speler-paneel-*.html`, renders in
`docs/assets/tvos-unified/mockups-2026-09-05/`, hier geschoten met een plaatshouder als
backdrop omdat `art/` niet in git staat; de definitieve schoten komen van de Mac). Negen
standen: A Info, B Video, C Geluid, D Ondertitels, E synchronisatie-subweergave, F
hoofdstukken-subweergave, G slaaptimer-subweergave, H Geluid tijdens een Dolby-bitstream, I de
spelerbalk met tandwiel en sporenknop als ingangen. Goedkeuring per stand, daarna DEC-101 en de
bouwronde in de volgorde van het plan (negatieve controle eerst, kleine commits, SHA in de tabel).

**Goedgekeurd door Michel op 5 september 2026**, letterlijk "Akkoord", na drie correctierondes op
de negen standen: het onzichtbare vinkje (tv.css kleurt elk rij-icoon ink-2, ook op de witte
schijf), de stapchevrons in twee maten, de focusring die achter de volgende rij verdween (rijen op
8 px terwijl de ring 12 px uitsteekt), en het oordeel "het voelt nog cheap", waarna de vlakke band
met elf losse dozen een zwevende glaskaart met gegroepeerde rijen en een witte focusvulling werd.
Vastgelegd als DEC-101. De bouw volgt de volgorde van het plan; per stap een regel met SHA.

**Bouwronde, 5 september.** In één reeks, omdat Flutter in deze container ontbreekt en de
negatieve controles dus pas op de Mac rood-dan-groen te tonen zijn. Wat er staat:
`TvPanelRow` met `kind` (action, choice, value, toggle), `subtitle`, `onStepLeft/Right`,
`canRequestFocus` en automation-ids, en `TvPanelGroup`, `TvPanelColumns`, `TvPanelStaticRow`;
het paneel als zwevende kaart met `BackdropFilter` (`kTvPanelBlurSigma`, op hardware te wegen),
pills op `FocusableWrapper` met Select, een subweergave-enum met `TvSyncSubView` (geen slider),
`TvChapterSubView`, `TvSleepTimerSubView` (op de service, niet op `SleepTimerContent`, die
zonder overlay-scope de spelerroute popt), `TvShaderSubView` en `VersionQualityPicker` met
`onDismiss`; Video met Weergave en Afspelen, Geluid met Sporen en Uitvoer, Ondertitels met Sporen
en Stijl en timing; `TvInfoPanelRequest` van tandwiel, sporenknop en hoofdstukkenknop naar het
paneel; `onSetBoxFitMode` door `TrackControlsState`, `VideoControls` en `VideoFilterManager`;
`forcedTrackSuffix`; de sheet-gate op `isDesktopOS()`; de i18n-sleutels in en en nl met de
gegenereerde klassen met de hand in het slang-formaat bijgewerkt, zodat `dart run slang` op de
Mac een lege diff hoort te geven.

**Reviewronde, `de2e554`.** Vijf bevindingen, alle vijf terecht, alle vijf gesloten. Een
subweergave zonder eigen landingsnode (versie en kwaliteit komt uit de gedeelde picker) opende
met de ring nergens; de fallback loopt hem nu naar de eerste focusbare die er werkelijk staat.
LEFT en RIGHT klemmen sindsdien waar Select cyclet: de ontbrekende callback op de rand valt door
naar de traversal, zodat een kolom met alleen waarderijen te verlaten is, en dat is precies het
Video-tabblad op een Android TV; het lost tegelijk op dat RIGHT op +200% terugsprong naar Uit.
Een hoofdstuksprong meldt zich weer via `onSeekCompleted`, de enige weg naar
`WatchTogetherProvider.onLocalSeek`. De terugpijl van een subweergave was een kale `IconButton`
zonder eigen focus (DEC-053) en is nu `TvPanelBackButton`. Twee tests erbij: het klemmen aan de
randen, en de gemelde hoofdstuksprong.

**Testronde, 6 september.** De reeks is alsnog gedraaid, niet op de Mac maar in de container:
de Flutter-SDK uit `.fvmrc` (3.44.0) is er los naast gezet, dus `check_flutter_version.sh` klaagt
niet en `dart format` geeft dezelfde uitvoer als CI. Wat er groen staat: `flutter analyze` zonder
errors of warnings (48 infos), `dart format` over lib en test zonder wijziging, unused code en
unused files leeg, en de volledige suite op 6260 geslaagd, 6 overgeslagen, 66 rood. Die 66 zijn de
nullijn van main, geen ervan raakt dit werk: 51 goldens en 15 uit
`discover_hero_activation_test.dart`.

Drie dingen kwamen eruit die er in de bouw- en de reviewronde niet uit kwamen.

De eerste is een echt defect, en het staat als PNL3 in de tabel: Select op een pill die al actief
is verplaatste de focus niet. Alle drie de focusverplaatsingen van het paneel hingen aan
`addPostFrameCallback`, en die plant een callback voor de volgende frame zonder er een aan te
vragen. Op dat ene pad zet `_selectTab` niets dirty, dus er kwam geen frame en de callback bleef
staan. In de test valt dat hard op, want `WidgetTester.pump` tekent alleen als er een frame
gepland is; achter een spelend beeld tekent tvOS toch en zie je het niet, achter een gepauzeerd
beeld wel. `_afterNextFrame` vraagt de frame nu expliciet aan.

De tweede was de test zelf. De snelheidstest drukte twee keer RIGHT zonder frame ertussen, en de
rij leest zijn waarde uit `player.streams.rate`: beide drukken stapten dus vanaf dezelfde oude
waarde. Op een afstandsbediening zit er altijd een frame tussen; in de test moet die er staan.

De derde is de gedeelde eigenaar uit PLR3. De sheet-gate ging van `isDesktop(context)` naar
`isDesktopOS()`, en daarmee toont de sheet op een Linux-testhost wel degelijk de
audio-apparaatrij, met "Auto" als waarde. `video_settings_sheet_test.dart` zocht "Auto" in de hele
boom en vond er twee. De assertie leest hem nu uit de rij zelf, want de test gaat over de
uitvoermodus en niet over hoe vaak het woord voorkomt.

**Wat CI hierna nog rood houdt, en waarom het niet van deze branch is.** Code Analysis breekt op
`Verify generated files committed`, en Unit Tests op dezelfde 66. Beide zijn op main al maanden
rood en zijn hier gereproduceerd: `build_runner` schrijft gegenereerde code op 80 kolommen terwijl
de gecommitte bestanden op 120 staan, dus `git diff --exit-code lib/` slaat aan zonder dat er iets
verouderd is. PR #1 heeft dat als CI1 al opgelost (`e76e3f06`, plus `99442f0d`, `bd22a756` en
`213c6e82` voor de hero- en goldensuites) en staat daar groen. Die reeks raakt 121 bestanden en
hoort niet in deze PR overgezet te worden; zodra CI1 op main staat, gaat deze branch met een merge
mee.

**Wat hier niet kon draaien.** Het Verify-scenario `tvos.player.panel.yaml` vraagt een macOS- of
tvOS-simulatorbuild, dus dat bewijs ontbreekt nog, net als `/pleya-tvbuild`. Elke regel hierboven
gaat pas van "testrun groen" naar `VERIFIED` als die twee er zijn.

**Hardware only.** De veeg-opening, de bitstream-stand (H) en de hoorbaarheid van de boost en
de synchronisatiestap zijn alleen op het toestel te toetsen; STATUS.md meldt dat er nog geen
Apple TV-audiolog is.

### PLR4, PLR5 en PLR6, het spelerpaneel op hardware

Drie meldingen van Michel op 6 september 2026, alle drie op een fysieke Apple TV
met build 264, alle drie over hetzelfde oppervlak: het spelerpaneel van mockup 33.

**PLR4, de kap is krapper dan de inhoud.** `tv_info_panel.dart:297` begrenst de
kaart op `min(schermhoogte * 0,56, 620)` en `TvPanelColumns` geeft elke kolom een
eigen `SingleChildScrollView`. Past de inhoud niet, dan verdwijnt de rest zonder
melding onder de rand; er is geen affordance die zegt dat er meer staat.

Gemeten in de widgettest op 1920x1080, met de testfonts: een rij is 63 logische
pixels, de kop plus groepsmarge 48, en de kaart draagt buiten de kolommen om nog
129 (pilbalk, tussenruimte, voetregel, padding). Acht rijen leveren een kaart van
492 tegen een kap van 605. Het volledige stel dat een Apple TV toont is groter dan
wat de testopstelling opbouwt: links Beeldverhouding, Zoom, HDR, Shaders en
Ambient, rechts Afspeelsnelheid, Hoofdstukken, Versie en kwaliteit, Slaaptimer,
Automatisch volgende afspelen en Prestatie-overlay. Dat is 6 x 63 + 48 = 426 voor
de hoogste kolom, plus 129, dus 555 tegen 605. Op papier past het met vijftig
pixels over; op het toestel is de foto duidelijk en past het niet.

Dat verschil van vijftig pixels is dus de hele marge, en de testopstelling is
precies het instrument dat hem niet betrouwbaar meet: de echte lettertype-metrics
van tvOS ontbreken erin. Dezelfde discrepantie staat bij CAT8 beschreven. De
conclusie die wel hard is: de kap is een willekeurige fractie die geen relatie
heeft met wat het tabblad nodig heeft, en hij zit zo dicht op de inhoud dat één
extra rij hem breekt. De richting van de reparatie is de kap afleiden van de
beschikbare title-safe hoogte in plaats van van 0,56, en het scrollen te laten
staan als vangnet voor het pathologische geval.

**Gerepareerd in `5e07551f`.** De kap is nu de beschikbare hoogte binnen de
title-safe band, gemeten met een `LayoutBuilder` binnen de `SafeArea` in plaats
van met een fractie van `MediaQuery.sizeOf`. De kaart dimensioneert zichzelf nog
steeds op zijn inhoud, dus bij 1080 met deze rijen is er niets aan te zien: hij
blijft 555 hoog. Wat verandert is de ruimte erboven, van vijftig pixels naar
ruim vierhonderd, en die is er voor de rijen die de echte tvOS-metrics groter
maken dan de testfonts.

De negatieve controle bouwt het volledige stel van elf rijen op, inclusief de
vier die de oude testopstelling niet maakte omdat de nepspeler geen mpv claimde
en de staat geen shaderservice, sfeerverlichting, hoofdstukken of tweede versie
had. **Bij 1080p was die test ook op de oude code groen**, precies zoals de
meting hierboven voorspelt, dus daar is hij geen negatieve controle en steunt het
bewijs op de foto. Rood was hij bij de twee kleinere hoogtes waar de kap wél
bijt: op 900p verborg de rechterkolom 51 pixels, op 720p verborgen beide kolommen
89 en 152. Die drie hoogtes staan nu alle drie in de test, zodat de eigenschap
zelf vastligt en niet alleen de ene resolutie waarop hij toevallig al klopte.

**PLR5, LEFT en RIGHT horen bij de waarde en niet bij de kolom.** Een waarderij
verstelt op LEFT en RIGHT. `clampedSteps` geeft aan de uiteinden `null` terug,
zodat de ring de kolom kan verlaten (dat is PNL2 en het staat in
`side_navigation_rail`-stijl vastgelegd in de testsuite), maar dat betekent ook:
staat de waarde in het midden, dan kun je de kolom niet uit zonder hem te
veranderen. Vanaf Beeldverhouding is de rechterkolom onbereikbaar tenzij je de
beeldverhouding aanpast.

Michels voorstel is een rij die je eerst aanklikt: buiten die stand navigeren
LEFT en RIGHT tussen de kolommen, binnen die stand verstellen ze de waarde. Dat
is een ander interactiemodel dan het goedgekeurde paneel van DEC-101, waarvan de
voetregel letterlijk "Links en rechts stappen een waarde" belooft, en het raakt
elke waarderij van het paneel plus de voetregeltekst. Het gaat daarom als
DEC-voorstel en niet als stille correctie.

**Goedgekeurd als [DEC-107](DECISIONS.md#dec-107) en gebouwd in `08814bac`.**
Select klikt een waarderij aan en laat hem weer los, LEFT en RIGHT bereiken de
rij alleen in die stand, en Menu pelt één laag per druk: eerst de rij, dan een
open subweergave, dan het paneel. De pijlen naast de waarde staan er alleen als
de rij aanstaat, want een stand die je niet ziet is de val van DEC-053.

De negatieve controle gebruikt Zoom en niet Beeldverhouding, om een reden die
het noteren waard is: het tabblad geeft de beeldverhoudingsrij alleen stappen
wanneer `onSetBoxFitMode` er is, en de testopstelling zette alleen
`onCycleBoxFitMode`, dus die rij stapte in de test helemaal niet. Zoom staat op
100%, midden in `kTvPanelZoomPresets`, en is daarmee wél de rij uit de melding.
Met de oude bediening stapte RIGHT hem naar 110% en bleef de ring staan; nu
bereikt hij de andere kolom en verandert er niets.

Wat hier tegen elkaar afweegt: dit maakt de weg naar buiten één druk langer op
precies het oppervlak dat in PLR6 op hardware niet te verlaten was. De test
`Select enters a value row, Menu leaves it and keeps the panel open` bewaakt
daarom expliciet dat het paneel de eerste Menu overleeft en de tweede hem sluit.
Op hardware is dat nog niet nagelopen; dat hoort bij dezelfde devicerun als
PLR6.

**PLR6, het paneel is niet te verlaten.** Michel kwam er niet uit zonder de app
af te sluiten. De Dart-kant is niet de oorzaak, en dat is nu vastgelegd in plaats
van aangenomen: `Menu closes the panel from a focused row (PLR6 contract)` zet de
focus op een rij en stuurt één Escape-KeyDown, en het paneel sluit. Dat is precies
het pad dat `handleBackKeyAction` op Apple TV neemt, want daar draait `onBack` op
de KeyDown en wordt de KeyUp zwijgend geslikt. De spelerlaag zelf staat bewust
opzij zolang het paneel staat (`key_events.dart:92` en `:206`), dus als het paneel
de toets niet krijgt, vangt niemand hem op. Dat maakt de vastloper ook compleet:
geen enkele laag antwoordt nog op Menu.

Het log dat Michel meestuurde (`5pyur`) helpt hier niet, en het is het vermelden
waard waarom niet: de ringbuffer leeft per run, en dit log begint bij het opstarten
ná het geforceerd afsluiten. Wat erin staat over Menu gaat over het diagnosescherm,
niet over de speler. Voor de oorzaak is een log nodig uit de run waarin het
misgaat, en dat is precies de run die de gebruiker niet kan verlaten om te
uploaden. Volgende stap is daarom een build op het toestel met Xcode eraan, zodat
de console meeleest terwijl het paneel klemt.

**Wat de ronde van 6 september hieraan toevoegde.** De engine-fork is gelezen
(`scripts/tvos_engine_source.sh`, v3.44.0+3) om de ene verklaring te toetsen die
bij het logbeeld past: `sendSynthesizedKeyEventOfType:` houdt in
`synthesizedPressedKeys` bij welke toetsen de engine ingedrukt denkt, en laat een
Down vallen wanneer de toets er al in staat, terwijl hij een Up wél doorlaat en de
toets er dan uit haalt. Blijft escape in die verzameling achter, dan zie je precies
wat het log toont: een KeyUp in het Flutter-toetsenpad zonder KeyDown ervoor.

Alleen: dat verklaart één verloren druk, geen vastloper. Diezelfde Up ruimt de
toets op, dus de eerstvolgende druk komt weer aan. **De engine-verklaring
voorspelt "Menu werkt bij de tweede druk", en Michel meldt dat Menu helemaal niet
werkt.** Wie de devicerun doet moet dat als eerste toetsen: werkt Menu bij een
tweede of derde druk, dan is dit het spoor; blijft hij dood, dan is de oorzaak
ergens anders en is deze bookkeeping hooguit een bijverschijnsel. De passthrough
is in de speler niet de verdachte: `shouldPassTvosMenuToSystem` eist
`isSidebarFocused`, en dat is achter de speler nooit waar.

De Dart-kant is verder afgetast dan de ene contracttest en blijft overeind. Met de
focus op de pill sluit Escape het paneel; met `unfocus()` valt de focus terug op
`TvInfoPanelScope` zelf en sluit Escape nog steeds, want de `FocusScope` van het
paneel zit dan zelf in het toetsenpad. Er is dus geen focusstand gevonden waarin
het paneel de toets misloopt.

Eén tweede-orde bevinding staat hier apart, omdat hij een gok zou zijn als hij als
oorzaak werd gepresenteerd. `_close()` in `tv_info_panel.dart` zet `_closing` op
waar en roept `widget.onClose()` pas aan vanuit de voltooiing van een omgekeerde
animatie van 260 ms. Voltooit die animatie ooit niet, dan blijft `_closing` staan
en doet elke volgende Menu-druk niets, terwijl beide spelerlagen bewust opzij
staan zolang het paneel er is (`key_events.dart:92` en `:206`). Eén verloren
sluiting wordt daarmee een permanente. Dat is een robuustheidsgebrek, geen bewezen
oorzaak, en het wordt niet gerepareerd voordat de devicerun heeft laten zien of de
Down überhaupt aankomt.

**Wat er niet bewezen is.** Er is geen reproductie: het paneel opent op Apple TV
alleen via een veeg over het aanraakvlak, en de simulator heeft dat vlak niet. Er
is geen log uit de run waarin het misgaat. De regel blijft daarom `HARDWARE ONLY`
en gaat niet naar `FIXED` op een redenering. **Michel: plan een devicerun met Xcode
eraan**, open het paneel met een veeg, druk Menu twee of drie keer, en laat de
console meelezen; de meetregels staan in `docs/tvos-remote-press-pipeline.md`.

### CAT9, de chips op Alle films deden niets op iOS

Michel op 6 september, build 266: "Filters ios werken helemaal niet bij alle films, kan er niet op
drukken." Dit is de eerste iOS-bevinding in dit document; de lijst is tot nu toe tvOS, maar de
staande regel is dat een melding die werk oplevert hier landt en niet ergens anders.

**Wat er misging.** `MobileLandingScreen._TitleRow` opent het catalogusscherm met
`Navigator.of(context).push`. Die `Navigator` is de profielnavigator, en die zit *boven*
`MainScreen`. `MainScreen.build` is precies de plek die de `OverlaySheetHost` plaatst. De gepushte
`MobileCatalogScreen` is daarmee een broer van het scherm dat de host bezit, nooit een afstammeling,
en `OverlaySheetController.of` kijkt alleen omhoog. In een debugbuild valt dat op als
`No OverlaySheetHost found in context`; in een releasebuild is die assertie weggecompileerd, gooit
`scope!` een null-check die het framework opvangt, en gebeurt er bij een tik dus letterlijk niets.
Alle drie de chips zijn geraakt, niet alleen Filters.

**Waarom de bestaande tests dit niet zagen.** `pumpCatalog` in
`test/screens/home/mobile_catalog_screen_test.dart` zette de host er direct omheen en pushte niets.
Dat is een geldige montage voor het scherm zelf, maar niet de montage die de app gebruikt, en het
verschil tussen die twee is precies de bug. `pumpPushedCatalog` doet het nu zoals de app het doet.

**De fix, en de val erin.** Het scherm draagt zijn eigen host, zoals elk ander gepusht scherm hier
(hubdetail, mediadetail, het Seerr-detail). De eerste poging was niet genoeg en dat is het opmerken
waard: `_openFilters` en `_openSort` gebruikten de context van de `State`, en de host wordt in
`build` geplaatst, dus die host is een *afstammeling* van die context en `of` vindt hem nog steeds
niet. De sheetopeners krijgen daarom een context uit een `Builder` ónder de host. Zonder die tweede
stap opende er nog steeds niets, en de testopstelling met een buitenste host maskeerde dat door de
sheet achter de route te tekenen.

**Reikwijdte.** `MobileCatalogScreen` is het enige scherm uit de mobiele fasen 1 tot en met 3 dat op
deze manier gepusht wordt (`MaterialPageRoute` komt in `lib/screens/home/` precies één keer voor);
de andere mobiele schermen zijn tabinhoud onder `MainScreen` en zitten dus wél onder de host.

**Derde val, en die is zelf veroorzaakt.** De host installeert een `PopScope`, en de eerste versie
van de `onSystemBack` riep `Navigator.maybePop()` aan. Die callback *is* juist wat de `PopScope`
draait wanneer hij de pop weigerde, dus opnieuw om een pop vragen komt regelrecht terug op dezelfde
plek: een lus die de route laat hangen. `mobile_landing_screen_test` liep daarop vast op
`the pushed catalogue's search action pops and reaches the landing's own search target`, en dat is
ook precies hoe het gevonden is: de volledige suite bleef op die ene test staan. Het zusterscherm
gebruikt `Navigator.pop`, en dat is de reden.

### CAT17: de zijbalk blijft open en onbereikbaar na een sorteerkeuze

Gemeld op 7 september 2026 op een Apple TV met build 268, met logboek `h43qp`.
Kies je in Alle films of Alle series een sortering, dan sluit het sorteerpaneel wel,
maar blijft de rail links staan zonder dat je er nog in komt. Menu doet niets, LINKS
doet niets. Pas na het scherm verlaten en opnieuw openen is de rail weer te bedienen,
want dan zet `_tryEntryFocus` de ring op Bronnen.

**Wat het log laat zien.** Twee keer hetzelfde patroon, om 17:19:10 en om 17:19:27.
Select op een sorteerrij, meteen daarna de fetch met de nieuwe sortering, en daarna
staat de focus op een knooppunt met `onNav(up=true,down=false,left=true,right=false)`
en `onBack=false`. Dat is geen railrij: die dragen alle vier een `onBack`. Het is een
gridkaart in kolom 0 buiten de eerste rij, want `_buildCell` bindt UP alleen op de
eerste rij, LEFT alleen in kolom 0, en de catalogus gaf de grid geen `onBack` mee.
Escape kwam wel degelijk in Dart aan (`menuPassthroughEnabled` stond de hele sessie op
`false`) en werd door niemand opgepakt: `reason=fall-through`. De vier LINKS-drukken
erna melden `handled reason=onNavigateLeft` terwijl er niets verandert, en dat is de
tweede helft van de val: `onExitLeft` is `_openRail`, en die keerde op zijn eigen
`if (_railExpanded) return;` meteen terug.

**Root cause.** `TvCatalogCardGridState._reconcileNodes`. `_focusedId` is een
herinnering aan de laatst gefocuste kaart: gezaaid uit `initialFocusedId` voordat er
iets gefocust is, gezet bij elke focuswinst, en nooit gewist wanneer de focus de grid
verlaat. `_reconcileNodes` las hem als een claim op de focus. Een sorteerwissel
herpagineert de catalogus, dus de onthouden kaart staat niet meer op pagina één, en
dan vroeg de grid post-frame de focus op voor de naaste overlevende. Dat gebeurde één
frame ná `_withLauncherFocusRestore`, die de ring netjes op Sortering had teruggezet.
De laatste schrijver wint, en dat was de grid.

**Waarom de bestaande test dit niet zag.** `_FakeLibraryClient` in
`test/screens/tv/tv_unified_catalog_screen_focus_test.dart` negeerde `query` en gaf bij
elke sortering dezelfde twee items in dezelfde volgorde terug. De itemlijst veranderde
dus nooit, `_reconcileNodes` draaide nooit, en E13 stond groen terwijl het toestel rood
was. De fixture honoreert nu `sort`, `offset` en `limit` over 51 titels waarvan de
alfabetische en de toegevoegd-op volgorde elkaars omgekeerde zijn, zodat pagina één
werkelijk van inhoud wisselt. Op de oude implementatie eindigt E13 dan op
`TvUnifiedCard(group:movie:t50:)` in plaats van op `TvCatalogRailSort`, wat precies de
melding is.

**De fix, in drie delen.** `_reconcileNodes` verplaatst de focus alleen nog wanneer de
grid hem werkelijk vasthoudt (`hasFocus`, uitgelezen vóór de dispose-lus); de
vervanger wordt wél altijd onthouden, zodat een latere `focusGrid` goed landt.
`_openRail` focust een al open rail in plaats van niets te doen, synchroon, omdat er
zonder `setState` geen frame gepland wordt waar een post-frame callback op kan wachten.
En de grid krijgt `onBack: _railExpanded ? _closeRail : null`, zodat een open oppervlak
Menu opeet voordat de terugketen van de shell hem ziet, dezelfde regel die de railrijen
zelf al volgen. Met de rail dicht verandert er niets.

**Reikwijdte.** Dezelfde `_openRail`-vorm staat in de kijklijst en in beide
Seerr-vensters. Die kregen dezelfde drie regels, zonder eigen negatieve controle: er is
daar geen railharnas in de testsuite en er is ook geen melding. De catalogus is de
enige die met tests is dichtgetimmerd.

**Bewijs.** `test/widgets/tv/tv_unified_media_grid_test.dart` (een kaart die verdwijnt
terwijl de focus elders staat laat die focus met rust, en de grid onthoudt nog wel waar
hij later moet landen), de heropgebouwde E13 in
`test/screens/tv/tv_unified_catalog_screen_focus_test.dart`, en twee CAT17-tests in
`test/screens/tv/tv_catalog_filter_rail_test.dart` voor LINKS en Menu. Alle vier rood
vóór de fix. Ook `pleya_verify/scenarios/tvos.catalog.rail-sort-focus.yaml` loopt
het hele pad in één build; daarvoor dragen de drie railrijen en de grid nu
`tv.catalog.*`-automation-ids, zoals de kijklijst en de Seerr-vensters die al hadden.

#### Wat de Verify-run wel en niet zegt

`pleya_verify/scenarios/tvos.catalog.rail-sort-focus.yaml` staat groen op de
tvOS-simulator, en `02-after-sort.png` laat zien wat de melding niet liet zien: na het
kiezen van Titel Z-A staat de rail nog open met de witte ring op Sorteren. De weg erheen
kostte drie rondes en die zijn het opschrijven waard. Series is geen catalogus maar een
ontdekkingslanding met rijen en een "alles bekijken"-knop, dus Alle series ligt een Select
verder; dat stond niet in een aanname maar in de focus-trace van de eerste run, die de
node `TvDiscoveryViewAll` noemde. En Alle films is met deze fixture geen route: er zitten
nul films in `catalog.mixed.v1`, dus die pagina tekent de lege staat en bouwt nooit een
raster.

Wat het scenario niet is, is de negatieve controle. De fixture heeft één serie, dus er is
geen tweede pagina en de verwijdering die CAT17 veroorzaakt treedt er niet op; deze run
zou op de oude implementatie waarschijnlijk ook groen zijn geweest. Het bewijst het pad en
het focuscontract op een echte build. Het bewijs dát de regressie weg is, komt uit E13 in
`tv_unified_catalog_screen_focus_test.dart`, die op de oude code eindigt op
`TvUnifiedCard(group:movie:t50:)`.

#### De Codex-challenge erop, en wat die opleverde

Een onafhankelijke Codex-ronde over `42986a14..HEAD` kwam met vijf bevindingen. Vier
ervan waren raak en zijn gesloten; één hield geen stand.

**Raak, en het was mijn eigen fout.** De meegekopieerde `_openRail` in de kijklijst en de
twee Seerr-vensters focuste bij een al open rail de bovenliggende railrij, ook wanneer
er een subview open stond. Die rij is dan niet gemonteerd, want `_buildRail` geeft de
subview terug in plaats van het paneel, en `requestFocus` op een niet-gekoppelde node
meldt `canRequestFocus` true en doet vervolgens niets. De rem zat dus nog steeds vast op
precies het scherm waar hij losgemaakt moest worden. De tak gaat nu door `_closeSubview`,
dat al bestond en de juiste bovenliggende rij post-frame focust.

**Raak, en met een test beantwoord.** Menu op een kaart binden zou de terugketen van de
shell kunnen kortsluiten. Dat doet het niet, omdat de binding voorwaardelijk is: met de
rail dicht draagt de kaart geen `onBack` en valt de druk door. De nieuwe test in
`tv_catalog_filter_rail_test.dart` telt de drukken die het scherm passeren en eist dat de
eerste Menu de rail sluit zonder door te geven, en de tweede wél doorgaat. Met een
onvoorwaardelijke `onBack` staat hij rood op de tweede druk.

**Raak, en de claim was te breed.** PLR7 stond alleen op de rijen en de kaartomlijsting.
De Informatie-tab en de subviews hielden hun eigen pixelwaarden, met een titel op 22 en
een sync-cijfer op 44. Die staan er nu ook op, en er is een tweede meting bij die
de Informatie-tab leest; met de oude waarde meet hij 22,0 waar 18,7 hoort.

**Raak als opmerking, niet opgelost.** De kijklijst en Alle aanvragen geven hun raster
geen `onBack`, dus daar sluit Menu op een kaart een open rail nog niet. LINKS werkt er nu
wel. Bewust blijven staan: het zijn drie oppervlakken zonder railharnas in de testsuite en
zonder melding, en terugtoetssemantiek wijzigen zonder negatieve controle is precies wat
deze ronde niet doet.

**Hield geen stand.** Twee opeenvolgende verwijderingen zouden hun reddingscallbacks laten
racen. Een callback die vanuit `didUpdateWidget` wordt ingepland draait aan het eind van
datzelfde frame, dus een latere update kan er niet voor komen, en een test die de race
probeert na te bootsen staat groen met én zonder de wacht. De controle staat er wel, maar
voor iets anders: de focus die binnen hetzelfde frame naar een andere kaart verspringt,
wat `_buildCell` in `_focusedId` schrijft. Wat er niet bij staat is een test, want die zou
niets onderscheiden.

### PLR7: het spelerpaneel stond niet op de gedeelde typeladder

Gemeld op 7 september 2026 met een foto van het paneel op hardware: de rijen voelen
opgeblazen naast de rest van de app.

**Root cause.** `tv_panel_widgets.dart` en de kaartomlijsting in `tv_info_panel.dart`
schreven hun maten als losse pixelwaarden op en lazen `TvLayoutConstants.scaleOf`
nergens. Het paneel was daarmee het enige TV-oppervlak buiten de fase-4 paneeltaal.
De Apple TV rendert Flutter op ongeveer 1038x584 logisch met een verhouding van 1,85
(DEC-028), dus `scaleOf` staat daar op zijn klemvloer 0,85. Een rijlabel stond op 17
logisch, oftewel 31,5 referentie-px, terwijl hoofdstuk 8.3 voor die tier 23 tot 26
voorschrijft en elk ander paneel er 14,03 tekent. Een rij was 62 hoog waar dezelfde
ladder 54,4 vraagt.

**De fix.** `TvPanelMetrics` leest de schaal en zet elke maat om naar
`TvSourcePickerLayout` maal die schaal: rijhoogte, rijpadding, de drie teksttiers en de
sectiekop komen uit de gedeelde ladder, en wat de ladder geen mening over heeft (de
keuzestip, de schakelaar, de terugknop, de hoekradii, de tussenruimtes) wordt met
diezelfde schaal vermenigvuldigd. Een paneel dat zijn type schaalt en zijn meubilair
niet komt er slechter uit dan een paneel dat niets schaalt.

**Bewijs.** Twee metingen in `test/widgets/tv_info_panel_test.dart`, op het
Apple TV-venster (1038x584, schaal 0,85) en op het canonieke canvas (1920x1080, schaal
1,0). Op de oude waarden meet het label 17,0 op allebei, waar 14,03 en 16,5 hoort: rood
op beide. De negentien bestaande gedragstests, inclusief de PLR4-fittests op drie
hoogtes en de PLR6-contracttest, blijven groen. Er is geen golden die dit paneel tekent.

### DET1: filmdetail las de contentbox voor zijn schaal, niet het paneel

Gemeld op 7 september 2026 op hardware: de synopsis wordt afgekapt zonder een manier om
hem te openen, en de pagina voelt opgeblazen. Mockup 37 (`docs/tvos-redesign-37-approved.md`,
DEC-109) legt de doelcompositie vast; dit is de bouw ervan.

**Root cause.** OVR1a is eerder onderzocht op de TV-paneeltaal
(`TvSourcePickerLayout`/`TvCatalogLayout`) en daar `NOT REPRODUCED` bevonden: die
basiswaarden zijn al voorgedeeld door de 0,85-klem, dus de klem is daar geen fout. Op
filmdetail geldt dat niet. `media_detail_screen.dart:3917` berekende `detailScale` met
`TvLayoutConstants.scaleForSize(size)` op de contentbox van deze route, terwijl INV-1
voorschrijft dat de tienvoetsschaal uit `TvDisplayMetrics` komt: een geneste route is
korter dan het paneel omdat de topnav er een band van afhaalt, en die verkorting hoort de
typografie niet mee te krimpen. De titel-, synopsis- en actierijmaten van deze pagina
(56, 18, `_tvDetailActionSize`) zijn canonieke ontwerpwaarden uit de herotaal van
DEC-095/mockup 30, niet voorgedeeld zoals de paneelconstanten, dus hier is de klembasis
wel de fout.

**De fix.** `detailScale` leest nu `TvLayoutConstants.scaleOf(context)`, hetzelfde pad als
de actierij al gebruikte sinds SYS-1c; de losse `scaleOf`-aanroep die dat verschil moest
opvangen is vervallen omdat beide nu overeenkomen. `test/screens/media_detail_ovr1a_scale_test.dart`
zet een geneste contentbox van 900 logisch onder een gepubliceerd paneel van 1080 logisch
(schaal 0,85 tegenover 1,0) en toont dat de titel op de paneelschaal rendert, niet op de
kortere box.

**Wat er niet bij hoort.** De exacte referentie-pixelwaarden uit de melding (titel 75,5 om
64, synopsis 25,5 om 22-24, actierij 72,3 om 60) zijn niet opnieuw gemeten op een echt
toestel binnen deze bouwronde; de test hierboven bewijst het mechanisme (paneel wint van
contentbox), niet de exacte getallen op hardware. Die meting hoort bij de fysieke
controleronde van dit werk.

**Ernaast, nieuw gedrag.** Een compacte "Meer lezen"-actie tussen de synopsis en de
actierij, alleen aanwezig bij echte tekstoverflow, die een scrollbaar paneel opent met de
volledige tekst (DEC-109). `test/screens/media_detail_synopsis_panel_test.dart` bewijst het
focuscontract: geen actie en geen focusval zonder overflow, UP/DOWN tussen actierij en
actie, SELECT opent, Menu sluit en herstelt de focus.

**Bewijs.** `dc989713`. Golden `tv_detail_source_line` opnieuw opgenomen op de
gecorrigeerde schaal; de bestaande suite op `test/screens/media_detail_screen_test.dart`
en `test/navigation/tv/tv_detail_route_contract_test.dart` blijft groen. MOC-10's
seizoenchips (PB-4) en de VER5-Verify-dekking zijn hier niet meegenomen.

### DET2: de informatieband overflowde onder een hoge railreservering

Gemeld door Michel op een lokale build op main/later (screenshot, geen TestFlight-build):
geen titel/logo en geen synopsis meer, de metaregel en genres bovenaan, de actierij
afgekapt (`BOTTOM OVERFLOWED BY 12 PIXELS`), en de Acteurs-rail plus een stuk Trailers &
Extra's vullen de rest van het scherm. Mockup 37 A is de doelcompositie.

**Root cause.** `1805c75e` (MOC-09/MOC-10) telt `TvCatalogLayout.bottomSafeInset *
detailScale` op bij `foregroundBottom`, en zet `_tvDetailEpisodeThumbnailScale` van 0,8
naar 1,0. Op een klein paneel met een hoge actieve hub (een acteursrail, brede
extra's-kaarten) kan die reservering het hele beschikbare oppervlak voor
`_buildTvDetailForeground` opeten: de metaregel, genres, actierij en bronregel tekenen
daar onvoorwaardelijk, en de degradatielus had geen ondergrens zodra de synopsis op nul
regels stond, dus zakten titel en logo mee weg in plaats van dat de layout kromp.

**De fix.** `_tvDetailMandatoryForegroundHeight` is nu een harde vloer (titel/logo op zijn
minimum, metaregel, genres, actierij, bronregel) waar `_buildTvDetailScreen` tegen klemt:
tekort wordt eerst van de rail's eigen onderrand-inset afgehaald, dan van de "volgende
hub"-peek, als de vloer alleen zo niet past. Een tweede, zachtere doelwaarde
(`_tvDetailIdealForegroundHeight`) probeert daarnaast ook twee regels synopsis plus de
"Meer lezen"-affordance vrij te maken wanneer het paneel dat kan missen, zodat het
gangbare geval (één rail, niet de adversariale combinatie van acteurs én extra's) dicht
bij mockup 37 A's doelcompositie komt in plaats van op de kale vloer te blijven hangen.

**Een gotcha onderweg (H1/H2 uit de pauze-analyse).** De eerste versie van de
ideal-vloer-berekening riep de tekstmeting voor "Meer lezen" aan vanuit
`_buildTvDetailScreen`'s eigen `LayoutBuilder`-context: die zit boven de
`Scaffold`/`Material` die dit scherm zelf bouwt, waar `DefaultTextStyle.of(context)`
terugvalt op Flutters debug-fallbackstijl (48pt monospace) in plaats van het echte
thema. Bevestigd door dezelfde meting van daar en van binnen
`_buildTvDetailForeground`'s eigen, wél Material-omhulde context te printen:
`DefaultTextStyle` week af, `Theme.of(context).textTheme.bodyMedium` was identiek
(`Material` leidt zijn eigen `DefaultTextStyle` van precies die waarde af). De gedeelde
`_tvDetailReadMoreHeight`-helper leest die waarde nu rechtstreeks, ongeacht aan welke
kant van `Material` de aanroeper zit.

**Wat er niet bij hoort.** Stap 5 (iOS-audit) en stap 6 (dekkingstabel) uit de
oorspronkelijke opdracht zijn niet uitgevoerd. Geen Pleya Verify-scenario en geen
fixture-uitbreiding voor een film met cast+extra's. Geen simulator- of
hardwarebevestiging tegen 37 A/37 C.

**Bewijs.** `49b35d77`. Vier nieuwe widgettests in de DET2-groep van
`test/screens/media_detail_screen_test.dart`: rood bevestigd op de ongewijzigde code
(`RenderFlex overflow`) en op `1805c75e^` (synopsis al volledig afwezig, geen crash),
groen na de fix. `test/screens/media_detail_ovr1a_scale_test.dart`,
`test/screens/media_detail_synopsis_panel_test.dart` en `test/widgets/tv_browse_rail_test.dart`
blijven groen (`tv_browse_rail.dart`'s wijziging is additief, elke bestaande aanroep
behoudt zijn default). `scripts/ci_checks.sh` groen. Golden `tv_detail_source_line`
faalt op dit platform ook op `0aa808dc` (vóór deze fix), dus dat is bestaande
platform-staleness, geen regressie van deze wijziging.

### RAIL2, classificatie op de twee beschikbare logs

`h6ocl` (build 272) en `ijqxp` (build 280) opgehaald van `ice.pleya.app/logs/` en gedraaid
door `scripts/tvos_press_trace.sh` na het porten van `797ab55e`
(`nl.michelknoop.pleya/tvos_press_diag`, zie `docs/tvos-remote-input-authority.md`). Beide
builds gaan aan die instrumentatie vooraf, dus elk `RE-TAP` komt terug als `verdict=unknown`;
er is geen `uipress`-identiteit om `same-uipress` tegen `new-uipress` te toetsen. Dit is
daarom een classificatie op timing en context, niet op het harde bewijs dat de opzet
uiteindelijk vereist.

**Tellingen, zoals eerder al vastgelegd (NAV2-rij op `feat/t3a-mijn-pleya-fixtures`, hier
opnieuw gemeten):** `h6ocl` EARLY-KEYUP=3, KEYUP-ONLY=4, RE-TAP=2. `ijqxp` EARLY-KEYUP=4,
KEYUP-ONLY=3, RE-TAP=4.

**Het patroon dat in vier van de zes RE-TAP-omgevingen zichtbaar is, met de ruwe logregels
ernaast:**

```
h6ocl  22:49:05.209  keyup   arrowLeft   (231 ms hold, normale druk)
h6ocl  22:49:05.209  keydown arrowLeft   (0 ms na de vorige regel)
h6ocl  22:49:05.209  keyup   arrowLeft   (0 ms hold)

ijqxp  23:06:31.177  keyup   arrowLeft   (164 ms hold, normale druk; landt op Home)
ijqxp  23:06:31.178  keydown arrowLeft   (1 ms later)
ijqxp  23:06:31.179  keyup   arrowLeft   (1 ms hold)

ijqxp  23:07:26.837  keyup   arrowLeft   (118 ms hold, normale druk; landt op Home)
ijqxp  23:07:26.856  keydown arrowLeft   (19 ms later)
ijqxp  23:07:26.857  keyup   arrowLeft   (1 ms hold)
```

Drie eigenschappen die samen dit patroon onderscheiden van een tweede, echte druk:

1. het gat tussen de vorige loslaat en de nieuwe indruk is 0 tot 19 ms, tegen 60 tot 165 ms
   voor elke andere druk van dezelfde gebruiker in dezelfde log;
2. de vasthoudtijd van het tweede paar is 0 tot 1 ms, fysiek niet haalbaar voor een
   Siri Remote-klik (de kortste onbetwist echte druk in beide logs is 19 ms, gemeten op de
   volgende bullet's uitzondering);
3. in `ijqxp` 23:06:31 wordt het patroon voorafgegaan door een geflushte
   `menuPassthroughEnabled=true` (`TvosSystemNavigationService: keys released, sending the
   parked enable`), maar de toets is op dat moment al uit `synthesizedPressedKeys` verwijderd
   door de eigen `.ended` van die druk (de reguliere Up ging al uit). Een `enable` die niets
   meer aantreft in de set doet niets in `releaseAllSynthesizedPresses`, dus deze specifieke
   flush kan het fantoompaar niet verklaard hebben. `h6ocl` 22:49:05 en `ijqxp` 23:07:26
   hebben zelfs geen enkel kanaalbericht in de buurt: dat bevestigt wat de NAV2-rij al zei
   ("twee van de vier hebben geen kanaalbericht, dus dit is niet de NAV1-trigger") en laat
   zien dat het ook geldt voor het geval mét bericht.

Dit patroon is precies wat `docs/tvos-remote-input-authority.md` §2 als kandidaatmechanisme
beschrijft: beide swizzel-hops (`UIApplication` en `UIWindow`) leveren dezelfde `.ended`-fase
van hetzelfde `UIPress`-object af bij `tvosHandlePressFromUIEvent:`. De eerste aanroep
verwijdert de toets uit `synthesizedPressedKeys` en stuurt de echte Up. De tweede aanroep,
voor diezelfde fase, vindt de toets niet meer en `tapIfMissingKeyDown:YES` synthetiseert een
fantoom Down gevolgd door zijn eigen Up, allebei binnen enkele milliseconden. Werkende naam:
zijdeur 4.

**Waarom dit geen bewezen `same-uipress` is.** De trace bevat geen `uipress`-veld voor deze
logs, dus het bewijs hierboven is timing en context, niet identiteit. Een tweede, extreem
snelle fysieke herhaling (twee klikken binnen 20 ms, elk 0 tot 1 ms vastgehouden) is voor een
mens niet uitvoerbaar op een Siri Remote-ring, dus `PLATFORM_MULTIPLE_PRESS_OBJECTS` is voor
deze drie gevallen feitelijk uitgesloten door de vasthoudtijd zelf. Maar de tussenstap die de
opzet eist (`.began`/`.ended`-levenscyclus van beide objecten via hun `uipress`-hash
vergelijken) is met deze twee logs niet te zetten. Classificatie: **ENGINE_DUPLICATE als
werkhypothese, `UNKNOWN_HARDWARE_EVIDENCE_REQUIRED` als formele status** tot een log ná de
instrumentatie van deze branch een `native press=` regel naast elk van deze paren laat zien
met gelijke `uipress`-waarde.

**Het vierde, andere geval: `ijqxp` 23:09:18, catalogus.** Twee RE-TAPs op `arrowUp`, in een
reeks van acht drukken tussen 23:09:17.050 en 23:09:18.615. Op dit scherm heeft
`FocusableWrapper` geen enkele richting gebonden (`onNav(up=false,down=false,left=false,
right=false)` op elke regel): omhoog doet hier niets, ongeacht wat er native gebeurt. Drie van
de acht paren hebben een vasthoudtijd van 41 tot 53 ms met gaten van 0 tot 28 ms, korter dan
de overige vijf (120 tot 165 ms) maar niet in de buurt van de 0 tot 1 ms uit de drie gevallen
hierboven. Dit past beter bij een gebruiker die snel en herhaald op een schijnbaar dode knop
klikt dan bij een synthesefout, en heeft sowieso geen zichtbaar gevolg: geen enkele druk in
deze reeks verplaatst focus. Classificatie: **INTENTIONAL_REPEAT, geen RAIL2-instantie** (geen
focusverplaatsing om te verklaren).

**Wat dit oplevert voor fase 3 van deze opdracht.** Geen van de zes onderzochte gevallen
levert het bewijs dat een softwarefix rechtvaardigt. De drie sterkste gevallen wijzen
consistent naar zijdeur 4 in de engine, niet naar een Dart-laag: er is dus geen
`DART_DUPLICATE`- of `FOCUS_TRAVERSAL`-fix te bouwen op basis van dit bewijs, en een fix in de
patchreeks zonder bevestigde `uipress`-identiteit zou een gok zijn op precies het mechanisme
dat deze opdracht verbiedt. RAIL2 blijft **HARDWARE VALIDATION PENDING**: de ontbrekende
meting is één toestellog, gemaakt op een build van deze branch (met
`nl.michelknoop.pleya/tvos_press_diag` erin), tijdens herhaald snel links/rechts klikken op
Home-rails, gelezen met `scripts/tvos_press_trace.sh` voor een `same-uipress`/`new-uipress`
oordeel op elke `RE-TAP`.

**Kanttekening bij het meetinstrument zelf.** De trace markeert een keydown als `RE-TAP` zodra
hij binnen 400 ms na een vroege keyup valt; `ijqxp` 23:07:26.997 (160 ms vasthoudtijd, 140 ms
na het fantoompaar hierboven) valt in dat venster en krijgt dezelfde vlag als het fantoompaar
zelf, terwijl zijn eigen duur een gewone druk beschrijft. Het venster vindt dus het fantoompaar
correct, maar kan er een daaropvolgende echte druk aan vastplakken. Een scherpere vlag (gat
onder ~20 ms én vasthoudtijd onder ~5 ms) zou het fantoompaar specifiek isoleren zonder deze
bijvangst; niet doorgevoerd in deze ronde omdat het geen van de classificaties hierboven
verandert en buiten de sterk verkleinde fase 5-scope van deze opdracht valt. Vastgelegd hier
als follow-up voor wie `scripts/tvos_press_trace.sh` de volgende keer aanraakt.

### RAIL2, closure-run op build 281 (log `8x94u`, 15 september 2026)

De ontbrekende meting uit de vorige sectie. Build 281 (`a7d5d3c7`, ongewijzigd) geïnstalleerd op
het gepairde toestel via `devicectl`. Debug logging aangezet, daarna herhaald snel en normaal
LEFT/RIGHT geklikt op een Home-rail. Log `8x94u` opgehaald van `ice.pleya.app/logs/8x94u`
(1963 regels, 524 press-/key-diagnostiekregels).

**Stap 2 bevestigd vóór verdere conclusies.** `nl.michelknoop.pleya/tvos_press_diag` verschijnt
daadwerkelijk in de relaylog, met echte `native press=<richting>(<ordinal>) phase=<fase>
uipress=<hash>`-regels naast elke `native keydown`/`native keyup`.

**Meetinstrument had een regex-bug.** `scripts/tvos_press_trace.sh` matchte
`native press=(\w+) phase=...`, maar de richting in build 281 logt met een ordinal erachter
(`right(3)`, niet `right`), dus de match faalde op elke regel en elke `RE-TAP` kwam terug als
`unknown`, ongeacht de werkelijke `uipress`-waarde. Gefixt in dezelfde sessie: `(\w+)(?:\(\d+\))?`.
Handmatig geverifieerd tegen de ruwe logregels vóór de fix vertrouwd werd; ná de fix komt het
script op dezelfde uitkomst.

**Zes `RE-TAP`s, drie onafhankelijke fantoompaar-instanties.**

```
20:29:51.966  keydown arrowRight  uipress=8705
20:29:51.971  keyup   arrowRight  uipress=8705  (5 ms hold, EARLY-KEYUP)
20:29:52.026  keydown arrowRight  uipress=8705  (55 ms gat, RE-TAP, same-uipress)

20:29:57.306  keydown arrowRight  uipress=8705
20:29:57.345  keyup   arrowRight  uipress=8705  (39 ms hold, EARLY-KEYUP)
20:29:57.406  keydown arrowRight  uipress=8705  (61 ms gat, RE-TAP, same-uipress)

20:30:23.305  keydown arrowLeft   uipress=62021
20:30:23.345  keyup   arrowLeft   uipress=62021 (40 ms hold, EARLY-KEYUP)
20:30:23.425  keydown arrowLeft   uipress=62021 (80 ms gat, RE-TAP, same-uipress)
```

De overige drie `RE-TAP`s (52.146, 52.305, 23.585) vallen binnen het bestaande 400 ms-venster
van deze drie fantoompaar-instanties en zijn bijvangst in de zin van de eerdere kanttekening,
niet apart geteld: ook zij zijn `same-uipress` (8705 respectievelijk 62021), wat de identiteit
bevestigt maar geen zelfstandig bewijs toevoegt.

**Classificatie.** Elke geïsoleerde fantoompaar-instantie heeft dezelfde `uipress`-waarde vóór
en ná het fantoompaar. Volgens de beslisregel in `docs/tvos-remote-input-authority.md` §6
("`same-uipress` op een fantoom Down/Up-paar → ENGINE_DUPLICATE bevestigd") is de werkhypothese
uit de vorige sectie nu een bevestigde classificatie: **ENGINE_DUPLICATE**, zijdeur 4 (dezelfde
`UIPress`-fase twee keer afgeleverd via beide swizzel-hops, `docs/tvos-remote-input-authority.md`
§3). Een engine-lifecyclepatch is gerechtvaardigd. Gebouwd en hardware-geverifieerd in de
volgende sectie.

### RAIL2, hardwarebewijs op build 282 (log `scvdm`, 15 september 2026)

**De fix.** `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)`
(`tvos/Runner/AppDelegate.swift`, `3408f061`) hield tot nu toe geen state bij: beide
swizzel-hops (`UIApplication` en `UIWindow`) gaven hun aanroep onvoorwaardelijk aan `super`
door, en de engine zelf onderscheidt de twee niet. Sinds deze fix onthoudt de controller het
laatst aan `super` doorgegeven `(press, phase)`-paar en het resultaat daarvan; een tweede
aanroep met exact dezelfde combinatie speelt dat resultaat terug in plaats van `super` opnieuw
aan te roepen. De eerste aanroep van elke fase gaat ongewijzigd naar `super`, dus
`synthesizedPressedKeys` en de herhaaltimer bewegen nog steeds precies één keer per echte
fase-overgang, alleen niet meer twee keer voor dezelfde. Dit is niet de inslik- of
doorgeeffout uit de NAV1-sectie hierboven (build 256/257): er wordt geen fase overgeslagen of
aan UIKit teruggegeven, alleen een aantoonbaar overtollige herhaling van een al verwerkte fase
kortgesloten.

**Build en installatie.** Build 282 (`444fb0ee`, bovenop `3408f061`) gebouwd met `/pleya-tvbuild`
in de bestaande detached worktree, Release/AOT bevestigd (Mach-O dylib, geen
snapshots in `flutter_assets/`), correct gesigned (Apple Development, team `XL9KN38ATX`).
Geïnstalleerd en gestart op het gepairde toestel via `devicectl`.

**Reproductie en meting.** Dezelfde stappen als de closure-run hierboven: debug logging aan,
herhaald snel en normaal LEFT/RIGHT op een Home-rail, log `scvdm` opgehaald van
`ice.pleya.app/logs/scvdm` (1684 regels, 316 press-/key-diagnostiekregels, 76
keydown/keyup-paren).

**Uitkomst.** `scripts/tvos_press_trace.sh` (de gefixte versie uit de closure-run-sectie):
`EARLY-KEYUP=0, KEYUP-ONLY=5, RE-TAP=0, ENABLE-HELD=0`. Geen enkele `RE-TAP`, dus geen enkel
fantoompaar, tegen drie in het vóór-de-fix-log op vergelijkbaar aantal drukken. Onafhankelijk
gecontroleerd met een aparte telling over alle 76 keydown/keyup-paren in het ruwe log: geen
enkele vasthoudtijd van 40 ms of korter (de fantoompaar-signatuur uit de closure-run-sectie).
De vijf `KEYUP-ONLY`-vlaggen zijn stuk voor stuk `reason=gesture-owned-by-swipe`: hetzelfde,
niet-RAIL2-mechanisme (station 9, swipe-gesture-eigendom in `AppleTvRemoteTouchService`) dat
ook al vóór deze fix voorkwam (één exemplaar in log `8x94u`), dus geen regressie en geen nieuw
gevonden probleem.

**Status.** RAIL2: **FIXED**, `3408f061` (fix) / `444fb0ee` (build 282, hardware-bewijs).

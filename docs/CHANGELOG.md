# Changelog

Sessie-voor-sessie logboek. Nieuwste bovenaan.

## [2026-08-17] De kijklijst-kaart paste niet in zijn cel, en het accountmenu stond dubbel

### Dependencies
- **`mobile_scanner` 5.2.3 → 7.4.0, ring 3, bewust geaccepteerd.** De iOS-simulator kon niet bouwen op Apple Silicon omdat GoogleMLKit geen arm64-slice levert, en sinds iOS 18 is er geen x86_64-simulator om op terug te vallen. In 7.x is ML Kit op iOS vervangen door Apple's Vision-framework, dus de arm64-uitsluiting is weg. De Dart-API die Pleya gebruikt (`MobileScanner(onDetect:)`, `barcode.rawValue`) is broncompatibel en het scanscherm is niet aangeraakt. `mobile_scanner` staat alleen in `ios/Podfile.lock`, dus tvOS en macOS vallen buiten de impact. Dat de simulator bouwt bewijst een gezonde iOS-build, niet dat scannen werkt: de decoder is juist het onderdeel dat wisselde en een simulator heeft geen camera. Daarom staat er nu een verplichte smoketest op fysieke hardware in [TESTFLIGHT.md](TESTFLIGHT.md), af te vinken vóór de eerstvolgende iOS-upload. Zie [DEC-024](DECISIONS.md#dec-024).

### Fixed
- **Metadata van rij 1 werd over de posters van rij 2 getekend in de Kijklijst.** Op TV liep de titel van een speelbare kaart de rij eronder in, verdween sommige metadata achter een poster, en waren posters binnen dezelfde rij ongelijk hoog. Oorzaak: `MediaCard.height` is in standard-grid-modus de **poster**hoogte, niet de kaarthoogte, en `WatchlistCard` gaf de hele celhoogte door. Elke speelbare kaart werd daarmee 32 logische pixels hoger dan zijn cel, en `SliverGrid` klipt niet. Dezelfde fout zat in de kijklijst-rail op Mijn Pleya. De insets, de gap en de gereserveerde teksthoogte verschilden bovendien tussen de twee kaarttakken, dus posters lagen niet op dezelfde pixel.
- Nieuw `lib/widgets/media_card_grid_layout.dart` (`MediaCardGridLayout`, zusje van `MediaCardListLayout`) bezit die geometrie: 2:3 gemeten over de posterbreedte, plus een captionreserve die met de systeemtekstgrootte meeschaalt. `WatchlistCard` heeft geen `height`-parameter meer, dus celhoogte en kaarthoogte kunnen niet meer uit elkaar lopen. `MediaCard` zelf is alleen van commentaar voorzien; `hub_section`, `tv_browse_rail` en `extras_section` rekenen op het huidige gedrag en blijven ongemoeid.
- Bewijs: met de fix teruggedraaid vallen zes nieuwe geometrietests om met `A RenderFlex overflowed by 32 pixels on the bottom`, exact het voorspelde getal. Met de fix erin is de volledige suite groen.

### Changed
- **Op mobiel is Mijn Pleya de enige persoonlijke ingang.** De avatar met accountmenu rechtsboven in de Home-header verdwijnt daar; Profielen, Opties en Uitloggen staan nu onderaan Mijn Pleya, en de Mijn Pleya-tab draagt de echte profielavatar in plaats van een generiek persoon-icoon. Desktop en tvOS houden het menu, want hun sidebar rendert Mijn Pleya bewust nooit. Eén predicaat (`showsHeaderAccountMenu`) stuurt beide kanten, met dezelfde `isMobile` als de gate op de tab, zodat de acties nooit op twee plekken staan en nooit op geen enkele. Zie [DEC-023](DECISIONS.md#dec-023).
- Uitloggen en het openen van de profielkiezer verhuisden naar `lib/services/account_ui_actions.dart`, naar het model van `WatchlistUiActions`. Dat haalde elf imports uit `discover_screen.dart`, waaronder `auth_screen.dart` en vier registries.

### Notes
- Het twee-personen-icoon in de Home-header is **Samen Kijken** en het telefoon-icoon is de **Companion Remote**. Geen van beide is een accountknop, dus beide blijven staan.
- Het oude menu toonde als eerste items de *andere* profielen, als snelwissel. Die snelwissel kost op mobiel nu een tik meer, via de identiteit bovenaan Mijn Pleya naar `ProfileSwitchScreen`. Dat scherm doet meer dan wisselen (beheren, PIN, verwijderen, Plex-account afmelden), dus een tweede dunnere wisselaar is bewust niet gebouwd.

## [2026-08-17] Copyright gezet, en de indiencheck opgeschreven

### Fixed
- **Het copyright-veld blokkeerde "Add for Review".** Alleen App Store Connect, geen code. Alle drie de 2.8.0-versies stonden op `Buildmind`, een naam zonder jaartal, en dat is niet wat Apple in dat veld verwacht. Gezet op `2026 Michel Knoop` met `PATCH /v1/appStoreVersions/<id>` (drie keer), en teruggelezen: alle drie geven nu `copyright='2026 Michel Knoop'` en staan nog op `PREPARE_FOR_SUBMISSION`.

### Changed
- `docs/TESTFLIGHT.md` kreeg de sectie "Indienen voor review": de veldenchecklist per platform met per veld of de API hem kan zetten, de version-id's van 2.8.0, en de volgorde bij een hertest na afwijzing. "Add for Review" noemt alleen het eerste veld dat het mist, dus zonder lijst vind je de volgende blokkade pas na de volgende poging. Dit is dezelfde valkuil als bij het versienummer, de export compliance en de buildkoppeling.

### Notes
- **Screenshots zijn de enige harde blokkade die overblijft.** tvOS en macOS hebben er geen enkele; die erven niet van iOS. iOS heeft 6× iPhone 6.5" en 2× iPad 12.9". Verder is elk versierecord compleet: beschrijving, keywords, support- en marketing-URL, reviewnotities, demo-account `applereview`, contactpersoon en bijlage staan op alle drie. App-niveau ook: categorie Entertainment, leeftijdsclassificatie 4+, privacybeleid-URL, `contentRightsDeclaration` op `DOES_NOT_USE_THIRD_PARTY_CONTENT`, prijs met basisterritorium NLD, 175 van 175 territoria.
- **Build 221 bestaat wél en hangt aan tvOS**, anders dan de notitie van eerder vandaag meldde. tvOS 2.8.0 draagt build 221 (geüpload 17 augustus, `VALID`, `IN_BETA_TESTING`, export compliance beantwoord); iOS en macOS staan op 220. Geen blokkade, maar de drie platforms lopen dus niet meer gelijk.
- **App Privacy en de EU DSA trader status zijn niet gecontroleerd.** De API-sleutel (rol App Manager) kan ze niet lezen: `appDataUsages` en `appDataUsagePublishState` geven HTTP 404 als relatie op `/v1/apps/<id>`, geen 403. Een sessie in de webinterface was er ook niet (geen Apple-cookies lokaal, en de login vraagt 2FA). Beide staan vermoedelijk goed omdat de iOS-inzending van 6 juli door de indienstap kwam, maar dat is een afleiding en geen meting.

## [2026-08-17] De reviewbuild gekoppeld, en het koppelen geautomatiseerd

### Fixed
- **De drie App Store-versies hingen nog aan de afgewezen build 156.** Alleen App Store Connect, geen code. iOS en tvOS 2.8.0 stonden op build 156 (de build die Apple op 6 juli afwees), macOS had helemaal geen build, terwijl build 220 sinds 15 augustus op alle drie de platforms `VALID` in TestFlight stond. Een reviewer die nu hertest had dus opnieuw de build zonder de inlogfix van `21eb01b` gekregen. Gekoppeld met `PATCH /v1/appStoreVersions/<id>/relationships/build` (drie keer HTTP 204); iOS ging daarmee van `REJECTED` naar `PREPARE_FOR_SUBMISSION`, en alle drie de versies dragen nu build 220 met export compliance al beantwoord.

### Added
- **De TestFlight-lanes koppelen de build zelf aan het versierecord** (`fastlane/Fastfile`). Een upload zet de build in TestFlight, niet in de versie die je indient; die tweede stap was handwerk en ging daarom mis. `ios_beta`, `tvos_beta` en `macos_beta` wachten na de upload op processing (`wait_for_build`) en selecteren de build in de bewerkbare versie van dat platform (`attach_build_to_version`, via `Spaceship::ConnectAPI` `select_build`). In `beta` gebeurt dat pas ná alle drie de uploads, anders staat platform twee te wachten op Apple's processing van platform één. Koppelen is nooit fataal en slaat een versie in review of live over met een melding; wachttijd via `ASC_ATTACH_TIMEOUT` (default 1800s). Losse lane `attach_builds [platform:ios] [build:220]` voor handwerk en herstel. Geverifieerd tegen App Store Connect: alle drie de platforms melden "build 220 was al gekoppeld", dus de idempotente tak klopt.

### Changed
- `docs/TESTFLIGHT.md` kreeg de sectie "Build koppelen aan het App Store-versierecord", met de reden erbij zodat dit niet opnieuw stil misgaat.
- `docs/app-review-reply-2026-08.md` bijgewerkt: de verificatie van de demoserver van vandaag staat erin, plus het aanbod van een schermopname en de instructie om de reply samen met de herindiening te versturen.
- `add_testers` maakt geen eigen Spaceship-token meer aan maar gebruikt de gedeelde `spaceship_app`-helper.

### Notes
- Demoserver opnieuw gemeten: `demo.pleya.app` antwoordt in 296 ms (Jellyfin 10.11.11), het account `applereview` authenticeert, en de bibliotheek geeft de drie rechtenvrije Blender-films terug. De "Authentication timed out" van de reviewer kwam dus niet daarvandaan.
- **Build 221 staat niet in App Store Connect.** De upload die in STATUS als lopend stond heeft geen enkel platform bereikt; het hoogste nummer is op alle drie 220 (15 augustus).
- Zie [DEC-022](DECISIONS.md#dec-022).

## [2026-08-17] Kijklijst afgemaakt, en de Plex-cloudgrens getrokken

### Fixed
- **De servertoken van je eigen mediaserver ging mee naar `epg.provider.plex.tv`** (`lib/services/plex_client/parts/live_tv.dart`, `lib/services/plex_cloud_http_client.dart`, `lib/services/plex_epg_client.dart`, `lib/services/livetv/plex_favorite_channels_service.dart`, commits `a089264`, `74ce20f`, `20ed398`, `2f171c4`). De favorieten van Live TV werden opgehaald en weggeschreven via `_http`, de `FailoverHttpClient` van `PlexClient`, die `config.headers` als defaults draagt met de PMS-token erin; `MediaServerHttpClient._send:288` merget die ook bij een absolute URL. Gemeten tegen een echt account: die host accepteert de servertoken (200), weigert een verzoek zonder token (401) en accepteert de plex.tv-accounttoken net zo goed (200). Weglaten was dus geen optie, verhuizen wel. `PlexCloudHttpClient` is nu de transportgrens naar plex.tv: geen `baseUrl`, geen `defaultHeaders`, nooit een `FailoverHttpClient`, en de token als verplichte parameter per call. `PlexWatchlistClient` staat er ook op, zodat Live TV geen uitzondering werd maar het patroon volgde. De scopecheck zit in `PlexFavoriteChannelsService`, die per operatie opnieuw om user-scoped auth vraagt en de owner-fallback weigert. Zonder scope is de functie afwezig en niet stuk: geen store, geen ster, geen schrijfactie, geen foutmelding. Zie [DEC-021](DECISIONS.md#dec-021).
- **Een mislukte lees van de favorietenlijst wiste je favorieten** (`lib/screens/livetv/live_tv_screen.dart`, `lib/screens/livetv/live_tv_favorites.dart`, commits `2f171c4`, `8f7f937`). `getFavoriteChannels()` ving elke fout af en gaf `[]`, `_loadFavorites` maakte daar een lege lijst van terwijl de store- en source-maps al gevuld waren, en één ster aantikken schreef die leegte terug als de volledige lijst van het account. Een `sharedFullList`-write eist nu een geslaagde lees van precies dezelfde store-instantie binnen dezelfde favorietengeneratie. Dat leesbewijs is een eigen type (`FavoriteStoreReadProof`) in plaats van een set naast een teller, zodat de regel niet stil kan verzwakken als iemand later een `clear()` vergeet.
- **De leescall van de favorieten kon je eigen server offline melden.** `FailoverHttpClient` overridet alleen `get` (`failover_http_client.dart:78`), dus een 5xx van de cloudhost kon de endpoint-cascade van de mediaserver starten en in het uiterste geval `onAllEndpointsExhausted` vuren. Dat pad bestaat niet meer.

### Added
- **Sorteren op de kijklijst: recent toegevoegd, titel, jaar** (`lib/media/watchlist_entry.dart`, `lib/widgets/watchlist_sort_sheet.dart`, `lib/screens/watchlist_screen.dart`, commit `3634fa0`). Het plan beloofde drie ordeningen en offline expliciet "sorteren blijft actief", maar het scherm kende alleen de volgorde van toevoegen. Sorteren gebeurt volledig over de entries in het geheugen: geen refetch, geen availability-resolve, en daarom blijft het offline werken terwijl het filter Beschikbaar verdwijnt. De comparators zijn totaal gemaakt zodat de mergevolgorde niet in het resultaat lekt: titel valt terug op jaar en dan op key (een remake en het origineel delen hun titel), jaar sorteert nieuwste eerst met een ontbrekend jaar achteraan in plaats van als jaar nul.
- **Nederlandse vertalingen voor de kijklijst en Mijn Pleya** (`lib/i18n/nl.i18n.json`, commit `195904e`). Kijklijst is de gekozen term, ook in de navigatie en de meldingen na een mutatie.

### Changed
- **`LiveTvSupport` splitst in server en opslag** (`lib/media/live_tv_support.dart`, commit `b4bc5d9`). `buildFavoriteChannelSource` blijft serverkennis, de vier opslag-members zitten op `LiveTvFavoritesStore`, en `LiveTvSupport.favorites` geeft de store die de server zelf bezit. Jellyfin geeft zichzelf terug en verandert twee regels; Plex geeft `null`, bewust en niet een stub met mode `none`, want Plex-favorieten bestaan wél en wonen alleen elders.
- **De favorietenregels van het Live TV-scherm staan naast het scherm** (`lib/screens/livetv/live_tv_favorites.dart`, commit `e41975c`), zodat een regel die beslist of een volledige lijst overschreven mag worden testbaar is zonder widgetboom. Daar staat ook het onderscheid dat de degraded state draagt: `isFavoriteCapable` stuurt zichtbaarheid, `canToggleFavorite` de bevoegdheid van dit moment.
- **`myPleya.settings` en `myPleya.switchProfile` verwijderd** ten gunste van `common.settings` en `screens.switchProfile`; de profielkop in Mijn Pleya draagt nu een Semantics-label, zodat een avatar met een naam ernaast ook hoorbaar een knop is.

### Notes
- **De scope van `favoriteChannels` is niet vastgesteld.** Het testaccount heeft geen provider met het `livetv`-protocol, dus er bestaat geen geldige `source` en er kon geen onderscheidende regel worden weggeschreven; een synthetische regel wordt geweigerd met 400 `Bad source value`. User-scoped auth is dus de gekozen veilige faalrichting en geen gemeten eigenschap. De gesaniteerde meting staat in `test/fixtures/livetv/`, inclusief een afleiding die achteraf ongeldig bleek en als zodanig gemarkeerd is: het meetscript concludeerde "account/owner-scoped" uit twee lege antwoorden.
- De kijklijst kreeg zijn beslissing in [DEC-020](DECISIONS.md#dec-020) (commit `dd75c69`), de cloudgrens in [DEC-021](DECISIONS.md#dec-021) (commit `d867260`).
- 3264 tests groen, 50 nieuwe. `scripts/ci_checks.sh` schoon op alle zes de gates.

## [2026-08-16] Mijn Pleya en de kijklijst

### Added
- **De universele kijklijst, gevoed door de Plex-watchlist en Jellyfin-favorieten** (`lib/media/watchlist_*.dart`, `lib/services/plex_watchlist_client.dart`, `lib/services/watchlist/`, `lib/providers/watchlist_provider.dart`, `lib/screens/watchlist_screen.dart`, commits `310ace8` tot en met `11ec313`). Titels die je op je telefoon aan je kijklijst zet bestonden in Pleya niet. Het contract is eerst gemeten en gesaniteerd vastgelegd in `test/fixtures/watchlist/`, en die meting sneuvelde vier planaannames: het padsegment `available` gaat over streamingdiensten en niet over eigen servers, de lijst draagt geen `watchlistedAt` per titel terwijl de serverkant wel op `watchlistedAt:desc` sorteert, dubbel toevoegen geeft 200, en alle beeld-URL's zijn absolute publieke CDN-links die zonder header laden.
- **Mijn Pleya op mobiel** (`lib/screens/my_pleya_screen.dart`, `lib/navigation/navigation_tabs.dart`, `lib/screens/main_screen.dart`, commit `7c4f06c`), met Watchlist als eigen bestemming in de sidebar op desktop en TV. Downloads, Verzoeken en Instellingen zijn op mobiel geen bar-items meer maar ingangen binnen Mijn Pleya, dus die zijn daar twee tikken in plaats van één.
- **Toevoegen en verwijderen vanaf het detailscherm, het contextmenu en de sheet** (`lib/services/watchlist_ui_actions.dart`, commit `11ec313`), alleen op film en serie en alleen online. Offline verdwijnt de actie in plaats van te falen, want een kijklijstmutatie wordt geweigerd en niet in de wachtrij gezet.

### Notes
- Een entry draagt meerdere memberships, want dezelfde film kan tegelijk een Plex-watchlistregel en een Jellyfin-favoriet zijn. Verwijderen haalt hem overal weg en is compenserend: lukt de compensatie niet, dan volgt `partiallyFailed` en leest de provider de lijst terug in plaats van te raden. Alle state is genamespaced op profiel plus echte gebruiker. Zie [DEC-020](DECISIONS.md#dec-020).
- Artwork gaat via `MediaImageHelper.catalogPosterUrl` over images.plex.tv zonder auth, met een invariant-test die voorkomt dat er ooit een accounttoken in een persistente image-cachekey belandt.

## [2026-08-15] Het systeemtoetsenbord op Apple TV reageert weer op de Siri Remote

### Fixed
- **Klikken op een letter in het tvOS-systeemtoetsenbord deed niets** (`tvos/Runner/AppDelegate.swift`, `Runner-Bridging-Header.h`, `NativeTextEntryViewController.swift`, `NativeTextEntryPlugin.swift`, commit `6bab0ca`, tvOS-build 219). Vegen werkte, dictatie werkte, continuity-typen werkte, alleen de klik kwam nooit aan. De oorzaak zat in de gepinde fork-engine en is uit de binary bewezen: `-[UIApplication(FlutterTvosPressEvents) flutterTvos_sendEvent:]` slaat de originele `sendEvent:` over zodra `FlutterTvosHandlePressesEvent` `YES` teruggeeft, en `-[FlutterViewController tvosHandlePressFromUIEvent:]` eindigt in `synthesizeRemotePressType:`, die onvoorwaardelijk `YES` retourneert (`mov w0, #0x1` op `0x4b828`; er is geen enkel pad dat 0 geeft). Een select-press werd dus geclaimd op de allereerste hop, voordat UIKit zijn responder chain begon. Vegen bleef werken omdat de swizzle bovenaan bailt op `[event type] != 3`: dat is `UIEventTypeTouches`, geen press. De scheidslijn in het symptoom viel exact samen met de scheidslijn UITouch/UIPress.

  `PleyaFlutterViewController` beantwoordt die vraag nu zelf en geeft `false` zolang een native tekstinvoersessie loopt, **zonder `super` aan te roepen**: super is wat de press synthetiseert en `flutter/keydata` post, dus meelopen zou het achtergrondlek terugbrengen. De selector staat in geen publieke header en wordt gedeclareerd als categorie in `Runner-Bridging-Header.h` (was 0 bytes); Swift importeert hem als `tvosHandlePress(fromUIEvent:)`, geverifieerd met `swiftc -typecheck` tegen de gepinde `Flutter.framework`. Het eigendomsvenster is aan beide kanten aan de responder-staat gekoppeld: aan bij een geslaagde `becomeFirstResponder`, uit in het opruimpad van `NativeTextEntryField.finish` ná de dismissal. Zie [DEC-019](DECISIONS.md#dec-019).

### Changed
- **De Dart-gates zijn vangnet geworden in plaats van het normale pad.** `_blockKeysDuringSession` en de sessie-gate in `apple_tv_remote_touch_service.dart` blijven staan, maar verschijnt hun logregel tijdens een sessie, dan heeft de native hook gefaald. De `requestClose()`-uitzondering voor Back is vervallen: Menu gaat nu met de rest naar UIKit. Eén legitieme trefkans blijft over, de key-up van de select die het toetsenbord opende.
- **Startup-guard tegen een stille engine-bump.** `AppDelegate` logt `FlutterViewController.instancesRespond(to:)` op de selector. Nadrukkelijk op de superclass en niet op een instance: de eigen subklasse implementeert hem, dus een instance zou altijd ja zeggen en de guard waardeloos maken.
- **`scripts/tvos_sim.sh check-select`** meet nu of `textChanged length=N` oploopt én of de Dart-vangnetten stil bleven. Alleen het eindresultaat controleren bewijst de eigendomsoverdracht niet, en juist dat gat liet deze bug langs `check-keyboard` glippen. Op de simulator faalt de check zolang Connect Hardware Keyboard aanstaat, want Return submit dan in plaats van een letter te kiezen.

### Notes
- Twee correcties op eerdere aannames. De gate uit DEC-017 was **niet** de oorzaak: select werd al door de engine opgeslokt vóór die commit, en wat DEC-017 deed was het achtergrondlek dichten. En er is nooit een app-side override geweest, ondanks een geheugennotitie die het tegendeel beweerde; die is gecorrigeerd.
- Meegemerged uit `test`: de hero die verdween nadat het zoektoetsenbord open was geweest, en de watch-state-sync waarbij een tweede apparaat dat verder keek nu wint van een verouderde lokale positie. 2935 tests groen.
- Losse defecten, genoteerd maar bewust niet meegefixt: `forwardedPressCount` telt tijdens een sessie nu nul, waardoor de watchdog altijd `KEYBOARD_UNAVAILABLE` kiest in plaats van `KEYBOARD_DEAD`; en de play/pause-afvang in `AppDelegate.swift` vergelijkt tegen een presstype dat door dezelfde raw-value-mismatch als Menu (2040/2041 tegenover 4/5) waarschijnlijk nooit matcht.

## [2026-08-14] Apple TV: toetsenbord, skip-knoppen, autoplay, scrubben en de log-upload

### Fixed
- **De D-pad bediende de UI achter het systeemtoetsenbord** (`lib/services/apple_tv_native_text_entry.dart`, `lib/services/apple_tv_remote_touch_service.dart`, `tvos/Runner/NativeTextEntryViewController.swift`, `lib/screens/search_screen.dart`, commits `5dba184` + `c8ae4b7`). Select op een letter liet het scherm eronder scrollen en de focus verspringen. De diagnose uit DEC-011 bleek onvolledig: de tvOS-fork-engine swizzlet `sendEvent:` op `UIApplication` én `UIWindow` en levert elke press rechtstreeks als key event aan Dart, buiten de responder chain om, met een window-scan die de root-controller altijd vindt. Alle first-responder- en `pressesBegan`-logica draait dus op een pad dat bij een open toetsenbord nooit wordt uitgevoerd. Tweede valkuil: een `HardwareKeyboard`-handler die `true` teruggeeft stopt de focus-tree-walk niet, want `KeyEventManager` roept `_dispatchKeyMessage` onvoorwaardelijk aan. De gate zit nu op `FocusManager.addEarlyKeyEventHandler`, die vóór die walk draait en dus voor elk invoerveld tegelijk geldt. Back sluit de sessie via `requestClose()` en wordt daarna alsnog geconsumeerd. Aan Swift-kant meldt `finish()` pas ná de dismissal-transitie, zodat de vlag niet uitgaat terwijl het toetsenbord nog op het scherm staat. Zie [DEC-017](DECISIONS.md#dec-017).
- **De skip- en volgende-aflevering-knop waren met de remote nauwelijks te bereiken** (`lib/widgets/video_controls/parts/key_events.dart`, `parts/visibility.dart`, `parts/markers.dart`, `widgets/skip_marker_button.dart`, commit `2dfbcd4`). De knop staat als sibling búiten de `FocusScope` van de bediening, en de root-keyhandler consumeerde alle richtingstoetsen: omhoog opende de bediening met focus op afspelen/pauzeren, omlaag opende het TV-infopaneel, en de knop was nooit kandidaat. De enige route liep via de tijdlijn. Omhoog springt er nu rechtstreeks naartoe zolang hij zichtbaar is, omhoog/links/rechts geven de focus terug zodat hij geen doodlopende weg meer is, en auto-hide dismisst hem niet langer terwijl hij focus heeft.
- **Tijdens de aftiteling stonden er twee volgende-aflevering-knoppen** (`lib/screens/video_player/parts/playback_prompts.dart`, `lib/widgets/video_controls/parts/markers.dart`, zelfde commit). Bij credits-tot-einde wordt de skip-knop zelf "Next Episode", terwijl de Play Next-kaart op vrijwel dezelfde plek verschijnt. De uitsluiting bestond al via `hasPlayNextPrompt`, maar liep achter een `await` op de instellingen, dus in dat venster stonden beide op het scherm. De promptstatus en het wissen van de marker gebeuren nu synchroon vóór die await.
- **De focusring paste niet om de knop** (`lib/screens/video_player/widgets/player_prompt_overlays.dart`, `widgets/skip_marker_button.dart`, zelfde commit). "Play Next" is een `FilledButton` met themaradius 4 en "Cancel" een `OutlinedButton` met de Material-standaard `StadiumBorder`, terwijl beide een pilvormige ring krijgen. Beide staan nu lokaal op `StadiumBorder`; `mono_theme.dart` blijft ongemoeid. De skip-knop gebruikte een achtergrondtint die onzichtbaar was achter zijn eigen dekkende witte vlak en tekent nu een ring. De drie labels liepen hardgecodeerd in het Engels en gaan nu via slang.
- **Autoplay sloeg de volgende aflevering stil over** (`lib/screens/video_player/parts/episode_navigation.dart`, `parts/playback_prompts.dart`, `lib/screens/video_player_screen.dart`, commit `ee96f6c`). Drie onafhankelijke breekpunten. De laadvlaggen bleven staan bij elk van de twaalf `!isCurrentReload()`-uitgangen in `_reloadMediaInPlace`, waarna `_playNext()` de rest van de sessie zwijgend afketste; opruimen gebeurt nu in een `finally`, behalve wanneer een nieuwere herlaadpoging eigenaar is geworden. Een einde-bestand tijdens een overgang of achter de nog-aan-het-kijken-vraag verdween voorgoed, terwijl mpv `eof-reached` per bestand maar één keer flipt; dat wordt nu onthouden en opnieuw afgespeeld zodra het scherm vrij is, met een controle dat de speler nog aan het eind van hetzelfde bestand staat. En bij een korte aflevering die eindigde voordat de volgende bekend was sloot de speler; er wordt nu maximaal drie seconden op de lopende ophaal gewacht. De countdown zit in `lib/screens/video_player/auto_play_countdown.dart` en elke beslissing logt op infoniveau.
- **De log-upload faalde altijd met dezelfde nietszeggende melding** (`lib/screens/settings/logs_screen.dart`, `lib/utils/log_upload.dart`, commit `73ba2b8`). De relay leefde gewoon; de client hield zich niet aan het contract. De statuscode werd nooit gelezen, dus elke weigering liep via `jsonDecode` op een `text/plain`-body naar een lege `catch`. Daaronder zat een echte contractfout: de server accepteert 1 MB en de logbuffer mag 5 MB worden, zonder afkapping. De body wordt nu op UTF-8-bytelengte afgekapt tot 900 KB op een regelgrens, nieuwste regels eerst, met een markering erboven. Per uitkomst is er een eigen melding (te groot, te snel achter elkaar inclusief de wachttijd, geweigerd, serverfout, geen verbinding), de knop blokkeert tijdens een upload, en het verzoek wordt afgebroken zodra niemand er nog op wacht. Dat laatste voorkwam dat de dialoog "duurde te lang" meldde terwijl de log wél opgeslagen werd en de code onbereikbaar bleef.
- **Geen enkele macOS-build in TestFlight was installeerbaar sinds build 196** (`macos/Runner/Info.plist`, commit `9c896d7`). `ITSAppUsesNonExemptEncryption` ontbrak, dus Apple zette elke upload op `MISSING_EXPORT_COMPLIANCE` en daarmee was hij voor geen enkele tester zichtbaar. iOS en tvOS hadden de sleutel al. De upload zelf slaagt en `processingState` wordt gewoon `VALID`, dus de release-lane meldt misleidend succes. De al geüploade builds 214 en 216 zijn losgetrokken via `PATCH /v1/builds/{id}` met `usesNonExemptEncryption: false`. Zie [DEC-018](DECISIONS.md#dec-018).

### Added
- **Positie kiezen op de voortgangsbalk** (`lib/widgets/video_controls/desktop_video_controls.dart`, commit `d9706ad`). Select op de gefocuste tijdlijn pauzeert en opent een previewpositie met vastgezette thumbnail: links en rechts verschuiven alleen die preview, select bevestigt via `onSeekEnd` (en levert daarmee ook `onSeekCompleted` voor Watch Together), terug annuleert zonder te springen. Links of rechts op een gepauzeerde video stapt er impliciet in, alleen bij D-pad-navigatie. De bouwstenen lagen er al: `_timelinePreviewPosition`, `_flushTimelinePreviewSeek`, de BIF/trickplay-thumbnails en `PlayerChromeHold.scrub` stonden alleen achter de transcoding-tak.
- **De spoelsnelheid loopt op met het tempo van klikken** (zelfde commit). De acceleratie hing aan `KeyRepeatEvent`, en die komt alleen van een fysieke D-pad-hold: touchpad-swipes sturen los een down en een up, dus die bleven eeuwig op de basisstap van 10 seconden steken. De streak is nu tijdgebaseerd met een venster van 800 ms en reset bij richtingswissel; de bestaande tiers (1,5x tot 10x) en de clamp blijven. De scrub-thumbnail verschijnt daardoor ook bij swipes.

### Notes
- 2925 tests groen, `flutter analyze` zonder waarschuwingen. TestFlight 2.8.0: tvOS build **216**, macOS build **216**, iOS build **215** (nummers geverifieerd via de ASC-API, niet afgeleid uit de lane-output).
- De iOS-lane hing 32 minuten op `xattr -r -d com.apple.FinderInfo` met een `build/`-map van 13 GB. Opgelost door de map te verwijderen en een reaper mee te draaien die alleen een `xattr`-proces boven de 45 seconden afbreekt. Bekend patroon, zie de toolchain-notitie in STATUS.md.
- Nog te doen op een fysieke Apple TV: de gezamenlijke regressieronde over deze vijf punten. Alles is unit- en widget-gedekt, maar de remote zelf is niet te simuleren.
- Er staan twee app-records in App Store Connect: `nl.michelknoop.pleya` (`6787464031`, actueel) en `nl.michelknoop.plexflixnetwork` (`6786811460`, oud, blijft rond build 140 hangen).

## [2026-08-11] Opruimronde: dode Live TV-interface, eenmalige abstracties, no-op-vlaggen

### Removed
- **41 nooit-aangeroepen leden uit `LiveTvSupport`** (commits `d0ad971`, `e9b9fe5`). Grabber-beheer, de EPG-lineup-wizard, DVR-CRUD, media-providers, sessiedetails en de twee notificatie-URI's stonden in vier lagen tegelijk: de interface, `NoopLiveTvSupport`, een rij `UnimplementedError`-gooiers in de Jellyfin-adapter en de Plex-adapter met de `PlexClient`-implementaties eronder. Callers waren er nul. `buildNotificationWebSocketUri` en `buildNotificationEventSourceUri` hoorden er sowieso niet: het zijn geen live-TV-operaties, en de noop-variant gaf een lege `Uri()` terug in plaats van te weigeren, wat een stille verkeerde verbinding zou opleveren zodra iemand ze wél ging gebruiken. Vijf modelbestanden (`livetv_lineup`, `livetv_server_status`, `livetv_session`, `media_grabber_device`, `media_provider_info`) hingen alleen aan die leden en zijn mee verdwenen.
- **`ConnectionAuthService`** (`lib/connection/connection_auth_service.dart`, commit `24fe41e`). Eén implementatie, en geen enkele call-site die op het abstracte type leunde. `JellyfinConnectionAuthService` houdt `validate`/`refresh`/`signOut` gewoon als eigen methoden.
- **`TvLayoutConstants.heroContentMaxWidth`** en de prefs `preferred_video_codec` / `preferred_audio_codec` (commit `c605852`). De constante had nul lezers; de twee codec-prefs werden nergens uitgelezen, alleen netjes meegereset. De export-test gebruikt nu `subtitle_text_color` als representatieve string-pref.

### Changed
- **DVR-operaties zitten in een eigen `LiveTvDvrSupport`** (`lib/media/live_tv_dvr_support.dart`, commit `208cd6e`). Alleen Plex implementeert opnameregels en gidsherlaad, dus `MediaServerClient.liveTvDvr` is `null` op Jellyfin, lokale mappen en Pleya Share. Dat vervangt `ServerCapabilities.liveTvDvr` als beveiliging op de aanroeppaden: waar die vlag eerst een afspraak was die drie callers vergaten (`livetv_recording_actions.dart`, `record_options_sheet.dart`, `program_details_sheet.dart`), wijst de compiler ze nu aan. Gedragsnuance: `program_details_sheet` zette `_checkedMapping` voorheen via een gevangen `UnimplementedError`, nu via een expliciete null-check.
- **Hold-to-2x draait op `TemporaryOverride`** (`video_controls.dart`, `parts/playback_input.dart`, commit `e6133c5`). De twee losse velden `_isLongPressing` en `_rateBeforeLongPress` waren precies de constructie waar de gotcha in CLAUDE.md voor waarschuwt. `engage` capture't nu eenmalig en `release` herstelt eenmalig. Daarmee heeft `lib/utils/temporary_override.dart` een echte gebruiker en kon de `ignore_for_file: unused-code, unused-files` uit de kop weg (zie de "Changed"-notitie van 2026-08-06, die daarmee vervalt).
- **`kBlurArtwork` is een dart-define geworden** (`lib/utils/obfuscation_utils.dart`, commit `187f4a1`). Screenshot-builds draaien voortaan met `--dart-define=BLUR_ARTWORK=true` in plaats van een handmatige const-flip in de bron. De waarde blijft `const`, dus een gewone build shaket het hele blur-pad er nog steeds uit. Toegevoegd aan de env-tabel in `docs/release-baseline.md`.
- **TV-tekstinvoerdiagnostiek hangt aan de bestaande debug-pref** (`lib/utils/text_input_diagnostics.dart`, commit `7ecaffd`). Het `enabled`-veld stond hard op `false` en had geen schakelaar in de UI, dus de logregels waren onbereikbaar. Ze gaan nu via `appLogger.d`, waarmee "debug logging" in Instellingen de enige knop is.
- **Twee handgeschreven `_listEquals`-kopieën vervangen door `ListEquality`** uit `package:collection` (`host_playback_coordinator.dart`, `guest_playback_reconciler.dart`, commit `a3e71dd`). Zelfde patroon als `playback_state.dart:149` al gebruikte, en het houdt beide services Flutter-vrij.

### Notes
- Vier vondsten uit de audit zijn bewust blijven staan. De donatie-flow is een gedocumenteerd patroon in `docs/DECISIONS.md`. `TemporaryOverride` krijgt juist een gebruiker in plaats van de prullenbak. De `kBlurArtwork`-callsites horen bij een levende screenshot-feature. En de Plex-adapter platslaan in `PlexClient` zou een klasse van 4315 regels nog eens ~62 publieke namen geven, terwijl de adapters na deze sanering dun genoeg zijn.
- Geverifieerd met `scripts/ci_checks.sh` volledig groen (format, codegen-freshness, analyze, unused-code, unused-files) en **2888 tests groen**. Netto 1384 regels minder in `lib/` en `test/`.
- Handmatig nog te doen zodra er weer ingelogd kan worden: Live TV openen op een Plex-server (gids laadt, opname plannen zichtbaar) en op een Jellyfin-server (kanalen en favorieten, geen DVR-knoppen). Dat dekt de gedragsnuance in `program_details_sheet`.

## [2026-08-10] — Inloggen: de Apple-afwijzing dichtgezet en het lege profielscherm op macOS

### Fixed
- **De uitweg naar Jellyfin kwam vijf minuten te laat** (`lib/screens/auth/plex_pin_auth_flow.dart`, commit `6f4d6d9`, iOS-build 213 / tvOS + macOS 214). App Review wees de indiening van 6 juli af op 2.1(a) met *"the app displayed 'Authentication timed out'"*. Dat is geen Jellyfin-bug: die string komt uit precies één plek — de Plex PIN-flow — dus de reviewer koos "Sign in with Plex" en typte daar het Jellyfin-demoaccount in. Zo'n PIN wordt nooit geclaimd. Sinds `93e82da` bestond de knop "Using a Jellyfin server?" al, maar alleen in `_buildErrorBlock`, en de poll staat sinds diezelfde commit op vijf minuten: de uitweg verscheen dus pas ná vijf minuten staren. Hij hangt nu ook onder de PIN zelf, in beide vormen (QR en browser-wachtend), als ingetogen tekstknop en alleen wanneer de ouder een route aanbiedt — het toevoegen van een Plex-account vanuit Instellingen verandert dus niet. Geen nieuwe i18n-string nodig. Zie [DEC-015](DECISIONS.md#dec-015).
- **Diezelfde uitweg brak de lopende poging niet af** (zelfde commit). `_switchToJellyfin()` deed alleen `_clearError()` + callback, wat veilig was zolang de knop pas ná de time-out bestond. Tijdens het pollen niet: de ouder pusht `AddJellyfinScreen` bóven deze widget, die dus blijft leven en doorpollt, en een alsnog geclaimde PIN laat `_connectToAllServersAndNavigate` een `pushReplacement` doen — dwars door het Jellyfin-scherm heen. De knop bumpt nu `_attemptId` (waarmee `shouldCancel` aanslaat) en zet de poll-toestand terug vóór de callback.
- **Het profielscherm op macOS was leeg tot een druk op Esc** (`lib/screens/profile/profile_switch_screen.dart`, commit `fd87cad`). Twee oorzaken over elkaar. De `StreamBuilder` stond op `initialData: ProfilesView.empty` en las `connectionState` noch `hasError`, dus "nog niet geladen", "leeg" en "stilgevallen" zagen er identiek uit — permanent en zonder feedback. En de toevoeg-knop stond als eigen sliver structureel ónder een viewport-vullende `SliverFillRemaining`: op TV trok de initiële focus hem in beeld, maar macOS start in pointer-modus (`input_mode_tracker.dart:58`) en `FocusedScrollScaffold._requestInitialFocus()` is expliciet gated op keyboard-modus, dus daar deed niets dat. Er lag niets overheen; de knop stond onder de vouw. Nu drie toestanden, en de knop zit in de lege staat zelf met `hasScrollBody: false`. De focus-gate bleef ongemoeid, dus op TV verandert er niets. Zie [DEC-016](DECISIONS.md#dec-016).

### Added
- **Diagnostiek in de gecombineerde profielstream** (`lib/profiles/profiles_view.dart`). `_combineLatest4` emit pas als álle vier de bronnen een waarde hebben, dus één stille bron houdt het scherm voorgoed leeg — en statisch lezen wijst niet aan wélke. Na drie seconden zonder emissie logt hij nu welke slots gevuld zijn en welke niet (`received: [...] / pending: [...]`), en de eerste lege snapshot logt de vier invoergroottes. Dat scheidt "een stream vult zijn slot nooit" (verdachte: `ConnectionRegistry.watchConnections()`, de enige met `asyncMap` + crypto per rij) van "`connectionsById` komt leeg binnen waardoor `profile_merge.dart:19` alle Plex Home-profielen weggooit". Op infoniveau, want `appLogger.d` wordt in de app-log gefilterd.
- **Testdekking waar die nul was** (8 tests). `test/screens/auth/plex_pin_auth_flow_test.dart` (nieuw) drijft de poll-UI zonder plex.tv te raken via een `authServiceFactory`-seam plus `MockClient`; `test/screens/profile/profile_switch_screen_test.dart` dekt nu spinner-versus-leeg, de knop zonder scrollen, de lege staat op een korte viewport, de tegenspraak-fouttoestand en de bezinkdeadline. Totaal 2875 → 2883 groen.

### Changed
- **`docs/APP_REVIEW_NOTES.md`**: de waarschuwing tegen "Sign in with Plex" en de Jellyfin-stappen staan nu bovenaan in plaats van onder de rejectie-historie — twee reviewrondes strandden op dezelfde verwisseling. Conceptantwoord voor de Resolution Center in `docs/app-review-reply-2026-08.md`.
- **App Store Connect (app-id `6787464031`) via de API bijgewerkt.** De versie-records voor macOS en tvOS stonden nog op **1.0** terwijl de builds op 2.8.0 zitten; daardoor kon er geen build gekoppeld worden, wat verklaart waarom die twee platforms nooit zijn ingediend. Beide naar **2.8.0** gezet (iOS stond er al op, status REJECTED). De reviewnotities van alle drie de records beginnen nu met dezelfde Plex-waarschuwing.

### Nog te doen
- **Toestelverificatie van beide fixes.** iPad: bewust "Sign in with Plex" kiezen met het demoaccount — de Jellyfin-uitweg hoort meteen zichtbaar te zijn. macOS: koud starten en kijken wélke toestand verschijnt, plus de nieuwe `profiles_view`-regel in Instellingen → Logs. Tegenproef: een pijltje omlaag in plaats van Esc; doet dat hetzelfde, dan is de focus-scrollketen bevestigd als het onthullende mechanisme. tvOS mag niet veranderen.
- **Het antwoord aan App Review versturen** en 2.8.0 opnieuw indienen, nu met build 213/214 koppelbaar op alle drie de platforms.

## [2026-08-09] — Atmos: zelfcorrigerende passthrough, en de diagnose die twee sporen doodverklaarde

### Fixed
- **`auto` stuurde een bitstream naar een sink die hem niet nam** (`lib/services/audio_output_decision.dart`, commit `a0a2018`, build 211). Regressie uit build 207: op een Apple TV via HDMI met een E-AC3-track gaf de speler geen geluid en liep hij vast op de audiorenderer. De auto-beslissing koos op een digitale poort met een Dolby-codec voor passthrough zonder dat ooit was vastgesteld dat de andere kant hem accepteert. `auto` bitstreamt daarom voorlopig nooit meer; passthrough blijft een bewuste keuze van de gebruiker.

### Added
- **Passthrough die zichzelf corrigeert in plaats van stil te vallen** (`lib/services/audio_output_coordinator.dart`, `lib/screens/video_player_screen.dart`, commit `87844bb`, build 212). De ontbrekende schakel was geen code maar een signaal: mpv meldt zelf dat de compressed renderer faalt, maar `msg-level` stond op `all=error`, dus die waarschuwing bereikte de app nooit. Nu staan `ad_spdif` en `ao` op `warn` — ook zonder debug-logging — en luistert de coordinator op de bestaande logstream. Mislukt de bitstream, dan valt de app binnen een seconde terug op PCM, meldt dat, en onthoudt de route in een statische `_bitstreamBlocked` zodat de volgende aflevering niet opnieuw stalt. Een stall-watchdog dekt het geval waarin mpv niets zegt maar de positie stilstaat.
- **`current-ao` en `audio-out-params/format` in de performance-HUD** (`lib/widgets/video_controls/widgets/performance_overlay/*`, `android/.../mpv/MpvPlayerCore.kt`). De enige in-app manier om te zien of de bitstream écht buiten komt: `avfoundation` + `spdif-eac3` betekent dat hij loopt, `audiounit` + `s16`/`float` betekent dat mpv decodeert, wat de instelling ook zegt. Toegevoegd aan het mpv-pad én het Android-mpv-fallbackpad.
- **`server/README.md` en `server/deploy-nas.sh`**: de relay die `ice.pleya.app` bedient is nu deploybaar. Zie [DEC-014](DECISIONS.md#dec-014).

### Changed
- **`server/Caddyfile` en `server/docker-compose.yml` stonden nog op `ice.plezy.app`** — upstream's domein, dat naar een server van edde746 wijst. De rebrand had de app-kant omgezet naar `ice.pleya.app` maar de serverkant niet, en die hostnaam is nooit aangemaakt. Omgezet, `bugs`-container eruit, Caddy naar een `vps`-profile en `cloudflared` erbij.

### Diagnose (nog geen fix)
Een iOS-log van build 211 met Ted Lasso S4E1 verschoof het onderzoek beslissend:

- **De bitstream-keten wérkt.** `Selected decoder: spdif_eac3` → `AO: [avfoundation] … spdif-eac3` → `EAC3 config: … JOC=yes`. De compressed stream mét Atmos-objecten bereikt de AVSampleBufferAudioRenderer. `audiounit does not support spdif formats` is de normale doorval, geen fout, en de route-check van de fork is expliciet `(diagnostic only)` — hij blokkeert niets.
- **`audio-exclusive` is een dood spoor.** De AO-lijst in de meegeleverde libmpv is `audiounit, avfoundation, lavc, null, pcm`; `coreaudio` en `wasapi` — de enige twee consumenten van die optie — ontbreken.
- **Een MPVKit-bisect is niet nodig**: de Atmos-sink in 1.0.16 is aantoonbaar functioneel.
- **De app kan niet zien dát Atmos werkt.** Tijdens de lopende bitstream logt de fork `audio rendering mode: not-applicable`. De app leest exact dezelfde `AVAudioSession.renderingMode` (`AudioSessionPlugin.swift:137`) en `audioRenderingLabel()` mapt dat op `null`, dus de badge zwijgt precies wanneer hij iets zou moeten zeggen. `AudioOutputCoordinator.decision` bestaat, is gedocumenteerd "for the player's rendering badge", en heeft geen enkele lezer.
- **Loudness-normalisatie en passthrough sluiten elkaar uit** en niets coördineert dat. Voor afspeelsnelheid bestaat die guard al (`player_native.dart:311-323`). Android TV arbitreert het conflict zelfs al, maar andersom: `ExoPlayerCore.kt:1952-1955` blokkeert direct output zodra normalisatie aanstaat, terwijl de coordinator `passthrough` blijft rapporteren — daar liegt de badge vandaag. Zie [DEC-013](DECISIONS.md#dec-013).

### Nog te doen
- **De meting op de Apple TV zelf ontbreekt nog.** Alle logs tot nu toe komen van de iPhone. Build 212 staat al op het toestel, dus de meting kan zonder nieuwe build.
- Implementatie van DEC-013 (arbiter, badge uit de beslissing, `auto` op digitale poorten). Plan: `~/.claude/plans/pleya-v2-8-0-211-ios-smooth-frog.md`.

## [2026-08-08] — Blu-ray ISO's en uitgepakte BDMV-mappen afspelen

### Added
- **Een `.iso` is geen stream maar een UDF-filesysteem**, dus mpv kon hem niet demuxen en een ISO was simpelweg onzichtbaar in de app (commit `de48dbb`). De zware helft bleek al aanwezig: de meegeleverde mpv is gebouwd met `-Dlibbluray=enabled`, linkt `bd_open`/`bd_get_main_title`, en `Libbluray.framework` zit in de bundle. Die libbluray bevat udfread en opent een `.iso` rechtstreeks zonder mounten — er was dus geen fork-rebuild nodig, alleen de Dart-kant die mpv vertelt dat dit een schijf is. `detectDiscSource()` (`lib/mpv/disc_source.dart`, nieuw) classificeert een pad als ISO, BDMV-map of gewoon bestand; `player_native.dart`, `local_folder_client.dart` en de speler-foutafhandeling sluiten daarop aan. 97 regels tests in `test/mpv/disc_source_test.dart`.

## [2026-08-07] — Atmos-grondslag op Apple, en Seerr zegt wat er misging

### Added
- **Dolby Atmos en spatial audio op iOS en tvOS** (commit `87c5e04`, build 207). Op AirPods gaf de app stereo waar andere spelers Atmos gaven, en de oorzaak zat niet in mpv: de app riep nergens `setSupportsMultichannelContent(true)` aan. Zonder die opt-in rapporteert de route twee kanalen, ziet `ao_audiounit` `outputNumberOfChannels <= 2` en downmixt hard naar stereo — er valt dan niets meer te spatializen. Daarbovenop sloot `supportsAudioPassthrough()` iOS en Apple TV uit, dus het bitstream-pad lag óók dicht. Nieuw: `shared/apple/AudioSession/AudioSessionPlugin.swift` zet de sessie op `.moviePlayback` plus de multichannel-opt-in en publiceert route-, spatial- en renderingMode-wijzigingen; `AudioOutputCoordinator` en de pure `decideAudioOutput()` kwamen erbij met 385 regels tests.
  - Let op: dezelfde commit introduceerde de auto-passthrough die in build 211 werd teruggedraaid, zie de entry van 2026-08-09.

### Fixed
- **Ontdekken toonde altijd "Something went wrong. Try again."** (commit `24f9054`). `SeerrClient` onderscheidt 401 en 403 netjes en de teksten `errorAuth`/`errorForbidden` bestonden al, maar het scherm keek alleen naar `isNetwork`. Een verlopen sessie of een ontbrekend recht las dus als "probeer opnieuw", terwijl opnieuw proberen daar per definitie niets aan verandert. De soort fout wordt nu geclassificeerd in `lib/utils/seerr_error_message.dart` en per rij bijgehouden; faalt alles, dan wint de meest specifieke melding.

## [2026-08-06] — Apple TV: focus maakt geen gekke sprongen meer

### Fixed
- **Eén veeg verplaatste de focus soms twee cellen, of een richting op die je niet geveegd had** (`lib/services/apple_tv_remote_touch_service.dart`). Een veeg over de touch-surface komt via twee onafhankelijke paden binnen: tvOS' eigen swipe-recognizer synthetiseert `UIPress`-pijlen, en de engine-fork streamt daarnáást de ruwe coördinaten op `flutter/gamepadtouchevent` waar de service zelf pijlen uit bouwt. Ontdubbeling ging per losse toets binnen 120 ms, en dat venster begint te lopen op emit-moment terwijl `simulateKeyPress` de dispatch uitstelt tot een post-frame callback — één trage frame (poster-decode, de 250 ms scroll-animatie in de rail) en de native pijl viel erbuiten. Erger nog: beide paden bepalen de veeg-as los van elkaar en de ontdubbeling matchte alleen dezelfde toets, dus een diagonale veeg kon `arrowLeft` uit het ene pad en `arrowDown` uit het andere opleveren — allebei geldig, samen een sprong schuin weg. Nu bezit de eerste bron die een richting produceert het hele gebaar en wordt de andere gedempt tot het gebaar eindigt, inclusief 250 ms grace na het optillen van de vinger omdat tvOS' recognizer zijn pijl regelmatig pas ná `touchesEnded` levert. `KeyRepeatEvent` werd in de oude ontdubbeling helemaal niet afgehandeld en lekte dus altijd door; dat valt nu vanzelf onder de latch. Zie [DEC-012](DECISIONS.md#dec-012).
- **Dezelfde fysieke veeg leverde de ene keer één en de andere keer drie stappen.** Het veeg-anker sprong na elke stap naar de vinger, waarmee de reis vóórbij de drempel werd weggegooid — en hoevéél weggegooid werd hing af van sample- en frametiming. Het anker schuift nu met exact één drempel op, zodat de rest doortelt naar de volgende stap: het aantal stappen is `floor(afstand / drempel)`. De 190 ms-cooldown blijft als snelheidsplafond maar draagt de logica niet meer.

### Changed
- De as-hysterese in `_resolveSwipeAxis` is **bewust ongemoeid** gelaten. Die is op device getuned (zes tests dekken hem af) en de verkeerde-richting-klacht komt aantoonbaar uit het cross-as-lek hierboven, niet uit de as-keuze zelf — de oude test `synthetic swipe does not suppress a different native direction` legde dat lek zelfs vast als gewenst gedrag.

### Nog te doen
- **Device-QA op een echte Apple TV** (niet simuleerbaar): één veeg = één poster, tien keer herhaald; diagonale veeg mag geen tegengestelde horizontale stap geven; richtingsring-klikken moeten ongewijzigd werken; bibliotheek-grid tijdens snel scrollen, waar de framedruk het hoogst is. In de logs hoort na elke `emit key=… source=swipe` een `consume native … reason=gesture-owned-by-swipe` te staan en nergens nog een ongesuppresseerde `native keydown` erachteraan.

## [2026-08-06] — Apple TV: geen onbedienbare tekstinvoer meer

### Fixed
- **De native tekstinvoer op tvOS was dood én niet te sluiten** (`tvos/Runner/AppDelegate.swift`, `NativeTextEntryPlugin.swift`). `PleyaFlutterViewController` neemt first responder in `viewDidAppear` en geeft die alleen terug in `viewWillDisappear` — wat bij een `.alert`-presentatie nooit vuurt. Alle presses landden dus bij Flutter, dat ze aan `super` doorgaf: de engine zet ze om in `flutter/keydata` en valt pas op de responder-chain terug als Dart de toets als onafgehandeld terugmeldt, wat met Pleya's focus-tree nooit gebeurt. De alert kreeg daardoor geen enkele press — ook de Menu-override erop draaide nooit. Nu staat de controller first responder af zodra een sessie loopt (`NativeInputSession`), gaan presses naar `next?` in plaats van naar de engine, is `pressesChanged` toegevoegd (ontbrak, terwijl de engine hem wél overschrijft) en zit het Menu-vangnet op de Flutter-controller zelf — het enige object dat gegarandeerd in het press-pad zit. Raakt naast zoeken ook login, server-URL en Seerr, die dezelfde surface gebruiken. Zie [DEC-011](DECISIONS.md#dec-011).
- **Synthetische toetsen bleven de UI achter het toetsenbord besturen** (`lib/utils/native_input_session.dart` nieuw, `key_event_simulator.dart`, `gamepad_service.dart`, `apple_tv_remote_touch_service.dart`). `_nativeTextInputFocused` bestond al maar stond alleen in logregels; de enige echte gate was `_windowFocused`, en die is desktop-only en dus altijd `true` op tvOS. Alle drie de routes dispatchen rechtstreeks in de focus-tree, langs `HardwareKeyboard` heen, en verplaatsten de focus onzichtbaar terwijl het toetsenbord openstond. De gate zit nu op het gedeelde choke point én per service. Let op: `Gamepad.pause()` is op iOS/tvOS een no-op in de plugin, en de Siri Remote komt sowieso nooit langs `GamepadService` — die gate raakt alleen een gekoppelde MFi-controller.
- **`SpeechSearchService.capture()` slikte elke `PlatformException` in** en gaf `null` terug, waardoor het zoekscherm nooit leerde dat de surface stuk was en de fallback-toets nooit verscheen. Alleen `BUSY` is nog een stille no-op; de rest gaat door naar de aanroeper.

### Added
- **Systeem-toetsenbord in plaats van een alert-venster** (`tvos/Runner/NativeTextEntryViewController.swift`, nieuw): één `UITextField` die in `viewDidAppear` first responder wordt, zodat tvOS meteen zijn eigen toetsenbord toont. Dat toetsenbord ís de dictatie-surface — de mic-knop op de Siri Remote typt erin — dus het tussenscherm dat je eerst moest bedienen is er niet meer. `textFieldDidEndEditing` sluit de sessie af, anders blijf je na het sluiten van het toetsenbord achter met een lege overlay.
- **Watchdog tegen een dode surface**: komt het toetsenbord niet binnen 4 s op, dan sluit de view zichzelf met `KEYBOARD_DEAD` (er kwamen presses binnen zonder reactie) of `KEYBOARD_UNAVAILABLE`. Die codes latchen een fallback naar het inline D-pad-toetsenbord voor élke aanroeper. Alleen `KEYBOARD_DEAD` wordt persistent opgeslagen (`SettingsService.nativeTextEntryUnavailable`, uitgesloten van export/iCloud — het is een oordeel over dít toestel); `KEYBOARD_UNAVAILABLE` blijft in-memory zodat een eenmalige onderbreking je dictatie niet voorgoed kost.

- **Menu deed niets zolang het systeemtoetsenbord openstond** (builds 203/204). `press.type == .menu` matcht op tvOS 26 nooit: de runtime levert 2041 terwijl `UIPress.PressType.menu.rawValue` naar 5 compileert. De escape hatch werd dus overgeslagen en de druk ging naar `next?`; zonder actieve sessie ging Menu naar `super` en werkte hij wél — vandaar dat terug alléén mét toetsenbord stuk was. Gemeten en geverifieerd in de tvOS-simulator via het nieuwe `scripts/tvos_sim.sh`.
- **Gepresenteerde view controller vervangen door een tekstveld in de Flutter-view.** De hele bugklasse eromheen — `dismiss` dat het gepresenteerde kind raakt in plaats van zichzelf, `viewDidAppear` die opnieuw vuurt als het toetsenbord sluit, `presentingViewController` die nil kan zijn — bestond alleen omdat er een modal gepresenteerd werd. Nu is teardown onvoorwaardelijk: resign + removeFromSuperview. Plus een responder-poll die de sessie beëindigt zodra het toetsenbord weg is, ongeacht wélke delegate-callback tvOS kiest.
- **Het toetsenbord was niet te verlaten** (build 203, device-test): `entry.dismiss()` sluit niet de entry-VC maar zijn gepresenteerde kind — en dat kind is het systeemtoetsenbord. Menu sloot dus het toetsenbord, beëindigde de sessie en gaf de remote aan Flutter terug (achtergrond navigeerde zichtbaar terug) terwijl de lege overlay bleef staan. Nu via `presentingViewController.dismiss(...)`. Daarbovenop vuurt `viewDidAppear` een tweede keer zodra dat toetsenbord sluit, wat het direct heropende; een tweede verschijning telt nu als "klaar".

### Changed
- De mic-knop in het zoekscherm is weg op Apple TV (`lib/screens/search_screen.dart`): de mic zit op de afstandsbediening en werkt zodra het toetsenbord openstaat, wat select op de zoekbalk al doet. Android TV houdt zijn knop — daar opent die `RecognizerIntent`.

## [2026-08-05] — Zoeken op elk apparaat: Siri Remote-dictatie en focus-hardening

### Added
- **Gedeelde native-tekstinvoerclient** (`lib/services/apple_tv_native_text_entry.dart`, nieuw): singleton `AppleTvNativeTextEntry` rond channel `com.pleya/native_text_entry`. Flutter routeert inkomende platform-calls op **channel-naam**, dus met een client-instantie per aanroeper landden live `textChanged`-events op de laatst geconstrueerde handler — bij voice search was dat een afgeronde sessie met een genulde callback, waardoor gedicteerde tekst nooit aankwam. De singleton geeft de events aan de actieve sessie, zet de gamepad-pauze in de client zelf (fix voor elke aanroeper) en behandelt `BUSY` als stille no-op i.p.v. een Flutter-keyboard achter de zichtbare alert te stapelen. `FocusableTextField._openAppleTvNativeEntry` delegeert hierheen. Zie [DEC-009](DECISIONS.md#dec-009).
- **Zoekveld op Apple TV is invoer geworden** (`lib/screens/search_screen.dart`, `_buildTvSearchHeader`): de pill was een kale `InputDecorator` zonder focus en dus niet selecteerbaar. Nu een `FocusableButton` die op select het systeem-toetsenbord opent, voorgevuld met de huidige query — dat toetsenbord ís op tvOS de dictatie-surface van de Siri Remote. `_openNativeSearchEntry()` streamt partials naar `_searchController` zodat de bestaande debounce meezoekt tijdens het dicteren; `submitted` roept `_handleSearchSubmit()` aan. De inline `TvVirtualKeyboardPanel` blijft als fallback (`_nativeEntryUnavailable`); Android TV en Fire TV ongewijzigd.
- **`SpeechSearchService.capture()`** (`lib/services/speech_search_service.dart`) geeft nu `({String text, bool submitted})` terug en accepteert `initialText` + `onPartial`. Voorheen gooide hij de `submitted`-vlag weg, waardoor annuleren-met-tekst alsnog zocht en Done nooit het eerste resultaat focuste.

### Fixed
- **`SelectKeyUpSuppressor` at een hele select-druk op** (`lib/focus/dpad_navigator.dart`, `focusable_wrapper.dart`): de context-menu-toets armde de globale suppressor óók als er geen `onLongPress` was (er opende dus niets), en alleen een key-up wiste hem. De eerstvolgende echte SELECT verdween daardoor geruisloos. Armen gebeurt nu alleen bij een echte handler, en een verse key-down wist de suppressie zonder te consumeren — een nieuwe druk kan nooit de release zijn waarvoor de suppressor bedoeld is.
- **Verweesde select-key-ups** (`focusable_wrapper.dart:_handleKeyEvent`, `focusable_chip_mixin.dart`): met `enableLongPress` vuurde `onSelect` alleen op key-up. Verschoof de focus tussen down en up (rebuild, autoscroll), dan claimde de nieuwe node de key-up en verdween de druk zonder feedback. Zonder bijbehorende key-down geeft de handler nu `ignored`.
- **Recente-zoekopdrachten waren onbruikbaar met de remote** (`search_screen.dart:_buildRecentSearches`): plain `ActionChip`s en een kale `TextButton` — op Apple TV zit `select` niet in de standaard shortcut-map, dus die chips waren daar niet eens activeerbaar, en de focus-highlight ontbrak. Nu `FocusableFilterChip` + `FocusableButton`. **"Wis geschiedenis" gooide bovendien een `TypeError`** (`const []` is `List<dynamic>`, `StringListPref` eist `List<String>`) en deed dus op géén enkel platform iets.
- **Focus-zwart-gat bij het starten van een zoekactie** (`search_screen.dart:_performSearch`): `_isSearching = true` vervangt de resultaten door skeletons zonder focusables, dus stierf de focus met de unmounted kaart en lag de D-pad stil. Focus parkeert nu op het invoerveld, gescoped op dit scherm zodat een achtergrond-refresh geen focus tussen tabs steelt.
- **Back ontsnapte uit een open sheet** (`lib/screens/main_screen.dart`): de host-fallback sloot de sheet terwijl `_handleBackKey` in dezelfde druk naar de sidebar sprong. Main-screen negeert nu toetsen zolang `_isOverlaySheetOpen`.
- **Sheets zonder focus op hostloze schermen** (`lib/widgets/overlay_sheet.dart`, `lib/screens/seerr/seerr_media_detail_screen.dart`): de `showModalBottomSheet`-fallback negeerde `initialFocusNode`, dus opende een sheet met niets gefocust en dode D-pad. Het Seerr-detailscherm — direct bereikbaar vanuit zoekresultaten — kreeg een `OverlaySheetHost`, en de fallback honoreert de node nu post-frame.
- **Toetsenbord toonde een opgelichte toets zonder focus** (`lib/widgets/tv_virtual_keyboard.dart`): las als "druk select om te typen" terwijl de druk elders landde.
- **Android cold-start `ACTION_SEARCH`** (`android/app/src/main/kotlin/nl/michelknoop/pleya/MainActivity.kt:handleSearchIntent`): de query werd alleen gestasht als de `binaryMessenger` ontbrak, maar bij koude start bestaat die al vóórdat Dart zijn handler registreert — "zoek X in Pleya" via de Assistent landde op een leeg scherm. Nu altijd stashen en pas clearen bij bevestigde delivery.

### Changed
- `lib/utils/temporary_override.dart` kreeg `ignore_for_file: unused-code, unused-files`. De klasse wordt bewust aangehouden (zie de gotcha in CLAUDE.md) maar liet de CI-gate sinds 15 juli rood staan. Let op: een `exclude` in `analysis_options.yaml` werkt **niet** voor `check-unused-code` — alleen file-level ignores.
- Drie tests in `test/screens/video_player/player_prompt_overlays_test.dart` annuleren nu de auto-hide-timer die `PlayerChromeController` bij het vrijgeven van een hold bewust opnieuw armt. Ze faalden op de pending-timer-invariant, niet op gedrag; dit was de "3 pre-existing failures" uit eerdere sessies.

### Notes
- **Verificatie:** `scripts/ci_checks.sh` volledig groen, `flutter analyze` zonder issues, **2792 tests groen**. Vier nieuwe testbestanden: `test/focus/dpad_navigator_suppressor_test.dart`, `test/focus/focusable_wrapper_select_test.dart`, `test/services/speech_search_service_test.dart` plus TV-cases in `test/screens/search_screen_test.dart`.
- **Deploy:** build **202** op TestFlight voor iOS, tvOS én macOS (commits `3b193f8`, `3148604`).
- **Nog te verifiëren op apparaat** (niet simuleerbaar): Apple TV — mic-knop op de Siri Remote dicteert in de native alert, Menu sluit hem en play/pause + D-pad werken daarna, iPhone-continuity streamt live. Android TV — mic-knop en Assistent-zoekopdracht vanuit een volledig afgesloten app.
- **Toolchain-valkuil onderweg:** na een Xcode-update faalt élke build tot Xcode één keer handmatig is gestart; `xcodebuild -runFirstLaunch` lost dit niet op. Zie [DEC-010](DECISIONS.md#dec-010).

## [2026-08-03] — Bruikbaarheidsronde: voice search, TV-invoer, App Review 2.1(a)

### Added
- **Voice search** (`lib/services/speech_search_service.dart`, nieuw): Android (incl. Android TV) via `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` als activity-result, dus zonder `RECORD_AUDIO`-permissie — die is op een TV-afstandsbediening lastig te verlenen. Plus `ACTION_SEARCH`-afhandeling voor de Assistent en de leanback-zoekrij (`android/app/src/main/res/xml/searchable.xml`).
- **Inline TV-zoektoetsenbord** op de zoekpagina in plaats van een pop-up (`ac21110`): `TvVirtualKeyboardPanel` uit `lib/widgets/tv_virtual_keyboard.dart` geëxtraheerd; de modale variant is nu een dunne wrapper.
- **Guard-test** `test/no_bare_text_field_test.dart`: laat de build falen op een kale `TextField`/`TextFormField` in `lib/`, want zo'n veld is op TV niet te vullen.

### Fixed
- **Geen dead-end meer bij inloggen** (App Review 2.1(a)): Plex en Jellyfin zijn gelijkwaardige startpunten (`21eb01b`), met verzachte timeout-teksten in alle talen (`1337487`).
- **Hero op Discover crashte** op `context.select` tijdens layout (`89f7641`).
- **`tvos_beta` haalt zijn eigen engine op** in plaats van te leunen op oude artefacten (`a6218ad`).

### Notes
- Bekende bug uit deze ronde, opgelost op 2026-08-05: de cold-start-tak van `handleSearchIntent` verloor de query.

## [2026-07-30] — Fastlane external-testing lanes

### Added
- **Lane `external`** (`fastlane/Fastfile`): distribueert de laatste geüploade build naar de external TestFlight-groep via `upload_to_testflight` met `distribute_only: true` — bouwt niets, wacht op processing, triggert Beta App Review bij de eerste build van een versie. Per platform: `fastlane external platform:ios|appletvos|osx`; zonder optie alle drie, gaat door als één platform faalt. Changelog-tekst via `TESTFLIGHT_CHANGELOG` env-var.
- **Lane `add_testers`** (`fastlane/Fastfile`): koppelt e-mailadressen aan de external groep. Via Spaceship (`group.post_bulk_beta_tester_assignments`) omdat `pilot` als Fastfile-actie een alias van `upload_to_testflight` is en geen tester-commando's kent. Faalt per adres i.p.v. de hele run af te breken; duidelijke fout als de groep niet bestaat.
- Groepsnaam configureerbaar via `EXTERNAL_GROUP` env-var (default "External Testers").

### Notes
- **Handmatige stap**: groep "External Testers" eenmalig aanmaken in App Store Connect → TestFlight → External Testing.
- Geverifieerd: `ruby -c` syntax OK, beide lanes zichtbaar in `fastlane lanes`; Spaceship-API gecontroleerd tegen de geïnstalleerde fastlane 2.236.1.
- Interne flow (`beta`-lanes) ongewijzigd: `distribute_external: false` blijft de default.

## [2026-07-24/29] — Ondertitel-labels, tvOS-hero en zoom, home-rijen, downloads-hervatten

### Added
- **Ondertitel-labels lenen serverdata** (`lib/utils/player_subtitle_labeling.dart`, nieuw): `matchServerSubtitle()` koppelt mpv-ondertitelsporen positioneel aan de serverstreams onder de niet-externe sporen en `labelForPlayerSubtitle()` leent daarvan `languageCode`/`displayTitle`. Bij direct play draagt de UI alleen wat de containertags bevatten, waardoor een ongetagd spoor tot "Track 1" verviel. Containertags winnen, externe sporen blijven ongemoeid, placeholders ("Unknown", "Onbekend", "und") worden gefilterd. Aangeroepen vanuit `sheets/track_sheet.dart` en `tv_info_panel/tv_audio_subtitle_tabs.dart`.
- **Diagnostiek voor die koppeling** (zelfde bestand): `SubtitleAlignmentOutcome` + `diagnoseSubtitleAlignment()` benoemen de drie stille uitvalspaden (`noServerData`, `countMismatch`, `contradiction`); `logSubtitleLabelingDiagnostics()` logt uitkomst, aantallen en per-spoor metadata eenmalig per wijziging. Bewust op **infoniveau**: debug-regels worden gefilterd tenzij de gebruiker debug-logging aanzet, en Instellingen > Logs is de enige praktische manier om een tvOS-build te inspecteren. `key` wordt als vlag gelogd, niet als pad.
- **Rij "Recently Added Shows"** op serie-niveau (`lib/providers/discover_provider.dart`, `data_aggregation_service.dart`, client-kant in `plex_client.dart` en `jellyfin_client/parts/browse.dart`).
- **Downloads hervatten** na systeempauze, netwerkverlies en retry (`lib/services/download_manager_service.dart`, `lib/database/download_operations.dart`).

### Fixed
- **Beeldverhouding/zoom op iOS en tvOS** (`lib/services/video_filter_manager.dart`, `lib/screens/video_player/parts/pip.dart`): de instelling had daar geen effect.
- **tvOS-hero**: details-knop weer bereikbaar via D-pad; ondertitels blijven in beeld bij zoom.
- **Billboard** (`lib/widgets/tv_spotlight_background.dart`): haalt ontbrekend artwork/logo alsnog op en blijft leesbaar tijdens bladeren.
- **Home-indeling** werkt direct in plaats van pas na herstart.

### Notes
- Deploy: TestFlight 187 t/m 194 (tvOS 194 bevat de diagnostiek).
- **Open**: op de Apple TV toont het paneel nog steeds "Track 3", dus de koppeling draait daar niet. De diagnostische logregel in build 194 wijst de oorzaak aan; vervolgstap staat in [STATUS.md](../STATUS.md).
- Bekende ruis: 3 pre-existing failures in `test/screens/video_player/player_prompt_overlays_test.dart` (falen ook op HEAD).

## [2026-07-22/23] — Pleya Share device-naar-device compleet, Wi-Fi Aware, hero-resume-fix

### Added
- **Pleya Share verbindingslagen** (`lib/services/pleya_share/`): `pairAny` multi-IP QR-pairing (hotspot-proof, gateway-probes .1/.129/.254 voor USB-tethering), link-local (169.254.x) voor directe kabel, E2E-encrypted **relay-tunnel** (`pleya_share_relay*.dart`, zelfde relay als Watch Together; auth-header-forwarding, ping/pong, cancel-frames, 5min ack-timeout, zelfheling) en **Wi-Fi Aware** als additioneel routerloos transport (in-repo plugin `plugins/pleya_aware`: Android WifiAwareManager, iOS 26 WiFiAware-framework; byte-pipe naar de bestaande HTTP-stack via `pleya_share_aware.dart`). Volgorde: LAN → Aware → relay.
- **iOS host-keepalive** (`ios/Runner/AppDelegate.swift`): stille-audio-loop + interruption-recovery zodat een vergrendelde iPhone blijft serveren; Android had al een foreground-service.
- **Sync-brug voor share-items** (`server_matchable_client.dart`, `local_server_match_service.dart`): posters/metadata en bidirectionele voortgang (ook per aflevering) via Plex/Jellyfin-match, net als lokale mappen.
- **Multi-client**: meerdere guests streamen tegelijk van één host (scan-cache 30s TTL); watch-state per guest.
- Website: Pleya Share Premium-kaart + FAQ; geheime APK-downloads via NAS-volume (`/downloads/<token>/`).

### Fixed
- **Hero-resume** (`lib/utils/video_player_navigation.dart:navigateToVideoPlayer`): direct-play herfetcht het item wanneer `viewOffsetMs` ontbreekt — hero-items uit `/library/recentlyAdded` droegen geen per-user voortgang en startten op 0; detail deed al `fetchItem`, vandaar het verschil.
- **iCloud-voortgang** (`icloud_sync_service.dart`): `local_progress_/local_watched_`-maps mergen (max/OR) i.p.v. last-writer-wins; >100KB values geskipt; Pleya Share-keys op de denylist (`settings_export_service.dart`).
- iOS background-audio bij lock (Dart-pauze weggehaald, native `vid=no` doet audio-only), episode-sortering share-client, lokale posters bij koude start (statusStream-trigger), offline start bindt LAN-bronnen (`hasLanCapableConnections`, main.dart), join-row-fallback voor auto-resume, sessietokens persistent (host-herstart breekt streams niet), companion-remote AEAD-desync-teardown, 48633-bind-contentie.

### Changed
- Energie: wakelock alleen nog desktop/TV, adaptieve beacons (3s↔15s), share-poll-backoff 45s→180s.
- Hero toont watched-status (checkmark, mobiel/desktop + tvOS, live via WatchStateStore).

### Decisions
- DEC-006 (byte-pipe/loopback-transportarchitectuur), DEC-007 (Wi-Fi Aware additioneel) — zie DECISIONS.md.

### Notes
- Deploy: TestFlight 182–186; signed APK op de geheime pleya.app-link. Device-QA nodig: host-lock-scenario's, Wi-Fi Aware (iOS 26-device), ice.pleya.app-relay-eisen (zie PLEYA_SHARE.md).

## [2026-07-04] — Jellyseerr/Overseerr-requests, tvOS-hero + native keyboard, discover-hero

### Added
- **Jellyseerr/Overseerr-integratie** (`lib/services/seerr/`, `lib/providers/seerr_provider.dart`, `lib/screens/seerr/`, `lib/widgets/seerr_request_sheet.dart`): films/series aanvragen vanuit de app, met discover-scherm, media-detail, poster-cards en instellingen. Auth via apiKey/plex/local modes met silent re-auth.
- **tvOS native systeem-toetsenbord** (iPhone-continuity) + hero die de focus volgt; grotere billboard-hero op home (Netflix-effect).
- **Discover-hero** toont de nieuwste uitgekomen films over alle servers i.p.v. "verder kijken" (release-date-sortering, films-only, form-factor-specifieke afbeeldingen).
- **iCloud settings-sync** via `NSUbiquitousKeyValueStore`.

### Changed
- **TestFlight build-number-coördinatie** herschreven naar per-platform onafhankelijke builds (`fastlane/Fastfile`): iOS/tvOS/macOS delen hetzelfde nummer via pubspec-versie, maar kunnen los gebouwd worden.
- **Seerr-foutmeldingen** surfacen nu de echte server-respons i.p.v. generieke tekst (`seerr_client.dart`), zodat login-fouten diagnosticeerbaar zijn.

### Fixed
- **Plex-login 415** (`lib/utils/media_server_http_client.dart`): `http.Request.body` zette bij ontbrekende content-type standaard `text/plain; charset=utf-8`, waardoor Seerr `/auth/plex` met 415 "unsupported media type" weigerde. Content-type wordt nu vóór de body gezet zodat `application/json` blijft staan. Geldt voor alle json-body POSTs. Commit `826dfa7`.
- **tvOS native keyboard reopen-loop**: opent nu op select i.p.v. focus.
- **tvOS**: zoom/stretch-knop weer bereikbaar, AirPlay-knop weg op Apple TV.
- **macOS iCloud-KVS-plugin**: `registrar.messenger` als property i.p.v. functie-call (FlutterMethodChannel-init).

### Notes
- **Deploy**: iOS build 139 / tvOS build 140 naar TestFlight; per-platform build-nummers actief.

## [2026-07-03] — Rebrand naar Pleya + on-device aanbevelingen + UX-polish

### Changed
- **Rebrand PlexFlixNetwork → Pleya** overal: display-naam (iOS/macOS/tvOS Info.plist), client-ID's naar servers (`plex_client.dart`, `jellyfin_client.dart`, `plex_auth_service.dart`), alle 15 i18n-locales, `pubspec.yaml`, `README.md`. Zie [DEC-001](DECISIONS.md#dec-001).
- **Merkkleuren** in `lib/theme/mono_theme.dart`: `kAccent` `#E50914` → `#F42B1F`, nieuwe `kAccentAlt` `#F68F16` en `kBrandGradient`. "XX% match"-badge van groen `#46D369` → amber (`discover_screen.dart`, `media_detail_screen.dart`). Zie [DEC-002](DECISIONS.md#dec-002).
- **Bundle-ID** `nl.michelknoop.plexflixnetwork` → `nl.michelknoop.pleya` (iOS/macOS/tvOS pbxproj + TopShelf + app-group), Android appId → `nl.michelknoop.pleya`, FileProvider-authority meegewijzigd. tvOS-entitlement/Swift app-group-mismatch gefixt.
- **`media_progress_bar.dart`** herschreven van `LinearProgressIndicator` naar een gradient-`Stack` (links-verankerd, geanimeerd).
- **`media_detail_screen.dart`** opgesplitst (4605 → 4482 regels): `cast_section.dart`, `extras_section.dart` geëxtraheerd.

### Added
- **On-device aanbevelingssysteem** (`lib/services/recommendations/`): `taste_profile.dart` (scorer + affinity-vector met 90d-decay), `affinity_engine.dart`, `interaction_recorder.dart`, `candidate_pool.dart`, `personalized_rows_builder.dart`, `recommendation_service.dart`, `hub_dedup.dart`. Drift **v17**: tabellen `MediaInteractions` + `AffinitySnapshots` (`tables.dart`, migratie in `app_database.dart`). Rijen: Aanbevolen voor jou / Omdat je van X houdt / Verborgen parels. Gewired in `discover_provider.dart` + `profile_session_screen.dart`. Settings-toggle `personalizedRecommendations`. Zie [DEC-004](DECISIONS.md#dec-004).
- **Multi-seed "Because you watched"** (3 rijen), cross-row dedup en rij-prioritering in `discover_provider.dart` + `media_hub_ordering.dart`.
- **Rijkere Jellyfin home-rows**: "Top Rated" (`SortBy=CommunityRating`) en "Something Different" (`SortBy=Random`) in `jellyfin_client/parts/browse.dart` + see-more-routing.
- **UX-widgets**: `state_view.dart` (empty/error/offline overal toegepast), `pressable.dart`, `new_content_badge.dart`, `skeletons.dart`, `hero_flight.dart`, animated watched-check in `watched_indicator.dart`.
- **Trakt read-endpoints** (`recommendations/trending/popular`) in `trakt_client.dart` — dormant tot keys. Zie [DEC-005](DECISIONS.md#dec-005).
- **Legal**: `NOTICE`-bestand, GPL-attributie + source/privacy/BuildMind-links in `about_screen.dart`.

### Decisions
- [DEC-001](DECISIONS.md) rebrand · [DEC-002](DECISIONS.md) kleuren · [DEC-003](DECISIONS.md) GPL/secrets · [DEC-004](DECISIONS.md) aanbevelingen · [DEC-005](DECISIONS.md) uitgestelde features.

### Fixed (review-passes)
- **/codex** (5): affinity-snapshot verversde niet bij retentiecap (`latestInteractionAt` toegevoegd); stale aanbevelings-rijen bleven bij uit/leeg; dedup-excludeKeys incompleet; episode-rollup te smal.
- **/code-review** (7): progress-bar vulde vanuit midden i.p.v. links; scorer strafte brede genre-matches af (`top2Of`); sterke afkeer onderdrukte voorkeuren (normalisatie op max-positief); jitter kon negatief (`.abs()`); seed-rijen vóór vulling gelezen → duplicaten (geordend via `_loadRecommendationRows`); delta-reconnect verfriste rijen niet; recorder schreef onder leeg profiel-id.

### Notes
- **Deploy/TestFlight**: bundle-ID-wissel verweest de bestaande TestFlight-app (6786811460). Nieuw ASC-record + App Group `group.nl.michelknoop.pleya` + provisioning nodig vóór de volgende upload, óf tijdelijk de oude bundle-ID aanhouden. Secrets via `--dart-define` bij release.
- Verificatie: `flutter analyze lib/` 0 errors; 1678 tests groen (4 pre-existing baseline-failures in `side_navigation_rail`/`tv_browse_rail`, niet van dit werk); macOS-build `Pleya.app` ✓.

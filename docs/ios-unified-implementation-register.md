# Implementatieregister: iOS Unified 2026

Aangelegd op 11 september 2026 (UNI0). Dit register houdt per iPhone-scherm bij hoe ver het is.
Volgorde, statusladder, bewijsregel en releasegate staan in
[unified-2026-closure.md](unified-2026-closure.md) en worden hier niet herhaald.

## Autoriteit

- [DEC-090](DECISIONS.md#dec-090): de 21 beelden in `docs/assets/ios-unified/northstar/` zijn de
  bevroren visuele autoriteit voor de iPhone. De vijf comps in dezelfde map gelden voor Home, Home
  gefilterd en het profiel-laadscherm; waar comp en mockup elkaar raken wint de mockup. De hashes
  staan in `SHA256SUMS` in die map.
- [ios-unified-2026-audit.md](ios-unified-2026-audit.md): tokens, navigatie en de beslispunten.
  Bevroren. De twee open Home-details uit paragraaf 10 zijn gesloten door
  [DEC-110](DECISIONS.md#dec-110).
- Waar een northstar bestaat, komt er geen nieuw ontwerp. Een zichtbare afwijking vraagt een DEC.
- De iPad is een regressiegrens. Hij houdt zijn bestaande presentatie (DEC-103); een iPad-redesign
  is een eigen traject met een eigen northstar en hoort hier niet bij.

De indeling in fase 4 tot en met 9 uit `ios-unified-2026-fase1-plan.md` (sectie SURFACE
IMPLEMENTATION) is vervangen door de werkvolgorde van de closure. Fase 1 tot en met 3 zijn gebouwd
en in PR #5 op `main` gekomen (`70ec21b5`). `feat/netflix-mobile` wordt niet gemerged
([DEC-106](DECISIONS.md#dec-106)).

## Schermen

Nummering volgt `docs/assets/ios-unified/northstar/`. De kolom "Closure" noemt het workitem uit de
werkvolgorde.

| nr | Scherm | Status | CODE | VERIFY/SIM | HARDWARE | Closure |
|---|---|---|---|---|---|---|
| 01 | Series-landing | IN PROGRESS | `mobile_landing_screen.dart`, DEC-104 | scenario `ios.landing.northstar` bestaat; geen groene run met bundel en SHA vastgelegd | n.v.t. | 15 |
| 02 | Films-landing | IN PROGRESS | zelfde scherm als 01 | het scenario raakt 02 alleen indirect | n.v.t. | 15 |
| 03 | Alle films | IN PROGRESS | `mobile_catalog_screen.dart`, DEC-105, CAT9 `3b0a9b65` | scenario `ios.catalog.northstar` bestaat; geen groene run vastgelegd | n.v.t. | 15 |
| 04 | Filtersheet | IN PROGRESS | `mobile_catalog_filters_sheet.dart` en `mobile_catalog_sort_sheet.dart`; eigen widgettest ontbreekt | open | n.v.t. | 15 |
| 05 | Zoeken | CODE/SIM CLOSED · HARDWARE OPEN | `search_screen.dart` (mobiele sectie-UI), `PersonSearchClient` in Plex/Jellyfin (SRCH-2), DEC-112, `b5b8f0e8`, automation-IDs en playlist-routefix `f86e558a`, `/v1/input/text`-endpoint `52cc06ab` | handmatige simulatorscreenshot tegen 05-zoeken.png (11 sep 2026): header/chevron/zoekbalk/filterchips/sectiekaarten kloppen met de northstar; Jellyfin-personenpad live bevestigd tegen Pleya Demo. `search.results.section[<id>]`/`search.results.item[<id>.<index>]` automation-IDs toegevoegd op alle zeven secties (`f86e558a`). Widgettests dekken nu activatie vanuit alle zeven resultaatgroepen (movies/shows via `_mobileGroupRow`, episodes apart bewezen, collections, playlists, people/SRCH-2, other): 23 tests groen in `test/screens/search_screen_test.dart`. Het schrijven van de playlist-test legde een echte bug bloot: `navigateToMediaItem` had geen `MediaKind.playlist`-tak, dus een zoekresultaat (een kale `MediaItem`, nooit de echte `MediaPlaylist`) viel door naar `default` en opende de film/serie-detailpagina in plaats van `PlaylistDetailScreen`. Gefixt door de echte `MediaPlaylist` op te halen via de bestaande `fetchPlaylistMetadata`-capability vóór het pushen. **ios-sim Verify niet langer geblokkeerd**: `/v1/input/text` (`52cc06ab`) laat `IosSimulatorDriver`/`MacosDriver` een `TextEditingController` van het gefocuste veld vullen, dezelfde techniek als `tv_virtual_keyboard.dart`, want een synthetische toetsdruk bereikt het IME-kanaal van een `EditableText` niet. Groene run `pleya_verify/scenarios/ios.search.text-input.yaml` op `52cc06ab`: tikken op `home.header.search`, typen van "aurora" via de transport, en het fixture-resultaat "Aurora (2021)" verschijnt in `search.results.section[movies]`, bundel in `.build/pleya-verify/ios-search-text-input-1789140338485/` (niet gecommit, `.build/` is gitignored), inclusief screenshot. Onderweg bleek de eerste run zonder de gebruikelijke 3500ms-settle na `wait_until: screen.discover` (zie `ios.home.northstar.yaml`) te falen: de `search`-tab is `onlineOnly`, en `_selectTab` filtert hem stilzwijgend weg zolang de offline-check nog niet is opgelost, dus een tap direct na het laden no-opt. Geen app-bug, wel een scenario-les. **Nog open: HARDWARE**, geen device-run op een genoemde build (n.v.t. tot een TestFlight-build met deze commit erin zit) | HARDWARE OPEN | 2 (I4) |
| 06 | Filmdetail | OPEN | `media_detail_screen.dart`; DEC-109 geldt alleen voor TV | open | n.v.t. | 5 (I6) |
| 07 | Seriedetail met afleveringen | OPEN | idem | open | n.v.t. | 5 (I6) |
| 08 | Bronkeuze-sheet | CODE CLOSED · VERIFY/SIM OPEN | `mobile_source_picker_sheet.dart` met test; `mobile_media_source_picker_route.dart` (`68f98bbb`) neemt de groep nu via `openMobileMediaGroup` tot aan `navigateToMediaItemDetails`/`navigateToMediaItem` op alle vier detail-call-sites (Home, Alle films/series, de landing, Zoeken), plus "Wijzigen" en de playback-failure re-entry | widgettests groen (`mobile_activation_test.dart`, `search_screen_test.dart`); geen ios-sim Verify-run tegen `08-bronkeuze-sheet.png` vastgelegd | n.v.t. | 4 (I5) |
| 09 | Contextmenu-sheet | CODE CLOSED · VERIFY/SIM OPEN | `mobile_unified_context_menu.dart` (`025b400b`) hergebruikt `UnifiedGroupAction`/`runUnifiedGroupAction` uit de tvOS-kant; `_RailCardCell` (`mobile_media_rail.dart`) is de enige call site die vandaag al een group in scope had, op de nieuwe sheet overgezet | widgettest groen (`mobile_media_rail_test.dart`, long-press opent de groepsbewuste sheet); geen ios-sim Verify-run tegen `09-contextmenu-sheet.png` vastgelegd | n.v.t. | 4 (I5) |
| 10 | Live TV | OPEN | `live_tv_screen.dart` | open | n.v.t. | 11 (I9a) |
| 11 | Mijn lijst | OPEN | `watchlist_screen.dart` | open | n.v.t. | 8 (I7) |
| 12 | Downloads | OPEN | `downloads_screen.dart` | open | n.v.t. | 8 (I7) |
| 13 | Meldingen | OPEN | bestaat niet (audit 4.5) | open | n.v.t. | 8 (I7) |
| 14 | Instellingen | OPEN | `settings_screen.dart` | open | n.v.t. | 8 (I7) |
| 15 | Bibliotheken | CODE/SIM CLOSED · VERIFY/SIM OPEN | `mobile_libraries_screen.dart` (nieuw, DEC-114), `main_screen.dart` `when _isPhone` | widgettests groen (`mobile_libraries_screen_test.dart`: kaartraster, serverfilterchips, verborgen bibliotheken, Bewerken, terugknop, tik-naar-`LibrariesScreen`); geen ios-sim Verify-run tegen `15-bibliotheken.png` vastgelegd | n.v.t. | 8 (I7) |
| 16 | Profiel kiezen | OPEN | `profile_switch_screen.dart` | open | open: PIN en wisselen op een iPhone | 10 (I8) |
| 17 | Inloggen | OPEN | `auth_screen.dart` | open | open: eerste start op een iPhone | 10 (I8) |
| 18 | Mijn Pleya volledig | CODE CLOSED · VERIFY/SIM OPEN | `my_pleya_screen.dart`, kaartrijen en `ServersScreen` naar northstar 18, DEC-113, `4eb138bc` | widgettests groen (`my_pleya_screen_test.dart`, TV-regressie in `tv_my_pleya_screen_test.dart` meegecheckt); geen ios-sim Verify-run tegen `18-mijn-pleya-volledig.png` vastgelegd | n.v.t. | 8 (I7) |
| 19 | Aanvragen | OPEN | `seerr_discover_screen.dart`; DEC-108 geldt alleen voor TV | open | n.v.t. | 8 (I7) |
| 20 | Speler | OPEN | `mobile_video_controls.dart` | open | open: afspelen in landschap | 12 (I9b) |
| 21 | Activiteit | OPEN | mobiel alleen een sheet uit de Home-header (goedgekeurde afwijking, audit 9a) | open | n.v.t. | 8 (I7) |

## Comps en Home-besluiten

| ID | Onderwerp | Status | CODE | VERIFY/SIM | Closure |
|---|---|---|---|---|---|
| home-comp, home-comp-gefilterd | Home | IN PROGRESS | `mobile_home_screen.dart`, DEC-102, DEC-103 | scenario `ios.home.northstar` bestaat; geen groene run vastgelegd | 15, 16 |
| profiel-laden-comp | profiel laden | OPEN | | | 10 (I8) |
| serie-detail-comp | seriedetail | OPEN | | | 5 (I6) |
| mijn-pleya-comp | Mijn Pleya | OPEN | | | 8 (I7) |
| IOS-HOME-AB | secundaire hero-CTA en carouselindicator volgens DEC-110 | OPEN | A staat al op `moreInfo` (`mobile_hero_actions.dart:25`); B staat op `persistentDots` (`mobile_hero_indicator.dart:30`) en moet naar de segmentindicator | n.v.t. | 14 |

## Bijhouden

Een rij verandert alleen met een SHA en het bewijs per soort erbij, volgens de bewijsregel in de
closure. Een rij verdwijnt alleen door een eindstatus.

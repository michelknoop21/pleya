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
| 05 | Zoeken | CODE CLOSED · VERIFY/SIM OPEN | `search_screen.dart` (mobiele sectie-UI), `PersonSearchClient` in Plex/Jellyfin (SRCH-2), DEC-112, `b5b8f0e8` | handmatige simulatorscreenshot tegen 05-zoeken.png (11 sep 2026): header/chevron/zoekbalk/filterchips/sectiekaarten kloppen met de northstar; Jellyfin-personenpad live bevestigd tegen Pleya Demo. Geen Pleya Verify-scenario: `search_screen.dart` heeft nul automation-IDs, dat is eigen instrumentatiewerk | n.v.t. | 2 (I4) |
| 06 | Filmdetail | OPEN | `media_detail_screen.dart`; DEC-109 geldt alleen voor TV | open | n.v.t. | 5 (I6) |
| 07 | Seriedetail met afleveringen | OPEN | idem | open | n.v.t. | 5 (I6) |
| 08 | Bronkeuze-sheet | IN PROGRESS | `mobile_source_picker_sheet.dart` met test, alleen bereikbaar vanaf Play op Home | open | n.v.t. | 4 (I5) |
| 09 | Contextmenu-sheet | OPEN | legacy `MediaContextMenu` via `mobile_media_rail.dart:171` | open | n.v.t. | 4 (I5) |
| 10 | Live TV | OPEN | `live_tv_screen.dart` | open | n.v.t. | 11 (I9a) |
| 11 | Mijn lijst | OPEN | `watchlist_screen.dart` | open | n.v.t. | 8 (I7) |
| 12 | Downloads | OPEN | `downloads_screen.dart` | open | n.v.t. | 8 (I7) |
| 13 | Meldingen | OPEN | bestaat niet (audit 4.5) | open | n.v.t. | 8 (I7) |
| 14 | Instellingen | OPEN | `settings_screen.dart` | open | n.v.t. | 8 (I7) |
| 15 | Bibliotheken | OPEN | alleen verhuisd naar Mijn Pleya, `my_pleya_screen.dart:83-93` | open | n.v.t. | 8 (I7) |
| 16 | Profiel kiezen | OPEN | `profile_switch_screen.dart` | open | open: PIN en wisselen op een iPhone | 10 (I8) |
| 17 | Inloggen | OPEN | `auth_screen.dart` | open | open: eerste start op een iPhone | 10 (I8) |
| 18 | Mijn Pleya volledig | OPEN | `my_pleya_screen.dart`, nog kale lijstrijen | open | n.v.t. | 8 (I7) |
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

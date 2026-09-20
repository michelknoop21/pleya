# B. Dependency map

## B.1 Stromen en hun impact op Pleya Server

Classificatie: **hard** (Pleya Server kan niet af zonder), **zacht** (raakt elkaar, geen
blokkade), **design-authority** (bepaalt hoe iets eruitziet, niet wat de server doet),
**onafhankelijk**, **conflictrisico** (dezelfde bestanden of nummers).

| Stroom | Branch / commit | Server | Web | Protocol | Database | Directe afhankelijkheid | Classificatie | Actie in dit traject |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pleya Server PS-4 tot PS-9 | `feat/pleyaserver` `5eebb83` | eigenaar | eigenaar (`schema.d.ts`) | eigenaar, venster dicht | 7 migraties, schema 7 | `main` voor `ServerCapabilities.userRating` en `OfflineActionType.removedFromContinueWatching` | hard, conflictrisico | S0: integratiebranch, conflicten op `server_capabilities.dart`, `profile.dart`, `pleya_wire.dart`, hergenereren `profile.freezed.dart` en `app_database.g.dart` |
| Pleya Unified TV 2026 | in `main` (`4f398be` tot `95e21b3`) | nee | nee | nee | ja: `OfflineActionType` | wijzigt `pleya_server_capabilities.dart`, `parts/browse.dart`, `parts/unsupported.dart` | hard | S0 merge; S14 vult `userRating`-resolutie voor Pleya Server (nee, tot PS-9P) |
| iOS Unified 2026 | `feat/netflix-mobile` `cf256fb` | nee | nee | nee | nee | zelfde unified-laag als main; DEC-090 is web-authority voor de mobiele breedte | design-authority, conflictrisico (DEC 091, 093, 094, 095) | niets mergen; northstar volgt de set; DEC-hernummering bij hun merge |
| E-books client | `feat/ebooks` `5d6ab71` | nee | nee | wacht op `LibraryKind: books`, `capabilities.ebooks`, `/ebooks` | nee | S3 levert het contract dat `BooksSource` nodig heeft | hard (contract), conflictrisico (`navigation_tabs.dart`, `main_screen.dart` met netflix-mobile) | S14 vervangt `DemoBooksSource` door `PleyaServerBooksSource`; navigatieconflict blijft hun merge |
| E-books server (PS-14, 15, 16) | niet gestart; ontwerp in `docs/pleya-server-ps14-proposal.md` | ja | ja | ja, achter een venster | ja | PS-9 gesloten, dus vrij te geven | design-authority | S3 en S6 voeren PS-14 en het servergedeelte van PS-15 uit |
| Unified Search | in `main`, `search_projection.dart` | nee | nee | nee | nee | roept `searchItems()` per backend; Pleya stuurt geen `kind` | zacht | S5 geeft de server `filters`; de web-search is gesectioneerd zonder projectie (RB-5) |
| tvOS 10-foot design authority | in `main`, `docs/tvos-unified-experience.md`, mockups 09-26 | nee | nee | nee | nee | gedeelde tokens en TV-conventies (topnav, hero, chips) | design-authority | web-northstar volgt de TV-topnav op ≥900 (RB-1) |
| Pleya Verify | in `main`, `pleya_verify/` | consument: `pleya_fake_server.dart` spreekt `/pleya/v1` | nee | consument | nee | elke protocolwijziging moet in de fake mee | hard (één richting) | S0: contracttest fake-server tegen `openapi.yaml`; L: Verify voor cross-client |
| Navigatieregistry (`tv_content_route_registry`, DEC-091 main) | in `main` | nee | nee | nee | nee | `feat/ebooks` splitst `navigation_tab_id.dart`, netflix-mobile voegt `mobile_shell_scope` toe | conflictrisico | buiten dit traject; S14 raakt navigatie niet |
| PS-5 DeviceCapabilities | in `feat/pleyaserver`, code complete | nee | nee | nee (spec h19) | nee | criterium 4 open, DEC-097 | zacht, open releasegate | N: hardwareronde vóór publieke release; blokkeert de slices niet |
| CarPlay | bestaat niet | nee | nee | nee | nee | zou `MediaServerClient` en hubs hergebruiken | onafhankelijk | niets |
| Relay `server/` | in beide | andere server (`ice.pleya.app`) | nee | nee | nee | los | onafhankelijk | niets |
| `worktree-pleya-web-ps4e` | `4368635` | subset | subset | subset | subset | ingehaald | onafhankelijk | opruimen |
| Losse fixes, backup-branches, `unlazy-safe`-commits | diverse | nee | nee | nee | nee | ruis | onafhankelijk | niets |

Twee stromen die alleen conceptueel gelijk moeten blijven en niets delen in code: de TV-shell
(Flutter, `lib/screens/tv/`) en de webshell (Svelte). Ze delen tokens via
`pleya_web/src/styles/tokens.css`, dat per regel naar `mono_theme.dart` verwijst, en verder niets.
Dat is de bedoeling (DEC-046: Pleya Web is een protocolclient).

## B.2 Oud Pleya Server-plan versus de code van vandaag

Per domein: wat het plan aannam, wat de code doet, welke nieuwe afhankelijkheid er sinds die
tijd is, en wat dat voor het masterplan betekent.

| Domein | Oude aanname (plan 21 augustus, roadmap h23) | Code op `5eebb83` | Nieuwe afhankelijkheid | Gevolg |
| --- | --- | --- | --- | --- |
| Endpoints | 24 paden na PS-9 | 24 paden, 28 routes incl. `/healthz`, `/readyz`, SPA-fallback (`server.go:92-165`) | northstar vraagt beheer-, boeken-, filter- en leesvoortgangsresources | additief venster per slice (deel J) |
| Auth | setupcode, owner, refreshrotatie | plus 4 rollen, sessies per toestel, in-process intrekking per 64 KiB-blok, `/auth/refresh` zonder rate limit | web-admin vraagt niets extra aan auth | S1 voegt `administration`-capability en admin-klassetest per route toe; refresh-limiter in S15 |
| Users | PS-9 API, scherm in PS-11A | 5 endpoints, per request rol uit DB, 404 voor alles wat je niet mag zien | northstar 26 en 27 | S10 bouwt de schermen; geen API-wijziging behalve "eigen account-id" (deel J) |
| Libraries | env-only, CRUD in PS-11A | `syncLibraries` uit `PLEYA_SERVER_LIBRARIES`, `kind IN ('movies','shows')` | Boeken als derde soort; northstar 21, 22, 42 | S2 (CRUD, `managed`), S3 (`books`) |
| Storage locations | intern, `mounts`-pakket meet inodevertrouwen | tabel plus `statfs_linux.go`; niet over HTTP | northstar 24, 41 | S2: `GET /storage/roots` uit de mounts, nooit uit invoer |
| Catalogus | file, version, item, streams | zoals ontworpen; `content_fingerprint` dood | boeken passen niet in `media_*` (DEC-107) | S3: `publications` en `publication_files`; `media_*` blijft audiovisueel |
| Scanner | drie lagen, inode en signatuur | zoals ontworpen; `probe_attempts` wordt niet gelezen; geen `.nfo` | EPUB-analyse per bibliotheeksoort; sidecars | S3 dispatch per soort; S4 sidecars; S2 begrensde backoff |
| Search | ILIKE, meten eerst | ILIKE zonder index, geen scores, geen soortveld | northstar 06 sectioneert per soort incl. Boeken en Auteurs | S5: `pg_trgm`, `/ebooks?q=`; geen gedeelde projectie op de server (RB-5) |
| Artwork | PS-7A uitgesteld | `width` niet gelezen, geen cache, `CacheDir` ongebruikt | 8-koloms raster op 1600, DPR 2 op 393 | S4: PS-7A verplicht (RB-7) |
| Streaming | direct play, range, streamsessies | zoals ontworpen; verlopen `stream_sessions` worden nooit opgeruimd | browserspeler (PS-4W) | S13 speler; S15 opruimjob |
| Watch-state | DEC-049 lease en revisie | zoals ontworpen | leesvoortgang is geen kijkstatus (DEC-107) | S6: eigen `reading_states` (RB-4) |
| Continue watching, next up | leeg tot PS-4-defect | gerepareerd in `2c214fd`, `store_hubs.go` | web-e2e asserteert nog de lege staat | S8: PS-4E, test omdraaien |
| Capabilities | 13 vlaggen, alle eerlijk | klopt (deel F, 11) | `administration`, `ebooks`, `filters`, `reading_state` | deel J; `feature_level` blijft 1 |
| Webbundel | embed in de binary | `//go:embed all:dist`, releasebuild faalt zonder bundel | ongewijzigd | S7 bouwt in dezelfde `dist/` |
| Serverbeheer | PS-11A: 6 routes | niets | northstar 20 tot 33 | S1, S2, S10 |
| Settings | env-only | env-only, niets in DB | northstar 28, 30, 31 | S1: `server_settings`; grens host versus server in RB-16 |
| Database | 7 migraties | 7, checksums, advisory lock | boeken, settings, leesvoortgang, sidecars, `managed` | deel J: migraties 0008 tot 0013 |
| Tests | 237 Go, 112 web-unit, 28 e2e | kloppen; geen CI | Verify-fake spreekt het protocol zonder contracttest | S0: CI plus fake-contracttest |

## B.3 Oude fasen: stand en oordeel

| Fase | Stand | Oordeel in dit traject |
| --- | --- | --- |
| PS-0 tot PS-4, PS-3W, PS-9 | gesloten | klaar; blijven bevroren |
| PS-5 | code complete, criterium 4 open | zacht; hardwareronde hoort bij release (N) |
| PS-4E | niet gestart | opgaan in S8 met de northstar als authority in plaats van app-screenshots |
| PS-4W | niet gestart, geknipt door DEC-106 | S13, met één extra mockup (speler) vóór de bouw |
| PS-7N | niet gestart, gate 80% | S4; de gate wordt zichtbaar in beheer (northstar 29) |
| PS-7A | niet gestart, uitgesteld | S4, verplicht (RB-7); dekt ook boekcovers |
| PS-7 | niet gestart | S22: providerladder met TMDB, automatisch matchen en automatisch inladen van metadata en artwork; handmatige correctie overleeft drie rondes |
| PS-7F | niet gestart | S5 gedeeltelijk: filters, facetten, sortering; alfabalk uitgesteld tot na meting |
| PS-11A | niet gestart, definitie in masterplan 16.3 | S1, S2, S10, S11; met de settings-grens uit RB-16 |
| PS-11 | niet gestart | S24: proxy-gedrag, rate limits, metrics op loopback, publieke-endpointlijst als test |
| PS-11R | niet gestart | S21: websocket-hub met volgnummers; polling blijft de correcte weg |
| PS-11B | niet gestart | S25: back-up met hersteltest, restore, upgrade over twee schemaversies, faalpaden als set (northstar 35) |
| PS-14 | goedgekeurd, niet vrijgegeven | S3, vrijgave is een besluit bij S0 |
| PS-15 | begrensd | servergedeelte in S6, webreader in S12; de app-reader blijft op `feat/ebooks` |
| PS-16 | gereserveerd | buiten scope |
| PS-6 | niet gestart | S17: `POST /playback/plan` met de DeviceCapabilities uit PS-5 |
| PS-8 | niet gestart | S18: remux en transcode met sessielevenscyclus, fMP4 en HLS, hardwareversnelling; browserspeler krijgt hls.js |
| PS-10 | niet gestart | S23: downloads naar de app met digest en sync-back |
| PS-9C | niet gestart | S19: verzamelingen en afspeellijsten (northstar 17, 18) |
| PS-9P, PS-9T | niet gestart | S20: geschiedenis, favorieten, waarderingen, spoorvoorkeuren (northstar 19) |
| PS-12 | niet gestart | **keuzefase na afronding**, nooit automatisch; ontwerp blijft hoofdstuk 19 en de fasetabel |
| PS-13, PS-16 | niet gestart | buiten scope |

De oude PS-nummers blijven de naam van de fasen in `docs/pleya-server-architecture.md`. De
slices in deel I zijn de uitvoeringseenheden en verwijzen naar de PS-nummers die ze dekken.

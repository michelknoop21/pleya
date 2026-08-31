# Edge-case register: Pleya Unified TV 2026

Bron: [docs/tvos-unified-experience.md](../tvos-unified-experience.md) hoofdstuk 26. Dit bestand is
het afvinkbare register; het architectuurdocument houdt alleen de regels en de categorieën.

**Regels.**

- Iedere rij krijgt een unit-, widget-, integratie- of hardwaretest voordat hij op `covered` mag.
- Een nieuw ontdekte situatie zonder expliciet gedrag is een releaseblocker: eerst het gedrag
  vastleggen (in het architectuurdocument of een DEC), dan pas hier een rij toevoegen of aanpassen.
- Status is één van: `open` (nog geen test), `covered` (test bestaat en is groen — vul de
  vindplaats in), `n.v.t.` (met reden, nooit stilzwijgend geschrapt).
- Categorieën volgen geen vaste fase-toewijzing behalve waar het architectuurdocument dat expliciet
  zegt (register C is minimaal vereist in fase 1, zie hoofdstuk 27). Een fase mag een deelverzameling
  afvinken; het register als geheel sluit pas bij de laatste fase die het raakt.
- Rijen worden nooit verwijderd. Een geschrapt scenario gaat naar `n.v.t.` met een korte reden.

Bijgewerkt: 2026-08-31 (fase 6 afgerond). Aangemaakt in fase 0. Fase 1 (unified identity foundation) dekt register C
(C1-C24) volledig af — zie de vindplaatsen in de tabel hieronder. De overige categorieën blijven
`open` tot de fase die ze raakt.

**Fase 4 en register F.** Fase 4 was intern gesplitst in een headless deel (activation coordinator,
ranking, voorkeur, cancellation) en een GUI-deel (de source picker zelf). Het headless deel bewees
per case *het besluit*; of de gebruiker dat besluit ook ziet en met de afstandsbediening kan bedienen
was pas bewezen toen de picker-widgettests er waren. Beide helften staan er nu, dus register F is
gesloten op F19 na — dat scenario heeft nog geen vastgelegd productgedrag en is niet zelf ingevuld.

F21 is in fase 4 toegevoegd: de voorkeursserver van hoofdstuk 14.8a mag zélf een bron kiezen, en dat
is een nieuw scenario met eigen gedrag, geen herformulering van een bestaand. De regel bovenaan
schrijft voor dat gedrag eerst wordt vastgelegd — dat is gebeurd in 14.8a — en pas daarna een rij.

**Fase 5 en de nagelopen rijen.** Fase 5 bouwde Films en Series, en daarmee de merge, de paging, de
filters en het raster. Bij het sluiten is het register nagelopen tegen álles wat er sinds fase 1 aan
tests bij is gekomen: vierentwintig rijen in A, B, D, E, I en J bleken al bewezen en waren alleen
nooit ingevuld. Er is voor die rijen geen test bijgeschreven, alleen de vindplaats opgezocht en de
test gelezen. Een rij die niet precies het scenario van die rij bewijst is `open` gebleven, ook waar
een test er dichtbij kwam; een te optimistisch register is erger dan een leeg.

**Hardware.** J2 (4K-output), J4 (overscan), J8 (VoiceOver) en J9 (Reduce Motion) zijn niet in een
test vast te leggen — ze vragen een echte Apple TV. Ze staan op `open` met die reden in de
Test-kolom en horen bij de eindacceptatie na fase 10A (hoofdstuk 29), niet bij de gate van een fase.
Ze gelden dan voor de hele TV-UI, dus ook voor de schermen die er nu nog niet zijn.

## A. Server- en topologycases

| # | Case | Test | Status |
|---|---|---|---|
| A1 | Geen servers geconfigureerd | | open |
| A2 | Eén Plex-server | test/providers/unified_catalog_provider_test.dart (`ensureStarted loads the first page and settles into the snapshot`) — één Plex-client, één library, en de snapshot die de grid tekent | covered |
| A3 | Eén Jellyfin-server | | open |
| A4 | Eén Pleya Server | | open |
| A5 | Plex plus Jellyfin | | open |
| A6 | Drie of meer servers | test/services/unified_catalog_service_test.dart (`merges two libraries into one globally title-ordered stream, collapsing a shared duplicate`, drie servers in één merge); test/services/unified_catalog/source_resolver_test.dart (`the same film on three servers yields three concrete sources`) | covered |
| A7 | Twee servers met dezelfde displaynaam | test/services/unified_catalog/unified_activation_coordinator_test.dart (`F12: duplicate server names fall through to server id, then item id`); test/widgets/tv/tv_media_source_picker_test.dart (`F12: two servers with one name stay tellable apart by their library`) | covered |
| A8 | Eén server offline bij twee online servers | test/services/unified_catalog_service_test.dart (`one library erroring leaves the healthy results in place, and is retried on the next call`); test/services/unified_catalog/source_resolver_test.dart (`an offline expected server makes coverage incomplete`); test/goldens/tv_unified_catalog_golden_test.dart (`films, complete with one library missing`) voor de melding onder de grid | covered |
| A9 | Eén server met auth-error | test/services/unified_catalog/source_resolver_test.dart (`an auth-errored server is distinguished from a plain offline one`); test/services/unified_catalog/unified_activation_coordinator_test.dart (`F7: an auth error outranks offline…`); test/widgets/tv/tv_media_source_picker_test.dart (`F7: an auth error says something else than an offline server`) | covered |
| A10 | Alle servers offline | test/services/unified_catalog_service_test.dart (`every library failing on the very first round reports initialLoadFailed`); test/goldens/tv_unified_catalog_states_golden_test.dart (`films, nothing answered`) | covered |
| A11 | Server komt laat online | test/providers/unified_catalog_provider_test.dart (`a late server coming online reconciles the eligible library set`) | covered |
| A12 | Server valt weg tijdens paging | | open |
| A13 | Server valt weg in source picker | test/services/unified_catalog/unified_activation_coordinator_test.dart (`focus after a source stops being usable`, vijf tests); test/widgets/tv/tv_media_source_picker_test.dart (`F11: the focused source going offline moves focus to the nearest usable row`) | covered |
| A14 | Server valt weg tijdens detail load | | open |
| A15 | Server valt weg tijdens playerstart | | open |
| A16 | Server wordt verwijderd | | open |
| A17 | Server wordt hernoemd | | open |
| A18 | Server wordt opnieuw toegevoegd met ander ID | | open |
| A19 | Profiel verwacht server die nog geen live client heeft | | open |
| A20 | Live TV-capability komt laat binnen | | open |

## B. Librarycases

| # | Case | Test | Status |
|---|---|---|---|
| B1 | Eén movie library | test/providers/unified_catalog_provider_test.dart (`ensureStarted loads the first page and settles into the snapshot`); test/services/unified_catalog/source_cursor_test.dart (`restricts to the requested kind`) | covered |
| B2 | Meerdere movie libraries op dezelfde server | test/services/unified_catalog_service_test.dart (`paging target is a group count: it stops at groupsPerPage new groups, not a raw item count`) — twee libraries op één server, allebei in de merge | covered |
| B3 | Movie libraries op meerdere servers | test/services/unified_catalog_service_test.dart (`merges two libraries into one globally title-ordered stream, collapsing a shared duplicate`) | covered |
| B4 | Series-only profiel | | open |
| B5 | Movies-only profiel | | open |
| B6 | Mixed/shared Plex library | | open |
| B7 | Verborgen library als enige bron | test/providers/unified_catalog_provider_test.dart (`server.hidden excludes a library from the merge, matching eligibleCatalogLibraries`, `a hidden-library change after starting reconciles and reloads with the library excluded`); test/services/unified_catalog/source_cursor_test.dart (`excludes a library the user hid, even though its server is visible`) | covered |
| B8 | Verborgen library als tweede duplicate bron | | open |
| B9 | Library wordt tijdens gebruik verborgen | test/providers/unified_catalog_provider_test.dart (`a hidden-library change after starting reconciles and reloads with the library excluded`) | covered |
| B10 | Library wordt verwijderd | | open |
| B11 | Library heeft geen items | | open |
| B12 | Library fetch geeft timeout | | open |
| B13 | Library antwoordt met lege pagina vóór total bereikt | | open |
| B14 | Backend herhaalt item op twee pagina's | | open |
| B15 | Item verhuist tussen libraries | | open |

## C. Identitycases

Minimaal deze categorie is vereist in fase 1 (hoofdstuk 27, `test/media/canonical_media_identity_test.dart`
en `test/services/unified_grouping_service_test.dart`).

| # | Case | Test | Status |
|---|---|---|---|
| C1 | Zelfde TMDB-ID | test/media/canonical_media_identity_test.dart (`externalIdTokens C1`); test/services/unified_grouping_service_test.dart (`C1`) | covered |
| C2 | Zelfde IMDb-ID | test/media/canonical_media_identity_test.dart (`externalIdTokens C2`) | covered |
| C3 | Zelfde TVDB-ID voor serie | test/media/canonical_media_identity_test.dart (`externalIdTokens C3`) | covered |
| C4 | Zelfde stabiele GUID | test/media/canonical_media_identity_test.dart (`normalizeStableGuid C4`, `guidTokens C4`) | covered |
| C5 | Gelijke titel en jaar zonder IDs, ondubbelzinnig | test/services/unified_grouping_service_test.dart (`two sources with no strong evidence still merge via title+year when unambiguous`) | covered |
| C6 | Gelijke titel met verschillend jaar | test/media/canonical_media_identity_test.dart (`bucketKey C6/C9`) | covered |
| C7 | Gelijke titel en jaar met conflicterende IDs | test/services/unified_grouping_service_test.dart (`C7`) | covered |
| C8 | Gelijke titel zonder jaar | test/media/canonical_media_identity_test.dart (`bucketKey C8`) | covered |
| C9 | Remake met dezelfde titel | test/services/unified_grouping_service_test.dart (`C9`); test/media/canonical_media_identity_test.dart (`bucketKey C6/C9`) | covered |
| C10 | Movie en serie met dezelfde titel | test/media/canonical_media_identity_test.dart (`bucketKey C10`, `canonicalIdentityOf C10`) | covered |
| C11 | `agents.none://` GUID | test/media/canonical_media_identity_test.dart (`normalizeStableGuid C11`, `guidTokens C11/C12`) | covered |
| C12 | Serverlokale GUID | test/media/canonical_media_identity_test.dart (`normalizeStableGuid C12`, `guidTokens C11/C12`) | covered |
| C13 | Director's Cut en theatrical edition | test/services/unified_grouping_service_test.dart (`C13`) | covered |
| C14 | Zelfde item met meerdere media versions | test/services/unified_grouping_service_test.dart (`C14`) | covered |
| C15 | Unicode, leestekens en diakritische titels | test/media/canonical_media_identity_test.dart (`bucketKey C15`) | covered |
| C16 | Alternatieve of originele titel | test/services/unified_grouping_service_test.dart (`C16`) | covered |
| C17 | Verkeerd serverjaar | test/services/unified_grouping_service_test.dart (`C17`); test/media/canonical_media_identity_test.dart (`yearAgreesWith C17`) | covered |
| C18 | Eén bron heeft jaar, andere niet | test/media/canonical_media_identity_test.dart (`yearAgreesWith C18`) | covered |
| C19 | Meerdere kandidaten op één server | test/services/unified_grouping_service_test.dart (`C19`) | covered |
| C20 | External-ID-fetch faalt | test/services/unified_catalog/identity_resolver_test.dart (`C20`) | covered |
| C21 | External IDs veranderen na metadata-refresh | test/services/unified_catalog/identity_resolver_test.dart (`C21`) | covered |
| C22 | Group krijgt later sterker bewijs | test/services/unified_grouping_service_test.dart (`C22`) — alleen inhoudelijke stabiliteit; sessie-stabiliteit van `groupId` volgt pas met fase 3's `UnifiedCatalogProvider` | covered |
| C23 | Groupingconflict in een connected component | test/services/unified_grouping_service_test.dart (`C23`) | covered |
| C24 | Pleya Server/local item zonder external IDs | test/media/canonical_media_identity_test.dart (`externalIdTokens C24`); test/services/unified_grouping_service_test.dart (`C24`) | covered |

## D. Series- en episodecases

| # | Case | Test | Status |
|---|---|---|---|
| D1 | Zelfde serie op twee servers | test/providers/tv_discovery_landing_provider_test.dart (`one series watched on two servers is one card carrying both concrete episodes`) — één kaart, twee bronnen, en de bronnen blijven de concrete afleveringen die elke server zelf heeft (S1E3 naast S2E7); test/services/unified_catalog/home_projection_service_test.dart (`a group's sources stay the concrete resumable episodes, never a series item`) voor dezelfde regel op serviceniveau | covered |
| D2 | Verschillende seizoensdekking | | open |
| D3 | Zelfde episode met sterke ID | | open |
| D4 | Zelfde episode via serie-ID plus S/E | | open |
| D5 | Specials seizoen 0 | test/media/canonical_media_identity_test.dart (`D5: season 0 (specials) is a real, distinct, bucketable season index`) | covered |
| D6 | Ontbrekend seizoennummer | test/media/canonical_media_identity_test.dart (`D6/D7: a missing season or episode index makes the episode bucket unusable`, `D6: an episode missing its season index has no bucketable identity`) | covered |
| D7 | Ontbrekend afleveringsnummer | test/media/canonical_media_identity_test.dart (`D6/D7: a missing season or episode index makes the episode bucket unusable`) | covered |
| D8 | Double episode | | open |
| D9 | Absolute numbering versus season numbering | | open |
| D10 | Eén bron loopt één aflevering achter | | open |
| D11 | Next Episode alleen op andere bron | | open |
| D12 | Verschillende editions/runtimes van aflevering | | open |
| D13 | Show watched count verschilt | | open |
| D14 | Bronwissel op open seriesdetail | | open |
| D15 | Nieuwe episode verschijnt terwijl details openstaat | | open |

## E. Paginationcases

| # | Case | Test | Status |
|---|---|---|---|
| E1 | Bronnen met verschillende page sizes | | open |
| E2 | Eén bron veel groter dan de andere | | open |
| E3 | Veel duplicates waardoor één fetchronde weinig groups oplevert | test/services/unified_catalog_service_test.dart (`paging target is a group count: it stops at groupsPerPage new groups, not a raw item count`) — vier ruwe items voor twee groups | covered |
| E4 | Duplicate verschijnt pas veel pagina's later | test/services/unified_catalog_service_test.dart (`a duplicate arriving many pages later merges into the existing group instead of creating a new one`) | covered |
| E5 | Eén bron is veel trager | | open |
| E6 | Eén bron faalt na eerdere succesvolle pagina's | | open |
| E7 | Total ontbreekt | | open |
| E8 | Total verandert tijdens paging | | open |
| E9 | Sort key ontbreekt | test/services/unified_catalog/unified_catalog_query_test.dart (`release-date sort sinks a dateless item to the end regardless of direction`, `addedAt sort sinks a missing value to the end`, `recentlyWatched sort compares lastViewedAt, missing sinks to the end`) | covered |
| E10 | Sort key verschilt tussen duplicate sources | | open |
| E11 | Query verandert met requests in flight | test/services/unified_catalog_service_test.dart (`a stale in-flight fetch from before a query change never lands in the new state`) | covered |
| E12 | Profiel wisselt met requests in flight | | open |
| E13 | Filter verwijdert de gefocuste group | | open |
| E14 | Late merge zou zichtbare sortpositie wijzigen | | open |
| E15 | Bron geeft dezelfde source twee keer terug | | open |

## F. Source-pickercases

`ACT` = test/services/unified_catalog/unified_activation_coordinator_test.dart.
`RES` = test/services/unified_catalog/source_resolver_test.dart.
`PREF` = test/services/unified_catalog/source_preference_store_test.dart.
`PICK` = test/widgets/tv/tv_media_source_picker_test.dart.
`ROW` = test/widgets/tv/tv_source_row_descriptor_test.dart.
`GOLD` = test/goldens/tv_media_source_picker_golden_test.dart.

| # | Case | Test | Status |
|---|---|---|---|
| F1 | Eén source | ACT (`F1: exactly one online source skips the picker and routes directly`) — de picker gaat niet open, dus er is geen visueel deel meer | covered |
| F2 | Twee sources | ACT (`F2: two online sources open the picker`) plus PICK (`the row the coordinator named is the one that starts focused`, `Select activates exactly the focused source, not its neighbour`) en GOLD (`two online sources`) | covered |
| F3 | Tien sources met scroll | PICK (`F10: a late source lands at the bottom without moving the focus`) bewijst het groeien; de lijst scrollt binnen het paneel en vervaagt aan de rand die nog inhoud heeft (GOLD `mixed states`) | covered |
| F4 | Alle sources online | ACT (`F4/F9: the route context carries coverage and every source key`, plus de ranking-groep) en PICK (`complete coverage says nothing about unchecked servers`) | covered |
| F5 | Eén source offline | ACT (`F5/14.6: one online source plus an offline one still skips the picker`) — de picker gaat niet open | covered |
| F6 | Alle sources offline | ACT (`F6: every source offline reports allOffline, keeping all rows`, `F6: with nothing online there is still a focused row`) en PICK (`with nothing reachable the two panel actions appear and take the focus`, beide headline-tests) plus GOLD (`nothing reachable`) | covered |
| F7 | Auth-error | ACT (`F7: an auth error outranks offline…`), ROW (`an unusable row says why, and outranks every other marking`) en PICK (`F7: an auth error says something else than an offline server`) | covered |
| F8 | Coverage nog bezig | RES (`cancellation (hoofdstuk 14.5)`, vier tests) en PICK (`F8: the resolving line shows without blocking the list`) plus GOLD (`still resolving`) | covered |
| F9 | Coverage incompleet | ACT (`F4/F9: …`), RES (`a cancelled run reports the servers it never reached as unchecked`) en PICK (`F9: partial coverage is stated in the header`) | covered |
| F10 | Nieuwe source arriveert terwijl modal open is | ACT (`F10: sources arriving while the modal is open`, vier tests) en PICK (`F10: a late source lands at the bottom without moving the focus`) | covered |
| F11 | Source verdwijnt terwijl modal open is | ACT (`focus after a source stops being usable`, vijf tests) en PICK (`F11: the focused source going offline moves focus to the nearest usable row`) | covered |
| F12 | Duplicaatservernamen | ACT (`F12: duplicate server names fall through to server id, then item id`) en PICK (`F12: two servers with one name stay tellable apart by their library`) | covered |
| F13 | Geen quality metadata | ROW (`F13: a source with no media versions has no quality line at all`, plus de hele `quality line`-groep) en PICK (`F13: a source with no quality metadata simply has one line fewer`) | covered |
| F14 | Afwijkende editions | ROW (`context line`-groep: edition, library en backend worden alleen getoond wanneer ze bestaan) en GOLD (`two online sources`, met Director's Cut) | covered |
| F15 | Afwijkende progress | ACT (`F15: with no remembered source, the most recent progress takes focus`) en ROW (`progress`-groep, vier tests) | covered |
| F16 | Last-used source offline | ACT (`F16: an offline remembered source falls back…`), PREF en PICK (`F16: an offline remembered source is not focused and is not marked`) | covered |
| F17 | Cancel | test/diagnostics/select_trace_test.dart (`a picker cancel that opened nothing is ordinary, not an anomaly`) en PICK (`Menu closes the picker, activates nothing, and restores the exact CTA`) | covered |
| F18 | Playerstart faalt | ACT (`F18: playback failure offers an alternative but never takes it`, vijf tests) en PICK (`offers a choice and a way out, and takes neither by itself`) plus GOLD (`playback failure alternative`) | covered |
| F19 | Detailroute faalt | gedrag nog niet vastgelegd in hoofdstuk 15 — niet zelf ingevuld, zie de regel bovenaan dit bestand | open |
| F20 | Terugkeer behoudt focus | PICK (`Menu closes the picker, activates nothing, and restores the exact CTA`) — de overlay geeft de focus terug aan exact de node die hem had | covered |
| F21 | Voorkeursserver kiest zelf (14.8a) | ACT (`preferred server (profile default)` elf tests + `the preferred server is global to the profile, not per title` acht tests, incl. de A-t/m-G-tabel uit 14.8a), test/services/unified_catalog/preferred_server_store_test.dart (elf tests, incl. de sleutelvorm) en PICK (`the preferred server can be set from here`, `explicit source selection bypasses the global preference`) | covered |

## G. Watch-statecases

| # | Case | Test | Status |
|---|---|---|---|
| G1 | Eén actieve progress | | open |
| G2 | Twee verschillende progressposities | | open |
| G3 | Oudere bron heeft hogere progress | | open |
| G4 | Nieuwere bron is watched | | open |
| G5 | Clock skew | | open |
| G6 | Geen timestamps | | open |
| G7 | Verschillende runtimes | | open |
| G8 | Scrobble race | | open |
| G9 | Playback return met null route result | test/utils/media_navigation_helper_test.dart (`onPlaybackReturned fires when the player pops null`, `onRefresh alone does not fire when the player pops null`) — `handlePlaybackReturn` is puur en heeft geen visueel deel | covered |
| G10 | Remove Continue gedeeltelijk mislukt | | open |
| G11 | Offline suppressie wordt later gereplayed | | open |
| G12 | Mark watched op één source | | open |
| G13 | Mark watched op alle sources gedeeltelijk mislukt | | open |
| G14 | Episodeprogress op verkeerde serie mag niet mergen | | open |

## H. Herocases

| # | Case | Test | Status |
|---|---|---|---|
| H1 | Clearlogo aanwezig | | open |
| H2 | Geen clearlogo | | open |
| H3 | Landscape-art | | open |
| H4 | Square-art | | open |
| H5 | Alleen poster | | open |
| H6 | Geen artwork | | open |
| H7 | Lange titel | | open |
| H8 | Geen synopsis | | open |
| H9 | Spoilers verbergen | | open |
| H10 | Watched titel | | open |
| H11 | In-progress titel | | open |
| H12 | Meerdere bronnen | test/screens/discover_screen_tv_hero_test.dart (`a mergeable duplicate becomes one slide carrying both sources`, `two concrete copies of one recent film are one hero slide, not two`) — één slide per logische titel, met beide bronnen erin, gereden door het echte `DiscoverScreen`; de tweede test legt ook vast dat een titel waarvan de identiteit niet te bewijzen is één bron houdt in plaats van er stilzwijgend een bij te verzinnen | covered |
| H13 | Source valt weg | | open |
| H14 | Hero-data komt laat | | open |
| H15 | Geen hero-kandidaten | test/screens/discover_screen_tv_hero_test.dart (`zero recent films keeps the existing hub fallback billboard`) en test/providers/tv_home_projection_provider_test.dart (`a hero with no eligible recent film is empty rather than padded from hubs`) — een lege filmpool valt terug op het bestaande on-deck/hub-billboard en wordt niet met hubs opgevuld (DEC-067) | covered |
| H16 | Alleen series beschikbaar | | open |
| H17 | Auto-rotation tijdens focus | | open |
| H18 | App gaat background | | open |
| H19 | Reduce Motion | | open |
| H20 | Light theme | | open |
| H21 | Artworkrequest faalt | | open |

## I. Navigatiecases

| # | Case | Test | Status |
|---|---|---|---|
| I1 | Cold-start focus | | open |
| I2 | Topnav naar hero | | open |
| I3 | Hero naar row | | open |
| I4 | First row terug naar hero | | open |
| I5 | Root Back naar topnav | | open |
| I6 | Topnav Back naar systeem | | open |
| I7 | Source picker Back | test/widgets/tv/tv_media_source_picker_test.dart (`Menu closes the picker, activates nothing, and restores the exact CTA`) | covered |
| I8 | Nested Mijn Pleya Back | | open |
| I9 | Profile picker Back | | open |
| I10 | Native keyboard Back | | open |
| I11 | Live TV-item verschijnt | | open |
| I12 | Live TV-item verdwijnt | | open |
| I13 | Actieve destination opnieuw selecteren | | open |
| I14 | Tab wisselen met overlay open | | open |
| I15 | Select KeyUp na focusverplaatsing | test/focus/focusable_wrapper_select_test.dart (`key-up landing on a wrapper that never saw the key-down fires nothing`); test/focus/dpad_navigator_suppressor_test.dart (`armed suppressor eats the in-flight select key-up and clears`) | covered |
| I16 | Trackpad swipe versus D-pad | | open |
| I17 | Android TV back | | open |
| I18 | Focused item verdwijnt | | open |
| I19 | Return uit player | | open |
| I20 | Return uit settings | | open |

## J. Accessibility en layoutcases

| # | Case | Test | Status |
|---|---|---|---|
| J1 | 1080p | test/goldens/tv_unified_catalog_golden_test.dart (`films, default state`, `series, default state`) en test/goldens/tv_unified_catalog_states_golden_test.dart — elke catalogusgolden rendert op het DEC-028-canvas, 1920x1080 gedeeld door 1,85 | covered |
| J2 | 4K-output | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J3 | Laagste ondersteunde TV-surface | | open |
| J4 | Overscan | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J5 | Lange vertaling | test/goldens/tv_unified_catalog_golden_test.dart (`films, labels at the length a long locale produces`, `films, long titles`) — de labels hebben de lengte van de Duitse strings; een echt omgeschakelde locale is in `flutter test` niet te renderen, want elke niet-basislocale is deferred | covered |
| J6 | Grote tekst | | open |
| J7 | RTL | test/widgets/tv/tv_unified_media_grid_test.dart (`builds under a right-to-left directionality without breaking`) bewijst dat het raster onder een omgekeerde `Directionality` bouwt, de kaarten vindt en zijn prefetch nog steeds start. Dat is een guard, geen RTL-acceptatie: geen van de zestien locales van Pleya is rechts-naar-links, dus er valt vandaag geen beeld te keuren dat een gebruiker kan bereiken | open |
| J8 | VoiceOver | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A. test/widgets/tv/tv_media_source_picker_test.dart (`a row announces its position and everything it actually shows`) en test/widgets/tv/tv_unified_media_card_semantics_test.dart leggen de semantics van een source row en van een catalogkaart vast — inclusief dat de kaart één node aanbiedt en niet titel en jaar dubbel uitspreekt — maar niet wat VoiceOver ervan maakt | open |
| J9 | Reduce Motion | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J10 | Light theme | | open |
| J11 | OLED theme | | open |
| J12 | Focusglow bij eerste/laatste card | | open |
| J13 | Panel met veel sources | | open |
| J14 | Lege panelsecties | | open |
| J15 | Selected versus focused | | open |
| J16 | Focus verandert de layout niet | test/widgets/tv/tv_unified_media_grid_test.dart (`focus moves nothing but the focused card`) — het raster is een `Column` van `Row`s en een `Row` is zo hoog als zijn hoogste kind, dus een kaart die bij focus groeit tilt zijn hele rij op en duwt de rijen eronder omlaag terwijl de gebruiker ernaar kijkt. De test legt alle negenendertig andere kaarten vast vóór en na de focus. Toegevoegd in fase 5; het gedrag zelf staat in hoofdstuk 10.2b ("ruimtelijk stabiel") | covered |

## Totaal

181 cases: A20, B15, C24, D15, E15, F21, G14, H21, I20, J16. Nul `covered` bij aanmaak (fase 0).
F21 kwam er in fase 4 bij, samen met het gedrag dat hij beschrijft (hoofdstuk 14.8a). J16 kwam er bij
het sluiten van fase 5 bij, langs dezelfde regel: het gedrag stond al vast in hoofdstuk 10.2b, de
situatie — een focus die de rij eronder verschuift — was alleen nog niet als rij benoemd.

Stand na fase 6: 73 `covered` en 108 `open`. Fase 5 sloot op 70/111; fase 6 voegt D1, H12 en H15
toe. Per categorie is dat A 8 van 20, B 5 van 15, C 24 van 24, D 4 van 15, E 4 van 15, F 20 van 21,
G 1 van 14, H 2 van 21, I 2 van 20 en J 3 van 16.

De stand na fase 5 was 70 `covered` en 111 `open`. Dat was de stand na fase 4 — C1-C24, F1-F18, F20-F21 en
G9, samen 45 rijen, hier eerder als 46 opgeteld — plus de vierentwintig rijen die fase 5 heeft
nagelopen: A2, A6-A11, A13, B1-B3, B7, B9, D5-D7, E3, E4, E9, E11, I7, I15, J1 en J5. Per categorie
is dat A 8 van 20, B 5 van 15, C 24 van 24, D 3 van 15, E 4 van 15, F 20 van 21, G 1 van 14, H 0 van
21, I 2 van 20 en J 3 van 16 — J16 meegeteld.

Register F is nog steeds volledig op één rij na: F19 (detailroute faalt) heeft nog geen vastgelegd
productgedrag en wacht daarop, niet op een test.

**Fase 6 en de drie rijen die erbij komen.** Fase 6 bouwde de discovery-landings, de unified Search
op de TV-tak, de Continue Watching-projectie en — na [DEC-067](../DECISIONS.md#dec-067) — de
gededupliceerde TV-hero. Bij het sluiten is het register nagelopen tegen wat die fase daadwerkelijk
bewijst, met dezelfde strengheid als fase 5: een rij verschuift alleen als er een test is die
precies dát scenario aantoont. Dat leverde er drie op — D1, H12 en H15 — en niet meer. Wat
nadrukkelijk `open` blijft, met reden:

- **H14 (hero-data komt laat).** De datakant is bewezen (`hasProjectedHero` en
  `projectedLatestMovies` scheiden een nog niet afgeronde projectie van een echt lege filmpool, en
  het billboard valt tijdens een koude load niet leeg), maar hoofdstuk 9.7's layoutregel — een hero
  die pas wordt toegepast wanneer Home weer bovenaan staat en er geen interactie loopt — is
  presentatie en daarmee fase-8-werk. Half bewezen is hier niet `covered`.
- **H16 (alleen series beschikbaar).** De lege-filmpool-test gebruikt een filmhub als fallback, niet
  een bibliotheek die alleen series heeft. Dat is een ander scenario.
- **G1-G8 (watch-state merge).** `every source keeps its own watch state` bewijst hoofdstuk 13.1
  (bronstate blijft intact) voor Continue Watching, maar geen van die rijen vraagt dát — ze vragen
  welke voortgang de kaart *toont* (hoofdstuk 13.2). Die keuze is niet apart vastgelegd in een test.
- **D2 (verschillende seizoensdekking).** D1's test heeft twee servers op verschillende afleveringen,
  niet twee servers met een verschillend seizoensbereik.

De overige fase-6-rijen (H1-H11, H13, H17-H21) hangen aan hero-*presentatie* en horen bij fase 8;
I1-I6 en I8-I14 hangen aan de topnav en de root-shell en horen bij fase 7.

De F-rijen dragen nu beide helften: het besluit (coordinator, resolver, stores) én het zichtbare en
met de afstandsbediening bedienbare deel (`test/widgets/tv/tv_media_source_picker_test.dart`,
`test/widgets/tv/tv_source_row_descriptor_test.dart`). De goldens in
`test/goldens/tv_media_source_picker_golden_test.dart` renderen dezelfde toestanden op het
tvOS-canvas van DEC-028; ze bewaken compositie op dit platform en vervangen geen hardwareverificatie
(hoofdstuk 29).

De rijen die fase 5 heeft ingevuld leunen op de merge-engine
(`test/services/unified_catalog_service_test.dart`) en op de provider die hem aanstuurt. Waar zo'n
rij ook een zichtbaar deel heeft staat dat ernaast: A8 en A10 wijzen naar de goldens, want een
library die niet antwoordde meldt zich onder de grid en een catalogus waar niets uit kwam vult de
hele pagina. D5-D7 zijn identityrijen en worden, net als register C, door de identiteitstests alleen
bewezen; er is nog geen serie- of afleveringscherm waar iets van te zien zou zijn.

Wat bewust `open` is gebleven, en waarom. Register H staat nog helemaal open: de hero bestaat niet,
die komt in fase 6 en 8. Register I is op twee rijen na een zaak van fase 7 (topnav en Mijn Pleya);
alleen I7 en I15 gaan over mechanismen die er nu al zijn. Register G is op G9 na open, en dat is de
zwaarste post: `selectRepresentativeWatchState` — de functie die per group beslist wélke bron de
kijkstatus levert, inclusief de klok-skew, de ontbrekende timestamps en de afwijkende runtimes uit
G5 tot en met G7 — heeft geen enkele eigen test. In A, B en E zijn de rijen die over een tweede ronde
gaan open gebleven (A12 server valt weg tijdens paging, B13 lege pagina vóór total, E6 bron faalt ná
geslaagde pagina's, E8 total verandert onderweg, E15 dezelfde source twee keer): de tests die er het
dichtst bij komen falen of stoppen in de eerste ronde, en dat is een ander pad door dezelfde code.
Elke fake client in de catalogustests is bovendien een Plex-client, dus A3 (Jellyfin), A4 (Pleya
Server) en A5 (Plex plus Jellyfin) zijn niet aangetoond, hoe klein het verschil ook lijkt.

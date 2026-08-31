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

**Fase 7 en register I.** Fase 7 bouwde de TV-root: de horizontale topnav, de gedeelde
geneste-routestapel en Mijn Pleya. Daarmee is register I van "leeg" naar acht ingevulde rijen
gegaan (I1, I5, I6, I8, I11, I12, I13, plus I7 en I15 die er al stonden). I18 is bewust op `open`
gebleven: de topnav-helft is bewezen, het griditem-geval niet, en een half bewezen rij hoort niet
`covered` te heten. I2, I3, I4 gaan over de hero en horen bij fase 8; I9, I10, I14, I16, I17, I19
en I20 raken paden die fase 7 niet heeft aangelegd. I21 is er tijdens fase 7 bijgekomen als
*bevinding over fase-5-code* en bewust niet opgelost — zie de noot onder register I. I22 en I23
kwamen uit de fase-7-systeemaudit en zijn bij het sluiten van de fase alsnog gerepareerd, omdat ze
allebei gedrag raken dat hoofdstuk 7.4, 7.6 en 24 al vastleggen en dat fase 7 zélf gebroken heeft:
vóór fase 7 was de complete catalogus een fullscreen push, waaruit de balk niet te bereiken was, dus
het scenario bestond niet. I24 is er als laatste bijgekomen en is geen gedragsrij maar een
dekkingsrij: de keten klopt in productie, maar geen test loopt er in zijn geheel doorheen — zie de
noot onder register I voor waarom dat coverage debt is en geen productbug.

**Hardware.** J2 (4K-output), J4 (overscan), J8 (VoiceOver) en J9 (Reduce Motion) zijn niet in een
test vast te leggen — ze vragen een echte Apple TV. Ze staan op `open` met die reden in de
Test-kolom en horen bij de eindacceptatie na fase 10A (hoofdstuk 29), niet bij de gate van een fase.
Ze gelden dan voor de hele TV-UI, dus ook voor de schermen die er nu nog niet zijn.

Fase 7 voegt daar geen nieuwe categorie aan toe, maar wel drie concrete gevallen die onder J8 en J9
vallen en die pas na 10A afgetekend kunnen worden:

- **VoiceOver op de topnav (J8).** `tv_top_navigation_test.dart` legt vast dát de actieve
  bestemming zichzelf anders aankondigt dan de gefocuste (`Films, current section` tegenover
  `Films`), en dat het label niet dubbel in de node zit. Wat VoiceOver er hoorbaar van maakt — en of
  het onderscheid op een echte Apple TV ook als onderscheid *landt* — is hardware.
- **Reduce Motion op de navfocus (J9).** De focus-transitie duurt 160 ms (hoofdstuk 8.4). Of hij
  onder Reduce Motion kort genoeg of instant hoort te zijn is alleen op het toestel te beoordelen.
- **De Menu-press op de root (J8/J9-buur).** De engine claimt presses vóór de responder chain
  (`CLAUDE.md`, [DEC-019](../DECISIONS.md#dec-019)). Fase 7 heeft dat pad níet aangeraakt en voert
  Menu door hetzelfde `shouldPassTvosMenuToSystem`-predicaat als de zijbalk, dus er is geen nieuw
  native gedrag om te bewijzen — maar dat de nieuwe rootgrens op echte hardware op dezelfde plek
  ligt, is wel een runtimewaarneming.

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
| D1 | Zelfde serie op twee servers | test/providers/tv_discovery_landing_provider_test.dart (`D1: the same episode of one series on two servers is one card carrying both sources`, `D1: two episodes of one series on two servers stay two cards`) — beide helften van de rij, door de productieprovider heen; test/services/unified_catalog/home_projection_service_test.dart (`C: the same episode on two servers is one card, and its sources stay the concrete episodes`, `A/E: two episodes of one series stay two cards, on one shared series-wide id`, `B: two seasons of one series stay two cards`) voor dezelfde regel op serviceniveau. In alle vijf krijgen beide rijen dezelfde serie-brede tmdb/tvdb, dus geen ervan slaagt doordat de externe ids leeg waren | covered |
| D2 | Verschillende seizoensdekking | | open |
| D3 | Zelfde episode met sterke ID | test/services/unified_catalog/identity_resolver_test.dart (`D3: an episode guid is exact-episode evidence and contributes on its own`); test/services/unified_catalog/home_projection_service_test.dart (`D: two servers reporting the same strong episode guid merge without any external id`, `D/E: a strong episode guid never merges two different episodes of one series`) | covered |
| D4 | Zelfde episode via serie-ID plus S/E | test/services/unified_catalog/identity_resolver_test.dart (`D4: a series-wide external id becomes exact-episode evidence, not series evidence`, `E: two episodes forced into one bucket still get different tokens from one series id`); test/services/data_aggregation_bridge_test.dart (`getOnDeckFromAllServers hides the same episode listed twice under one stable show id`, `getOnDeckFromAllServers keeps two different episodes of one show under one stable show id`) — de upstream-dedup, die vóór elke Home-projectie draait | covered |
| D5 | Specials seizoen 0 | test/media/canonical_media_identity_test.dart (`D5: season 0 (specials) is a real, distinct, bucketable season index`) | covered |
| D6 | Ontbrekend seizoennummer | test/media/canonical_media_identity_test.dart (`D6/D7: a missing season or episode index makes the episode bucket unusable`, `D6: an episode missing its season index has no bucketable identity`); test/services/unified_catalog/identity_resolver_test.dart (`D6/D7: an episode with no usable ordinal has no bucket at all, so it never buys a series id`) voor de Verder kijken-helft | covered |
| D7 | Ontbrekend afleveringsnummer | test/media/canonical_media_identity_test.dart (`D6/D7: a missing season or episode index makes the episode bucket unusable`); test/services/unified_catalog/identity_resolver_test.dart (`D6/D7: an episode with no usable ordinal has no bucket at all, so it never buys a series id`), plus test/services/unified_catalog/home_projection_service_test.dart (`G: episodes with no usable season or episode index never merge on their series alone`) | covered |
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
| H1 | Clearlogo aanwezig | `tv_hero_billboard_card.dart` `_titleBlock` tekent de clearlogo in dezelfde gereserveerde band als de titeltypografie, zodat de metaregel eronder niet verschuift; de band is een constante van [TvHomeLayout.heroLogoMaxHeight] | covered |
| H2 | Geen clearlogo | idem — de titelfallback vult exact dezelfde band, `test/goldens/tv_home_production_golden_test.dart` rendert die tak (de fixtures dragen geen clearlogo) | covered |
| H3 | Landscape-art | test/widgets/tv_hero_artwork_test.dart (`a real backdrop is drawn sharp`, `the backdrop wins over the poster…`) | covered |
| H4 | Square-art | test/widgets/tv_hero_artwork_test.dart (`square background art is sharp on a wide card only when no backdrop exists`) — op een 2.465:1-kaart wint de backdrop, square is de fallback (DEC-057's ratio-invariant) | covered |
| H5 | Alleen poster | test/widgets/tv_hero_artwork_test.dart (`poster-only art becomes a blurred fill, never a sharp crop`) | covered |
| H6 | Geen artwork | test/widgets/tv_hero_artwork_test.dart (`a title with no artwork at all resolves to nothing, not to a stand-in`) plus `_EmptyHeroArt`'s themagradiënt | covered |
| H7 | Lange titel | test/goldens/tv_home_production_golden_test.dart (`Home with long titles and prose`) — titel, metaregel en synopsis kappen af binnen hun gereserveerde hoogtes; de knoppenrij staat op exact dezelfde plaats als in `Home at rest` | covered |
| H8 | Geen synopsis | `tv_hero_billboard_card.dart` reserveert de synopsisband ook zonder tekst, dus een titel zonder samenvatting verplaatst de CTA-rij niet | covered |
| H9 | Spoilers verbergen | | open |
| H10 | Watched titel | | open |
| H11 | In-progress titel | | open |
| H12 | Meerdere bronnen | test/screens/discover_screen_tv_hero_test.dart (`a mergeable duplicate becomes one slide carrying both sources`, `two concrete copies of one recent film are one hero slide, not two`) — één slide per logische titel, met beide bronnen erin, gereden door het echte `DiscoverScreen`; de tweede test legt ook vast dat een titel waarvan de identiteit niet te bewijzen is één bron houdt in plaats van er stilzwijgend een bij te verzinnen | covered |
| H13 | Source valt weg | test/screens/tv/tv_content_feed_test.dart (`a row whose sources did not all answer says so, and still shows what it has`) — de projectie markeert partial, de rij toont wat er is; de hero verliest een slide pas als de logische groep zelf verdwijnt, en volgt dan zijn groep en niet zijn index (test/widgets/tv_hero_billboard_carousel_test.dart, `the carousel follows its group, not its index, when the list shortens`) | covered |
| H14 | Hero-data komt laat | test/screens/tv/tv_content_feed_test.dart — `TvContentFeed` onderscheidt "nog niet geprojecteerd" van "authoritatief leeg" via `hasProjectedHero` + `projectedLatestMovies`, en reserveert in het eerste geval de billboardruimte (hoofdstuk 9.7) in plaats van een fallback te tonen die een tel later omklapt | covered |
| H15 | Geen hero-kandidaten | test/screens/discover_screen_tv_hero_test.dart (`zero recent films keeps the existing hub fallback billboard`) en test/providers/tv_home_projection_provider_test.dart (`a hero with no eligible recent film is empty rather than padded from hubs`) — een lege filmpool valt terug op het bestaande on-deck/hub-billboard en wordt niet met hubs opgevuld (DEC-067) | covered |
| H16 | Alleen series beschikbaar | test/screens/tv/tv_content_feed_test.dart (`no recent films falls back to the first Continue Watching title`) — een filmloze bibliotheek valt terug op het bestaande on-deck/hub-billboard, met één slide en zonder rotatie | covered |
| H17 | Auto-rotation tijdens focus | test/widgets/tv_hero_billboard_carousel_test.dart (`an interaction pauses the rotation for the inactivity window`) en test/screens/tv/tv_content_feed_test.dart (`a focused content row holds the rotation and fades the hero text`) — zie [DEC-070](../DECISIONS.md#dec-070) punt 1 voor waarom 9.6's lijst niet letterlijk kan gelden | covered |
| H18 | App gaat background | test/widgets/tv_hero_billboard_carousel_test.dart (`autoplayEnabled false stops the rotation, and restoring it resumes deterministically`) en test/screens/tv/tv_content_feed_test.dart (`leaving the destination stops the rotation, and returning resumes it`) — `TvContentFeed` observeert de lifecycle en vouwt hem samen met de overige pauzeredenen in één vlag | covered |
| H19 | Reduce Motion | test/widgets/tv_hero_billboard_carousel_test.dart (`reduced motion stops the rotation but not the remote`) — geen automatische wissel, handmatige navigatie blijft werken; hardwarebevestiging blijft J9 | covered |
| H20 | Light theme | | open |
| H21 | Artworkrequest faalt | `tv_hero_artwork.dart` geeft `_EmptyHeroArt` als zowel `placeholder` als `errorWidget` mee, dus een mislukte request valt terug op de themagradiënt in plaats van op een lege of kapotte laag | covered |

## I. Navigatiecases

| # | Case | Test | Status |
|---|---|---|---|
| I1 | Cold-start focus | test/screens/tv/tv_my_pleya_screen_test.dart (`Down from the top navigation lands on the profile action`) en test/screens/tv/tv_root_shell_test.dart (`the scope every content screen already talks to reaches the bar`) — de shell verplaatst focus uitsluitend expliciet, er staat geen `autofocus` op de contentscope | covered |
| I2 | Topnav naar hero | test/screens/discover_screen_test.dart (`TV tab focus returns to the Home feed instead of the reload action`) — de shell vraagt `focusActiveTabIfReady` en landt op `tvHeroPlay` (hoofdstuk 7.1/7.3) | covered |
| I3 | Hero naar row | test/screens/discover_screen_test.dart (`Down from the hero Play pill reaches the first browse row`) en test/widgets/tv_hero_billboard_carousel_test.dart (`Down leaves for the content feed and Up for the top navigation`) | covered |
| I4 | First row terug naar hero | test/screens/tv/tv_content_feed_test.dart (`walking a content row leaves the featured slide exactly where it was`, `the hero keeps its slide across a row focus round trip`) — UP keert terug naar de *laatst gebruikte* CTA, en haalt de carousel eerst terug in beeld wanneer de feed hem weggescrold had | covered |
| I5 | Root Back naar topnav | test/screens/tv/tv_back_chain_test.dart (`step 4: root content hands the focus to the top navigation`) | covered |
| I6 | Topnav Back naar systeem | test/screens/tv/tv_back_chain_test.dart (`step 5: the top navigation at the root defers to the system contract`, `Menu reaches the system only from the root destination with the bar focused`) — het bestaande `shouldPassTvosMenuToSystem`-predicaat, ongewijzigd van vorm; wat de engine daarna met de press doet is hardware (DEC-019) | covered |
| I7 | Source picker Back | test/widgets/tv/tv_media_source_picker_test.dart (`Menu closes the picker, activates nothing, and restores the exact CTA`) | covered |
| I8 | Nested Mijn Pleya Back | test/screens/tv/tv_back_chain_test.dart (`step 2 comes first`, `step 2 beats the focus test, wherever the remote happens to be`) en test/navigation/tv/tv_navigation_coordinator_test.dart (de nested-routegroep) en test/screens/tv/tv_root_shell_test.dart (`popping brings the destination back`) | covered |
| I9 | Profile picker Back | | open |
| I10 | Native keyboard Back | | open |
| I11 | Live TV-item verschijnt | test/widgets/tv/tv_top_navigation_test.dart (`a Live TV slot appearing does not replace the focus node of an existing item`) en test/screens/tv/tv_root_shell_test.dart (`appears and disappears without disturbing its neighbours`) — het nieuwe item krijgt een eigen stabiele id, en de buren houden hun focusnode én hun volgorde | covered |
| I12 | Live TV-item verdwijnt | test/screens/tv/tv_root_shell_test.dart (`losing it while it is open moves the viewer to Home`) en test/navigation/tv/tv_live_tv_capability_test.dart (`a transient outage does not retire a remembered capability`) — een tijdelijke storing laat het item staan, alleen een sluitende meting haalt het weg (DEC-069) | covered |
| I13 | Actieve destination opnieuw selecteren | test/navigation/tv/tv_navigation_coordinator_test.dart (activate op de reeds actieve bestemming geeft `false` en notificeert niet, dus geen rebuild en geen refetch — hoofdstuk 7.2) | covered |
| I14 | Tab wisselen met overlay open | | open |
| I15 | Select KeyUp na focusverplaatsing | test/focus/focusable_wrapper_select_test.dart (`key-up landing on a wrapper that never saw the key-down fires nothing`); test/focus/dpad_navigator_suppressor_test.dart (`armed suppressor eats the in-flight select key-up and clears`) | covered |
| I16 | Trackpad swipe versus D-pad | | open |
| I17 | Android TV back | | open |
| I18 | Focused item verdwijnt | test/navigation/tv/tv_navigation_coordinator_test.dart (Live TV verdwijnt terwijl het alleen de focusring droeg: de ring verhuist in plaats van naar een verdwenen bestemming te wijzen). Alleen bewezen voor de topnav; het griditem-geval blijft open | open |
| I19 | Return uit player | | open |
| I20 | Return uit settings | | open |
| I21 | Filters bereiken vanaf diep in het grid | gedrag ligt vast in hoofdstuk 7.4 en 10.6, maar de snelkoppeling is niet gebouwd — zie de noot onder deze tabel | open |
| I22 | Terugkeren op dezelfde kaart binnen een bestemming | test/screens/tv/tv_destination_restoration_test.dart (`All movies`/`All series comes back to the card and the scroll region it was left on`, `the Films landing comes back to the rail tile it was left on`) — binnenkomen vanaf de balk landt op de primaire focus van het scherm (hoofdstuk 7.1/7.4), en DOWN daaruit landt op de kaart waar de kijker stond; de catalogus leest die kaart uit `TvNavigationCoordinator.contentFocusFor`, de landing uit zijn eigen rails | covered |
| I23 | Bestemming wisselen met een geneste route open | test/screens/tv/tv_root_shell_test.dart (`belongs to its own destination and does not follow the viewer elsewhere`) bewijst dat de route bij zijn eigen bestemming blijft; test/screens/tv/tv_destination_restoration_test.dart (`coming back does not restart the merge that is already loaded`, plus de twee restauratierijen hierboven) bewijst dat terugkeren de geladen pagina's, de scrollpositie en de gefocuste kaart houdt | covered |
| I24 | Vanuit content de balk bereiken, end-to-end | beide helften bewezen, de schakel ertussen niet; geclassificeerd als *integration-test coverage debt* en niet als productiedefect — zie de noot onder deze tabel | open (coverage debt) |

**I24 — de content→balk-keten is aan beide uiteinden bewezen en in het midden met de hand
geknoopt.** Toegevoegd op 31 augustus 2026, na fase 7.

De keten die een kijker gebruikt om vanuit een pagina bij de balk te komen loopt in drie schakels:

1. het scherm vraagt erom — `onNavigateUp`/`onNavigateLeft` → `MainScreenFocusScope.focusSidebar`
   (`tv_unified_catalog_screen.dart:503,517,529` en `:586`);
2. `MainScreen._focusSidebar` (`main_screen.dart:1419`) vertaalt dat op TV naar
   `SidebarFocusCoordinator.focusSidebar(focusActiveItem: …)` en focust de node van
   `TvNavigationCoordinator.focusedDestination`;
3. de balk krijgt de ring.

Schakel 1 is bewezen in `test/screens/tv/tv_unified_catalog_focus_test.dart` (`UP from every header
action reaches for the top navigation`, plus de twee LEFT-rijen), schakel 3 in
`test/screens/tv/tv_root_shell_test.dart` (`reaching the bar puts the ring on a destination in it`).
Schakel 2 wordt door geen enkele test uitgevoerd: niets in de suite monteert `MainScreen` — met
`grep -rln "MainScreen(" test/` is de uitkomst leeg — en de twee tests die eromheen staan stoppen
allebei op een stub (de ene op een `focusSidebar`-teller, de andere op een `onFocusNav` die het
lichaam van `_focusSidebar` nabouwt).

Het gevolg is scherp: een breuk in die zes regels productiecode zou groen door CI komen. Het staat
hier omdat het opschrijven eerlijker is dan een testcommentaar dat suggereert dat de keten sluit.
Repareren betekent `MainScreen` monteerbaar maken in een test of die TV-tak eruit trekken naar iets
dat los te testen is; dat is groter dan het gat dat fase 7 achterliet en hoort in een eigen stuk werk
thuis, niet als bijvangst van een testuitbreiding.

**Wat I24 wél en niet is.** Bij het sluiten van fase 7 is schakel 2 één keer statisch nagelopen, om
te bepalen of hier een productiebug onder zit of alleen een gat in de dekking. Er zit geen bug
onder, en dat is aantoonbaar uit vier regels die allemaal naar hetzelfde exemplaar wijzen:

- `_tvNavNodes` is één `FocusMemoryTracker` (`main_screen.dart:413`) en gaat als `navNodes` naar
  `TvRootShell` (`:2186`), die hem ongewijzigd doorgeeft aan `TvTopNavigation.nodes`;
- de balk maakt zijn nodes met `nodes.get(destinations[i].focusKey, …)`
  (`tv_top_navigation.dart:133`), en `_focusSidebar` vraagt er één op met
  `_tvNavNodes.get(_tvNav.focusedDestination.focusKey)` (`main_screen.dart:1431`) — dezelfde
  tracker, en dezelfde sleutelafleiding (`TvDestinationId.focusKey`);
- `_tvNav` is één `TvNavigationCoordinator` (`:408`) en gaat als `coordinator` naar diezelfde shell
  (`:2185`), dus `focusedDestination` en de getekende items komen uit één bron;
- `onFocusNav: _focusSidebar` (`:2193`) is wat `TvRootShell` als
  `MainScreenFocusScope.focusSidebar` publiceert, en dat is precies wat schakel 1 aanroept.

Er is dus geen tweede tracker, geen tweede coördinator en geen tweede sleutelconventie waar de
keten op mis kan lopen. Daarmee is I24 **integration-test coverage debt** en geen productbug: het
risico is een toekomstige regressie die niemand ziet, niet gedrag dat vandaag stuk is. Een
`MainScreen`-harnas bouwen om zes regels bedrading te dekken zou meer testoppervlak toevoegen dan
het bewijst, dus dat is bewust niet gedaan.

Dezelfde vaststelling geldt voor een tweede stuk bedrading, en dat hoort er eerlijk bij:
`_openTvCompleteCatalog` bindt `restoreFrom: _tvNav.contentFocusFor(destination)` en
`onRemember: (place) => _tvNav.rememberContentFocus(destination, place)`
(`main_screen.dart:1901,1902,1907,1908`). De restauratietests uit I22/I23 draaien op de
productieschermen en de productiecoördinator, maar de `_ShellHost`-harnas legt díe twee regels zelf
weer aan in plaats van ze uit `MainScreen` te halen. Ook hier wijzen beide kanten naar hetzelfde
`_tvNav`-exemplaar en is de binding eenduidig; ook hier zou een breuk groen door CI komen. Wie I24
ooit oplost, lost deze in dezelfde beweging op — het is één gat met twee uitgangen, niet twee
problemen.

**I21 — de filterknop ligt ver weg vanaf rij zes.** Toegevoegd op 31 augustus 2026, tijdens fase 7,
over fase-5-code. `TvUnifiedMediaGrid` geeft de uitgang naar de header alleen aan de bovenste rij
(`onNavigateUp: isFirstRow ? widget.onExitTop : null`, `tv_unified_media_grid.dart:313`). Dat is op
zichzelf correct spatial navigation — omhoog is omhoog — maar het betekent dat iemand die op rij zes
van vijfhonderd films staat zes keer Up plus Right nodig heeft om bij Filters te komen.

Hoofdstuk 7.4 en 10.6 hebben daar allebei al een antwoord op staan: *"Play/Pause mag als zichtbare
snelkoppeling het filterpaneel openen, maar filters blijven ook met een normale focusbare knop
bereikbaar"*, en *"De zichtbare knop blijft de primaire route; Play/Pause is hooguit een
snelkoppeling"*. Het gedrag is dus vastgelegd — wat ontbreekt is de implementatie: er is geen enkele
Play/Pause-afhandeling op het catalogusscherm.

Dit is geen regressie van fase 7, en fase 7 heeft het pad juist één stap korter gemaakt door
`Up` vanaf de header op de topnav aan te sluiten. Het staat hier omdat het tot nu toe nergens stond:
het was stilzwijgend blijven liggen als "mag" in plaats van als "moet nog", en dat is precies hoe een
bereikbaarheidsgat een release haalt. **De positie van de controls is niet het probleem en staat niet
ter discussie** — hoofdstuk 33.5 legt die als bindend vast (rustige controls rechts naast de kop,
ondergeschikt, geen CTA-pillen).

Niet ingevuld tijdens fase 7, met opzet: het catalogusscherm is fase-5-scope, en een snelkoppeling
erbij bouwen zou werk uit een andere fase vooruittrekken (hoofdstuk 27, regel 4). Het hoort thuis bij
fase 9 (functionele integratie en uitzonderingen) of bij een gerichte fase-5-aanvulling.

**I22 en I23 — wat de fase-7 systeemaudit vond en wat er niet aan gedaan is.** Een read-only audit
op de volledige fase-7-diff vond één blokkerend defect en acht kleinere. Het blokkerende is
gerepareerd en heeft nu een test die er zonder de fix rood van gaat
(`test/navigation/tv/tv_destination_test.dart`, `the bar cannot name a destination the screens list
will not build`): Mijn Pleya stond in de balk maar werd door `getVisibleTabs` op TV weggefilterd,
omdat de poort op `isMobile` stond en dat op een TV onwaar is. De pil lichtte op, het scherm werd
nooit gebouwd, en élke route erbinnen — Instellingen, Servers, Bibliotheken, de hoofdstuk-6.4-adapter
— was onbereikbaar. Dat geen enkele test het zag komt doordat ze allemaal het scherm rechtstreeks
monteerden in plaats van via de schermenlijst; de nieuwe test loopt wél door de productiepoort.

Vier kleinere bevindingen zijn ook gerepareerd: opnieuw selecteren van de actieve bestemming deed een
netwerkrefresh (hoofdstuk 7.2 verbiedt dat); `lastLiveTvCheckWasConclusive` was waar wanneer er
*niets* gevraagd was, waardoor een meting die met geen enkele server sprak een onthouden capability
kon intrekken; `TvLiveTvCapabilityStore.clearForProfileScope` werd nergens aangeroepen bij het
verwijderen van een profiel; en een geneste Mijn Pleya-sectie opende zonder gefocust element.

Twee zijn eerst geregistreerd in plaats van opgelost. Bij het sluiten van fase 7 zijn ze allebei
alsnog gerepareerd — ze bleken één defect met twee namen, en het was fase 7 dat het introduceerde:

- **I22 — kaartniveau focusherstel.** `TvNavigationCoordinator.rememberContentFocus` bestond en was
  getest, maar had geen productieconsument, dus de map bleef in de praktijk leeg en
  `clearFocusMemory` wiste niets. De reparatie is die consument, niet een tweede mechanisme: de
  memory is nu hoofdstuk 7.6's `TvDestinationFocusMemory` (gefocust element, `groupId`,
  scrolloffset) en `TvUnifiedCatalogScreen` schrijft hem weg bij `deactivate` en leest hem terug bij
  `initState`. Alleen de catalogus schrijft: elk ander bestemmingsscherm staat in de `IndexedStack`
  en bewaart zijn eigen positie al — de rails van een landing houden hun tegel in
  `TvDiscoveryRailState`, Mijn Pleya zijn tegel in zijn `FocusMemoryTracker` — en twee schrijvers per
  bestemming zouden twee antwoorden op dezelfde vraag zijn.

  Wat daarmee *niet* verandert, en ook niet hoort te veranderen: binnenkomen vanaf de balk landt op
  de primaire focus van het scherm en niet meteen op een kaart. Hoofdstuk 7.1 en 7.4 schrijven dat
  voor ("Down vanaf topnav focust de eerste headeractie"), en de kaart is één stap verder: DOWN
  daaruit landt op de kaart waar de kijker stond.
- **I23 — de complete catalogus herlaadde bij bestemmingswissel.** De landing eronder blijft
  gemonteerd, de geneste catalogus niet: alleen de *actieve* bestemming bouwt zijn bovenste route, dus
  naar Series wisselen en terug bouwde `Alle films` opnieuw op. Twee dingen gingen daarbij verloren
  en allebei zijn ze nu gedicht. De pagina's: `_applyQuery(startIfNeeded: true)` riep
  onvoorwaardelijk `setQuery`, wat de merge van generatie wisselt en elke geladen pagina weggooit —
  `startIfNeeded` betekent nu "start hem als hij niet loopt" in plaats van "start hem opnieuw", wat
  precies de belofte uit [DEC-069](../DECISIONS.md#dec-069) en hoofdstuk 24 is dat een geneste route
  geen herlaadbeurt kost. En de plek: die reist via de memory uit I22.

  De doccommentaren die het tegenovergestelde beweerden (`TvRootShell.child`: "switching
  destinations never … throws away a loaded catalogue") zijn meegecorrigeerd. Een commentaar dat een
  contract claimt dat de code niet nakomt is de duurste soort fout in dit register: hij zorgt dat
  niemand meer kijkt.

**Wie wat onthoudt, per bestemming.** Bij het sluiten van fase 7 is per bestemming nagelopen welke
laag daadwerkelijk bewaard wordt, omdat "focusherstel werkt" op deze shell twee verschillende
mechanismen kan betekenen en het verschil precies is waar I22 en I23 zaten. De scheidslijn is of het
scherm gemonteerd blijft:

| Oppervlak | Scherm blijft staan | Rij/sectie | Exacte kaart/tegel | Scrolloffset | Binnenkomst vanaf de balk |
| --- | --- | --- | --- | --- | --- |
| Home | ja — `IndexedStack` (`main_screen.dart:1190`, `_discoverKey`) | `TvBrowseRailState._hubIndex` | `TvBrowseRailState`, via `requestFocus()` (`tv_browse_rail.dart:544`) | `DiscoverScreen._scrollController` (`:156`) + de rail zelf | `focusActiveTabIfReady` → `_focusTvBrowseRailWhenReady` (`discover_screen.dart:1035,422`) |
| Films landing | ja — `IndexedStack` (`:1198`, `_moviesKey`) | `_railKeys`, gesleuteld op `hubId` (`tv_discovery_landing_screen.dart:104`) | `_focusedGroupIdByHubId` → `initialFocusedGroupId` (`:101,226`) | `_scrollController` (`:91`) | `focusActiveTabIfReady` → `_viewAllFocus`, de paginakop (`:279`) — hoofdstuk 7.1, niet de kaart |
| Series landing | ja — `IndexedStack` (`:1203`, `_seriesKey`) | idem (zelfde `TvDiscoveryLandingScreen`) | idem | idem | idem |
| Search | ja — `IndexedStack` (`:1214`, `_searchKey`) | `_firstTvRailKey` (`search_screen.dart:119`) | `TvDiscoveryRailState`, eigen nodes op `groupId` | met het scherm; query en resultaten ook | `focusActiveTabIfReady` → `_searchFocusNode`, het invoerveld (`:538`) |
| Mijn Pleya | ja — `IndexedStack` (`:1225`, `_tvMyPleyaKey`) | tegelgroepen in één scherm | `nodes.lastFocusedKey` op de eigen `FocusMemoryTracker` (`tv_my_pleya_screen.dart:204,235`) | `SingleChildScrollView`'s eigen positie (`:286`) | `focusActiveTabIfReady` → de laatst gefocuste tegel (`:235`) |
| Alle films | **nee** — `TvNestedRoute`, alleen de actieve bestemming bouwt hem | n.v.t., één plat grid | `TvDestinationFocusMemory.groupId` → `initialFocusedGroupId` (`tv_unified_catalog_screen.dart:578`) | `TvDestinationFocusMemory.scrollOffset`, geklemd toegepast in `_scheduleRestore` (`:215`) | `focusActiveTabIfReady` → `focusedElementId`, de laatst gebruikte headeractie (hoofdstuk 7.4) |
| Alle series | **nee** — idem | n.v.t. | idem | idem | idem |

Vijf van de zeven oppervlakken bewaren dus niets *ergens anders*: ze staan in de `IndexedStack` van
`MainScreen`, worden nooit afgebroken, en houden hun scrollpositie, hun rails en hun focusnodes
gewoon in hun eigen `State`. Alleen de complete catalogus wordt bij een bestemmingswissel
afgebroken, en alleen die schrijft daarom naar `TvNavigationCoordinator` — bij `deactivate`
(`tv_unified_catalog_screen.dart:175`) en terug bij `initState` (`:156`). Dat is met opzet precies
één schrijver per bestemming; twee zouden twee antwoorden op dezelfde vraag zijn.

De kolom "binnenkomst vanaf de balk" staat er los in, omdat hij een andere vraag beantwoordt dan de
rest van de rij en dat verschil bij het sluiten van fase 7 twee keer voor verwarring zorgde. Down
uit de balk landt op de *primaire focus van het scherm* — een paginakop, een invoerveld, een
headeractie — en niet meteen op een kaart. Hoofdstuk 7.1 en 7.4 schrijven dat zo voor. De onthouden
kaart ligt één stap verder: DOWN daaruit. Een matrixrij die "exacte kaart" leest en "landt op de
kaart" betekent, zou dus de verkeerde eis zijn.

Daarnaast drie noteringen zonder rij, omdat ze geen scenario zijn maar een tekortkoming: bij het
wegvallen van Live TV terwijl het open staat gaat Pleya wél naar Home maar zónder de korte melding
die hoofdstuk 19 noemt; `TvLiveTvCapabilityStore` bepaalt zijn profielscope op het moment van
schrijven in plaats van bij de aanroep, zodat een schrijfactie die over een profielwissel heen
uitloopt in de verkeerde entry kan landen; en de vijf schermen die op TV via Mijn Pleya geopend
worden staan óók nog in de `IndexedStack`, zodat er twee exemplaren tegelijk gemonteerd zijn.

## J. Accessibility en layoutcases

| # | Case | Test | Status |
|---|---|---|---|
| J1 | 1080p | test/goldens/tv_unified_catalog_golden_test.dart (`films, default state`, `series, default state`) en test/goldens/tv_unified_catalog_states_golden_test.dart — elke catalogusgolden rendert op het DEC-028-canvas, 1920x1080 gedeeld door 1,85 | covered |
| J2 | 4K-output | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J3 | Laagste ondersteunde TV-surface | | open |
| J4 | Overscan | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J5 | Lange vertaling | test/goldens/tv_unified_catalog_golden_test.dart (`films, labels at the length a long locale produces`, `films, long titles`) — de labels hebben de lengte van de Duitse strings; een echt omgeschakelde locale is in `flutter test` niet te renderen, want elke niet-basislocale is deferred. Fase 7 voegt de topnav toe: test/widgets/tv/tv_top_navigation_test.dart (`a long locale keeps every destination on one line and the bar one row high`) en test/goldens/tv_shell_long_locale.png | covered |
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
is dat A 8 van 20, B 5 van 15, C 24 van 24, D 3 van 15, E 4 van 15, F 20 van 21, G 1 van 14, H 17 van
21, I 5 van 20 en J 3 van 16 — J16 meegeteld. (H en I zijn bijgewerkt bij het sluiten van fase 8;
de overige tellingen zijn die van fase 6/7.)

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
- **D2 (verschillende seizoensdekking).** D1's tests hebben twee servers op dezelfde en op
  verschillende afleveringen, niet twee servers met een verschillend seizoensbereik. *(Bijgewerkt bij
  de fase-8-sluiting: D1's fixtures zijn herschreven naar exact-episode-semantiek, zie de noot
  daarover verderop. D2 blijft om dezelfde reden open.)*

De overige fase-6-rijen (H1-H11, H13, H17-H21) hangen aan hero-*presentatie* en horen bij fase 8;
I1-I6 en I8-I14 hangen aan de topnav en de root-shell en horen bij fase 7.

**Fase 8 en de zeventien rijen die erbij komen.** Fase 8 bouwde de definitieve Home: de afgeronde
in-page carousel, de unified contentfeed eronder, en het loskoppelen van rijfocus en hero
([DEC-070](../DECISIONS.md#dec-070)). Register H gaat daarmee van 2 van 21 naar 17 van 21, en I2,
I3 en I4 sluiten. Dezelfde strengheid als altijd: een rij verschuift alleen als er een test of een
constructie is die precies dát scenario aantoont, en H14 is een goed voorbeeld van wat dat betekent
— hij stond hier als "half bewezen is niet covered", en sluit nu pas omdat de layoutkant van
hoofdstuk 9.7 er is (`TvContentFeed` reserveert de billboardruimte tijdens een onafgeronde
projectie in plaats van een fallback te tonen die een tel later omklapt).

Wat in register H **open** blijft, en waarom:

- **H9 (spoilers verbergen)** en **H10/H11 (watched / in-progress titel).** De hero leest
  `hideSpoilers` en tekent een resumebalk in de primaire pil, en `_HeroPill`'s `progress` komt uit
  `resumeFractionFor(group)` — maar geen test rijdt die drie toestanden af, en de hero draagt per
  hoofdstuk 9.5 alleen films en series, dus de spoilerregel bijt er in de praktijk alleen op een
  fallbackbillboard. Ongetest is ongetest.
- **H20 (light theme).** Alle Home-renders staan op het donkere thema. De kaart leest zijn kleuren
  uit `MonoTokens`, dus er is geen hardgecodeerde donkere aanname, maar dat is een argument en geen
  bewijs.

**De tegenspraak tussen hoofdstuk 11.8 en rij D1 over Verder kijken is opgeheven.** Geregistreerd op
1 september 2026 bij het naverifiëren van de fase-8-sluiting, en op dezelfde dag opgelost door de
identiteitslaag naar het hoofdstuk toe te brengen in plaats van andersom.

Hoofdstuk 11.8 schrijft voor: *"Verder kijken groepeert op exacte aflevering: `show identity +
season + episode`. Nooit: alle afleveringen van dezelfde serie als één Continue Watching-item."* De
implementatie deed dat niet. `continueWatchingScope` gaf `'show'` voor een aflevering,
`continueWatchingBucketKey` bucket'te op `grandparentTitle`, en de externe ids kwamen van de *serie*,
zodat twee verschillende afleveringen die hetzelfde serie-brede tmdb/tvdb oplosten één sterk token
deelden en één kaart werden.

Wat er is veranderd, in `lib/services/unified_catalog/identity_resolver.dart` en
`lib/media/unified/identity_evidence.dart` — de smalste plek die deze regel bezit, en de enige twee
bestanden met een gedragswijziging:

- een aflevering wordt gescoped op `episode` en een seizoen op `season`, niet meer allebei op `show`;
- `continueWatchingOrdinal` levert de ordinaal (`s2e4`, `s2`), die als `discriminator` aan
  `externalIdTokens` meegaat: een serie-breed `tmdb:95396` wordt daarmee `episode:tmdb:95396/s2e4`,
  dus bewijs over één aflevering in plaats van over de hele serie (rij D4);
- dezelfde ordinaal zit in de bucketsleutel, dus twee verschillende afleveringen delen geen bucket
  meer en kopen die serie-brede id niet eens meer op;
- de eigen guid van een aflevering telt weer mee — die is al exact-aflevering-bewijs en is nu
  precies de granulariteit waarop gegroepeerd wordt (rij D3);
- een aflevering zonder bruikbare seizoen- of afleveringsindex heeft géén bucket, dus valt terug op
  alleen zijn guid: hoofdstuk 11.8's "ontbrekende indexen vereisen een sterk episode-ID", en de
  invariant dat een false merge erger is dan een false negative (rijen D6/D7).

Beide kanten zijn met een negatieve controle bewezen. Met de identiteit tijdelijk terug op
serie-breed vallen tien tests over vijf bestanden om, in de identity-laag, de upstream dedup, de
productieprovider, de serviceprojectie én de Home-feed; met alleen de token-discriminator
uitgeschakeld vallen de twee identity-tests om die precies dát isoleren. De vier tests die het oude
contract vastlegden zijn herschreven in plaats van verwijderd, en de gedeelde fixture
(`tvDiscoveryEpisodeGroup`, `disc-cw-two-servers`) draagt nu één aflevering op twee servers in plaats
van twee verschillende afleveringen in één groep — met een assert die dat afdwingt. Geen enkele
golden veranderde: de representative source van die groep rendert byte-identiek.

Register D gaat daarmee van 4 van 15 naar 6 van 15: D3 en D4 sluiten op de tests hierboven, en D1
blijft `covered` maar nu zonder voorbehoud. D2 blijft open — seizoensdekking is niet wat deze
correctie aantoont — en D8-D15 evenmin.

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

Wat bewust `open` is gebleven, en waarom. *(Deze alinea is geschreven bij het sluiten van fase 5 en
beschrijft de stand van toen; de fase-6- en fase-8-alinea's hierboven zijn de actuele lezing van H
en I.)* Register H staat nog helemaal open: de hero bestaat niet, die komt in fase 6 en 8. Register I
is op twee rijen na een zaak van fase 7 (topnav en Mijn Pleya); alleen I7 en I15 gaan over
mechanismen die er nu al zijn. Register G is op G9 na open, en dat is de
zwaarste post: `selectRepresentativeWatchState` — de functie die per group beslist wélke bron de
kijkstatus levert, inclusief de klok-skew, de ontbrekende timestamps en de afwijkende runtimes uit
G5 tot en met G7 — heeft geen enkele eigen test. In A, B en E zijn de rijen die over een tweede ronde
gaan open gebleven (A12 server valt weg tijdens paging, B13 lege pagina vóór total, E6 bron faalt ná
geslaagde pagina's, E8 total verandert onderweg, E15 dezelfde source twee keer): de tests die er het
dichtst bij komen falen of stoppen in de eerste ronde, en dat is een ander pad door dezelfde code.
Elke fake client in de catalogustests is bovendien een Plex-client, dus A3 (Jellyfin), A4 (Pleya
Server) en A5 (Plex plus Jellyfin) zijn niet aangetoond, hoe klein het verschil ook lijkt.

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

Bijgewerkt: 2026-08-29, aangemaakt in fase 0. Fase 1 (unified identity foundation) dekt register C
(C1-C24) volledig af — zie de vindplaatsen in de tabel hieronder. De overige categorieën blijven
`open` tot de fase die ze raakt.

## A. Server- en topologycases

| # | Case | Test | Status |
|---|---|---|---|
| A1 | Geen servers geconfigureerd | | open |
| A2 | Eén Plex-server | | open |
| A3 | Eén Jellyfin-server | | open |
| A4 | Eén Pleya Server | | open |
| A5 | Plex plus Jellyfin | | open |
| A6 | Drie of meer servers | | open |
| A7 | Twee servers met dezelfde displaynaam | | open |
| A8 | Eén server offline bij twee online servers | | open |
| A9 | Eén server met auth-error | | open |
| A10 | Alle servers offline | | open |
| A11 | Server komt laat online | | open |
| A12 | Server valt weg tijdens paging | | open |
| A13 | Server valt weg in source picker | | open |
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
| B1 | Eén movie library | | open |
| B2 | Meerdere movie libraries op dezelfde server | | open |
| B3 | Movie libraries op meerdere servers | | open |
| B4 | Series-only profiel | | open |
| B5 | Movies-only profiel | | open |
| B6 | Mixed/shared Plex library | | open |
| B7 | Verborgen library als enige bron | | open |
| B8 | Verborgen library als tweede duplicate bron | | open |
| B9 | Library wordt tijdens gebruik verborgen | | open |
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
| D1 | Zelfde serie op twee servers | | open |
| D2 | Verschillende seizoensdekking | | open |
| D3 | Zelfde episode met sterke ID | | open |
| D4 | Zelfde episode via serie-ID plus S/E | | open |
| D5 | Specials seizoen 0 | | open |
| D6 | Ontbrekend seizoennummer | | open |
| D7 | Ontbrekend afleveringsnummer | | open |
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
| E3 | Veel duplicates waardoor één fetchronde weinig groups oplevert | | open |
| E4 | Duplicate verschijnt pas veel pagina's later | | open |
| E5 | Eén bron is veel trager | | open |
| E6 | Eén bron faalt na eerdere succesvolle pagina's | | open |
| E7 | Total ontbreekt | | open |
| E8 | Total verandert tijdens paging | | open |
| E9 | Sort key ontbreekt | | open |
| E10 | Sort key verschilt tussen duplicate sources | | open |
| E11 | Query verandert met requests in flight | | open |
| E12 | Profiel wisselt met requests in flight | | open |
| E13 | Filter verwijdert de gefocuste group | | open |
| E14 | Late merge zou zichtbare sortpositie wijzigen | | open |
| E15 | Bron geeft dezelfde source twee keer terug | | open |

## F. Source-pickercases

| # | Case | Test | Status |
|---|---|---|---|
| F1 | Eén source | | open |
| F2 | Twee sources | | open |
| F3 | Tien sources met scroll | | open |
| F4 | Alle sources online | | open |
| F5 | Eén source offline | | open |
| F6 | Alle sources offline | | open |
| F7 | Auth-error | | open |
| F8 | Coverage nog bezig | | open |
| F9 | Coverage incompleet | | open |
| F10 | Nieuwe source arriveert terwijl modal open is | | open |
| F11 | Source verdwijnt terwijl modal open is | | open |
| F12 | Duplicaatservernamen | | open |
| F13 | Geen quality metadata | | open |
| F14 | Afwijkende editions | | open |
| F15 | Afwijkende progress | | open |
| F16 | Last-used source offline | | open |
| F17 | Cancel | | open |
| F18 | Playerstart faalt | | open |
| F19 | Detailroute faalt | | open |
| F20 | Terugkeer behoudt focus | | open |

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
| G9 | Playback return met null route result | | open |
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
| H12 | Meerdere bronnen | | open |
| H13 | Source valt weg | | open |
| H14 | Hero-data komt laat | | open |
| H15 | Geen hero-kandidaten | | open |
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
| I7 | Source picker Back | | open |
| I8 | Nested Mijn Pleya Back | | open |
| I9 | Profile picker Back | | open |
| I10 | Native keyboard Back | | open |
| I11 | Live TV-item verschijnt | | open |
| I12 | Live TV-item verdwijnt | | open |
| I13 | Actieve destination opnieuw selecteren | | open |
| I14 | Tab wisselen met overlay open | | open |
| I15 | Select KeyUp na focusverplaatsing | | open |
| I16 | Trackpad swipe versus D-pad | | open |
| I17 | Android TV back | | open |
| I18 | Focused item verdwijnt | | open |
| I19 | Return uit player | | open |
| I20 | Return uit settings | | open |

## J. Accessibility en layoutcases

| # | Case | Test | Status |
|---|---|---|---|
| J1 | 1080p | | open |
| J2 | 4K-output | | open |
| J3 | Laagste ondersteunde TV-surface | | open |
| J4 | Overscan | | open |
| J5 | Lange vertaling | | open |
| J6 | Grote tekst | | open |
| J7 | RTL | | open |
| J8 | VoiceOver | | open |
| J9 | Reduce Motion | | open |
| J10 | Light theme | | open |
| J11 | OLED theme | | open |
| J12 | Focusglow bij eerste/laatste card | | open |
| J13 | Panel met veel sources | | open |
| J14 | Lege panelsecties | | open |
| J15 | Selected versus focused | | open |

## Totaal

179 cases: A20, B15, C24, D15, E15, F20, G14, H21, I20, J15. Nul `covered` bij aanmaak (fase 0).

# Pleya Unified TV 2026 — Netflix-referentie IA/UX-plan

**Status:** goedgekeurd op 2026-08-30, met bindende correcties van Michel verwerkt; de
**visuele north star is op 30-08-2026 bevroren** — acht referentiebeelden in
`docs/assets/tvos-unified/northstar/`, bindend per hoofdstuk 33 van de baseline en
[DEC-065](DECISIONS.md#dec-065).
Vastgelegd in [DEC-064](DECISIONS.md#dec-064); hoofdstuk 10, 27 en 33.10 (voorheen 33.6) van de baseline
zijn navenant geamendeerd. Dit document is het uitvoeringsplan, niet meer het voorstel.
**Datum:** 2026-08-30
**Basis:** origin `00d22e1`, fase 5 in uitvoering.
**Referentie:** Michel's Netflix TV 2025/2026 screenshots (3 stuks) als primaire
compositiereferentie; `docs/tvos-unified-experience.md` als architectuurbaseline;
`DEC-063` als besluitenkader.

> **Leeswijzer.** De blocker uit de eerste versie van dit plan (Films/Series landing
> versus hoofdstuk 10.2) is **opgelost** door Michel op 2026-08-30. Sectie 20 legt de
> beslissing vast. De kern: fase 5 wordt **niet opnieuw ontworpen** — wat daar gebouwd is
> wordt de *Alles bekijken*-catalogus, en de Netflix-achtige landing is fase-6-werk.

---

## 1. Canonieke huidige codearchitectuur

Alles hieronder is geverifieerd tegen de werkboom op `00d22e1`, niet uit geheugen.

### 1.1 Root-TV-navigatie — *sidebar, niet topnav*

| Onderdeel | Bestand | Feit |
|---|---|---|
| Shell | `lib/screens/main_screen.dart` (±1200 r.) | `_currentTab` als `NavigationTabId`; `_sideNavKey` → `SideNavigationRailState`; TV-tak op r. 461 |
| Rail | `lib/widgets/side_navigation_rail.dart` | De TV-navigatie is vandaag een **verticale zijbalk** |
| Tabs | `lib/navigation/navigation_tabs.dart` | `NavigationTabId.movies/series` op r. 100–101; TV-only gate op r. 192; labels r. 231–232 |
| Profielscope | `lib/navigation/profile_session_screen.dart` | Geneste `Navigator` + `ProfileNavigationScope`; provider-ownership |

**Gat t.o.v. doel:** de horizontale topnav bestaat nog niet. Fase 7 voorziet
`lib/widgets/tv/tv_top_navigation.dart` + `lib/screens/tv/tv_root_shell.dart`.

### 1.2 Home — *oude full-bleed spotlight*

`lib/screens/discover_screen.dart` (2478 r.) is de huidige TV-home:

- `_heroController` (`PageController`), `_currentHeroIndex`, autoscroll `Duration(seconds: 8)` (r. 96)
- `_spotlightItem` (`ValueNotifier<MediaItem?>`) — **rowfocus vervangt de hero** (r. 140)
- `_tvRailRevealed` (r. 160) — rail schuift via `AnimatedSlide` over een schermvullende spotlight
- `TvSpotlightBackground` (`lib/widgets/tv_spotlight_background.dart`, 627 r.)
- `DiscoverScreen.heroPaginationKey` — permanente paginatiedots
- Hero-bron: *newest released films*, niet on-deck (r. 117)

Dit is precies wat fase 8 expliciet **verwijdert** (ch. 27 fase 8: "Verwijderen uit de
nieuwe TV-home: fullscreen spotlight; `_tvRailRevealed`; rail-overlay via `AnimatedSlide`;
rowfocus die `_spotlightItem` vervangt").

### 1.3 Data die Home/discovery vandaag al heeft

`lib/providers/discover_provider.dart`:

| Getter | Betekenis |
|---|---|
| `onDeck` (r. 143) | Verder kijken |
| `latestMovies` (r. 144) | Hero-pool (release-date gesorteerd) |
| `hubs` (r. 145) | `_seedHubs` + `_personalizedHubs` + `_latestShowsHub` |

Plus `lib/services/recommendations/` (`personalized_rows_builder.dart`,
`recommendation_service.dart`, `hub_dedup.dart`, `affinity_engine.dart`).

**Belangrijk:** deze data is *per concrete bron*, nog niet unified-gegroepeerd.
Groepering op Home is fase 6 (`home_projection_service.dart`, `featured_selector.dart`,
`unified_media_hub.dart` — nog niet aanwezig).

### 1.4 Films/Series — *catalogusgrid, fase 5, vrijwel af*

| Bestand | R. | Rol |
|---|---|---|
| `lib/screens/tv/tv_movies_screen.dart` | 32 | Dunne wrapper → gedeeld scherm |
| `lib/screens/tv/tv_series_screen.dart` | 30 | idem |
| `lib/screens/tv/tv_unified_catalog_screen.dart` | 660 | Header + grid + skeleton + empty |
| `lib/widgets/tv/tv_unified_media_grid.dart` | 384 | `groupId`-gekeyde `FocusNode`s (r. 183–184), prefetcher |
| `lib/widgets/tv/tv_unified_media_card.dart` | 571 | 2:3 poster + meta-footer |
| `lib/widgets/tv/tv_catalog_header_bar.dart` | 255 | Bronnen/Filters/Sorteren |
| `lib/widgets/tv/tv_catalog_filter_panel.dart` | 857 | Tweekolomspaneel |
| `lib/widgets/tv/tv_catalog_sort_panel.dart` | 293 | Sorteerpaneel |
| `lib/widgets/tv/tv_panel_primitives.dart` | 165 | Gedeelde paneelonderdelen |

Ownership: `lib/providers/unified_catalogs.dart` (96 r.) — profielgescoped, **lui**,
`catalogs.movies` / `catalogs.shows`, leeft bóven de tabwissel zodat Movies → Series →
Movies dezelfde merge/scroll behoudt.

### 1.5 Engine (fase 3) en activation (fase 4) — *klaar, niet aanraken*

- `catalog_service.dart` — k-way merge, `groupsPerPage`, generatie-cancellatie
- `source_cursor.dart` — `eligibleCatalogLibraries()` sluit visibility vóór grouping
- `unified_catalog_query.dart` — `UnifiedCatalogSortField`, comparator
- `unified_activation_coordinator.dart` (502 r.) + `tv_media_source_picker.dart` (1105 r.)
- `preferred_server_store.dart`, `source_preference_store.dart`

### 1.6 Focus- en artworkprimitieven

`lib/focus/`: `focus_memory_tracker.dart` (`get(key)`, `restoreFocus(fallbackKey:)`,
`pruneExcept(validKeys)`), `card_focus_scope.dart`, `focusable_wrapper.dart`,
`dpad_navigator.dart`, `focus_theme.dart` (**witte ring, r. 16–19, gepind**).

Artwork: `lib/widgets/optimized_media_image.dart` +
`lib/services/unified_catalog/unified_artwork_prefetcher.dart` (398 r., viewport + marge).

### 1.7 Schaal

`DEC-028`: `_AppleTvScale._scale = 1.85` → canvas **1038×584 logisch**.
`TvLayoutConstants.scaleForHeight = (h/1080).clamp(0.85, 1.35)` → op TV **constant 0.85**.
Tokens in `lib/widgets/tv/tv_unified_layout.dart`: `TvSourcePickerLayout`,
`TvCatalogLayout` (poster 2:3, `cardRadius 10`, `cardFocusRingGap 5`, schaduw/lift-tokens).

---

## 2. Netflix-referentie → Pleya mapping

Uit de drie screenshots afgelezen, niet uit een template:

| Netflix-observatie | Bindend voor Pleya? | Vertaling |
|---|---|---|
| Geen sidebar; horizontale topnav | **BINDEND** | Fase 7 `TvTopNavigation` |
| Actieve bestemming = lichte pill | **BINDEND** | Wit/licht capsule, niet rood |
| Zoek als compact icoon links van de items | **BINDEND** | Search als icoon, geen breed veld |
| Profiel-avatar links, merk-mark rechts | **RICHTINGGEVEND** | Pleya: compacte mark; positie te bepalen |
| Grote rounded featured card **in** de pagina | **BINDEND** | Fase 8 billboard; niet full-bleed |
| Eerstvolgende row peekt onder de hero | **BINDEND** | "Verderkijken" is zichtbaar in screenshot 1 |
| Focused item wordt **breder**, buren blijven zichtbaar | **BINDEND** | Screenshot 2: Black Mirror breed + 3 smalle posters |
| Metadata/synopsis **alleen** onder het focused item | **BINDEND** | Screenshot 2: genre/jaar/TV-MA + synopsis onder de brede kaart |
| Focused CW-kaart toont "Nog 20 minuten" onder de rail | **BINDEND** | Screenshot 3 |
| Artwork draagt de kleur, chrome is neutraal donker | **BINDEND** | ch. 28 van de prompt |
| "Alleen op Netflix" als rowtitel | **NIET BINDEND** | Pleya heeft geen originals (§30) |
| Games-tab | **NIET BINDEND** | Geen Pleya-equivalent |
| Exacte pixelspacing/artwork | **NIET BINDEND** | Tokens winnen |

**Pleya-bindend, wint altijd van de referentie:** witte focusring
(`focus_theme.dart:16-19`), witte primaire Play-CTA, `#E5140F`/`#FFB020` spaarzaam,
bronsemantiek (`2 bronnen` alleen bij >1), preferred-server-gedrag, filtergedrag.

---

## 3. Definitieve Pleya TV IA

```
TOPNAV (permanent, enige rootchrome)
[◉ profiel]  [⌕]  Home   Series   Films   [Live TV]   Mijn Pleya        [Pleya]

Home ─────────────► detail ──► player
  └─ featured carousel
  └─ Verder kijken   (discovery rail)
  └─ Voor jou        (discovery rail)
  └─ enkele bestaande hubs

Films ────────────► detail ──► player
  └─ discovery rails (bestaande hubs, filmscope)
  └─ "Alles bekijken" ──► ALLE FILMS (catalogusgrid + filters/sort)

Series ───────────► detail ──► player
  └─ discovery rails (serie-scope)
  └─ "Alles bekijken" ──► ALLE SERIES (catalogusgrid + filters/sort)

Mijn Pleya ───────► geneste navigator
  └─ Kijklijst · Bibliotheken · Servers · Aanvragen · Activiteit · Instellingen
```

**Volgorde — beslist.** De referentie zet Series vóór Films, en dat wordt het
(`Home · Series · Films`). Mijn eerste voorstel was de bestaande volgorde in
`navigation_tabs.dart` (r. 271–287) te houden omdat die al gecommit is; Michel heeft dat
verworpen, en terecht: reeds-gecommit-zijn is geen ontwerpargument. De Netflix-referentie is
leidend voor de compositie van de topnav, inclusief de volgorde. Zie DEC-064, *Topnavvolgorde*.
De actieve bestemming is een lichte/witte capsule.

**Live TV:** verschijnt alleen bij een bekende Live TV-bron, maar **zijn positie is vast**
— een tijdelijke outage mag de andere items niet laten verspringen (prompt §1). Implementatie:
positie gereserveerd op basis van *profielcapability*, niet van live serverstatus.

**Back/Menu op rootniveau** (5 trappen, ongewijzigd t.o.v. de prompt):
1. modal/paneel sluiten → 2. nested route pop → 3. detail/player pop →
4. contentfocus → topnav → 5. topnav/root → tvOS systeemcontract.

> ⚠️ Zie `CLAUDE.md`: op tvOS claimt de engine élke press vóór de responder chain.
> Het Menu-contract loopt via `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)`,
> niet via `pressesBegan`. Fase 7 moet dat pad respecteren, niet omzeilen.

---

## 4. Home-ontwerp

```
┌ TOPNAV ────────────────────────────────────────────────┐
├────────────────────────────────────────────────────────┤
│  ╭──────────────────────────────────────────────────╮  │  rounded, IN de pagina
│  │  FEATURED (1 actieve kaart)                      │  │  radius ≈ TvCatalogLayout
│  │  [clearlogo]                                     │  │  marges = viewport-proportie
│  │  Serie · Thriller · 2025 · 3 seizoenen           │  │
│  │  [▶ Afspelen]  [Meer info]                       │  │  Play = WIT
│  ╰──────────────────────────────────────────────────╯  │
│  Verder kijken                                         │  ← peekt, altijd zichtbaar
│  [═══ EXPANDED ═══][sm][sm][sm][sm]                    │
└────────────────────────────────────────────────────────┘
```

**Rowvolgorde (rustig, max ~5):**
1. Featured carousel — 5–8 unieke *groups*
2. Verder kijken — alleen als niet leeg
3. Voor jou
4. Recent toegevoegd
5. hooguit enkele bestaande hubs

**Hero-gedrag:** links/rechts = vorige/volgende featured; omlaag = eerste rail; omhoog =
topnav. Autorotatie ~8s (bestaand contract), **pauzeert** bij interactie, focusgebruik,
open modal en achtergrond-lifecycle; hervat niet direct na interactie. Geen audio.
Geen permanente dots — hooguit een tijdelijke segmentindicator (ch. 9.6/33.10 #6).

**Hero mag de contentfocus nooit stelen** (prompt §10, §40). Dat is precies de omkering
van het huidige `_spotlightItem`-gedrag, waar rowfocus de hero stuurde.

---

## 5. Films landing-ontwerp

```
TOPNAV
Films
Recent toegevoegd
[═══ EXPANDED ═══][sm][sm][sm][sm]
  Dune · 2021 · Sci-fi · 2 bronnen
  Korte synopsis…
Opnieuw bekijken
[…]
Alle films                                    [ Alles bekijken → ]
```

Rows komen **uitsluitend** uit de fase-6 projectielaag, gevoed door bestaande
hub/recommendation-data en gefilterd op filmscope. Een TV-widget mag nooit zelf een
pseudo-discoveryhub uit de complete catalogus construeren (hoofdstuk 10.2a).
Geen Top 10, geen Trending, geen Originals (§30).

**Geen chrome boven de eerste rail.** De landing draagt géén permanente
`[Alle bronnen] [Filters] [Sorteren]` — dat was een fout in de eerste versie van dit plan en
Michel heeft hem gecorrigeerd. De landing is content-first; refinement hoort bij *Alles
bekijken*. Een compacte refinement-actie mag hier later alléén bij aantoonbaar productbewijs
bijkomen, niet als standaard.

## 6. Series landing-ontwerp

Identiek systeem, serie-scope. Focused context toont waar betrouwbaar beschikbaar:
`S2 E4 · 18 min resterend · 2025 · Drama · 2 bronnen`.
Continue Watching behoudt **episode-identiteit** — geen samenklappen tot serieniveau (§31).

## 7. All Movies-ontwerp — *bestaat al*

Dit is het huidige `TvUnifiedCatalogScreen` + `TvUnifiedMediaGrid`, ongewijzigd van
compositie. Grid, 2:3 posters, ~6–7 kolommen, witte focusring + kleine scale + lift +
schaduw. **Geen** expanded landscape-transformatie (ruimtelijke stabiliteit).

## 8. All Series-ontwerp

Zelfde grid. Seriecontext op de kaart blijft klein en betrouwbaar (seizoenen, ongezien,
progress). Poster blijft dominant.

## 9. Filters/sort-ontwerp — *bestaat al*

`TvCatalogFilterPanel` (857 r.) is al tweekoloms met `Wissen` / `TOEPASSEN`.
Capability-omissie is al geïmplementeerd (`unified_filter_options.dart`).
**Vereiste wijziging:** filters horen bij *Alles bekijken*, niet bij de landing — en dat is
absoluut, niet "hooguit compact". Op de landing staat geen filter- of sorteerchrome boven de
eerste rail (§18, §44, hoofdstuk 10.2a, DEC-064). Wat er vandaag staat blijft dus staan waar
het staat; er verhuist in fase 6 niets naar de landing.

Server/library-filter ≠ preferred server blijft hard gescheiden (§21) — dat is vandaag al zo.

---

## 10. Focus/navigatie-statemachines

**Topnav** — `idle → focused(i) → committed(i)`; Left/Right binnen de rij; Down → eerste
contentsectie; Up vanaf content → laatst gefocuste topnav-item (niet index 0).

**Hero** — `slide(n)` × `subfocus{play, info}`. Left/Right muteert `slide` alléén als
`subfocus` niet actief bediend wordt; autorotatie muteert `slide` **nooit** terwijl
`subfocus` interactie heeft.

**Discovery rail** — `railFocus(rowId, groupId)`. Expansie mag navigatie **niet blokkeren
tot de animatie klaar is**; rapid input moet veilig zijn (geen stale animation state, geen
onbedoelde activatie tijdens geometriewissel). Identiteit is `groupId`, nooit index.

**Grid** — bestaand gedrag in `TvUnifiedMediaGrid`; `FocusNode` per `groupId` (r. 183–184).
Load-more mag focus/scroll niet verplaatsen.

**Filterpaneel** — `category → options → footer`; `focused ≠ selected`; sluiten herstelt
focus op de launcher.

## 11. Restoration / state-ownership

| Surface | Bewaren | Waar |
|---|---|---|
| Home | laatst gefocuste sectie + item per rail + heroslide | Home-provider (fase 6/8) |
| Films/Series landing | laatst gefocuste rail + `groupId` | landing-state |
| Alle films/series | `groupId` + scroll-offset + filters/sort | `UnifiedCatalogProvider` (bestaat) |
| Filterpaneel | actieve categorie + launcherfocus | paneelstate |

Gebruik `FocusMemoryTracker` (`get/restoreFocus/pruneExcept`) — **geen** tweede
focusframework. `pruneExcept` is precies gebouwd voor "item verdween na refresh".

## 12. Performance/prefetch

Budgetten: geen sourcelookup per focusmove; geen catalogusrebuild bij focus; hero maximaal
een kleine set high-res resident images; rails gevirtualiseerd; grid-prefetch = viewport +
marge (bestaand `UnifiedArtworkPrefetcher`). Focus-expansie mag geen provider-recreatie of
pagingreset veroorzaken.

## 13. Accessibility

Semantics op topnav, hero (+ carouselpositie), titel, episode/progress, broncount, Filters,
Sorteren, Alles bekijken, grid, empty/error-acties. `Reduce Motion` respecteren op
expansie én hero. Lange locales en RTL testen — er is al een RTL-guard (`dbc5601`).

---

## 14. Fase-aware volgorde

Vastgesteld op 2026-08-30. Elke fase heeft nu een **rol**, niet alleen een filelijst:

| Fase | Definitieve rol | Status |
|---|---|---|
| 5 | **Unified Complete Catalog** — All Movies / All Series grid, filters, sort, source activation, paging, restoration, catalogfocus | **sluiten op wat er ligt** |
| 6 | **Unified Discovery** — Movies landing, Series landing, Home-projecties, Continue Watching, Search, herbruikbare `TvDiscoveryRail`, expanded-focus contract, *Alles bekijken*-links naar fase 5 | volgende |
| 7 | **Unified TV Shell** — sidebar eruit, horizontale topnav, root focus/back, Mijn Pleya | |
| 8 | **Home Experience** — rounded featured carousel (5–8), autoplay/pause-lifecycle, CW- en Voor jou-carousels, cinematic ambient, finale Home-compositie | |
| 9 | Integratie van discovery/catalog/shell + accessibility/edge cases | |
| 10A | Finale automatische harding | |
| Final | Fysieke Apple TV-acceptatie | |

**De architectonische scheiding die dit oplevert:**

```
Unified catalog/data
        │
        ├── Complete Catalog Projection ──► All Movies / All Series grid   ← FASE 5
        │
        └── Discovery Projection ─────────► Home rails                     ← FASE 6
                                            Movies landing
                                            Series landing
                                            Continue Watching
                                            Search/hubs
```

Dit is ook technisch schoner dan recommendations en discovery-rows in een gridscherm
proppen: de twee projecties hebben verschillende cardingen, verschillende paginering en
verschillende focusmodellen.

**Waarom de landing niet in fase 5 kan.** Discovery rails hebben de unified hub-projectie
nodig (`home_projection_service.dart`, `unified_media_hub.dart`) en die bestaat nog niet.
Ze nu bouwen betekent een tweede projectielaag in de TV-widgets — precies wat §48 verbiedt.

### 14.1 Herziene fase-5 acceptatie

De oude eis was impliciet *"fase 5 moet eruitzien als de definitieve Netflix Movies-pagina"*.
Onder de nieuwe IA is dat **de verkeerde eis**, en hij verklaart waarom de fase-5
screenshots tegenvielen: twee dragende onderdelen van dat eindbeeld — discovery-rows en
horizontale rootnavigatie — waren bewust nog niet gebouwd.

De correcte fase-5 acceptatie is nu:

> *All Movies* en *All Series* moeten een uitstekende premium TV-catalogusgrid zijn.

Concreet: mooie posters · goede schaal · witte focus · sterke filtermodal · geen
databasegevoel · goede typografie · snelle remote-navigatie.
**Expliciet géén** expanded Netflix-discovery-card in het grid — die hoort op de landing in fase 6.

### 14.2 Wat fase 5 nog nodig heeft om te sluiten

Onder de nieuwe acceptatie was dit een korte lijst — geen redesign. Stand bij het sluiten:

1. ✅ `test/widgets/tv/tv_unified_media_grid_test.dart` — de `flutter_localizations`
   `depend_on_referenced_packages` is weg. De RTL-test stelt de richting nu rechtstreeks via
   `Directionality` in plaats van via een locale plus `GlobalMaterialLocalizations`: dat is
   precies wat de test beweert, en het houdt een pakket dat hier alleen transitief bestaat
   buiten de testdependencies (`CLAUDE.md`, ringdiscipline).
2. ✅ QA-register nagelopen. Vierentwintig rijen in A, B, D, E, I en J bleken al bewezen en
   waren alleen nooit ingevuld; een rij die niet precies zijn eigen scenario bewees is `open`
   gebleven. **J7 (RTL)** heeft nu de vindplaats van de guard erbij staan maar blijft `open` —
   geen van de zestien locales is rechts-naar-links, dus er is geen bereikbaar beeld te keuren.
   **J16 is nieuw** (zie punt 5).
3. ✅ 33.10 (voorheen 33.6) #7 en #8 staan op *besloten* (DEC-064, sectie 20).
4. ✅ Route herbestemd op papier: `TvMoviesScreen`/`TvSeriesScreen` zijn vanaf nu de
   *Alles bekijken*-bestemming, niet de eindlanding. Tot fase 6 blijven ze bereikbaar via
   de bestaande topnav-items; dat is een bewuste tussenstate, geen eindbeeld.
5. ✅ Eén echt gridgebrek gevonden en gedicht. De kaartvoet betaalde zijn onderpadding alleen
   bij focus, en omdat een `Row` zo hoog is als zijn hoogste kind tilde de gefocuste kaart zijn
   hele rij op en duwde de rijen eronder omlaag — het tegendeel van de *ruimtelijk stabiele*
   focus die hoofdstuk 10.2b van de complete catalogus eist. De padding is nu onvoorwaardelijk
   gereserveerd. Bewezen rood→groen door `focus moves nothing but the focused card`, dat álle
   negenendertig andere kaarten vastlegt; als register **J16** opgenomen.

## 15. Bestand/symbool-wijzigingsplan (per fase)

**Fase 5 (afsluiten, klein):**
- `tv_movies_screen.dart` / `tv_series_screen.dart` → later herbestemmen tot *Alles bekijken*-route
- `test/widgets/tv/tv_unified_media_grid_test.dart:12` → `flutter_localizations` dependency
  opruimen (`depend_on_referenced_packages`)
- QA-register A/E/J bijwerken (zie sectie 16)

**Fase 6 (nieuw):** `home_projection_service.dart`, `unified_media_hub.dart`,
`featured_selector.dart`; + **nieuw** `tv_discovery_rail.dart`, `tv_expandable_media_tile.dart`,
`tv_section_header.dart`, `tv_view_all_action.dart`; landingsschermen voor Films/Series.

**Fase 7:** `tv_root_shell.dart`, `tv_top_navigation.dart`, `tv_destination.dart`,
`tv_navigation_coordinator.dart`, `tv_my_pleya_screen.dart`; wijzig `main_screen.dart`,
`navigation_tabs.dart`.

**Fase 8:** `tv_hero_billboard_carousel.dart`, `tv_hero_billboard_card.dart`,
`tv_hero_artwork.dart`, `tv_ambient_background.dart`, `tv_content_feed.dart`,
`tv_content_row.dart`; verwijder `_tvRailRevealed`/`_spotlightItem`-pad uit `discover_screen.dart`.

## 16. Testmatrix

Per surface: focusrichtingen, expansie-stabiliteit, load-more-met-focus, filterwissel,
sortwissel, restore-na-back, empty/partial/error, lange locale, RTL, Reduce Motion.
Plus **backfill** van het QA-register: vandaag **145 open / 49 covered / 1 partial**;
register E (paginering, 15 open) en A (server/topologie, 20 open) zijn feitelijk al door
fase 2/3-tests gedekt maar nooit afgevinkt.

## 17. Golden/screenshotmatrix

Bestaand: 19 fase-5 goldens + 8 source-picker goldens.
Nieuw nodig per prompt §53: Home (featured default, volgende hero, CTA focused, CW eerste/
midden focused, Voor jou, kleurrijk artwork, lange titel); Films/Series landing (eerste/
midden item focused, broncount, partial, Alles bekijken focus); All Movies/Series
(bestaand, uitbreiden met loading-more/filter-empty); Filter (Sources, Libraries, Genre,
multi-selected, unsupported).
**Goldens worden daadwerkelijk geopend en bekeken, niet "gegenereerd = geaccepteerd"** (§53).

## 18. Migratie/risico

| Risico | Mitigatie |
|---|---|
| Fase 8 verwijdert `_tvRailRevealed`/`_spotlightItem` uit een 2478-regelscherm | Fase 8 refactort expliciet, met de bestaande contracttests als vangnet |
| tvOS press-claim (`CLAUDE.md`) breekt het Menu-contract | Fase 7 gebruikt `tvosHandlePress(fromUIEvent:)`, niet de responder chain |
| Discovery-expansie veroorzaakt rowhoogte-jank | Rowhoogte reserveren op de *expanded* hoogte; buren schuiven binnen vaste band |
| Landing-rows verleiden tot tweede projectielaag | Harde regel: rows komen uit fase-6 projectie, niet uit widget-lokale aggregatie |
| iOS/macOS onbedoeld meeveranderen | Alle nieuwe widgets onder `lib/**/tv/`; `PlatformDetector.isTV()`-gate zoals `navigation_tabs.dart:192` |

## 19. Besluiten die niet heropend worden

Geen sidebar · horizontale topnav · rounded in-page featured · hero is carousel ·
Verder kijken en Voor jou zijn carousels · discovery is row-based · focus verandert de
compositie · volledige catalogus is een grid · Films én Series hebben Alles bekijken ·
filters vooral op de complete catalogus · **witte** TV-focus · Pleya-kleuren uit code ·
artwork draagt de kleur · geen Pleya Originals · iOS/macOS niet ombouwen ·
`MediaItem` blijft één concrete bron (DEC-063) · geen destructive action op
`representativeSource` · preferred server ≠ catalogusfilter.

## 20. Blockers — opgelost

### ✅ BESLIST (2026-08-30) — Films/Series krijgen twee niveaus

Hoofdstuk 10.2 beschreef Films/Series als *één* gridpagina zonder hero. De Netflix-richting
vraagt een discovery-landing. **Besluit: allebei, op twee niveaus.**

- **Films/Series landing** (fase 6) = row-based discovery met expanded focus.
- **Films/Series ▸ Alles bekijken** (fase 5, bestaand) = de complete catalogusgrid.

Dit is een **herbestemming, geen redesign**. Alles wat fase 5 opleverde houdt zijn waarde:
`UnifiedCatalogs`, paging, filters, sorteren, query-preferences, source counts, preferred
server, source picker, catalogusgrid, cards, loading/partial/error, image-prefetch en
focusstabiliteit. Dat is exact het gereedschap voor *"laat me gewoon mijn 500 films zien"*.

**Er komt dus geen vijfde herontwerp van fase 5.**

#### Wat dit betekent voor de baseline

`docs/tvos-unified-experience.md` loopt nu achter op dit besluit en moet worden bijgewerkt,
anders ontstaat exact de verwarring die dit plan net heeft opgelost:

| Plaats | Huidige tekst | Moet worden |
|---|---|---|
| ch. 10.2 | "Geen grote hero op deze pagina's… Grid met 6–7 kolommen" | Geldt voor **Alles bekijken**; de landing krijgt een eigen subhoofdstuk (discovery) |
| ch. 10 titel | "Films en Series" | Splitsen: landing (discovery) versus complete catalogus |
| ch. 27 fase 5 | "Films en Series GUI" | "Unified Complete Catalog — All Movies/All Series" |
| ch. 27 fase 6 | "Home-, Search- en Continue Watching-projectie" | "+ Movies/Series landing projections, `TvDiscoveryRail`" |
| ch. 33.10 #7/#8 | `Open` | `Besloten` (zie hieronder) |

Ch. 23.1 vraagt voor een afwijking van de baseline een *roadmap deviation proposal*. Dit
besluit is door Michel zelf genomen en vastgelegd; ik stel voor het als amendement in
ch. 10 + ch. 27 te verwerken met een verwijzing naar dit document, in plaats van een los
proposal-bestand. **Nog niet uitgevoerd — wacht op akkoord.**

---

### Historische context (de oorspronkelijke blocker, ter archivering)

Hoofdstuk 10.2 van de goedgekeurde baseline zegt letterlijk:

> "**Geen grote hero op deze pagina's.** Vaste topnav. Een compacte sticky page header.
> Grid met 6–7 kolommen…"

en definieert Films/Series als *één gridpagina*. De hele fase-5 DoD ("Alle films en series
uit alle zichtbare libraries") en de 19 gebouwde goldens gaan daarvan uit.

De nieuwe opdracht (§11–13) vraagt het tegenovergestelde: Films/Series **landing** wordt
row-based discovery, en het grid verhuist naar een aparte **Alles bekijken**-route.

Dat is geen presentatiedetail dat ik in de presentatielaag kan opvangen — het verandert het
aantal routes, de fase-5 DoD, en de betekenis van bestaande goldens. Per prompt §56 rapporteer
ik het conflict in plaats van het zelf te beslechten.

**Goed nieuws:** het bestaande fase-5-werk gaat *niet* verloren. `TvUnifiedCatalogScreen` +
`TvUnifiedMediaGrid` + filter/sortpanelen zijn exact wat "Alles bekijken" nodig heeft. Het is
een **herbestemming**, geen weggooiactie: dezelfde widgets, één routeniveau dieper, plus een
nieuwe landing ervóór.

**Antwoord (2026-08-30):** alle drie beantwoord — landing = discovery in **fase 6**, grid =
*Alles bekijken* in fase 5, amendement in ch. 10 + ch. 27 in plaats van een los proposal.
`TvMoviesScreen`/`TvSeriesScreen` zijn de *Alles bekijken*-bestemming.

---

### Overige openstaande punten — nu gesloten

- **33.10 #7** — "Gepland"/"Beschikbaar 24 mei"-badges in het filmgrid: **niet tonen**.
  Onder §30 (geen fake contentsemantiek) mag Pleya geen release-status presenteren die het
  niet betrouwbaar heeft. Als Seerr-data dat later wél levert is dat een eigen voorstel.
- **33.10 #8** — "Onthoud mijn keuze" per titel in de source picker: **niet bouwen**.
  §32 houdt activation op het bestaande fase-4-contract: preferred server is globaal per
  profiel, last-used source stuurt alleen picker-focus. Een derde per-titel opt-in bestaat
  in geen enkel hoofdstuk en wordt niet geïntroduceerd.

# Pleya iOS Unified 2026: repository-audit en fase-1-bouwplan

**Status:** voorstel, wacht op akkoord. Geen productiecode gewijzigd, niets gecommit.
**Datum:** 3 september 2026
**Auteur:** Michel Knoop
**Branch:** `feat/netflix-mobile` op `011ffdb`
**Authority:** DEC-090, `docs/ios-unified-2026-audit.md`, de 21 beelden in `docs/assets/ios-unified/northstar/`, de vijf Home-comps in `~/Downloads/mobile-netflix`.

De vraag van dit document is niet hoe Pleya iOS eruit kan zien. Die is beslist. De vraag is hoe de productiecode op deze branch gecontroleerd naar de bevroren northstar gaat, in stappen die elk compileren, testbaar zijn en een screenshot opleveren.

## A. Preflight

| Controle | Uitkomst |
|---|---|
| Repo root | `/Users/michelknoop/.supacode/repos/plezy-main/feat/netflix-mobile` (git worktree, locked) |
| Branch, HEAD | `feat/netflix-mobile`, `011ffdbf5a0f56a53cd4254758d03d6c84a6ef40` |
| Status | één untracked bestand: `docs/sessions/2026-09-03.md` (automatisch sessielog, geen productiecode) |
| `011ffdb` | bestaat, `docs(ios): bevries Unified 2026 northstar`, 24 bestanden, uitsluitend docs en assets |
| Relatie met `origin/main` | 1 vóór, 0 achter (`git rev-list --left-right --count` geeft `1 0`) |
| Gepusht | nee, geen enkele remote bevat `011ffdb` |
| Freeze intact | ja: de 21 PNG's staan in git, working tree schoon op het sessielog na |
| Drift op deze branch | geen |

Drift buiten deze branch, wel relevant: de tvOS-referentiekop is verschoven. Het auditrapport noemt `pleya-teleport` op `9a3f6e1`; die clone staat nu op `f8e0e59` (3 september 13:02, alleen een docs-commit) met ongecommit werk in `lib/widgets/tv/tv_discovery_rail.dart`, `lib/widgets/tv/tv_unified_layout.dart` en een test. Dat raakt de themabestanden niet; die zijn byte-identiek aan deze branch (gecontroleerd met `diff` op de vier bestanden in `lib/theme/` en `lib/widgets/pleya_logo.dart`).

Toolchain: de Flutter op PATH is 3.44.4, de pin in `.fvmrc` is 3.44.0. `scripts/check_flutter_version.sh` weigert dan, en `dart format` verschilt per versie. De gepinde SDK staat op `/Volumes/SSD/flutter-sdks/3.44.0/flutter` (let op de submap; het pad zonder
`flutter/` bestaat wel maar bevat geen `bin/`). Alle verificatie in dit plan draait met die SDK vooraan op PATH; een groen resultaat op 3.44.4 telt niet.

## B. Authority-check

- DEC-090 gevonden op `docs/DECISIONS.md:722`, status accepted, met de authority-volgorde en de twee open Home-details.
- `docs/ios-unified-2026-audit.md` gevonden, 211 regels, status "bevroren".
- 21 PNG's aanwezig, `01-series-landing.png` tot en met `21-activiteit.png`, alle 21 in git. Geen ontbrekende assets. Alle 21 zijn in deze sessie bekeken.
- De Home-compositie zelf staat niet in de 21-set. De authority daarvoor zijn de vijf comps plus paragraaf 10 van het rapport, dat de compositie goedkeurt: billboard-kaart op inset 16, rijen eronder, chips, header, tabbalk.
- **Authority-reparatie uitgevoerd (docs-only, ongecommit).** De comps stonden alleen in `~/Downloads/mobile-netflix`. Home is de eerste surface die gebouwd wordt, dus juist daarvoor was de authority niet reproduceerbaar in een verse checkout, in CI of op een tweede machine. De vijf bestanden staan nu byte-identiek in `docs/assets/ios-unified/northstar/` als `home-comp`, `home-comp-gefilterd`, `profiel-laden-comp`, `serie-detail-comp` en `mijn-pleya-comp` (`cmp` per bestand, hashes in rapport 4.8). Ze dragen een naam en geen nummer, zodat de bevroren set de 21 genummerde beelden blijft. Rapport 4.8 en 11 en de authority-volgorde in DEC-090 registreren ze; aan het ontwerp is niets gewijzigd en de rangorde comp-tegen-mockup verandert niet. Waar comp en mockup elkaar raken wint de mockup (rapport §9); concreet betekent dat: het lockup in plaats van het losse P-icoon, en de TV-metaregel in plaats van `Historisch drama • 6 seizoenen • 18`.
- Open details A (secundaire hero-CTA) en B (indicator) staan in rapport §10 en DEC-090 als non-blocking. Dit plan houdt ze open; zie F, stap 7.

### tvOS-referentie die dit plan gebruikt

Branch `claude/netflix-redesign-b4x21v`. Twee standen:

| Stand | SHA | Waar |
|---|---|---|
| GitHub-tip | `0270d7c` | `remotes/github/claude/netflix-redesign-b4x21v` in deze repo, en uitgecheckt in `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-tvbuild` |
| Echte kop | `f8e0e59` | losse clone `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-teleport`, remote `michelknoop21/pleya`; 54 commits vóór `main`, 0 achter |

Geraadpleegd op `f8e0e59`: `docs/tvos-unified-experience.md` (hoofdstuk 6.1, 8, 9, 10.2a, 10.7, 14, 15, 16, 18, 23, 33.7, 34), `lib/media/unified/*`, `lib/services/unified_catalog/*`, `lib/providers/tv_discovery_landing_provider.dart`, `tv_home_projection_provider.dart`, `unified_catalog_provider.dart`, `unified_catalogs.dart`, `lib/widgets/pleya_wordmark.dart`, `assets/branding/pleya_wordmark_{mark,text}.png`, `lib/widgets/tv/tv_hero_billboard_card.dart`, `tv_source_row_descriptor.dart`, `tv_unified_media_card.dart`, `lib/navigation/navigation_tabs.dart`, `lib/navigation/profile_session_screen.dart`, DEC-071 en DEC-086 tot en met DEC-089.

## C. Architecture audit

### C1. Wat de mobiele shell nu is

`MaterialApp` zonder router (`lib/main.dart:953`), `home: OrientationAwareSetup` → `ProfileSessionScreen` (`lib/navigation/profile_session_screen.dart:59`) → eigen `Navigator` onder `ProfileNavigationScope` → `MainScreen` (`lib/screens/main_screen.dart`, 2011 regels). `MainScreen.build` splitst op `PlatformDetector.shouldUseSideNavigation` (`:1794`): desktop en TV krijgen de rail, alles met `Theme.platform == iOS || android` krijgt de bottom bar (`:1943-2009`). Alle tabs blijven gemount in een `IndexedStack` met `TickerMode` (`:1017-1032`). Geen state restoration, geen `PageStorageKey`, geen deeplinks op iOS (geen URL-scheme in `Info.plist`, geen associated domains).

De bottom bar (`:1715-1790`) is een Material `NavigationBar` met blur, een rode 18×3-indicator boven het actieve icoon, en een `GestureDetector` over de Bibliotheken-slot voor de long-press. Tabset online: Home · Bibliotheken · [Live TV] · Zoeken · Mijn Pleya; offline: Downloads · Mijn Pleya. Kijklijst, Downloads, Aanvragen en Instellingen zijn achter Mijn Pleya geschoven via `_mobileTabsInsideMyPleya` (`:122-127`). `NavigationTabId` heeft op deze branch geen `movies` en `series`.

Elke tab bezit zijn eigen header; de shell tekent er geen. Home gebruikt een overlaid gradient-header (`lib/screens/discover_screen.dart:1217-1440`), de rest `DesktopSliverAppBar` of `CustomAppBar` uit `lib/widgets/desktop_app_bar.dart`.

### C2. Platformdetectie

Eén bron, `lib/utils/platform_detector.dart`: `isMobile` is `Theme.platform == iOS || android` (`:183-187`), `isDesktop` is het complement (`:200`), `isTablet` is diagonaal ≥ 7 inch (`:230`) en wordt door de shell nergens gelezen. Een iPad krijgt dus dezelfde vijf-slots bar als een iPhone. Breakpoints staan in `lib/utils/layout_constants.dart:5-30` (`mobile 600`, `wideTablet 900`, `desktop 1200`). Er is geen form-factor-enum en geen gedeelde responsive builder; elk scherm combineert zelf `MediaQuery.sizeOf` met `ScreenBreakpoints`.

macOS: een native macOS-build meldt `TargetPlatform.macOS` en krijgt de rail. De iOS-binary in de Mac-container meldt iOS en krijgt de mobiele shell. Dit plan raakt alleen het pad waar `isMobile` waar is; het native macOS-pad blijft ongewijzigd.

### C3. Page families

| Family | Schermen | Gedeeld primitief |
|---|---|---|
| Home | `discover_screen.dart` (2512 regels, één klasse voor phone, iPad, desktop en TV, TV-split op `:1470`) | `HubSection`, `MediaCard`, `HomeHeroArtwork`, `homeHeroLayout` |
| Catalogus | `libraries_screen.dart` (1845), `library_browse_tab.dart` (1957), `filters_bottom_sheet.dart`, `sort_bottom_sheet.dart` | `MediaGridGeometry`, `MediaCardGridLayout`, `FocusableMediaCard`, `AlphaScrollHandle` |
| Lijsten met chips | `search_screen.dart` (859), `watchlist_screen.dart` (415), `downloads_screen.dart` (344), `live_tv_screen.dart` (800), `seerr_requests_screen.dart` (397) | `FocusableFilterChip`, `FocusableTabChip`, `SegmentedTabGroup` (één plek) |
| Detail | `media_detail_screen.dart` (4849, TV-split op `:3412`, verder één tree voor phone, iPad, desktop) + `media_detail/action_buttons.dart` (779, `part of`) | `EpisodeCard`, `WatchedIndicator`, `CastSection`, `HubSection` |
| Sheets | `media_context_menu.dart` (1866), alle `*_sheet.dart` | `OverlaySheetHost` / `OverlaySheetController` (14 mounts, 86 aanroepen, nul rauwe `showModalBottomSheet` in schermen, één in `now_watching_button.dart:90`) |
| Mijn Pleya en instellingen | `my_pleya_screen.dart` (255, kale `ListTile`s), `settings/` (37 bestanden, 9207 regels) | `SettingNavigationTile`, `SettingsGroup`, `SettingsRows`, `SettingsIconBadge` |
| Identiteit | `profile/profile_switch_screen.dart` (841), `auth_screen.dart` (642), `profile_switching_overlay.dart` (88) | `ProfileAvatar`, `PleyaLogo`, `BackendBadge` |

### C4. Media- en dataflow

Op deze branch bestaat geen logische mediagroep. `MediaItem` draagt één `serverId`; `DataAggregationService` dedupliceert cross-server op `guid ?? globalKey` en gooit de verliezers weg (`data_aggregation_service.dart:203-209`, `:267-273`, `_deduplicateContinueWatching :297`). Elke actie (afspelen, bekeken markeren, downloaden, waarderen, verwijderen) gaat naar `item.serverId` (`watch_actions.dart:47-66`, `video_player_navigation.dart:180-182`). `WatchlistAvailabilityResolver` is de enige plek die een titel over servers oplost, met "eerste server in deterministische volgorde wint" (`watchlist_availability_resolver.dart:115-117`); het resultaat gaat als volwaardig schrijfbaar item de `WatchlistCard` in (`watchlist_card.dart:69-81`), inclusief long-press-menu met "van server verwijderen". Dat is vandaag al het patroon dat DEC-090 en hoofdstuk 23 verbieden.

Alles wat de northstar aan bronsemantiek vraagt staat op de tvOS-branch, en staat daar platformneutraal:

| Onderdeel | Bestand op `f8e0e59` | Flutter-imports |
|---|---|---|
| `UnifiedMediaGroup`, `UnifiedMediaSource`, `UnifiedMediaHub`, `UnifiedWatchState`, `CanonicalMediaIdentity`, `SourceAvailability`, `SourceCoverageState`, `RememberedSourceChoice` | `lib/media/unified/` (10 bestanden) | geen |
| k-way merge, identity, grouping, source resolver, filters, query, snapshot | `lib/services/unified_catalog/` (19 bestanden, ±4400 regels) | één (`unified_artwork_prefetcher.dart:70` → `optimized_media_image.dart`) |
| `UnifiedActivationCoordinator` (14.6: één bruikbare bron slaat de picker over) | `unified_catalog/unified_activation_coordinator.dart` (502) | geen |
| `HomeProjectionService`, `FeaturedSelector` (9.5: hero uit films, max 8 groepen, `2 bronnen` alleen bij meer dan één) | `unified_catalog/home_projection_service.dart`, `featured_selector.dart` | geen |
| `TvDiscoveryLandingProvider` (`movieRails`, `seriesRails`), `TvHomeProjectionProvider` (`heroGroups`, `continueWatching`, `hubs`), `UnifiedCatalogProvider` + `UnifiedCatalogs` | `lib/providers/` | geen; geregistreerd zonder platformguard in `profile_session_screen.dart:255`, `:359`, `:370` |
| `PleyaWordmark`, `PleyaBrandLockup`, `identGround` | `lib/widgets/pleya_wordmark.dart` (160) + `assets/branding/pleya_wordmark_{mark,text}.png` | alleen `material` en `mono_tokens` |
| `NavigationTabId.movies` / `.series` | `lib/navigation/navigation_tabs.dart:100-101`, zichtbaarheid TV-only door één guard op `:204` | n.v.t. |
| DEC-071 groepsacties (bekeken op alle bronnen, offline queue), `RatingActions` | `lib/services/unified_action_outcome.dart`, `rating_actions.dart`, `offline_watch_sync_service.dart` | geen |
| `heroMetaLineFor` / `heroTitleFor` (pure functies over een groep) | `lib/widgets/tv/tv_hero_billboard_card.dart:54-79` | geen, maar het bestand wel |
| `TvSourceRowDescriptor` (14.3: wat een bronrij toont) | `lib/widgets/tv/tv_source_row_descriptor.dart` (246) | geen `material`, geen focus |
| Broncapsule, watched-tick, resume-bar (ontwerp) | `tv_unified_media_card.dart:377-465` | TV-tokens; alleen het ontwerp is overdraagbaar |

Twee multi-server-bugfixes zitten in diezelfde branch en zijn geen TV-fixes: `DiscoverProvider.updateItem` matcht op `globalKey` in plaats van op een kale id (twee Plex-servers nummeren beide vanaf 1), en `unansweredServerIds` bestaat op `main` niet.

### C5. Shared primitives op deze branch

| Primitief | Bestand | Verdict | Reden |
|---|---|---|---|
| `monoTheme`, `MonoTokens`, `MonoShapes` | `lib/theme/` | KEEP | byte-identiek aan de tvOS-branch; `NavigationBar`-theme al getuned; `StadiumBorder` op alle knoppen; container-rollen vallen samen met `surface` (DEC-053), dus een verhoogde laag leest expliciet `surfaceElevated` |
| `PleyaLogo` | `lib/widgets/pleya_logo.dart` | KEEP voor splash en Over; niet voor headers | het losse P-icoon met getypte `PLEYA` is verboden (DEC-065 punt 1, rapport §3) |
| `PleyaWordmark` | ontbreekt hier | NEW via tvOS-branch | header, profielkiezer, inlogscherm |
| `FilledButton` + theme | `mono_theme.dart:82-89` | KEEP | wit-op-donker capsule is de primaire CTA; `test/theme/no_local_cta_shape_override_test.dart` bewaakt lokale `shape:` |
| Hero-play-knop | `discover_screen.dart:2446-2510` | REPLACE | handgebouwde `InkWell` met `Colors.white`/`Colors.black`, buiten de tokens |
| `Pressable` | `lib/widgets/pressable.dart` | KEEP | enige touch-feedbackprimitief met haptics |
| `FocusableButton` | `lib/focus/focusable_button.dart` | KEEP, niet uitbreiden | 120 aanroepen, D-pad-API; op touch onschadelijk |
| `FocusableFilterChip` | `lib/widgets/focusable_filter_chip.dart` | KEEP, EXTEND | rood-getinte actieve staat bestaat (`:135-138`); focusstyling is gegate op keyboard-mode dus onzichtbaar op touch |
| `FocusableTabChip`, `SegmentedTabGroup` | `lib/widgets/` | KEEP | seizoenkiezer (07), Live TV-chips (10) |
| `OverlaySheetHost` / `OverlaySheetController` | `lib/widgets/overlay_sheet.dart` | KEEP | drag-to-dismiss, `showDragHandle`, `panel` wordt onder 600 pt een bottom sheet, system-back sluit eerst de sheet; huis voor 04, 08, 09 |
| `MediaCard` | `lib/widgets/media_card.dart` (1254) | KEEP voor catalogus en bibliotheek in fase 1; REPLACE op de northstar-oppervlakken | 17 constructorvlaggen, `Object`-union, `height` is posterhoogte; neemt geen `UnifiedMediaGroup` |
| `MediaCardGridLayout` | `lib/widgets/media_card_grid_layout.dart` | KEEP | pure maten (13/11 pt, 2:3), textScaler-bewust; de nieuwe kaart leest hieruit |
| `HubSection` | `lib/widgets/hub_section.dart` (926) | KEEP voor desktop en detail; REPLACE op mobiel Home en landings | `onNavigateToSidebar`, `onVerticalNavigation`, `focusScrollAlignment` in de publieke API; per-hub eigen `ScrollController` |
| `TopTenRow` | `lib/widgets/top_ten_row.dart` | KEEP | expliciet `!isTV`, ArchivoBlack-cijfers |
| `OptimizedMediaImage`, `MediaImageHelper`, `PlexImageCacheManager` | `lib/widgets/optimized_media_image.dart`, `lib/utils/media_image_helper.dart` | KEEP | DPR-bewust, cache-key zonder token; `ImageType` heeft poster/art/thumb/logo/avatar |
| Image-prefetch | alleen `library_browse_tab.dart:1530-1580` | EXTEND | rails en hero hebben niets; `UnifiedArtworkPrefetcher` op de tvOS-branch is de kandidaat |
| `WatchedIndicator`, `MediaProgressBar`, `NewContentBadge` | `lib/widgets/` | KEEP (`NewContentBadge`, ongewijzigd op beide branches); REPLACE `WatchedIndicator` op de nieuwe kaart | het northstar-vinkje is een donkere capsule (03, 11), niet een kaal glyph |
| Skeletons | `skeletons.dart`, `skeleton_media_card.dart`, `SkeletonLoader` in `media_card.dart:1192` | KEEP, `SkeletonLoader` verhuizen | een import van `skeletons.dart` sleept 47 kB `media_card.dart` mee |
| `ProfileAvatar`, `WatcherAvatar` | `lib/profiles/`, `lib/widgets/` | KEEP | avatar in header, tabbalk en 16 |
| `SettingNavigationTile`, `SettingsGroup`, `SettingsRows`, `SettingsIconBadge` | `lib/widgets/setting_tile.dart`, `settings_section.dart`, `settings_rows.dart` | KEEP | 14 en 18 zijn dit patroon; `SettingsRows` tekent separators op echte geometrie |
| `AppIcon` | `lib/widgets/app_icon.dart` | KEEP | fill 1, weight 700, 312 aanroepen |
| `Haptics` | `lib/utils/haptics.dart` | KEEP, EXTEND | 10 aanroepen; pull-to-refresh, chips, tabbalk krijgen `light()` |
| `ScreenBreakpoints` | `lib/utils/layout_constants.dart` | KEEP | `mobile = 600`; het plan voegt geen nieuwe breakpoints toe |
| `homeHeroLayout`, `HomeHeroArtwork` | `lib/utils/home_hero_layout.dart` (619), `lib/widgets/home_hero_artwork.dart` (475) | EXTEND | hoogteformule (hero plus eerste rij vult de viewport) blijft; presentatie `mobileFeatured` komt erbij naast `island` en `fullWidth` |
| `AutomationNode`, `AutomationIds` | `lib/automation/` | EXTEND | mobiele bar, rails en sheets hebben nu geen id; alles wat niet door `FocusableWrapper` gaat is onzichtbaar voor Pleya Verify |
| `TvBrowseRail`, `TvSpotlightBackground`, `TvVirtualKeyboard`, `side_navigation_rail.dart` | `lib/widgets/` | KEEP, niet aanraken | TV en desktop |
| `showModalBottomSheet` in `now_watching_button.dart:90` | | REMOVE bij de Activiteit-fase | enige rauwe aanroep |

### C6. Dependency provenance: kan de gedeelde laag los landen?

De vorige versie van dit plan stelde voor `f8e0e59` te mergen. Dat is onderzocht en afgeraden. Een
merge trekt 54 tvOS-commits mee en maakt de mobiele release afhankelijk van het integraal landen van
een nog niet gemergede TV-feature, terwijl de werkelijke afhankelijkheid andersom loopt: één
gedeelde kern, waar tvOS en iOS allebei op staan.

*Herkomst.* Van de 54 commits raken er zes `lib/media/unified/`: `855f385` (fase 1, identity
foundation), `3beecae` (fase 2, all-source resolver en coverage), `a62fea0` (fase 3, k-way merge en
provider), `e41989a` (fase 4, activation coordinator), `6e90fb4` (fase 6, unified discovery) en
`95e21b3` (fase 9, unified surfaces plus de merkketen). Ze zijn geen van alle voorouder van `main`.
De vroege commits zijn schoon gescheiden (fase 1 tot en met 3 raken nul TV-paden), de latere mengen
kern en TV-presentatie in één commit. Cherry-picken per commit werkt dus niet; scheiden op pad wel.

*Meting.* Ik heb de scheiding op pad uitgevoerd in een wegwerp-boom in de scratchpad: `main` als
basis, daaroverheen de niet-TV-paden uit `f8e0e59`. Alles op de gepinde SDK
(`/Volumes/SSD/flutter-sdks/3.44.0/flutter`, `flutter --version` bevestigt 3.44.0).

| Stand | `flutter analyze` | Bevinding |
|---|---|---|
| `main` (schoon, HEAD) | 0 fouten, 146 meldingen | de baseline |
| alleen `lib/media/unified/` + `lib/services/unified_catalog/` + de vier providers + wordmark | 13 fouten in 12 bestanden | uitsluitend benoembare adaptergaten: `findAllByIdentity` ontbreekt op de vijf clients, drie `SettingsService`-getters, `DiscoverProvider.unansweredServerIds`, `MediaServerTimeouts.unifiedCatalogLibraryPage`, `OptimizedMediaImage.artworkCacheKey`. Geen enkele TV-koppeling |
| alle niet-TV-paden, vier seams terug op `main`, twee switch-armen bijgezet | **0 fouten**, 39 meldingen | de gedeelde laag compileert zonder één regel TV-presentatie |

*Testbewijs.* `flutter test` op die stand: 4813 geslaagd, 6 overgeslagen, 13 gefaald. De dertien zijn
geen gedragsregressies maar testbestanden die op `main` achterbleven terwijl hun implementatie
meekwam: elf in `watchlist_availability_resolver_test.dart` (de resolver draait nu op de gedeelde
`fanOutFindAllByIdentity`), één in `data_aggregation_bridge_test.dart`, één in
`automation_ids_yaml_test.dart` (de gegenereerde YAML). Met de bijbehorende versies van die drie
bestanden erbij zijn ze alle dertien groen, gecontroleerd per bestand.

*Conclusie.* De gedeelde laag landt als zelfstandige prerequisite, zonder de TV-presentatielaag en
zonder een tweede implementatie. Voorwaarde is dat de bijbehorende tests meekomen: 171 niet-TV
testbestanden verschillen tussen `main` en de branch.

### C7. De prerequisite-fileset

107 niet-gegenereerde bestanden onder `lib/` en `assets/`, plus de gegenereerde `.g.dart`-bestanden
en `strings.g.dart` uit `scripts/codegen.sh` en `dart run slang`:

| Gebied | Aantal | Wat |
|---|---|---|
| `lib/media/unified/` | 10 | groep, bron, hub, watch state, identiteit, coverage, onthouden keuze |
| `lib/services/unified_catalog/` | 18 | merge-engine, identity, grouping, source resolver, activation coordinator, projectie, filters, prefetch |
| `lib/services/` overig | 13 + 5 submappen | de vijf clients (`findAllByIdentity`), `settings_service`, `data_aggregation_service`, `offline_watch_sync_service`, `rating_actions`, `unified_action_outcome`, `watchlist_availability_resolver` |
| `lib/providers/` | 8 | `unified_catalog_provider`, `unified_catalogs`, de twee projectieproviders, `discover_provider` (met `unansweredServerIds` en de `globalKey`-fix in `updateItem`), `multi_server_provider`, `offline_watch_provider`, `watch_state_store` |
| `lib/media/` overig | 4 | `media_identity`, `media_server_client`, `server_capabilities`, `watch_progress` |
| `lib/utils/`, `lib/automation/`, `lib/database/`, `lib/diagnostics/`, `lib/exceptions/` | 18 | timeouts, external ids, automation-catalogus, drift |
| `lib/widgets/` | 2 + notice | `pleya_wordmark.dart`, `optimized_media_image.dart`, `notice/` |
| `lib/screens/video_player/` | 3 + 1 | de foutfamilie die bij `playback_failure_classifier` hoort |
| `lib/navigation/navigation_tabs.dart` | 1 | `NavigationTabId.movies` en `.series`, zichtbaarheid TV-only |
| `lib/i18n/*.json` | 16 | de `unifiedCatalog`-sleutels in alle locales |
| `assets/branding/` | 4 | de wordmark-lagen |

Vier bestanden blijven bewust op `main` staan, want ze dragen het routecontract dat de mobiele fasen
zelf invullen: `lib/utils/media_navigation_helper.dart`, `lib/utils/video_player_navigation.dart`,
`lib/navigation/main_screen_scope.dart` en `lib/widgets/side_navigation/nav_destinations.dart`. Twee
switch-armen worden met de hand bijgezet: drie in `main_screen.dart` en één in
`side_navigation_rail.dart`, telkens `movies`/`series` naar een niet-renderend geval, omdat die tabs
op mobiel en desktop onzichtbaar blijven tot fase 2.

Eén seam verdient een eigen notitie: `media_detail_screen.dart` op de branch heeft precies één
TV-import, `tv_media_source_picker.dart`, plus de parameters `unifiedRouteContext` en
`onChangeSource`. Dat bestand zit **niet** in de prerequisite. Fase 5 voegt die parameters toe met
een injecteerbare picker, zodat iOS zijn eigen sheet meegeeft en tvOS de zijne houdt.

### C8. Legacy die de redesign raakt

1. `discover_screen.dart` is één klasse voor vier platformen. De mobiele Home wordt een eigen widget die `_buildContent` op `isMobile` kiest, naast de bestaande TV-tak op `:1470`; de desktop-tak blijft in `discover_screen.dart`.
2. `main_screen.dart:1932`: `_isMobile` staat op `false` bij declaratie en `_screens` wordt in `initState` gebouwd, zodat frame 1 op een telefoon geen Mijn Pleya-tab bevat en alles daarna nog een keer wordt gebouwd. Raakt de tabbalk-restyle.
3. Geen `extendBody` op de mobiele `Scaffold` (`main_screen.dart:1954`): de blur op de bar werkt op een dichte achtergrond.
4. `AutomationIds.navTab` wordt alleen op de rail gemount (`side_navigation_rail.dart:1156`); de mobiele bar heeft geen nodes.
5. Home-header op mobiel draagt vijf acties (refresh, Nu aan het kijken, Samen kijken, Afstandsbediening, en op desktop Server Tasks). De northstar-header heeft zoekicoon en avatar. Samen kijken en Afstandsbediening zijn vandaag alleen via die header bereikbaar; ze verhuizen (mockup 18 en 21 leggen ze onder Mijn Pleya).
6. `Home` refresht via de headerknop; pull-to-refresh bestaat alleen in `base_library_tab.dart:262-278`.
7. `homeHeroLayout` bevat de iPad-`island`-presentatie met regressiepins die de tvOS-branch als "byte-identiek" aanhaalt (hoofdstuk 9.4). Een phone-`card`-presentatie erbij laat die pins staan; de iPad-vraag staat in H.

## D. Northstar gap matrix

Kolommen: Surface · Current · Northstar · Gap · Reuse · Change · Risk.

| # | Surface | Current | Northstar | Gap | Reuse | Change | Risk |
|---|---|---|---|---|---|---|---|
| H | Home (comp + §10) | overlaid gradient-header met `PleyaLogo(28)` + getypte `PLEYA`, geen chips, edge-to-edge hero van max 12 films met één witte pill, 8 s-carousel met pauzeknop en max 5 dots, Verder kijken + hubs via `HubSection`, geen pull-to-refresh | lockup 28 pt + zoekicoon + avatar; chips Series / Films / Nieuw / Genres; billboard-kaart inset 16, meta `kind · genre · jaar · duur (· leeftijd)`, wit Afspelen + open CTA B; open indicator; Verder kijken als 16:9-kaarten met rode voortgangslijn en `S1 · A4 (i)`; 2:3-rijen | header, chips, kaartvorm, groepsdata, CTA's, kaartfamilie, tabbalk | `homeHeroLayout`-hoogteformule, `HomeHeroArtwork`-lagen, `MediaCardGridLayout`, `OptimizedMediaImage`, `TvHomeProjectionProvider`, `UnifiedActivationCoordinator`, `heroMetaLineFor`, `Pressable` | nieuwe `MobileHomeScreen` + mobiele kaartfamilie; zie F | hoog, want dit is de eerste slice die de familie zet |
| 01 | Series-landing | bestaat niet (Series is geen tab) | titel `Series` + `Alle series ›`, rijen in providervolgorde, `2 bronnen`-capsule, amber stip | tab, landing, rijen | `TvDiscoveryLandingProvider.seriesRails`, mobiele rail en kaart uit fase 1, `NavigationTabId.series` | guard in `getVisibleTabs` versoepelen voor `isMobile`; `MobileLandingScreen(kind)`; tabset wisselen | middel: tabset-wissel raakt Zoeken en Bibliotheken |
| 02 | Films-landing | idem | idem met filmmeta `jaar · genre`, vinkje | idem | `movieRails` | idem | idem |
| 03 | Alle films | `library_browse_tab.dart`: per bibliotheek, opties-sheet met drie sub-pagina's, geen teller op mobiel (`:1670-1684`), geen "Alle bronnen" | back + titel + zoekicoon, chips `Alle bronnen · Filters 2 · Titel A–Z`, `126 titels geladen` + actieve filtersamenvatting, driekoloms 2:3-grid | cross-server catalogus, chips, telling (10.7) | `UnifiedCatalogProvider`, `UnifiedCatalogs`, `unified_catalog_filters.dart`, `MediaGridGeometry`, `FocusableFilterChip` | nieuw `MobileCatalogScreen`; `LibraryBrowseTab` blijft voor Bibliotheken | middel: paging-semantiek van de merge-engine |
| 04 | Filters-sheet | `FiltersBottomSheet`: één waarde per categorie, sub-pagina per categorie, sluit bij toepassen | tweekoloms paneel, actieve categorie als band met streep, selectie met vinkje, voet `Wissen` en `Toepassen`, `2 actief` | compositie, multi-select | `OverlaySheetHost.push` voor sub-pagina's, `unified_filter_options.dart` | nieuw `MobileFilterSheet` op `UnifiedCatalogQuery` | laag |
| 05 | Zoeken | eigen tab; platte lijst `FocusableMediaCard(forceListMode)`, geen groepering, Seerr-fallback als losse rij na expliciete tik | headericoon; gegroepeerd Films / Series met `2 bronnen`, `Niet op je servers` met `+ Aanvragen`-chip, chips Alles / Films / Series / Afleveringen | route in plaats van tab, groepering, bronaantal, Seerr-sectie | `SearchProjection` (16.1), `FocusableFilterChip`, `FocusableTextField`, Seerr-provider | `search_screen.dart` (859) krijgt mobiele body op de projectie; entree via header | middel: 859 regels met TV-toetsenbordpaden |
| 06 | Film-detail | `media_detail_screen.dart`: hero 60 % hoog met vierkante art, metaregel met `match`-percentage, `Play` zonder label, geen resttijd, geen bronregel, acties in één rij met overflow | 16:9-preview met play, tags `12 · 2u 46m · 4K · HDR · Atmos`, witte `Hervatten · nog 1u 12m`, `Downloaden`, bronregel `Bron NAS · Films 4K [Wijzigen]` bij meer dan één bron, overzicht, cast, actierij | compositie, resttijd, bronregel (15), route-replacement bij bronwissel | `UnifiedMediaGroup.watchState`, `UnifiedRouteContext`, `CastSection`, `ExtrasSection`, `HubSection` voor "Meer zoals dit" | mobiele detail-body als eigen widget onder de bestaande state; `action_buttons.dart` blijft de handlerlaag | hoog: 4849 regels, `part of`-structuur |
| 07 | Serie-afleveringen | seizoentabs (`FocusableTabChip.segmented`) + `EpisodeCard` (still 144 pt, `WatchedIndicator.compact`, downloadicoon) | witte `Hervatten S2:A4 · nog 18 min` bovenaan, tabs Afleveringen / Vergelijkbaar / Extra's / Details, seizoenkiezer als chip met chevron, `10 afleveringen · 4 bekeken`, rijen met resttijd en `gedownload` | tabs in plaats van één lange pagina, resttijd per rij | `EpisodeCard` (still, spoilerblur, downloadslice), seizoenpaging, `WatchStateStore` | mobiele tabs boven de bestaande secties | middel |
| 08 | Bronkeuze-sheet | bestaat niet; Play gaat naar `item.serverId` | sheet met poster + `beschikbaar op 3 servers`, rijen `NAS · Plex · Films 4K · 2160p · HDR10 · Dolby Atmos · Hervatten op 1:34:02`, `Laatst gebruikt`, offline bron gedimd, `Meer bronnen controleren…`, witte `Afspelen op NAS` | alles | `UnifiedActivationCoordinator`, `TvSourceRowDescriptor` (na extractie), `PreferredServerStore`, `SourcePreferenceStore`, `OverlaySheetHost` | `MobileSourcePickerSheet`; het integratiepatroon uit `tv_media_source_picker_route.dart` | middel |
| 09 | Contextmenu-sheet | `MediaContextMenu` (1866): `AppMenuSheet` met 20 acties op één `MediaItem` | groepskop met voortgang en `2 bronnen`, Hervatten met resttijd, Details, Mijn lijst, `Markeer als bekeken · Op alle bronnen`, Verwijder uit Verder kijken, `Downloaden · Kies eerst een bron ›`, `Bron wijzigen · NAS · Series 4K ›` | groepsacties (23), DEC-071 | `unified_action_outcome.dart`, `rating_actions.dart`, `WatchActions` per bron, `OverlaySheetHost` | nieuwe `MobileGroupActionSheet`; `MediaContextMenu` blijft voor bibliotheek en desktop | hoog: schrijfpaden |
| 10 | Live TV | `live_tv_screen.dart`: chips Gids / Nu op TV / [Opnames], EPG-raster 132 pt-kolom, hubs uit Plex, geen voortgang per zender | chips Nu op TV / Gids / Opnames, favorieten als 16:9-kaarten met LIVE-badge, `HDHomeRun · 42 kanalen`, zenderrijen met voortgangsbalk | kaartenrij, zenderrijen | `LiveTvFavorites`, `ProgramDetailsSheet`, EPG-data | mobiele body voor "Nu op TV"; gids blijft raster | laag |
| 11 | Mijn lijst | `watchlist_screen.dart`: grid, chips Alles / Films / Series / [Beschikbaar], `WatchlistCard` dimt `notFound` | `Alles · 24` rood omlijnd, sorteericoon, driekoloms grid met `2 bronnen` en vinkje | chips-stijl, kaart | `WatchlistProvider`, `WatchlistAvailabilityResolver`, mobiele kaart | `WatchlistCard` → mobiele kaart; long-press naar 09 | laag, maar zie C4 over `lastKnownMatch` als schrijfdoel |
| 12 | Downloads | drie tabs Beheren / Series / Films, `DownloadTreeView`, geen opslagbalk | opslagbalk `18,4 GB van 64 GB`, chips Alles / Series / Films / `Bezig · 2`, secties Bezig en Gedownload per titel met `synchronisatieregel` | opslagbalk (nieuwe data), secties | `DownloadProvider`, `SyncRulesScreen`, statusaggregatie uit `download_tree_view.dart:288-315` | mobiele body; opslagcijfers via een platformkanaal of `disk_space`-plugin (ring 2) | middel: nieuwe dependency |
| 13 | Meldingen | bestaat niet | `Nieuw voor jou` met Vandaag / Deze week: nieuwe aflevering, aanvraag beschikbaar, nieuw seizoen, recent toegevoegd, `Plex familie: opnieuw aanmelden` | scherm, feed, gelezen-status, instelling | `newBadgeLabel` (14-dagenvenster), `getLatestMoviesFromAllServers`, `SeerrRequestStatus`, `MultiServerProvider.authErrorServers` | nieuwe `NotificationFeedService` + scherm; rode stip op Mijn Pleya | middel: definitie van "gelezen" |
| 14 | Instellingen | `settings_screen.dart` (1259): tien groepen, `SettingNavigationTile` met waarde op subregel | vier groepen App en afspelen / Koppelingen / Verbindingen / …, waarde op subregel, amber punt bij Servers | hergroepering, statuspunt | alle settings-primitieven | groepen herindelen; `SettingsIconBadge` blijft | laag |
| 15 | Bibliotheken | `libraries_screen.dart`: dropdown-titel, tabs, grid per bibliotheek | serverchips `Alle · NAS · …`, tegels 2 per rij met status en count, `Recent toegevoegd in Films 4K` | tegelscherm als ingang | `LibrariesProvider`, `HiddenLibrariesProvider`, `LibraryQuickPickerSheet`-groepering, `fetchRecentlyAdded` | nieuwe `MobileLibrariesScreen` boven het bestaande browse-scherm | laag |
| 16 | Profiel kiezen | `_buildSelectionGate`: ArchivoBlack-titel, `Wrap` van 120 pt-tegels met witte focusrand, outline-knop | lockup 34–44 pt, `Wie kijkt er?`, 2×2 met radius, slotje, `Toevoegen` gestippeld, capsule `PROFIELEN BEHEREN` | lockup, tegelvorm, gestippelde Toevoegen | `ProfileAvatar` (slotje bestaat), `profile_activation.dart` | gate-body restylen, `PleyaLogo` niet gebruiken | laag |
| 17 | Inloggen | `PleyaLogo(96)` + getypte `PLEYA` + tagline; Plex en Jellyfin als capsules, QR als outline; Pleya Server, Share en lokale map alleen via Instellingen | lockup + tagline, `Verbind je mediaserver`, witte Plex-capsule, Jellyfin en Pleya Server als donkere capsules, Share en lokale map als tekstlinks, versie + docs-link | lockup, Pleya Server-knop, tekstlinks | `_primaryCta`, `AddPleyaServerScreen`, `PleyaShareJoinScreen`, `AddLocalFolderScreen` | brandheader → `PleyaBrandLockup`; knoppen herordenen | laag |
| 18 | Mijn Pleya volledig | avatar + naam, kijklijst-rail, Downloads, Aanvragen, Profielen, Instellingen, Uitloggen als kale `ListTile`s | header met `2 van 3 servers online` + amber authregel + `Wisselen`; tegels Mijn lijst 24 / Aanvragen 3 / Downloads 7; tegels Bibliotheken / Servers (amber punt) / Activiteit; lijst Nieuw voor jou (rode stip) / Samen kijken / Instellingen / Over Pleya | drie groepen (18.1), counts, statuspunten, zes nieuwe bestemmingen | `MultiServerProvider.authErrorServers`, `WatchlistProvider`, `SeerrProvider`, `DownloadProvider`, `SettingsGroup`/`SettingsRows` | `my_pleya_screen.dart` herschrijven op de settings-primitieven | middel: zes bestemmingen moeten bestaan |
| 19 | Aanvragen | `seerr_discover_screen.dart` (925) + apart `seerr_requests_screen.dart` | zoekveld, chips, `Mijn aanvragen · 3` met statusstip, Populair nu met `+ Aanvragen`-overlay, Binnenkort | samenvoegen in één scherm | `SeerrProvider`, `SeerrPosterCard`, `SeerrStatusBadge`, `SegmentedTabGroup` | mobiele body | laag |
| 20 | Speler | `mobile_video_controls.dart`: topbar met titel, 72 pt play, 48 pt prev/next, 10 s alleen via dubbeltik, tijdlijn met eindtijd, Skip intro rechtsonder | bronregel `NAS · 2160p · HDR10 · Dolby Atmos`, Cast + AirPlay + ⋯, 10 s-knoppen naast play, hoofdstukmarkers, resttijd, `Intro overslaan` boven de tijdlijn, actierij `1,0× · Vergrendelen · Audio en ondertitels · Slaaptimer · Afleveringen` | bronregel, 10 s-knoppen, actierij | `VideoControlsHeader`, `VideoTimelineBar`, `TrackSheet`, `VideoSettingsSheet`, `MobileSkipZones` | controls-layout aanpassen; bron uit `UnifiedRouteContext` | middel: speler is gevoelig |
| 21 | Activiteit | `now_watching_screen.dart` is TV-only; mobiel heeft een sheet vanuit de Home-header; Samen kijken en Afstandsbediening zijn losse headericonen | secties Nu aan het kijken (met `Bedienen`), Samen kijken (Kamer maken, recente kamer), Serveractiviteit | één scherm | `NowWatchingPanel`, `WatchTogetherScreen`-onderdelen, `MobileRemoteScreen`, `ServerActivities` | nieuwe `MobileActivityScreen` onder Mijn Pleya | laag |

## E. Dependency graph

**FOUNDATION**

- F0. De platformneutrale laag van `claude/netflix-redesign-b4x21v` beschikbaar krijgen. Zonder F0 heeft geen enkel northstar-oppervlak bronaantallen, groepsacties of een bronkiezer, en zou fase 1 een visuele pass op rauwe `MediaItem`s worden die later opnieuw bedraad moet worden. Dat is de half-gemigreerde tussenstand die het plan moet vermijden. **F0 is een zelfstandige prerequisite, geen merge van de TV-branch.** De meting die dat onderbouwt staat in sectie C6; de fileset in C7.
- F1. Toolchain-baseline: pinned SDK, `flutter test` groen, het bestaande ios-sim-scenario `discover.hero.layout` met screenshot als nulmeting vóór F0, en opnieuw na F0 met identiek beeld.
- F2. Drie extracties zonder gedragswijziging: `heroMetaLineFor`/`heroTitleFor` uit `tv_hero_billboard_card.dart` naar `lib/services/unified_catalog/hero_text.dart`; `TvSourceRowDescriptor` naar `lib/media/unified/source_row_descriptor.dart` als `SourceRowDescriptor`; `SkeletonLoader` uit `media_card.dart` naar `skeletons.dart`. TV-imports mee-verplaatsen.
- F3. Automation-ids voor mobiel: `nav.bar`, mount van `navTab` op de bottom bar, `home.header`, `home.header.search`, `home.header.avatar`, `home.chips`, `home.rail` (instanceable), `home.rail.item` (instanceable), `sheet.source_picker`, `sheet.source_picker.row` (instanceable). `discover.hero` en `discover.hero.play` blijven bestaan, want het bestaande scenario leunt erop.

**SHARED PRESENTATION** (mobiele familie, `lib/widgets/mobile/`)

- S1. `MobilePageHeader`: lockup of titel links, acties rechts (zoek, avatar). Hangt op F0 (`PleyaWordmark`).
- S2. `MobileChipBar`: horizontale rij `FocusableFilterChip`s met `Haptics.light()`.
- S3. `MediaMarkers`: `SourceCountCapsule`, `WatchedTick`, `ResumeLine`, `NewEpisodeDot`, platformneutraal in `lib/widgets/media_markers.dart`. Hangt op F0 (`UnifiedWatchState`).
- S4. `MobileMediaCard(UnifiedMediaGroup)`: 2:3 of 16:9, onderschrift uit `MediaCardGridLayout`, markers uit S3, `Pressable`, long-press-callback.
- S5. `MobileMediaRail(UnifiedMediaHub)`: kop met titel en `Alles bekijken ›`, `ListView.builder` van S4, hoogte uit `MediaCardGridLayout`.
- S6. `MobileHeroCard`: presentatie `mobileFeatured` in `homeHeroLayout`, artwork via `HomeHeroArtwork`, tekst via F2, CTA-rij en indicator als losse widgets (seam voor A en B).
- S7. Bottom bar restyle in `main_screen.dart:1715-1790` en `navigation_tabs.dart:15-78`: rood actief icoon plus label, avatar met rode ring op Mijn Pleya, dot-slot weg, `extendBody: true`.
- S8. `MobileSourcePickerSheet` op `OverlaySheetHost`, rijen uit F2, beslissing uit `UnifiedActivationCoordinator`.
- S9. `MobileRefreshScope`: `RefreshIndicator` + `Haptics.light()`, gedeeld door Home, landings, kijklijst, downloads.

S1 tot en met S9 hangen op F0, F2, F3. Onderling: S4 op S3; S5 op S4; S6 op F2 en S3.

**SURFACE IMPLEMENTATION**

- Fase 1: Home (S1–S9) plus tijdelijke verhuizing van drie headeracties naar Mijn Pleya. Tabset ongewijzigd.
- Fase 2: Series- en Films-landing (01, 02) op S1, S5; tabset naar Home · Series · Films · [Live TV] · Mijn Pleya; Zoeken als route vanuit S1; Bibliotheken-tegel in Mijn Pleya; `LibraryQuickPickerSheet` verhuist mee.
- Fase 3: Alle films / Alle series (03, 04) op `UnifiedCatalogProvider`.
- Fase 4: Zoeken (05) op `SearchProjection`.
- Fase 5: Detail (06, 07), bronregel, bronwissel via S8, contextsheet (09) met DEC-071. Hier landt de correctie van `WatchlistCard.lastKnownMatch` als schrijfdoel.
- Fase 6: Mijn Pleya (18), Meldingen (13), Activiteit (21), Bibliotheken (15), Instellingen (14).
- Fase 7: Profiel kiezen (16), Inloggen (17).
- Fase 8: Mijn lijst (11), Downloads (12), Live TV (10), Aanvragen (19).
- Fase 9: Speler (20).

Fase 2 hangt op fase 1 (rail, kaart, header). Fase 5 hangt op S8. Fase 6 hangt op niets uit 2 tot en met 5 en kan parallel na fase 1. Fase 3 en 4 hangen alleen op F0 en S1/S2/S4. Fase 8 en 9 hangen op S1–S5.

**VERIFICATION** (per fase, zie F en G)

- V1. Widgettests op iPhone 15 Pro-viewport (393×852 logisch, dpr 3) met gepinde maten uit de mockup.
- V2. `flutter test` volledig, `scripts/ci_checks.sh`, alles op 3.44.0.
- V3. Pleya Verify ios-sim-scenario per fase met `snapshot` en geometrie-asserts.
- V4. Contactvel northstar naast implementatie voor de visuele beoordeling; hulpscript buiten de repo.

## F. Fase-1-voorstel: Home als verticale slice, met F0 als voorwaarde

### Waarom Home, en waarom F0 eerst

Home legt de mobiele familie vast: header met lockup, chips, kaart met 2:3 en 16:9, rail, broncapsule, vinkje, voortgangslijn, tabbalk, pull-to-refresh, en de bronkiezer als de hero meer dan één bron heeft. Alle andere schermen in de 21-set gebruiken minstens vier van die onderdelen. De code bevestigt dat Home ook technisch de juiste eerste stap is: `discover_screen.dart` is al gesplitst op platform (`:1470`), de hero-geometrie heeft een eigen pure laag met 831 regels tests, en de projectieproviders voor groepsdata bestaan al op de tvOS-branch en zijn zonder guard geregistreerd.

F0 is geen opruiming. Zonder F0 kan Home geen `2 bronnen` tonen (01, 02 en de comp vragen het), kan de hero-Play niet door de activatiecoördinator, en zou het lockup een kopie van `pleya_wordmark.dart` op twee branches worden. De concrete Home-delta die F0 ontsluit: broncapsule op kaarten, hero uit `heroGroups` (9.5), Play via 14.6, metaregel via `heroMetaLineFor`, lockup in de header.

### Scope

- Nieuwe `MobileHomeScreen` die `DiscoverScreen._buildContent` op `PlatformDetector.isMobile` kiest, met de tiers `phone` van `HomeHeroContentTier`. iPad valt in fase 1 terug op de bestaande Home; zie H3.
- Header, chips Series en Films (functioneel: schakelen tussen Home, `seriesRails`, `movieRails`), hero-kaart, Verder kijken, rijen, tabbalk-restyle, pull-to-refresh, bronkiezer-sheet.
- Tijdelijke groep `Activiteit` in `my_pleya_screen.dart` met de drie rijen Nu aan het kijken, Samen kijken, Afstandsbediening, zodat niets uit de oude header verdwijnt.

### Expliciete non-scope

Tabset, Series/Films als tab, Zoeken als route, Alle films, detail, contextsheet (09), Mijn Pleya-herstructurering, verplaatsen van bestemmingen, Meldingen, iPad-hero, desktop, TV, de chips Nieuw en Genres (H5), de keuze in A en B.

### Stappen

Elke stap is één commit, tenzij anders vermeld. Alle commands met `PATH=/Volumes/SSD/flutter-sdks/3.44.0/bin:$PATH`.

**Stap 0. Nulmeting**

- DOEL: bewijs dat de mobiele Home vóór F0 en na F0 hetzelfde rendert.
- BESTANDEN: geen wijziging; output naar `.build/pleya-verify/<run-id>/`.
- WIJZIGING: `flutter test` volledig; `cd pleya_verify/runner && dart run bin/verify.dart run ../scenarios/discover.hero.layout.yaml --json`; screenshot bewaren als `home-before-f0.png` buiten de repo.
- WAAROM: de ios-sim-driver bestaat (`ios_simulator_driver.dart`), het scenario bestaat, en dit is de enige objectieve maat voor "mobiel ongewijzigd door F0".
- RISICO: het scenario draait in CI onder de macOS-job; lokaal moet een iPhone-simulator gebouwd worden. Kost tijd, geen onzekerheid.
- BEWIJS: testtelling groen op 3.44.0, PASS in `report.md`, screenshot.

**Stap 1. F0: de gedeelde laag als zelfstandige prerequisite**

- DOEL: de kern uit C7 beschikbaar maken zonder de TV-presentatielaag, zodat tvOS en iOS er allebei op staan in plaats van iOS op tvOS.
- BESTANDEN: de 107 bestanden uit C7 plus hun 171 niet-TV testbestanden, de vier seams op `main`, de twee switch-armen met de hand.
- WIJZIGING: een eigen commitreeks die de fasegrenzen van de herkomst volgt, zodat elke commit een leesbare eenheid is: (1a) identiteit en model, `lib/media/unified/` plus de vier gewijzigde `lib/media/`-bestanden en `findAllByIdentity` op de vijf clients; (1b) resolver, coverage en merge-engine; (1c) activation coordinator plus `PreferredServerStore` en `SourcePreferenceStore` met hun `SettingsService`-getters; (1d) projectie en de vier providers, inclusief `unansweredServerIds` en de `globalKey`-fix in `updateItem`; (1e) DEC-071 groepsacties en `RatingActions`; (1f) `PleyaWordmark` met de twee assets; (1g) `NavigationTabId.movies`/`.series` met de switch-armen; (1h) i18n en codegen. Elke commit draagt zijn eigen tests mee.
- WAAROM: gemeten, niet aangenomen. C6 laat zien dat deze snede op nul analyzerfouten uitkomt en dat de dertien testfalers hun eigen testbestand missen, niet gedrag. Een merge van `f8e0e59` zou de mobiele release aan 54 tvOS-commits binden.
- WAAR HIJ LANDT: dat is een aparte vraag, zie H1. De reeks is zo geschreven dat hij zowel op `feat/netflix-mobile` als op een gedeelde basis kan landen; de fileset verandert daar niet van.
- RISICO: de reeks raakt vijf backendclients en `settings_service`, dus servergedrag en voorkeuren. Dat is precies wat de 171 tests dekken. Tweede risico: `check-unused-code` valt over een gedeelde klasse die op deze branch nog geen aanroeper heeft; per commit controleren.
- BEWIJS: per commit `scripts/ci_checks.sh` en `flutter test` groen op de gepinde SDK; na de laatste commit stap 0 herhaald met byte-identieke screenshot (`cmp` tegen `home-before-f0.png`); `discover.hero.layout.macos` en `tvos.smoke.boot` PASS.

**Stap 2. F2: extracties**

- DOEL: pure functies uit TV-bestanden halen.
- BESTANDEN: nieuw `lib/services/unified_catalog/hero_text.dart` (`heroMetaLineFor`, `heroTitleFor`), nieuw `lib/media/unified/source_row_descriptor.dart` (`SourceRowDescriptor`, hernoemd), `lib/widgets/skeletons.dart` (`SkeletonLoader` erin), en de importupdates in `tv_hero_billboard_card.dart`, `tv_source_row.dart`, `tv_media_source_picker.dart`, `media_card.dart`.
- WIJZIGING: verplaatsen, hernoemen, imports.
- WAAROM: een mobiele widget die uit `lib/widgets/tv/` importeert is de koppeling die de audit wil vermijden.
- RISICO: `check-unused-code` en `check-unused-files` in `ci_checks.sh` vallen over een achtergebleven bestand.
- BEWIJS: `flutter test` groen, `ci_checks.sh` groen, diff bevat geen logica.

**Stap 3. F3: automation-ids**

- DOEL: de mobiele bar en de nieuwe familie zichtbaar maken voor Pleya Verify.
- BESTANDEN: `lib/automation/automation_ids.dart` (ids uit E, in `catalog()`), `main_screen.dart:1723-1732` (`AutomationNode` per tab met `navTab`), `pleya_verify/automation_ids.yaml` via `tool/generate_automation_ids_yaml.dart`.
- WAAROM: `test/architecture/automation_ids_test.dart` en `automation_ids_yaml_test.dart` bewaken de catalogus; zonder ids geen scenario.
- RISICO: geen.
- BEWIJS: beide architectuurtests groen; `GET /v1/automation_ids` in het scenario van stap 10 bevat de nieuwe ids.

**Stap 4. S3 + S4 + S5: markers, kaart, rail**

- DOEL: de kaartfamilie.
- BESTANDEN: nieuw `lib/widgets/media_markers.dart`, `lib/widgets/mobile/mobile_media_card.dart`, `lib/widgets/mobile/mobile_media_rail.dart`; tests `test/widgets/media_markers_test.dart`, `test/widgets/mobile/mobile_media_card_test.dart`, `test/widgets/mobile/mobile_media_rail_test.dart`.
- WIJZIGING: `MobileMediaCard({required UnifiedMediaGroup group, required MobileCardShape shape, VoidCallback onTap, VoidCallback onLongPress})`. Poster via `OptimizedMediaImage.poster` op `group.representativeSource.item`; onderschrift `title` 13 pt en `jaar · N seizoenen` of `jaar · genre` 11 pt uit `MediaCardGridLayout`; `SourceCountCapsule` alleen bij `hasMultipleSources`; `WatchedTick` (donkere capsule, `Symbols.check_rounded`) bij `watchState.isWatched`; `ResumeLine` in `kAccent` bij voortgang; `NewEpisodeDot` in `kAccentAlt` bij `newBadgeLabel == 'NEW EPISODE'`. Kaartradius `MonoTokens.radiusSm`. 16:9-variant met `S1 · A4` en info-icoon in het onderschrift. Rail: kop 20 pt w700 met `Alles bekijken ›` in `textMuted`, `ListView.builder`, kaartbreedte zodat 3,3 kaarten passen op 393 pt (mockup 01: kaart ±118 pt, gutter 12, inset 16).
- WAAROM: `MediaCard` neemt geen groep en draagt 17 vlaggen; `HubSection` draagt D-pad-API.
- RISICO: dubbele kaartfamilie tijdens de migratie. Bewust: `MediaCard` blijft voor bibliotheek en desktop tot fase 3 en 8 hem vervangen.
- BEWIJS: widgettests pinnen: posterverhouding 2:3 op 393 pt, capsule afwezig bij één bron, tick en NEW nooit samen (overgenomen invariant uit `tv_unified_media_card.dart:337-347`), onderschrifthoogte groeit mee met `textScaler`, geen overflow op 320 en 430 pt.

**Stap 5. S1 + S2 + S9: header, chips, refresh**

- BESTANDEN: nieuw `lib/widgets/mobile/mobile_page_header.dart`, `mobile_chip_bar.dart`, `mobile_refresh_scope.dart`; tests ernaast.
- WIJZIGING: header 28 pt `PleyaWordmark(height: 28)` links, `AppIcon(Symbols.search_rounded)` en `ProfileAvatar(size: 32)` rechts, padding 16, top uit `MediaQuery.viewPaddingOf`. Chips via `FocusableFilterChip(variant: outlined)`; actieve staat is de bestaande accent-tint (`focusable_filter_chip.dart:135-138`), zie H5 voor de stijlkeuze. Refresh: `RefreshIndicator` met `Haptics.light()` zoals `base_library_tab.dart:275`.
- WAAROM: rapport §3 (lockup), §7 (pull-to-refresh).
- RISICO: `pleya_wordmark.dart` verwacht een hoogte, geen breedte; een caller die breedte pint plet het lockup.
- BEWIJS: test dat `PleyaLogo` nergens in de nieuwe bestanden voorkomt; test dat het lockup 28 pt hoog is; test dat de zoekactie `_selectTab(search)` aanroept.

**Stap 6. S6: hero-kaart** (twee commits: layout, dan widget)

- BESTANDEN: `lib/utils/home_hero_layout.dart` (presentatie `mobileFeatured`), `lib/widgets/home_hero_artwork.dart` (clip op radius), nieuw `lib/widgets/mobile/mobile_hero_card.dart`, `mobile_hero_actions.dart`, `mobile_hero_indicator.dart`; tests `test/utils/home_hero_layout_test.dart` (nieuwe groep, bestaande pins ongewijzigd), `test/widgets/mobile/mobile_hero_card_test.dart`.
- WIJZIGING: `HomeHeroSharpPresentation.mobileFeatured` met inset 16, radius 14 (`cardTheme` in `mono_theme.dart:178`), hoogte uit de bestaande `homeHeroHeight`-formule minus inset; artwork `BoxFit.cover` met scrim in `MonoTokens.artworkScrim` (geen hardcoded zwart, hoofdstuk 34). Data: `TvHomeProjectionProvider.heroGroups`. Tekst: clearlogo of `heroTitleFor`, meta `heroMetaLineFor(group)` plus `contentRating` erachter, samenvatting twee regels. CTA-rij: `MobileHeroActions(primary: Afspelen of Hervatten met minuten, secondary: HeroSecondaryAction)`, met `enum HeroSecondaryAction { moreInfo, addToList }`. Indicator: `MobileHeroIndicator(style: HeroIndicatorStyle)` met `enum HeroIndicatorStyle { persistentDots, transientSegment }`. Beide enums krijgen een placeholder-default in één const in `mobile_hero_card.dart`, gemarkeerd als open (DEC-090 §10); de placeholder is geen besluit. Carousel: `PageView`, 8 s auto-advance, pauze bij elke interactie, geen rotatie onder Reduce Motion (9.6).
- WAAROM: rapport §7 zegt dat de kaart een wijziging in `home_hero_layout.dart` is, niet een tweede hero.
- RISICO: hoofdstuk 9.4 op de tvOS-branch noemt de mobiele geometrie byte-identiek. De `island`- en `fullWidth`-paden blijven ongewijzigd, dus de bestaande pins blijven groen; `mobileFeatured` komt ernaast. De naam zegt bewust niet `phone`: de presentatie is een layoutkeuze die de caller maakt, en `home_hero_layout.dart` bevat vandaag geen enkele `PlatformDetector`-aanroep. Dat blijft zo, zodat iPad hem later kan kiezen zonder de hero te hoeven verbouwen. Dat vraagt een DEC (H2).
- BEWIJS: bestaande 831 regels `home_hero_layout_test.dart` groen zonder wijziging; nieuwe pins: kaart links op 16, breedte 361 op 393, radius 14, hoogte zodat kaart plus rail-kop plus eerste rij in 852 pt passen; `HomeHeroArtwork`-test: één URL, één cache-entry (bestaand patroon).

**Stap 7. S8: bronkiezer-sheet**

- BESTANDEN: nieuw `lib/widgets/mobile/mobile_source_picker_sheet.dart`, `lib/services/unified_catalog/mobile_activation.dart` (het integratiepatroon uit `tv_media_source_picker_route.dart` zonder overlay-specifiek deel); tests.
- WIJZIGING: `OverlaySheetController.of(context).show(showDragHandle: true)`; kop met poster 56×84, titel, `beschikbaar op N servers`; rijen uit `SourceRowDescriptor` met groene of rode stip, `Laatst gebruikt`, offline gedimd, `Hervatten op h:mm:ss`; `Meer bronnen controleren…` zolang `SourceCoverageState` open is; witte `Afspelen op <server>`. Beslissing uit `UnifiedActivationCoordinator`: één bruikbare bron slaat de sheet over.
- WAAROM: zonder 08 kan de hero-Play niet source-aware zijn. Tap op een kaart opent detail met `representativeSource.item` (leespad), long-press opent tot fase 5 het bestaande `MediaContextMenu` op datzelfde item. Dat is het gedrag van vandaag: de dedup-winnaar is nu ook het schrijfdoel. Fase 1 verergert dat niet en verbetert het niet; fase 5 lost het op.
- RISICO: `PreferredServerStore` en `SourcePreferenceStore` moeten in de profiel-subtree staan; controleren na F0.
- BEWIJS: unit-tests op de coördinatorbeslissing bestaan al op de tvOS-branch; widgettest: sheet opent alleen bij meer dan één bruikbare bron; sheet kiest nooit zelf.

**Stap 8. Surface: `MobileHomeScreen`**

- BESTANDEN: nieuw `lib/screens/home/mobile_home_screen.dart` (doel onder 400 regels), `lib/screens/discover_screen.dart` (`_buildContent`: `if (PlatformDetector.isPhone(context)) return MobileHomeScreen(...)` naast de TV-tak). `my_pleya_screen.dart` wordt **niet** aangeraakt.
- HEADERACTIES: Nu aan het kijken, Samen kijken en Afstandsbediening blijven in de mobiele header, naast het zoekicoon en de avatar. Ze verhuizen pas in de fase waarin de rootnavigatie definitief migreert (fase 6, mockup 18 en 21). Refresh verdwijnt wel uit de header, want pull-to-refresh vervangt hem functioneel op hetzelfde scherm; dat is geen verplaatsing naar een andere bestemming. De header wordt daarmee in fase 1 voller dan de comp: lockup links, dan de conditionele acties, dan zoek en avatar. Dat is een zichtbare afwijking van de comp en staat als zodanig in de fase-1-oplevering, met de bijbehorende northstar-vergelijking. Ze verdwijnt vanzelf in fase 6.
- WIJZIGING: `CustomScrollView` met `MobileRefreshScope`; slivers: header, chips, hero (alleen op de Home-stand), Verder kijken uit `TvHomeProjectionProvider.continueWatching` als 16:9-rail, rijen uit `.hubs` (Home) of `TvDiscoveryLandingProvider.seriesRails` / `movieRails` (chip Series / Films); `HomeLayoutProvider` blijft de volgorde en verbergen bepalen; `TopTenRow` blijft; skeletons per rij; lege en foutstaat zoals nu. `AutomationScreen(screen.discover)` met de readiness van vandaag.
- WAAROM: `discover_screen.dart` mag niet groeien; de mobiele tak wordt een eigen bestand.
- RISICO: `_isMobile`-race in `main_screen.dart:1932` bestaat al; de nieuwe tak gebruikt `isPhone(context)` in `build`, dus geen extra race.
- BEWIJS: `test/screens/mobile_home_screen_test.dart`: rendert alle rijen uit de provider in volgorde; Series-chip toont `seriesRails` zonder hero; hero-Play met één bron gaat naar `navigateToVideoPlayer` met dat item; met twee bronnen opent de sheet; pull-to-refresh roept `DiscoverProvider.load`; de drie verhuisde acties bestaan in Mijn Pleya (`my_pleya_screen_test.dart` uitbreiden).

**Stap 9. S7: tabbalk**

- BESTANDEN: `lib/screens/main_screen.dart:1715-1790`, `:1954` (`extendBody: true`), `lib/navigation/navigation_tabs.dart:15-78`.
- WIJZIGING: `_TabIcon` zonder dot-slot; actief icoon en label in `kAccent`; `MyPleyaTabIcon` met 2 pt-ring in `kAccent` bij selectie; rode 18×3-indicator weg; blur behouden; `Haptics.light()` bij tabwissel. Tabset ongewijzigd.
- WAAROM: elke mockup toont deze bar.
- RISICO: `test/navigation/account_entry_point_test.dart` test de avatar-glyph; aanpassen op de ring.
- BEWIJS: widgettest op 393 pt: vijf slots, actief label in `kAccent`, geen `Positioned` indicator; `main_screen_layout_test.dart` groen.

**Stap 10. Verificatie en documentatie**

- BESTANDEN: nieuw `pleya_verify/scenarios/ios.home.northstar.yaml` (`target: ios-sim`; `wait_until screen.discover`, `wait_until discover.hero`, `assert home.header insideViewport`, `assert home.header.search minimumTapTarget: 44`, `assert discover.hero insideViewport`, `assert discover.hero.play minimumTapTarget: 44`, `assert home.rail[0] below: discover.hero`, `assert nav.bar insideViewport`, `snapshot: home-northstar`); `docs/DECISIONS.md` DEC-091 (H2) en DEC-092 (fase 1 gesloten); `docs/CHANGELOG.md`.
- BEWIJS: PASS; contactvel `northstar-home.png | home-northstar.png` naast elkaar (script in scratchpad, niet in de repo) ter beoordeling; geen claim "pixel perfect".

### Commit-grenzen

0 (geen commit) · 1 merge · 2 · 3 · 4 · 5 · 6a layout · 6b widget · 7 · 8 · 9 · 10. Elke commit compileert, `ci_checks.sh` groen op 3.44.0. Tussen 5 en 8 is de app functioneel ongewijzigd voor de gebruiker (nieuwe widgets zonder aanroeper), wat `check-unused-code` niet accepteert: stap 4 tot en met 7 worden daarom in één branch-lokale reeks gemaakt en pas na stap 8 als reeks gecommit, of elke widget krijgt zijn test als enige aanroeper en de gate wordt per commit gecontroleerd. Het eerste is eenvoudiger en eerlijk over de gate.

## G. Definition of Done, fase 1

1. `scripts/ci_checks.sh` groen op `/Volumes/SSD/flutter-sdks/3.44.0`, inclusief format, codegen-versheid, analyze zonder warnings, unused-code en unused-files.
2. `flutter test` groen op 3.44.0; geen bestaande test uitgezet of afgezwakt; nieuwe tests uit stap 4 tot en met 9 aanwezig.
3. `discover.hero.layout` PASS vóór en na F0 met byte-identieke screenshot (stap 0 en 1).
4. `ios.home.northstar` PASS met snapshot in de evidence-bundle.
5. Contactvel Home-comp naast implementatie, en `01`/`02` naast de Series- en Films-stand van de chips, beoordeeld door Michel; afwijkingen benoemd, niet weggeschreven.
6. Op een iPhone 15 Pro-simulator: lockup in de header, geen `PleyaLogo` en geen getypte `PLEYA` op Home; broncapsule zichtbaar op een titel die op twee servers staat (fixture `catalog.mixed.v1` of een tweede seed); hero-Play met twee bronnen opent de sheet, met één bron niet.
7. Nu aan het kijken, Samen kijken en Afstandsbediening staan nog in de header en werken; refreshen kan via pull-to-refresh. Geen bestemming is verplaatst.
8. Desktop (native macOS-build) en tvOS-simulator: `discover.hero.layout.macos` en `tvos.smoke.boot` PASS, als bewijs dat de andere shells niet bewogen zijn.
8a. iPad: `test/screens/discover_hero_activation_test.dart` groen zonder wijziging, inclusief de bestaande pins op 768, 834 en 1024 pt en de `tabletPortrait`-tier, plus een screenshot van de iPad-Home vóór en na fase 1 die gelijk is. Dat is het bewijs dat de gedeelde wijzigingen de bestaande iPad-Home niet hebben aangeraakt.
9. `discover_screen.dart` niet gegroeid; `mobile_home_screen.dart` onder 400 regels; geen bestand in `lib/widgets/mobile/` boven 400.
10. DEC-091 en DEC-092 in `docs/DECISIONS.md`; A en B nog open en zo gemarkeerd in de code.
11. Geen import uit `lib/widgets/tv/` in `lib/widgets/mobile/` of `lib/screens/home/`.

## H. Open risks en vragen

H1. **Waar de prerequisite landt.** C6 bewijst dat de gedeelde laag zonder de TV-presentatielaag
compileert en test. Waar de commitreeks uit stap 1 landt, is een besluit dat ik niet neem. Drie
vormen, in volgorde van mijn voorkeur:

1. *Op een gedeelde basis, en van daaruit naar zowel de tvOS-branch als deze branch.* Dit is de vorm
   die de werkelijke afhankelijkheid weerspiegelt: één kern, twee platformen erop. Prijs: de
   tvOS-branch moet die basis opnemen, wat op een branch van 54 commits een rebase of merge betekent
   en dus afstemming vraagt met het lopende tvOS-werk in `pleya-teleport`.
2. *Rechtstreeks op `feat/netflix-mobile` als eigen commitreeks.* Snelste weg naar fase 1, en de
   fileset is identiek. Prijs: als de tvOS-branch later naar `main` gaat, komen dezelfde bestanden
   langs twee wegen binnen en moet één van beide de ander opnemen. Dat is werk, geen risico, maar het
   moet bewust gebeuren.
3. *Merge van `f8e0e59`.* Wat het vorige plan voorstelde. Ik raad het nu af: het bindt de mobiele
   release aan het integraal landen van de complete TV-redesign.

Wat in alle drie de gevallen geldt: werk met de SHA, niet met de branchnaam. De referentie is
`f8e0e59` in `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-teleport`, remote
`michelknoop21/pleya`. Die commit staat **niet op de remote**: `origin/claude/netflix-redesign-b4x21v`
ligt er 71 commits achter. Zolang dat zo is, bestaat de bron van de prerequisite op één machine, en
is dat precies hetzelfde probleem als bij de Home-comp. Duw `f8e0e59` naar de remote voordat de
reeks gebouwd wordt, ongeacht welke vorm het wordt. Het ongecommitte TV-railwerk in die werkboom
raakt de reeks niet: er wordt op een commit gewerkt, niet op de werkboom.

H2. **DEC-091: derde hero-presentatie.** Akkoord verwerkt. De presentatie heet `mobileFeatured`, niet
`phone`, en `home_hero_layout.dart` blijft vrij van platformchecks: de caller kiest. Hoofdstuk 9.4 op
de tvOS-branch belooft dat de mobiele geometrie byte-identiek blijft; `island` en `fullWidth` blijven
dat, de belofte versmalt van "alles" naar die twee. Vast te leggen als DEC-091.

H3. **iPad.** Akkoord verwerkt. Fase 1 laat de iPad op de bestaande Home. Nieuw in dit plan is het
bewijs daarvoor: DoD-punt 8a eist de bestaande iPad-pins ongewijzigd plus een gelijk screenshot vóór
en na. Vóór fase 2 de tabset wisselt, is een eigen iPad-authority en acceptatiebesluit nodig, want
die wissel raakt de iPad wel.

H4. **Headeracties.** Akkoord verwerkt, no-go voor de tijdelijke verhuizing. Nu aan het kijken, Samen
kijken en Afstandsbediening blijven staan tot fase 6 de rootnavigatie migreert. Gevolg dat expliciet
opgeleverd wordt: de fase-1-header is voller dan de comp, en dat is een bekende, tijdelijke afwijking
in plaats van een stille. Refresh verdwijnt wel, omdat pull-to-refresh hem op hetzelfde scherm
vervangt.

H5. **Chips.** Akkoord verwerkt voor Nieuw en Genres: die worden niet gerenderd zolang er geen
productbetekenis is vastgelegd. Het tweede deel is nog open en moet vóór stap 5 beslist worden, want
het raakt elk chip-scherm in de set: de comp toont een actieve chip met donkerrode vulling, mockup
05, 10, 11, 12 en 19 tonen een rode omlijning met rode tekst, mockup 15 een witte vulling. Er moet
één authority gelden. Mijn advies is de rode omlijning, omdat vijf van de eenentwintig bevroren
beelden hem tonen en de comp op dit punt geen mockup naast zich heeft. Dat is een advies, geen keuze.

H6. **`check-unused-code` tussen commits.** Zie de commit-grenzen in F; keuze tussen één reeks na
stap 8 of tests als aanroeper. Geldt ook voor de reeks in stap 1, waar gedeelde klassen tijdelijk
zonder mobiele aanroeper staan.

De twee Home-details A en B zijn geen blocker; de seam staat in stap 6.

## I. Stop

Geen productiecode gewijzigd, geen commit, geen merge, geen fetch, geen push. Ongecommit in de
werkboom staan: dit plan, de vijf comps in `docs/assets/ios-unified/northstar/`, en de registratie
daarvan in `docs/ios-unified-2026-audit.md` en `docs/DECISIONS.md`. De metingen uit C6 draaiden in
een wegwerp-boom in de scratchpad, buiten de repository.

Het plan wacht op één besluit: de vorm van H1. H2 tot en met H5 zijn verwerkt zoals besloten; van H5
staat alleen de chipstijl nog open, met een advies. H6 is een uitvoeringskeuze.

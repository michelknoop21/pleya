# Changelog

Sessie-voor-sessie logboek. Nieuwste bovenaan.

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

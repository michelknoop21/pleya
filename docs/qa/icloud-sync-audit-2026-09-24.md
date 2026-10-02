> Geschreven tegen `github/main` `76b83521` (via `d23f6c9f` op `feat/unified-desktop-ipad`); de spec [2026-09-24-icloud-sync-repair-design.md](../superpowers/specs/2026-09-24-icloud-sync-repair-design.md) heeft de regelnummers opnieuw nagelopen op `3ad702d3`.

# Audit iCloud-voorkeurensync

Datum: 2026-09-24. Alleen gelezen, niets gewijzigd. Worktree `feat/unified-desktop-ipad`,
HEAD `d23f6c9f`. Getoetst tegen DEC-059, DEC-060, DEC-061, `docs/qa/phase-a-preference-sync-report.md`,
`docs/qa/preference-sync-and-playback-matrix.md` en `docs/qa/icloud-kvs-native-audit.md`.
`docs/agents/architecture.md` zegt niets over de sync; het contract staat alleen in DECISIONS en de QA-map.

Regelnummers verwijzen naar de bestanden op deze HEAD. "Bevestigd" betekent: het pad staat letterlijk in de
code en het scenario volgt eruit zonder aannames over Apple-gedrag. "Aannemelijk" betekent: het hangt af
van timing of van gedrag van `NSUbiquitousKeyValueStore` dat niet in de repo bewezen is.

## Wat het contract belooft en wat de code doet

Het ontwerp (DEC-059) belooft vier dingen: een revisie-envelop met deterministische last-writer-wins op
`(updatedAt, deviceId)` en tombstones, live doorgeven van wijzigingen via de KVS-notificatie, een prune die
alleen verwijdert wat lokaal echt weg is, en een statusregel die nooit liegt. Van die vier staat alleen de
prune-bescherming er, en die heeft onder v2 een gat. De envelop wordt lokaal gestempeld maar reist niet mee en
wordt bij het toepassen nooit geraadpleegd. De notificatie-listener bestaat maar wordt nergens aangesloten.
Dat zijn geen randgevallen; het is de kern van de engine.

## Deel 1: defecten

### Bevestigd

**B1. `listen()` wordt in productie nooit aangeroepen. Hoog.**
`lib/services/preferences/preference_sync_coordinator.dart:466-470` definieert `listen()`; `rg "listen\(\)" lib/`
levert alleen die definitie. `ICloudSyncService.start` (`lib/services/icloud_sync_service.dart:75-104`) en
`enable()` (122-126) roepen `refreshAvailability` en `requestReconcile` aan, geen `listen()`. Alleen tests doen het
(`test/services/preferences/reconcile_lifecycle_test.dart:152,165`, `quota_and_oversize_test.dart:127`).
Gevolg: `transport.changes` wordt nooit gelezen, dus `_eventSub` in `icloud_kvs_transport.dart:60-67` wordt nooit
aangemaakt en de EventChannel wordt nooit geabonneerd. Geen enkele `didChangeExternallyNotification`,
`QuotaViolationChange` of `AccountChange` bereikt Dart. De Swift-kant laat ze vallen op
`ios/Runner/ICloudKvsPlugin.swift:91,96` (`guard let sink = eventSink else { return }`).
Scenario: matrix S1/R1 ("Apple TV volgt zonder herstart") kan niet slagen; het andere toestel ziet een wijziging
pas bij de volgende foreground-reconcile. De native audit (punt "buffering") redeneert dat `listen()` "in de
boot- en enable-trigger draait"; dat klopt niet met de code. Alle bevindingen hieronder over quota en accountwissel
gaan pas spelen zodra dit gefixt is; nu is de engine feitelijk poll-on-foreground.

**B2. `reconcile()` schrijft élke syncbare sleutel opnieuw, ook als de waarde gelijk is aan de store. Hoog.**
`preference_sync_coordinator.dart:806-809`: `for (final e in eligible.entries) await transport.write(...)`, zonder
vergelijking met `remote[cloudKey]` dat drie regels eerder al gelezen is. Reconcile draait bij boot, foreground,
profielwissel, import en reset (`_runReconcile`, 429-442), dus bij elk terugkeren naar de app worden ~100 tot 300
sleutels opnieuw in KVS gezet. KVS lost conflicten server-side op op aankomsttijd. Scenario: toestel A zet
ondertitelgrootte om 12:00:00; toestel B komt om 12:00:02 naar voren, vóór A's wijziging in B's lokale KVS-kopie
staat; B's reconcile schrijft de oude waarde met een verse stempel; de server kiest B; A krijgt de oude waarde
terug. Dat is exact het symptoom uit de context van DEC-059 ("ondertitelkeuze die na hervatten omsloeg").
Zonder B3 is dit niet af te vangen.

**B3. De revisie-envelop zit niet op de draad en wordt bij toepassen niet gebruikt. Hoog (contractgat).**
Uitgaand schrijft `apply()` `SettingsExportService.encodeValue(portableValue)` (`preference_sync_coordinator.dart:301-316`),
een kaal `{'type','value'}`; `PreferenceRevision.encode()` (`preference_revision.dart:60`) wordt in `lib/` nergens
aangeroepen. Inkomend vervangt `applyEntries` de lokale waarde onvoorwaardelijk (578-592); `localRevision()`
(392-403) heeft buiten tests geen aanroeper. `kvs_footprint_test.dart:57` zegt het zelf: "The envelope is not on
the wire yet". `_stampRevision` (351-360) schrijft dus een `pleya_pref_revisions_v1`-blob die niemand leest en die
per sleutel blijft groeien. DEC-059 en DEC-061 beschrijven LWW met tombstones als gebouwd en getest; getest is
alleen de pure klasse. Gevolg: conflictoplossing is "wat KVS als laatste aanlevert wint", zonder tombstone, zonder
apparaatvolgorde, en zonder bescherming tegen B2.

**B4. Een lokale verwijdering wordt door het andere toestel teruggezet. Hoog.**
`applyAllRemote()` (494-497) geeft alleen aanwezige sleutels aan `applyEntries`; afwezigheid wordt alleen als
verwijdering gelezen in `applyRemoteKeys` (499-506), en dat pad wordt door B1 nooit bereikt. Daarna pusht
`reconcile()` elke lokale sleutel (B2). Scenario, deterministisch op de huidige build: A zet een instelling terug
naar de standaard (`remove` → `transport.remove`, regel 269-274). B komt naar voren: `applyAllRemote` ziet niets
voor die sleutel, doet niets; `reconcile` pusht B's oude waarde terug. A's volgende foreground haalt hem weer
binnen. Matrix S6 en R8 (reset) falen zo; een `SettingsService.reset` op één toestel wordt door elk ander toestel
ongedaan gemaakt.

**B5. Onder v2 verwijdert een oudere build de voorkeuren van een nieuwere build uit de cloud. Hoog.**
`ownsCloudKey` (660-669): de v2-tak claimt eigendom op namespace plus profielmatch alleen, de v1-tak eist
daarnaast `maySync`. De prune (811-830) slaat alleen over wat `eligible`, `oversize` of `known` is. `known` bevat
uitsluitend basissleutels die lokaal in `_prefs.keys` staan. Scenario: build N+1 registreert `foo` als global en
schrijft `__pleya_pref_v2/global/foo`. Build N (ook v2) kent `foo` niet; `applyEntries` slaat hem over op
`maySync` (545-548), dus hij komt nooit lokaal; `reconcile` op build N: owned, niet eligible, niet known →
`transport.remove`. Elke foreground van het oude toestel wist de nieuwe voorkeur. Hetzelfde gebeurt bij een
typewissel tussen versies: `writeTyped` faalt (`settings_export_service.dart:213-243` retourneert `false`),
sleutel niet known, dus verwijderd. De bescherming "aanwezig maar niet syncbaar blijft staan" uit DEC-059 dekt
alleen sleutels die al lokaal bestaan. Fix: in de v2-tak `PreferenceSyncPolicyRegistry.maySync(baseKey)` eisen,
zoals v1 doet.

**B6. Uit- en weer aanzetten binnen één sessie zet de sync definitief stil. Middel.**
`ICloudSyncService.disable()` (`icloud_sync_service.dart:130-134`) roept `_coordinator.dispose()`, dat
`_transport = null` zet en de transport sluit (`preference_sync_coordinator.dart:846-851`,
`icloud_kvs_transport.dart:134-139` sluit de broadcast-controller). `enable()` (122-126) maakt geen nieuwe
transport. Daarna: `refreshAvailability` → `_transport?.isAvailable() ?? false` → `unavailable` (456-461);
`apply()` stopt op `transport == null` (261-262); `reconcile()` idem (746-747). Scenario: schakelaar uit, spijt,
schakelaar aan: de subtitel onder de schakelaar zegt "Sign in to iCloud on this device" terwijl iCloud gewoon
ingelogd is, en er wordt tot de herstart niets meer gesynchroniseerd. Geen test dekt disable gevolgd door enable
(`icloud_sync_service_test.dart` test alleen `enable()`).

**B7. Statusregel meldt "Last sent to iCloud" terwijl iCloud is uitgelogd. Middel.**
`apply()` controleert de beschikbaarheid niet (`preference_sync_coordinator.dart:260-267`) en `starting()`
forceert `availability: ready` (`preference_sync_status.dart:563-567`), `writeSucceeded` ook (572-577).
`store.set` slaagt lokaal zonder account (`ICloudKvsPlugin.swift:72`). Scenario R5: uitloggen bij iCloud (of
opstarten zonder account, availability `unavailable`), daarna één instelling wijzigen: de status springt naar
`ready`/`success` en de regel toont een tijdstip (`icloud_sync_status_line.dart:61-67`). Matrix blok 4 ("mag
nooit beweren dat ...") wordt hier geschonden, want de write ging nergens heen.

**B8. Een geslaagde reconcile wist de quota-melding terwijl de quota nog vol is. Middel (na fix van B1).**
`reconcileSucceeded` (`preference_sync_status.dart:581-599`) zet `health` op `healthy` of `warning`, ongeacht
de vorige `quota`. `store.set` geeft geen fout bij een volle store; de afwijzing komt asynchroon als
`QuotaViolationChange`. Scenario L4: quota vol, melding staat; volgende foreground → reconcile schrijft alles
opnieuw (B2), KVS accepteert lokaal, `reconcileSucceeded` → melding weg; de volgende notificatie zet hem weer
terug. Knipperende status. Vandaag onzichtbaar omdat de notificatie door B1 nooit aankomt: quota kan op de
huidige build überhaupt niet gemeld worden.

**B9. Accountwissel: voorkeuren van account A lekken in de store van account B. Middel.**
Er is geen per-account-reset. Na `accountChanged` (mits B1 gefixt, of via de volgende foreground) draait
`_runReconcile` met `applyAllRemote` gevolgd door `reconcile`: alle lokale voorkeuren (van A) worden naar B's
store gepusht (806-809). B's eigen records voor dezelfde sleutels winnen lokaal (cloud wint bij apply), maar alles
wat B nog niet had krijgt A's waarde. `pleya_pref_v1_bootstrap_done` blijft staan
(`preference_legacy_bootstrap.dart:29-33`), dus B's eigen v1-erfenis wordt niet geïmporteerd. Matrix S10 vraagt
"geen dataverlies"; dat klopt, maar het omgekeerde (datalek naar een ander account) is niet afgedekt.

**B10. Profiel-scoped taalvoorkeur komt inkomend op een dode sleutel terecht. Hoog voor die functie.**
`pleya_profile_language_preferences` staat als `PreferenceScopeKind.profile`
(`preference_sync_policy.dart:251,498`), maar de app schrijft en leest hem kaal, zonder `user_<scope>_`-prefix
(`pleya_profile_language_preference_store.dart:69,96` via `SettingsService.pleyaProfileLanguagePreferences`;
de profielscope zit in de mapsleutels). Inkomend bouwt `localKeyFor` (`preference_sync_coordinator.dart:224-229`)
`user_<homeUserUuid>_pleya_profile_language_preferences`, een sleutel die niemand leest. Uitgaand gaat de hele map,
inclusief de entries van andere profielen, onder het namespace van het actieve profiel. Scenario: taal instellen
op de Mac, Apple TV haalt hem binnen, schrijft hem weg waar `SettingsService` niet kijkt, taal blijft ongewijzigd.
Geen enkele test onder `test/services/preferences/` noemt deze sleutel. DEC-096 belooft "geldt voor alle content"
over toestellen heen; dat werkt nu op geen enkel toestelpaar.

**B11. Acht `JsonPref`-sleutels zijn onzichtbaar voor de registratieguard en daardoor stil local-only. Middel.**
De guard in `test/services/preferences/preference_sync_policy_test.dart:175` gebruikt
`Pref[a-zA-Z<>]*\(\s*'...'`; dat matcht `JsonPref<Map<String, String>>(` niet (komma en spatie). Nagemeten:
dezelfde regex op `settings_service.dart` vindt 136 sleutels, geen van de JsonPrefs. Ongeregistreerd zijn
`keyboard_shortcuts`, `keyboard_hotkeys`, `media_version_preferences`, `track_language_preferences`,
`unified_source_preferences`, `tv_live_tv_capability`, `preferred_unified_server`, `custom_shader_presets`
(`settings_service.dart:584-706`). `track_preference_store.dart:18-20` beweert dat de keuze "rides the existing
allow-by-default iCloud key-value sync"; sinds DEC-059 is de default deny, dus per-serie taalkeuzes synchroniseren
niet meer. Die doc-claim is nu onwaar.

**B12. Profielscope is alleen portable voor Plex Home; Jellyfin- en Pleya Server-gebruikers krijgen geen
profiel-scoped sync. Middel (ontwerpgrens, niet gedocumenteerd als zodanig).**
`PreferenceSyncScope.forProfile` (`preference_sync_scope.dart:67-74`) markeert alles wat niet
`plex-home-<conn>-<uuid>` is als niet-portable. Een Jellyfin-profiel heeft een serverstabiele `userId` en een
Pleya Server-profiel een server-uitgegeven id; beide zouden onder `<serverId>/<userId>` portable kunnen zijn.
Gevolg: `hidden_libraries`, `library_order`, `library_*_` en de taalvoorkeur uit B10 synchroniseren voor die
gebruikers nooit, zonder melding. Memory "Pleya Server altijd meenemen" staat hier haaks op.

**B13. Een lokale write tijdens een remote-apply-venster wordt niet gepusht en er volgt geen reconcile. Laag.**
`preference_sync_coordinator.dart:247-252` laat de mutatie vallen "let the reconcile that follows pick it up",
maar na `applyRemoteKeys` volgt geen reconcile (alleen `_runReconcile` doet apply én reconcile). De lokale waarde
staat wel lokaal; de cloud houdt de oude tot de volgende foreground. Wordt relevant zodra B1 gefixt is.

### Aannemelijk

**A1. Event-sink vanaf een niet-hoofdthread in Swift.** `ICloudKvsPlugin.swift:90-101` roept `sink(...)` direct
in de notification-handler aan. Apple garandeert voor `NSUbiquityIdentityDidChange` geen thread; Flutter eist de
platformthread voor channel-verkeer en logt anders een fout, in debug een assert. Eén `DispatchQueue.main.async`
rond beide sink-aanroepen sluit het. Drie plugins zijn byte-identiek op dit punt (macOS verschilt alleen in
`registrar.messenger` vs `messenger()`), dus geen drift.

**A2. Eerste write vóór de initiële KVS-download wordt door het systeem weggegooid.** Apple documenteert
`InitialSyncChange` als "je write is verworpen omdat de eerste download nog niet gebeurd was". Bij het eerste
inschakelen op een nieuw toestel schrijft `reconcile` direct alles (B2); die writes verdwijnen, de status meldt
succes, en pas de notificatie (die door B1 niet aankomt) zou de cloudwaarden binnenhalen. Eerste start op een nieuw
toestel: de cloud wint uiteindelijk via de volgende foreground-`applyAllRemote`, maar het tijdstip in de statusregel
is dan een leugen.

**A3. Sleutelaantal richting de 1024-grens bij meerdere Plex Home-profielen.** Per profiel: 4 per-library-families
× servers × bibliotheken, plus lijsten. `kvs_footprint_test.dart` meet bytes (56 KB), niet het aantal sleutels. Vier
profielen op vier servers met twaalf bibliotheken zijn al ~800 sleutels naast de globals. Boven 1024 weigert KVS
stil.

**A4. `_revisions()`-blob groeit onbegrensd** (`preference_sync_coordinator.dart:330-360`): één entry per ooit
gestempelde basissleutel, inclusief per-library-sleutels, nooit opgeruimd. Lokaal, dus geen KVS-risico; wel
een JSON-decode per write.

### Wat in orde is

Platformgating faalt gesloten: `ICloudKvsTransport.supported` (`icloud_kvs_transport.dart:39`) en
`ICloudSyncService.start` (regel 80) maken van Android, Windows en Linux een no-op, alle callers gebruiken
`instance?.`, en de instellingentegel is verborgen (`settings_screen.dart:119`). tvOS-simulator zonder account
geeft `ubiquityIdentityToken == nil` → `unavailable`, schakelaar uit. Een mislukte `readAll` is `null`, geen lege
store, en dat wordt overal gerespecteerd (499-506, 689-692, 756). De scheduler heeft geen timers, dus niets om te
annuleren. `deinit` en de identity-observer staan er sinds de native audit. Secrets zijn allemaal `_secret` en
`maySync` eist `sensitivity == normal`; ik heb geen token- of credentialsleutel gevonden die kan reizen.
Foutafhandeling slikt niets stil: elke catch landt in `status.raise` en het log, alleen `flush()` is bewust
best-effort.

## Deel 2: scope

Sync-kolom is de werkelijke stand op deze HEAD (registry plus B10/B11/B12). "Advies" is mijn oordeel.

### Gesynchroniseerd (global)

| Sleutel | Wat | Sync | Advies | Reden |
|---|---|---|---|---|
| auto_play_next_episode, auto_skip_intro/credits, auto_skip_delay, force_skip_marker_fallback, intro_pattern, credits_pattern, rewind_on_resume, seek_time_small/large, click_video_toggles_playback, remember_track_selections, write_series_language_to_server, show_chapter_markers_on_timeline, default_box_fit_mode, sleep_timer_duration, default_playback_speed | afspeelgedrag | ja | sync | gebruikersintentie, geen toestelkenmerk |
| subtitle_font_size, _bold, _italic, _position, _text_color, _border_color, _border_size, _background_color, _background_opacity, subtitle_search_language, sub_ass_override | ondertitelweergave | ja | sync | volgt de kijker |
| audio_normalization, audio_normalization_mode, audio_reduce_loud_sounds, audio_level_volume | loudness | ja | sync | smaak, niet hardware |
| theme_mode, view_mode, focus_glow, hide_spoilers, show_episode_number_on_cards, show_season_posters_on_tabs, show_server_name_on_hubs, show_unwatched_count, episode_poster_mode, continue_watching_action, episode_action, app_locale, personalized_recommendations, use_global_hubs, group_libraries_by_server, show_hero_section, visual_effects, ambient_lighting(_intensity) | uiterlijk en gedrag | ja | sync | gebruikersintentie |
| download_on_wifi_only, download_include_specials, auto_remove_watched_downloads, sync_local_watch_state | downloadbeleid | ja | sync | keuze, geen pad |
| enable_trakt/mal/anilist/simkl_scrobble, enable_trakt_watched_sync | trackerschakelaars | ja | sync | account-level keuze; de sessies zelf zijn `_secret` |
| library_density, hover_expand_cards, always_keep_sidebar_open, show_nav_bar_labels, startup_section, require_profile_selection_on_open | layout per vormfactor | ja | twijfel | zinnig tussen twee iPads, niet tussen iPhone en Apple TV; een gedeelde tv wil profielkeuze bij openen, een eigen telefoon niet |
| tv_full_card_layout, tv_show_titles_under_posters, tv_hero_clear_logo, tv_hero_auto_advance, tv_reduce_motion | TV-only opties | ja | twijfel | onschadelijk op niet-TV, maar `tv_reduce_motion` hoort bij het toestel (toegankelijkheid van dát scherm) |
| default_quality_preset, buffer_size, mpv_config_text, mpv_config_presets, global_shader_preset | technische afspeelconfiguratie | ja | niet syncen | buffer en shaders hangen aan geheugen en GPU; een mpv-config kan `hwdec` en paden bevatten; kwaliteitspreset hangt aan het netwerk van het toestel |
| enable_discord_rpc, video_player_navigation_enabled, auto_check_updates_on_startup | desktop-integraties | ja | niet syncen | Discord en updatecontrole zijn per installatie (App Store versus sideload); bestaan niet op tvOS |

### Gesynchroniseerd (profile)

| Sleutel | Wat | Sync | Advies | Reden |
|---|---|---|---|---|
| hidden_libraries, library_order | bibliotheken per profiel | alleen Plex Home (B12) | sync, ook Jellyfin/Pleya Server | merge-familie filtert al op portable serverId |
| library_filters, library_filters_*, library_sort_*, library_grouping_*, library_tab_* | weergave per bibliotheek | alleen Plex Home | twijfel | sorteervolgorde volgt de persoon, geselecteerde tab is sessiestaat; per-library-sleutels zijn de grootste post in het sleutelaantal (A3) |
| pleya_profile_language_preferences | taalvoorkeur profiel | uitgaand ja, inkomend dode sleutel (B10) | sync, na fix | de hele reden voor de voorkeur (DEC-096) |

### Niet gesynchroniseerd, terecht

| Sleutel | Wat | Advies |
|---|---|---|
| custom_download_path(_type), enable_hardware_decoding, enable_hdr, audio_passthrough, tunneled_playback, use_exoplayer, match_refresh_rate, match_content_frame_rate, match_dynamic_range, display_switch_delay, start_in_fullscreen, exit_fullscreen_on_player_close, rotation_locked, force_tv_mode, volume, max_volume, audio_sync_offset, subtitle_sync_offset, audio_output_mode, audio_priority, dv_conversion_mode, subtitle_render_resolution, auto_pip, use_external_player, selected_external_player, custom_external_players, enable_companion_remote_server, companion_remote_last_host_address, custom_relay_url | toestel, scherm, chip, netwerk | blijven lokaal |
| show_performance_overlay, auto_hide_performance_overlay, enable_debug_logging, crash_reporting | debug | blijven lokaal |
| token, plex_token, server_url, server_data, client_identifier, credential_vault_key_v1, seerr_session, tautulli_session, pleya_share_*, trakt_*, mal_*, anilist_*, simkl_* | secrets | nooit in KVS; klopt |
| search_history, search_recent_items, watch_together_recent_rooms, servers_list, server_order, server_endpoint_*, episode_count_*, watched_threshold_*, plex_home_users_*, profile_last_used_*, home_users_cache(_expiry), selected_library_index/key, local_server_match_v1, local_progress_*, local_watched_*, alle migratievlaggen en `pleya_pref_*`-boekhouding, active_app_profile_id, current_user_uuid, user_profile, icloud_sync_enabled, update_last_check_time, update_skipped_version | runtime cache | blijven lokaal |
| home_row_order, hidden_home_rows, home_custom_rows, unified_catalog_preferences | home- en catalogusindeling | lokaal per DEC-059/100; de open meting op `hub.identifier` staat nog |

### Niet gesynchroniseerd, ten onrechte of te bespreken

| Sleutel | Wat | Advies | Reden |
|---|---|---|---|
| track_language_preferences | per-serie audio/ondertitelkeuze | sync (profile) | pure gebruikersintentie; mapsleutel `{profileScope}\|{seriesKey}` is portable via de logische serie-sleutel; doc in `track_preference_store.dart:18` gaat er al van uit |
| media_version_preferences | gekozen versie per item | twijfel | intentie, maar versie-index hangt aan wat de server aan dít toestel aanbiedt |
| unified_source_preferences, preferred_unified_server | bronkeuze in de unified catalog | sync, met serverId-filter | scope zit in de mapsleutel, waarde is een serverId; zelfde portabiliteitsfilter als `hidden_libraries` |
| custom_shader_presets | eigen shader-presets | twijfel | door de gebruiker gemaakt, maar GPU-gebonden zoals `global_shader_preset` |
| keyboard_shortcuts, keyboard_hotkeys | toetsbindingen | sync tussen desktops | intentie; betekenisloos op tvOS maar onschadelijk |
| tv_live_tv_capability | server kan live-tv | niet syncen | runtime cache, hoort als `_runtimeCache` geregistreerd |
| live_tv_default_favorites | favorietenlijst | sync | staat nu als `_deviceLocalPref` zonder toestelkenmerk in de waarde |

### Android, Windows, Linux

iCloud is het enige transport. `PreferenceTransport` (`preference_transport.dart`) is de poort, `ICloudKvsTransport`
de enige implementatie; `PleyaServerPreferenceTransport` uit het fase A-rapport bestaat niet. Op de drie platforms
is `ICloudSyncService.instance` `null`, de tegel is verborgen en de enige cross-device-route is het exportbestand
(`settings_export_service.dart`). De code is daar expliciet over (docstrings in de facade en het transport), de
gebruiker krijgt het niet te zien: er staat geen tekst in Instellingen die zegt dat sync alleen op Apple bestaat.
`docs/agents/architecture.md` noemt de sync niet.

## Volgorde van herstel

1. B1: `listen()` aanroepen in `start()` (na `refreshAvailability`) en in `enable()`; test die de productiefacade
   gebruikt in plaats van `coordinator.listen()`.
2. B5: `maySync` in de v2-tak van `ownsCloudKey`. Kleinste diff, grootste schade.
3. B2 en B4 samen: in `reconcile` alleen schrijven wat afwijkt van `remote`, en afwezigheid in een geslaagde
   `readAll` als verwijdering toepassen wanneer er een lokale revisie met een oudere stempel is. Dat vraagt B3.
4. B3: envelop op de draad (`PreferenceRevision.encode`) en `winsOver` in `applyEntries`. Dit is de v2-belofte;
   zonder deze stap is v2 alleen een namespace.
5. B6, B7, B8: transport opnieuw aanmaken in `enable()`, `apply()` op `availability` gaten, quota niet door
   `reconcileSucceeded` laten wissen.
6. B10 en B11: lokale sleutelvorm voor map-gescoped voorkeuren (scope `global` met portabiliteitsfilter op de
   mapsleutels, of de prefix consequent doorvoeren), en de guard-regex naar `Pref[^(]*\(\s*'`.
7. B12 en de scopetabel: aparte beslissing, want die raakt Jellyfin- en Pleya Server-profielidentiteit.

Alles hierboven is codelezing. Niets is op twee toestellen aangetoond; de matrix staat nog volledig open en dat
blijft zo tot B1 in een build zit.

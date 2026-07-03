# Changelog

Sessie-voor-sessie logboek. Nieuwste bovenaan.

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

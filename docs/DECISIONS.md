# Decisions (ADR-lite)

Append-only. Nummers zijn opeenvolgend; oude beslissingen worden niet verwijderd maar op `superseded`/`deprecated` gezet.

## DEC-001: Rebrand PlexFlixNetwork → Pleya

**Date:** 2026-07-03
**Status:** accepted
**Context:** "PlexFlixNetwork" combineert twee levende merken (Plex + Netflix) en het accent was exact Netflix-rood `#E50914` op Netflix-donkere surfaces — een reëel takedown-risico bij App Store-review en bij beide merkhouders.
**Decision:** Volledig rebranden naar **Pleya** (knipoog naar Plex/Plezy zonder "plex" letterlijk). Naam vervangen in display-naam, client-ID's naar servers, alle 15 i18n-locales, pubspec, README, wordmark en intro-splash. Bundle-ID `nl.michelknoop.plexflixnetwork` → `nl.michelknoop.pleya`, Android appId `com.edde746.plezy` → `nl.michelknoop.pleya`.
**Consequences:** Bundle-ID-wissel verweest de bestaande TestFlight-app (app-ID 6786811460): nieuw App Store Connect-record, App Group `group.nl.michelknoop.pleya` en provisioning nodig vóór de volgende upload. Interne Dart-package-naam `plezy`, method-channels `com.plezy/*` en PIN-salt `plezy-app-profile-pin-v1` blijven ongewijzigd (intern, geen merkrisico; salt wijzigen zou alle profiel-PINs invalideren).

## DEC-002: Merkkleuren uit het echte Pleya-logo

**Date:** 2026-07-03
**Status:** accepted
**Context:** Eerste rebrand koos een losse coral `#FF6B5E`; die paste niet bij het aangeleverde Pleya-logo.
**Decision:** Kleuren samplen uit het logo: rood **`#F42B1F`** (`kAccent`), amber **`#F68F16`** (`kAccentAlt`) en een rood→amber `kBrandGradient` (in `lib/theme/mono_theme.dart`). De P-mark en volledige wordmark worden als transparant-gekeyde crops uit de logo-PNG gebruikt (`assets/branding/pleya_logo.png`, `pleya_wordmark.png`) en als icoon-laag (`ios|macos/pleya.icon/Assets/pleya-cropped.png`). "XX% match"-badge van Netflix-signatuurgroen `#46D369` naar amber.
**Consequences:** BuildMind-brandbook-kleuren (paars/blauw) zijn developer-branding en worden bewust NIET in de app-UI gebruikt. Copyright staat in NOTICE op Michel Knoop tot BuildMind een rechtspersoon is.

## DEC-003: GPL-compliance en secrets ontgiften

**Date:** 2026-07-03
**Status:** accepted
**Context:** Pleya is een fork van GPL-3.0 "Plezy" (edde746); Michel is niet de enige rechthebbende. De app miste attributie/source-offer (GPL-schending) en shipte edde746's Trakt/Simkl/MAL-credentials, Sentry-DSN, auto-update-appcast en donatie-URL.
**Decision:** About-scherm (`lib/screens/settings/about_screen.dart`) kreeg attributie + source-link + upstream-link + privacy-link + "Developed by BuildMind"; `NOTICE`-bestand toegevoegd. Alle third-party-secrets naar `String.fromEnvironment` met lege default (feature verbergt zich netjes als niet geconfigureerd): `TRAKT_CLIENT_ID/SECRET`, `SIMKL_CLIENT_ID`, `MAL_CLIENT_ID`, `SENTRY_DSN`, `UPDATE_GITHUB_REPO/FEED_URL`, `DONATION_URL`, `PLEYA_ICE_BASE`.
**Consequences:** Voor release: repo publiek maken, `SOURCE_REPO_URL` + `PRIVACY_POLICY_URL` zetten, eigen API-apps registreren. Trackers zijn verborgen tot hun key via `--dart-define` meekomt.

## DEC-004: On-device aanbevelingssysteem (privacy-lokaal)

**Date:** 2026-07-03
**Status:** accepted
**Context:** De discover-feed had geen personalisatie — server-hubs in bibliotheekvolgorde. Alle signalen (genres, cast, rating) werden al geparsed in `MediaItem` maar nergens gebruikt.
**Decision:** Een lokale taste-engine in `lib/services/recommendations/`. Drift v17 tabellen `MediaInteractions` (append-only event-log, gedenormaliseerde features) + `AffinitySnapshots` (gecachte vector per profiel). `InteractionRecorder` abonneert op `WatchStateNotifier`; `AffinityEngine` bouwt een genormaliseerde vector met 90-dagen-decay; `recommendationScore` (puur, in `taste_profile.dart`) weegt genre/actor/director/decade/studio/mood + quality + novelty − already-seen. `RecommendationService` bouwt rijen (Top Picks / Because-you-like / Hidden Gems), gewired als optionele dependency in `DiscoverProvider`. Alles draait buiten de door tests gepinde fetch-paden zodat het call-count-contract in `discover_provider_test.dart` groen blijft.
**Consequences:** Geen ML-framework, geen externe calls: leren blijft on-device per profiel. Settings-toggle `personalizedRecommendations` (default aan); data wordt gewist bij profiel-delete (`deleteRecommendationDataForProfile`). Retentie 365 dagen / 5000 rijen. Snapshot-verversing checkt zowel row-count als `latestInteractionAt` (anders veroudert de vector bij de retentiecap).

## DEC-005: Trakt inbound en ambient trailer-previews uitstellen

**Date:** 2026-07-03
**Status:** accepted
**Context:** Het oorspronkelijke plan was A+B+Trakt-inbound plus trailer-autoplay op de billboard.
**Decision:** Trakt read-endpoints (`recommendations/trending/popular`) zijn toegevoegd, maar de mapping-naar-bibliotheek en de rijen zijn uitgesteld: Trakt is dormant zonder Michels keys en de fuzzy matching heeft live data nodig om te tunen. Ambient trailer-previews (singleton mpv-player) zijn uitgesteld omdat de mpv-lifecycle + TV-perf + audio-focus op device getest moeten worden en niet veilig ongetest vlak vóór een review te shippen zijn.
**Consequences:** Beide zijn post-build follow-ups. De read-endpoints staan klaar zodra keys geconfigureerd zijn.

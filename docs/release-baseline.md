# Release Baseline — Phase 1 Output

**Date:** 2026-07-07
**Flutter:** 3.44.4 (stable)
**Pubspec version:** 2.8.0+156

## Verification Baseline

### CI checks (`scripts/ci_checks.sh`)

Status: **PASS** (after fixes applied in this phase)

| Check | Result |
|-------|--------|
| dart format | PASS — 907 files correctly formatted |
| codegen freshness | PASS — no stale generated files |
| native format | PASS — native files correctly formatted |
| flutter analyze | PASS — no errors or warnings |
| dart_code_linter: unused code | PASS — none |
| dart_code_linter: unused files | PASS — none |

Fixes applied to reach green baseline:
- Ran `scripts/codegen.sh` to regenerate stale `.g.dart` / `.freezed.dart` for `lib/mpv/models.dart`, `lib/profiles/profile.dart`, `lib/media/media_item.dart`
- Ran `dart format` on 86 files that were not yet formatted at width 120
- Removed unused function `seerrPosterHeightOf` from `lib/widgets/seerr_poster_card.dart`

### Test suite (`flutter test`)

Status: **2556 passed, 27 failed (pre-existing)**

All 27 failures are pre-existing — confirmed by stashing this phase's changes and re-running representative failing tests against the `b0160ca` baseline. The same tests fail without any of our work.

Pre-existing failure categories:

| Category | Count | Files |
|----------|-------|-------|
| TV detail screen (focus, prefetch, seasons, ratings) | 9 | `test/screens/media_detail_screen_test.dart` |
| TV discovery / OSK / tab focus | 4 | `test/screens/discover_screen_test.dart`, `test/screens/auth_screen_test.dart` |
| Media detail (container mark, season/watched, phone detail) | 8 | `test/screens/media_detail_screen_test.dart` |
| Profile session / remote back | 4 | `test/navigation/profile_session_screen_test.dart`, `test/screens/profile/` |
| Theme provider | 1 | `test/providers/theme_provider_test.dart` |
| Settings TV keyboard | 1 | `test/screens/settings/` |

These are baseline tech debt, not regressions from this phase. They should be addressed in later phases or triaged separately.

## Release Inputs Inventory

### App identity

| Property | Value | Status |
|----------|-------|--------|
| Bundle ID (iOS) | `nl.michelknoop.pleya` | Set in `ios/Runner.xcodeproj/project.pbxproj` |
| Bundle ID (tvOS) | `nl.michelknoop.pleya` + `nl.michelknoop.pleya.TopShelfExtension` | Set in `tvos/Runner.xcodeproj/project.pbxproj` |
| Bundle ID (macOS) | `nl.michelknoop.pleya` | Set via `macos/Runner/Configs/AppInfo.xcconfig` |
| Android applicationId | `nl.michelknoop.pleya` | Set in `android/app/build.gradle.kts:93` |
| App Group (tvOS) | `group.nl.michelknoop.pleya` | Set in `tvos/Runner/Runner.entitlements` |
| App Group (iOS) | Not configured | `ios/Runner/Runner.entitlements` has no app-group entry |
| App Group (macOS) | Not configured | `macos/Runner/Release.entitlements` has no app-group entry |

### Entitlements

| Platform | File | Capabilities |
|----------|------|--------------|
| iOS | `ios/Runner/Runner.entitlements` | iCloud KV-store only |
| tvOS | `tvos/Runner/Runner.entitlements` | App Group + iCloud KV-store |
| macOS (Release) | `macos/Runner/Release.entitlements` | Sandbox + user-selected file r/w + iCloud KV-store |

### Runtime secrets (`--dart-define`)

| Define | Purpose | Default | Required for |
|--------|---------|---------|-------------|
| `ENABLE_SENTRY` | Enable crash reporting | `false` | Sentry init |
| `SENTRY_DSN` | Sentry project DSN | empty | Sentry init |
| `SENTRY_ENVIRONMENT` | Sentry environment label | empty | Sentry metadata |
| `SENTRY_DIST` | Sentry dist label | empty | Sentry metadata |
| `GIT_COMMIT` | Release version tag for Sentry | empty | Sentry release name |
| `TVOS_BUILD` | Marks a tvOS build | `false` | Platform detection, download, shelf, exit |
| `PLEX_TOKEN` | Dev/screenshot token | empty | Screenshot automation only |
| `BLUR_ARTWORK` | Blur artwork, scramble titles | `false` | Screenshot automation only |
| `TRAKT_CLIENT_ID` | Trakt tracker login, scrobble and sync | empty | Trakt login (Settings > Trackers), scrobble/sync |
| `SIMKL_CLIENT_ID` | Simkl tracker | empty | Simkl tracking |
| `MAL_CLIENT_ID` | MAL tracker | empty | MAL tracking |
| `PLEYA_ICE_BASE` | ICE relay/relay base URL | `https://ice.pleya.app` | Watch Together, Discord RPC, log uploads. De Pleya Share-relayfallback leest dezelfde waarde maar staat uit, zie [PLEYA_SHARE](PLEYA_SHARE.md#internetrelay-staat-uit). Host draait sinds 2026-08-10, zie [DEC-014](DECISIONS.md#dec-014) |
| `UPDATE_GITHUB_REPO` | Auto-update GitHub repo | empty | Desktop update check |
| `UPDATE_FEED_URL` | Auto-update appcast URL | empty | Desktop update check |
| `ENABLE_UPDATE_CHECK` | Enable update checking | `false` | Desktop update prompts |
| `DONATION_URL` | Donation link | empty | Donate tile in settings |
| `ENABLE_DONATIONS` | Show donate tile | `false` | Donate tile visibility |
| `SOURCE_REPO_URL` | GPL source link in About | empty | About screen source link |
| `PRIVACY_POLICY_URL` | Privacy policy link | empty | About screen privacy link |

`TRAKT_CLIENT_ID` comes from `.env` (see `.env.example`). `ios_beta` and `macos_beta` pass it through `api_key_defines` in `fastlane/Fastfile`, only when the value is non-empty. `tvos_beta` and `tvos_archive` need nothing extra: xcodebuild inherits the fastlane environment and `tvos/scripts/xcode_appletv.sh` adds the `-D` flag when it is set. A missing value leaves the feature off in the app.

The client ID ends up readable in places other than `.env`. xcodebuild echoes the full environment of every Run Script phase into the build log, fastlane logs the `flutter build` command line, and on iOS and macOS the defines sit base64-encoded in the generated xcconfig. Anyone with the binary can extract it too. That is acceptable because a Trakt client ID is a public app identifier: it reads no user data on its own and can be revoked and reissued at Trakt, which switches the public Trakt calls off in builds that carry the old ID until the next build ships.

Never put a secret in a dart-define. The release lanes therefore pass no Trakt secret and no TMDB key. The Trakt login (device code, token refresh, revoke) works with the client ID alone, measured on 11 October 2026, so `TraktConstants.isConfigured` is true for a build that carries `TRAKT_CLIENT_ID` and the login is visible in release builds. Children's profiles get no Trakt login, scrobble or sync. Pleya ships no TMDB key at all: `TmdbClient` takes the user's own TMDB token, entered in the app.

### Signing and distribution

| Input | Location | Status |
|-------|----------|--------|
| ASC API key (Key ID) | `.env` → `ASC_KEY_ID` | Required for TestFlight |
| ASC API key (Issuer ID) | `.env` → `ASC_ISSUER_ID` | Required for TestFlight |
| ASC API key (content) | `.env` → `ASC_KEY_CONTENT` (base64) | Required for TestFlight |
| Fastlane lanes | `fastlane/Fastfile` | `ios_beta`, `tvos_beta`, `macos_beta`, `beta` |
| TestFlight release script | `scripts/testflight_release.sh` | Bumps build number + runs lane |
| launchd schedule | Monthly TestFlight refresh | `~/Library/LaunchAgents/nl.michelknoop.pleya.testflight.plist` |
| macOS keychain partition-list | One-time setup | Required for `macos_beta` codesign |
| macOS sandbox | Enabled in Release.entitlements | Needs playback/network verification |

## Platform Release Commands

### Apple — TestFlight (internal testers)

```bash
# All platforms
scripts/testflight_release.sh

# Single platform
scripts/testflight_release.sh ios_beta
scripts/testflight_release.sh tvos_beta
scripts/testflight_release.sh macos_beta
```

Prerequisites: `.env` with ASC credentials, keychain partition-list set for macOS.

### Android — Google Play / Amazon

Build command needs verification — no Fastlane lane visible for Android in current `fastlane/Fastfile`.

```bash
flutter build apk --release
flutter build appbundle --release
```

### Desktop — GitHub releases

```bash
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

Auto-update requires `UPDATE_GITHUB_REPO` and `UPDATE_FEED_URL` defines.

## Blocked Release Prerequisites

| Blocker | Impact | Owner |
|---------|--------|-------|
| New ASC app record for `nl.michelknoop.pleya` | Cannot upload to TestFlight/App Store without it | Michel |
| App Group `group.nl.michelknoop.pleya` provisioning for iOS | Top Shelf / shared storage on iOS | Michel |
| macOS sandbox playback verification | Unknown if mpv + networking work under sandbox | Michel — manual test needed |
| Android release build verification | No Fastlane lane; build command not verified in this phase | Phase 4 |
| `SOURCE_REPO_URL` and `PRIVACY_POLICY_URL` not set | About screen links are empty | Michel |
| Tracker API keys not registered | Simkl/MAL features are dormant. Trakt needs only `TRAKT_CLIENT_ID`; a build that carries it shows the Trakt login, see "Trakt login release conditions" | Michel |
| 27 pre-existing test failures | Not blocking release builds, but blocking confidence | Phase 3-4 |

## Trakt login release conditions

A build that carries `TRAKT_CLIENT_ID` shows the Trakt login and reads the user's Trakt history and watchlist (BP-07). The lanes add that define by themselves as soon as the value is set in `.env`, so the gate is procedural: `TRAKT_CLIENT_ID` stays out of the release `.env` until every item below is met. On 11 October 2026 it is not set in the `.env` of the main checkout, so builds made from it do not show the login. Status of 11 October 2026:

| Condition | Status | Owner |
|---|---|---|
| Linking sends nothing back by itself: scrobble and watched-sync default to off, are asked once after linking, and the offline queue obeys the same consent (a rating the user gives is separate) | Built (BP-07 afronding) | done |
| Second refresh with the rotated token pair measured live, and the real shape of `/sync/watched` and `/sync/watchlist` | Open, needs `/grant TRAKT_CLIENT_ID` and one activation | Michel |
| `trakt_watchlist` and the "seen" filter checked on a device with a real Trakt account | Open, manual | Michel |
| The consent question is usable with the remote on Apple TV and on iPhone | Open, manual | Michel |
| App Store Connect privacy label and the privacy page name Trakt viewing data (what is sent: play events and watched marks, only after consent, and a rating the user gives; what is read: history and watchlist, used locally and the watchlist as a tool result). The consent answer syncs through iCloud between devices | Open, manual: `website/src/routes/privacy/+page.svelte` does not mention Trakt and must be extended and deployed; `PRIVACY_POLICY_URL` is empty | Michel |

## Launch Scope Decision

### Platforms

| Platform | Launch intent | Rationale |
|----------|---------------|-----------|
| iOS | Public (after Phase 2-4) | Primary mobile target, TestFlight pipeline ready |
| tvOS | Public (after Phase 2-4) | Primary TV target, TestFlight pipeline ready |
| macOS | Beta or Public (after sandbox verification) | Sandbox risk on playback needs real test |
| Android | Public (after Phase 4 build verification) | Large install base, no verified release lane yet |
| Windows | Beta or Public (after Phase 4) | Desktop, less tested in recent sessions |
| Linux | Beta or Public (after Phase 4) | Desktop, community-maintained packages exist |

### Features

| Feature | Launch status | Rationale |
|---------|---------------|-----------|
| Browse + discover | Core — public | P0, must be solid |
| Playback (play/pause/seek/resume) | Core — public | P0, must be solid |
| Subtitles + audio switching | Core — public | P0 |
| Downloads + offline | Core — public | P0, trust-sensitive |
| Profile switching | Core — public | P0 |
| Search | Core — public | P0 |
| Live TV / DVR | Public if verified | Plex-only, needs device test |
| Watch Together | Beta label recommended | Relay-dependent, high support cost |
| Seerr / Jellyseerr | Hidden unless configured | Optional integration |
| Trackers (Trakt/Simkl/MAL) | Hidden unless configured; Trakt shows when `TRAKT_CLIENT_ID` is set | Blocked for Trakt until the conditions in "Trakt login release conditions" are met |
| Discord Rich Presence | Desktop only, keep | Low risk |
| Recommendations | Keep, but not hero-marketed | On-device, still tuning |
| iCloud settings sync | Keep on Apple platforms | Low risk, already wired |
| Auto-update (desktop) | Keep if configured | Needs defines |
| Ambient lighting / shaders | Keep where supported | Not on iOS, tvOS only |
| External player launch | Keep | Low risk |

## Phase 1 Exit Criteria Check

- [x] Current code quality baseline is known (CI green, 27 pre-existing test failures catalogued)
- [x] Release prerequisites are enumerated (secrets, signing, entitlements, store records)
- [x] Launch scope is explicitly defined (platform + feature decisions above)

Phase 1 is complete. Next: Phase 2 — Harden First-Run and Authentication.
# Upstream Decoupling Plan

## Goal

Make this repo functionally independent from `edde746/plezy` and `edde746/*` build sources.

Target end state:
- no `pubspec.yaml` Git dependencies point to `edde746/*`
- no Android/iOS/macOS/tvOS build-critical downloads or package pins point to `edde746/*`
- no release/update workflow depends on `github.com/edde746/plezy/releases`
- only legal or historical attribution remains where required, such as `NOTICE`

Non-goals:
- removing legal fork attribution
- renaming everything in one pass
- changing package names, bundle IDs, or release artifact names before dependency hosting is stable

## Current Verified Upstream Dependencies

### Dart and Flutter package sources

From `pubspec.yaml`:
- `connectivity_plus` via `https://github.com/edde746/plus_plugins`
- `os_media_controls` via `https://github.com/edde746/media_controls`
- `wakelock_plus` via `https://github.com/edde746/wakelock_plus`
- `background_downloader` via `https://github.com/edde746/background_downloader`
- `auto_updater` via `https://github.com/edde746/auto_updater`
- `auto_updater_platform_interface` via `https://github.com/edde746/auto_updater`
- `auto_updater_macos` via `https://github.com/edde746/auto_updater`
- `auto_updater_windows` via `https://github.com/edde746/auto_updater`
- `sentry` and `sentry_flutter` via `https://github.com/edde746/sentry-dart`
- `material_symbols_icons` override via `https://github.com/edde746/material_symbols_icons`

### Native build and binary sources

From `android/app/build.gradle.kts`:
- `libmpv-android` release downloads from `https://github.com/edde746/libmpv-android/releases/...`
- `libdovi-builds` release downloads from `https://github.com/edde746/libdovi-builds/releases/...`

From `android/libass/src/main/cpp/CMakeLists.txt`:
- `libass` zip downloads from `https://github.com/edde746/libass/releases/...`

From SwiftPM lockfiles:
- `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `tvos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`

These pin `MPVKit` to `https://github.com/edde746/MPVKit` version `1.0.6`.

### Release and distribution coupling

From `.github/workflows/update-packages.yml`:
- Homebrew update downloads `plezy-macos.dmg` from `github.com/edde746/plezy/releases`
- Winget identifier is `edde746.Plezy`

From `.github/workflows/build.yml`:
- artifact names still use the `plezy-*` pattern
- generated appcast enclosure URLs point to `https://github.com/edde746/plezy/releases/download/...`

From `README.md`:
- download links point to `github.com/edde746/plezy/releases`
- install instructions still mention `edde746/plezy` and `edde746.Plezy`

## Execution Rules

1. Execute phases in order.
2. Do not combine native source migration and release workflow migration in the same change set.
3. After each dependency-source change, regenerate the lockfile and run verification before continuing.
4. Do not rename release artifacts from `plezy-*` to `pleya-*` until all relevant workflows and feeds already point to your own release source.
5. Keep attribution in `NOTICE` and any other legally required locations.
6. Prefer mirroring exact commits and exact release artifacts before attempting to modernize or refactor upstream forks.

## Phase 1: Low-Risk Flutter Fork Migration

### Objective

Move the lowest-risk package forks in `pubspec.yaml` to your own forks without changing behavior.

### Scope

- `connectivity_plus` from `edde746/plus_plugins`
- `os_media_controls` from `edde746/media_controls`
- `wakelock_plus` from `edde746/wakelock_plus`
- `material_symbols_icons` override from `edde746/material_symbols_icons`

### Preconditions

- create your own fork or mirror for each upstream repo
- preserve the exact commit SHA or equivalent content
- preserve folder layout used by `path:` dependencies

### File Changes

- `pubspec.yaml`
- `pubspec.lock`

### Verification

Run in this order:

```bash
flutter pub get
scripts/ci_checks.sh
flutter test
```

### Stop Conditions

Stop and do not continue to the next package if:
- `flutter pub get` fails to resolve a fork layout or ref
- a package path inside the new fork does not match the old `path:` structure
- `scripts/ci_checks.sh` or `flutter test` fails unexpectedly

### Exit Criteria

- `pubspec.lock` resolves these packages from your own forks
- analyze and tests pass
- no behavior changes are required in app code

## Phase 2: Medium-Risk Runtime and Build Fork Migration

### Objective

Move upstream forks that affect platform behavior or runtime integrations.

### Scope

- `background_downloader`
- `sentry-dart` and `sentry_flutter`

### Why This Is Separate

- `background_downloader` is tied to the iOS deployment-target workaround described in `scripts/fix_ios_spm.sh`
- `sentry-dart` is tied to symbol upload and crash reporting behavior

### Preconditions

- create your own fork or mirror for each repo
- preserve the exact branch or commit currently pinned in `pubspec.yaml`
- do not change app-level Sentry config while changing source location

### File Changes

- `pubspec.yaml`
- `pubspec.lock`

### Verification

Run in this order:

```bash
flutter pub get
scripts/ci_checks.sh
flutter test
flutter build apk --release
flutter build ios --config-only --no-codesign
scripts/fix_ios_spm.sh
flutter build macos --release
```

If a full macOS build is too expensive locally, say so explicitly and verify at least:

```bash
flutter build macos --config-only --release
```

### Stop Conditions

Stop if:
- iOS package resolution changes unexpectedly
- the `background_downloader` minimum deployment behavior changes
- Sentry build integration or symbol packaging changes unexpectedly

### Exit Criteria

- these packages resolve from your own forks
- Android release build passes
- iOS config-only build still works with the current patch flow
- macOS build or config-only build still works

## Phase 3: Updater Stack Migration

### Objective

Move the desktop updater package family to your own source while keeping the current release mechanics intact.

### Scope

- `auto_updater`
- `auto_updater_platform_interface`
- `auto_updater_macos`
- `auto_updater_windows`

### Why This Is Risky

- desktop update behavior is coupled to Sparkle and current Fastlane signing logic in `fastlane/Fastfile`
- this affects packaging and update distribution, not just build-time Dart resolution

### Preconditions

- fork or mirror `edde746/auto_updater`
- preserve exact package layout under `packages/`
- confirm there are no hidden hardcoded upstream release endpoints inside the fork before switching

### File Changes

- `pubspec.yaml`
- `pubspec.lock`

### Verification

Run in this order:

```bash
flutter pub get
scripts/ci_checks.sh
flutter build macos --release
flutter build windows --release
```

Also validate that the current signing/update tooling still runs where applicable:

```bash
dart run auto_updater:sign_update --help
```

### Stop Conditions

Stop if:
- Sparkle-related packaging breaks
- Windows updater packaging breaks
- package layout or CLI entry points differ from the mirrored repo

### Exit Criteria

- updater packages resolve from your own fork
- macOS and Windows release builds still succeed

## Phase 4: Native Source and Binary Supply Chain Migration

### Objective

Own all build-critical binary and native source dependencies currently hosted under `edde746/*`.

### Scope A: Android

- `libmpv-android`
- `libdovi-builds`
- `libass`

### Scope B: Apple

- `MPVKit`

### Strategy

Do this in two substeps per dependency:

1. Mirror hosting first.
2. Switch repo URLs second.

Mirror hosting first means:
- create your own repo or fork
- publish the exact same release tag or version where practical
- publish the exact same artifact filenames the current build expects

### File Changes

Android:
- `android/app/build.gradle.kts`
- `android/libass/src/main/cpp/CMakeLists.txt`

Apple:
- SwiftPM references or resolved package sources as needed
- likely lockfiles under:
  - `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  - `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  - `tvos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`

### Verification

Run in this order after each migrated native source:

```bash
flutter build apk --release
flutter build ios --config-only --no-codesign
scripts/fix_ios_spm.sh
flutter build macos --release
```

If tvOS is in scope for the migrated component, also verify the tvOS build path used by your release process.

### Runtime Smoke Test Requirements

Do not consider this phase complete without a playback smoke test on a built app where possible:
- app launches
- player initializes
- video starts
- subtitles render
- no immediate native crash around playback setup

### Stop Conditions

Stop if:
- a mirrored release artifact does not match expected filename or structure
- Android native link or extraction steps fail
- Apple SwiftPM resolution does not accept the mirrored source cleanly
- playback behavior changes after the source switch

### Exit Criteria

- no build-critical Android download URL points to `edde746/*`
- no Apple `MPVKit` source points to `edde746/*`
- release builds and playback smoke checks still succeed

## Phase 5: Release and Distribution Decoupling

### Objective

Move release workflows, package-manager updates, appcast generation, and docs to your own release source.

### Scope

- `.github/workflows/build.yml`
- `.github/workflows/update-packages.yml`
- `README.md`
- any cask, manifest, or appcast paths coupled to upstream release URLs

### Safe Order Inside This Phase

1. switch release URL sources to your own release host
2. update generated appcast enclosure URLs
3. update Homebrew and Winget integration
4. only then consider renaming artifacts from `plezy-*` to `pleya-*`

### Important Constraint

Do not rename artifacts first. The current workflows, package-manager hooks, and appcast generation still expect `plezy-*` names.

### Verification

At minimum verify:
- release artifact upload paths still match generated files
- appcast points to valid files
- Homebrew update script uses valid URLs and hashes
- Winget release config still matches the actual installer name
- README download links resolve to real artifacts

### Stop Conditions

Stop if:
- appcast points to a missing asset
- package-manager update jobs reference old names after URL migration
- build workflow still hardcodes upstream release URLs

### Exit Criteria

- no release or update workflow depends on `github.com/edde746/plezy/releases`
- docs point to your own distribution source
- artifact naming is either still intentionally legacy and stable, or fully migrated consistently

## Phase 6: Cleanup and Legacy Reduction

### Objective

Remove remaining non-essential legacy references after technical decoupling is complete.

### Safe Cleanup Targets

- issue template field names like `plezy-version`
- README install text that still references upstream package names where no longer needed
- internal comments that describe outdated upstream coupling
- artifact names only after all producers and consumers have been updated together

### Preserve

- `NOTICE`
- any legally required attribution

### Verification

Use targeted searches and then confirm behavior still works:

```bash
rg -n "edde746|github.com/edde746/plezy|edde746.Plezy|plezy-" .
scripts/ci_checks.sh
flutter test
```

### Exit Criteria

- remaining upstream references are only legal, historical, or intentionally documented

## Final Success Criteria

The repo is functionally decoupled when all of the following are true:
- `pubspec.yaml` has no build-critical `edde746/*` package sources left
- Android native downloads no longer point to `edde746/*`
- Apple `MPVKit` source no longer points to `edde746/*`
- release and update workflows do not depend on `github.com/edde746/plezy/releases`
- README and package-manager flows point to your own release source
- only legal attribution remains in files like `NOTICE`

## Recommended First Execution Step

Start with Phase 1 only.

Reason:
- lowest risk
- immediate reduction of upstream coupling in `flutter pub get` output
- minimal chance of breaking native or release pipelines
- creates a safe pattern for the higher-risk migrations

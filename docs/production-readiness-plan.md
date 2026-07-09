# Production Readiness Plan

## Goal

Bring Pleya from feature-rich beta state to a production-ready public release with predictable onboarding, stable playback flows, reliable offline behavior, and a repeatable release process across Apple, Android, desktop, and TV targets.

Target end state:
- first-run onboarding is clear and recoverable for both Plex and Jellyfin users
- profile selection and profile-bound server state behave predictably across app launch, reconnect, and profile switch
- playback, downloads, offline sync, and core navigation are stable on the platforms we claim to support
- release configuration, signing, store metadata, and runtime secrets are documented and repeatable
- non-core or high-risk features are either hardened, hidden behind configuration, or explicitly labeled as beta

Non-goals:
- shipping every advertised feature at the same quality bar in the first public release
- large-scale architecture rewrites before proving the highest-risk user journeys
- visual redesign for its own sake without a measured usability or support benefit

## Working Rules

1. Execute phases in order.
2. Do not start broad polish work before the critical flows are verified.
3. Keep scope tight: prefer targeted fixes over structural rewrites unless a repeated defect proves the current structure is blocking progress.
4. For every phase, produce verification evidence before marking it complete.
5. Any feature that cannot meet the phase exit criteria must be downgraded, hidden, or marked beta rather than silently shipped.
6. Public release claims must match what is actually verified on real target platforms.

## Release Principles

### P0 flows

These must be boring and reliable before public launch:
- install and first app open
- Plex sign-in
- Jellyfin sign-in
- profile pick and profile switch
- landing on Home with visible content
- play, pause, seek, resume
- subtitle and audio track switching
- download, offline playback, reconnect sync-back
- return navigation on mobile, desktop, and TV

### P1 flows

These should be solid before broad public promotion, but can trail the P0 pass:
- Live TV and DVR
- Seerr / Jellyseerr requests
- tracker integrations
- iCloud settings sync
- update prompts
- watch together

### P2 flows

These are post-launch polish or controlled-beta candidates:
- advanced sync rules UX
- recommendation tuning
- deeper customization and expert settings cleanup
- premium visual polish outside critical path screens

## Known Gap Summary

### Product and release gaps

- app identity migration is fresh and still coupled to provisioning, App Store Connect, and app-group setup
- runtime feature configuration depends on release-time `--dart-define` values that need a documented source of truth
- macOS sandbox behavior still needs explicit real-world verification for playback and networking
- platform release behavior differs enough that one generic launch checklist is not sufficient

### UX gaps

- onboarding is too critical to leave as a mostly technical connection flow
- auth failures and no-server states need guided recovery, not just surfaced errors
- profile behavior is powerful but cognitively heavy and must feel deterministic
- settings are rich but likely too dense for non-power users
- empty/loading/error states need to feel product-grade everywhere, not just exist mechanically

### Feature-risk gaps

- downloads and offline sync are high-value but trust-sensitive
- watch together has a high support cost if relay/sync quality is inconsistent
- request integrations and other optional services should not weaken the core experience when absent or misconfigured

## Execution Plan

## Phase 1: Lock Down Release Baseline

### Objective

Establish a verified release baseline so future work is measured against a known-good state instead of assumptions.

### Scope

- confirm current supported platforms and release intent
- inventory required secrets, signing, app-store records, app groups, and update feeds
- run the existing verification commands and record current failures
- define which features are core, optional, or beta for launch

### Tasks

1. Audit all release inputs:
   - App Store Connect records
   - bundle IDs and application IDs
   - app groups and entitlements
   - `--dart-define` requirements
   - Sentry, update, privacy, source, donation, and tracker configuration
2. Run the current project verification baseline:
   - `flutter pub get`
   - `scripts/ci_checks.sh`
   - `flutter test`
3. Record platform-specific release commands that currently work and which ones are blocked.
4. Decide launch surface by platform:
   - public now
   - beta only
   - hidden / disabled

### Deliverables

- a verified release checklist document
- a list of blocked release prerequisites
- a launch-scope decision list per platform and feature

### Verification

Run in this order:

```bash
flutter pub get
scripts/ci_checks.sh
flutter test
```

If a platform build is touched during this phase, also capture the exact build command and outcome.

### Stop Conditions

Stop and resolve before Phase 2 if:
- core checks are already red without understanding why
- release secrets and store setup are not fully known
- the intended launch scope is still ambiguous

### Exit Criteria

- current code quality baseline is known
- release prerequisites are enumerated
- launch scope is explicitly defined

## Phase 2: Harden First-Run and Authentication

### Objective

Make the path from fresh install to first playable content simple, guided, and recoverable.

### Scope

- auth entry screen
- Plex sign-in flow
- Jellyfin add/connect flow
- no-server and failed-auth recovery states
- immediate post-auth transition into profiles and content

### Tasks

1. Audit the current first-run UX on phone, desktop, and TV.
2. Simplify the auth decision points so Plex and Jellyfin feel like distinct guided paths.
3. Replace technical dead ends with recovery-oriented states:
   - no servers found
   - invalid server URL
   - bad credentials
   - network unavailable
   - partial account success with zero usable libraries
4. Ensure the app never flashes an empty or misleading Home state right after successful sign-in.
5. Add or improve tests for first-run flow decisions where practical.

### Deliverables

- improved auth/onboarding UI and copy
- stable handoff from sign-in to profile/content state
- explicit recovery paths for expected failure modes

### Verification

- `scripts/ci_checks.sh`
- `flutter test`
- manual smoke test for:
  - Plex sign-in success
  - Plex sign-in with no servers
  - Jellyfin sign-in success
  - Jellyfin invalid server or bad credentials
  - offline/no-network startup path

### Stop Conditions

Stop and fix before Phase 3 if:
- sign-in success can still land the user in an empty-looking shell without explanation
- failed auth states still require technical knowledge to recover
- TV flow cannot be completed cleanly with remote-only input

### Exit Criteria

- a new user can reach playable content predictably
- common auth failures are understandable and recoverable
- first-run behavior is consistent across supported form factors

## Phase 3: Stabilize Profiles, Session Binding, and Navigation

### Objective

Remove surprise behavior around active profile, server binding, reconnect, and back navigation.

### Scope

- profile selection and switching
- PIN prompt timing
- active-profile binding lifecycle
- reconnect and offline-to-online transitions
- back behavior on mobile, desktop, and TV

### Tasks

1. Trace the profile lifecycle from login, app relaunch, reconnect, and manual profile switch.
2. Eliminate ambiguous or surprising transitions:
   - auto-selected wrong profile
   - repeated or mistimed PIN prompt
   - stale libraries after profile changes
   - route-stack inconsistencies
3. Add visible loading/binding states where hidden async work currently causes a flash of wrong UI.
4. Verify main navigation behavior for each form factor.
5. Add focused regression tests for the pure decision helpers already present in `main_screen.dart` and related profile flow code.

### Deliverables

- deterministic profile/session UX
- fewer hidden state transitions
- regression coverage for high-risk bind/invalidation logic

### Verification

- `scripts/ci_checks.sh`
- `flutter test`
- manual smoke test for:
  - one-profile login
  - multi-profile login
  - profile switch with PIN
  - reconnect after offline period
  - logout / route back to auth
  - TV menu/back behavior

### Stop Conditions

Stop and resolve before Phase 4 if:
- profile switching can leave stale content visible
- reconnect state can strand the user in a blank or contradictory UI
- back navigation differs unpredictably between routes on the same platform

### Exit Criteria

- active profile always matches visible content
- transitions are understandable and reproducible
- navigation feels native and safe on every claimed platform

## Phase 4: Harden Playback, Downloads, and Offline Trust

### Objective

Make the core viewing experience trustworthy under normal and degraded conditions.

### Scope

- playback start, resume, seek, and player exit
- subtitle and audio switching
- downloads queue and retry behavior
- offline browsing and watch-progress sync-back
- storage and auto-delete behavior

### Tasks

1. Define the minimal supported playback matrix per platform.
2. Validate the top playback journeys:
   - start from Home
   - resume from continue watching
   - next episode
   - subtitle/audio changes
   - recover from playback error
3. Simplify downloads UX where needed:
   - downloading
   - downloaded
   - waiting for network
   - failed / retry needed
4. Make offline sync state explicit enough that users can trust what will happen after reconnect.
5. Add regression tests where logic is isolated and deterministic.

### Deliverables

- stable playback baseline per platform
- simpler and clearer downloads/offline states
- verified watch-progress sync-back behavior

### Verification

- `scripts/ci_checks.sh`
- `flutter test`
- manual smoke test for:
  - play and resume
  - seek and exit
  - subtitle/audio switch
  - download item
  - view downloaded item offline
  - reconnect and sync watch progress

### Stop Conditions

Stop and resolve before Phase 5 if:
- playback is not reliable on any platform included in launch scope
- download state can silently fail or mislead the user
- reconnect does not reliably sync core watch state

### Exit Criteria

- core playback journeys succeed repeatedly
- download/offline state is understandable
- user trust in watch progress is preserved

## Phase 5: Demote or Harden Secondary Features

### Objective

Prevent optional or high-risk features from dragging down the public release.

### Scope

- watch together
- Seerr / Jellyseerr requests
- trackers and optional integrations
- Live TV / DVR where not fully verified
- iCloud settings sync and other platform extras

### Tasks

1. Review each non-core feature against actual verification evidence.
2. For each feature choose one action:
   - keep public
   - mark beta / experimental
   - hide when not configured
   - remove from launch marketing
3. Ensure optional integrations fail soft:
   - missing config should hide feature cleanly
   - bad config should show actionable recovery
4. Tighten in-app labeling so users know when a feature depends on external services.

### Deliverables

- reduced launch risk from optional features
- clearer product expectations in app and release copy

### Verification

- `scripts/ci_checks.sh`
- `flutter test`
- manual checks on every kept feature in launch scope

### Stop Conditions

Stop and resolve before Phase 6 if:
- a non-core feature can still break or confuse the core experience
- product messaging still overpromises unverified features

### Exit Criteria

- optional features are either hardened or safely constrained
- launch copy matches verified behavior

## Phase 6: UX Consolidation and Settings Cleanup

### Objective

Reduce product complexity and make the app feel intentionally finished.

### Scope

- discover/home clarity
- settings information architecture
- empty/loading/error-state consistency
- copy and terminology cleanup

### Tasks

1. Review the first three minutes of use for cognitive overload.
2. Simplify or regroup settings, especially advanced/power-user options.
3. Standardize state messaging across major screens.
4. Remove or reword technical jargon where simpler wording works.
5. Check consistency of labels across mobile, desktop, and TV.

### Deliverables

- simpler settings structure
- cleaner state messaging
- more consistent language and navigation labels

### Verification

- `scripts/ci_checks.sh`
- `flutter test`
- visual/manual review of:
  - auth
  - profile select
  - Home/discover
  - downloads
  - settings
  - major empty/error states

### Stop Conditions

Stop and resolve before Phase 7 if:
- users still need product knowledge to interpret normal app states
- settings remain too dense to support confidently

### Exit Criteria

- core UI feels simpler than the underlying system complexity
- major screens communicate clearly without explanation

## Phase 7: Final Release Readiness Pass

### Objective

Prove that the chosen launch scope is actually ready to ship.

### Scope

- final verification
- store/release artifacts
- public positioning
- support readiness

### Tasks

1. Run the full code and test baseline again.
2. Execute a platform-by-platform manual smoke matrix.
3. Verify store metadata, privacy/source links, and feature descriptions against the actual build.
4. Confirm Sentry and logging behavior in release config.
5. Freeze the launch scope and create a known issues list for anything explicitly deferred.

### Deliverables

- final release checklist with evidence
- launch/no-launch decision
- known issues and post-launch backlog

### Verification

Required baseline:

```bash
flutter pub get
scripts/ci_checks.sh
flutter test
```

Then run the selected release build commands per target platform and capture results.

### Stop Conditions

Do not ship publicly if:
- any P0 flow still has a known blocker
- launch copy overstates platform or feature support
- release configuration is still person-dependent or undocumented

### Exit Criteria

- launch scope is verified, documented, and repeatable
- known tradeoffs are explicit
- we can support the release without tribal knowledge

## Recommended Implementation Order

1. Phase 1 immediately.
2. Phase 2 and Phase 3 next, because onboarding and profile-state are the biggest UX and support multipliers.
3. Phase 4 before any broad beta push.
4. Phase 5 before public marketing language is finalized.
5. Phase 6 after the critical flows are reliable.
6. Phase 7 only when all earlier exit criteria are met.

## Definition of Ready for Public Launch

Pleya is ready for a public launch when all of the following are true:
- core checks pass cleanly
- first-run sign-in succeeds or fails gracefully
- profile and navigation behavior is deterministic
- playback and offline trust hold across the chosen launch platforms
- optional features cannot degrade the core product
- store/release configuration is documented and repeatable
- marketing claims only describe verified behavior

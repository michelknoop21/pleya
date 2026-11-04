# Combined native acceptance — PASS

Verification report by the combined_native worker; root additionally viewed the iOS captures and representative TV captures. The first-person observations below belong to that worker.

Source: `0ae3ca2022b3b08077a1196b18c81ee6ca871bd3`, dirty=false before/after and in all eight scenario manifests. No source/authority changes or commits. Roadmap: existing scoped iOS/TV integration acceptance; Unified impact: both platforms verified on the combined candidate.

One fresh Debug Verify app per platform (REUSE_BUILD=0), then all scenarios reused that platform’s unchanged complete payload (REUSE_BUILD=1). Both Info.plists: `nl.michelknoop.pleya.verify`, 2.8.1 (430), simulator SDK27.0. Current repository driver pipeline used; iOS d692 host-runpath removal and nested signing executed. Both `codesign --verify --deep --strict` exited0.

| Scenario | Result / exit | Steps | Images |
|---|---|---:|---:|
| ios.catalog.header-collapse | PASS / 0 | 26 | 4 |
| ios.library.local-offline | PASS / 0 | 43 | 5 |
| tvos.catalog.full-bleed.grid | PASS / 0 | 51 | 3 |
| tvos.catalog.full-bleed.jump | PASS / 0 | 58 | 4 |
| tvos.my-pleya.libraries-cinema | PASS / 0 | 65 | 7 |
| tvos.my-pleya.libraries-remote-hold | PASS / 0 | 60 | 3 |
| tvos.nav.held-press-lands-once | PASS / 0 | 41 | 4 |
| tvos.profile.picker | PASS / 0 | 20 | 3 |

All 364 steps passed. Terminal combined exit0 (`terminal.json`); individual CLI envelopes/exits in `results.json`, original manifests/reports/logs/trees/captures preserved under `bundles/`. Complete file inventory hashes and app Info in `ios-payload-{before,after}.json` / `tvos-payload-{before,after}.json`. Aggregate SHA256 over sorted relative file→SHA256 JSON:

- iOS: `03f341c936ca25073adee84631fcdd1eb29657cabdb36b6dfcf97c4e3afd95cc`
- tvOS: `cfc7bc6fef8892ac7f5a24c02af2a2c664397d3ec287181b520b027f998888c2`

Personally viewed all33 original native captures (9 iOS750×1334;24 tvOS3840×2160): header hide/return and grid alignment readable; offline settings/storage, posters, search and disabled-playback explanation readable; TV six-column/two-row focus, B01 jump, library sheet/order/catalog return, held-input followup and picker/avatar return visible without a new observed layout/focus defect. The striped right-edge element in two iOS scroll captures is existing product ScrollCrown (`overlay.scroll_crown` in captured tree; gear22×96 logical/right−6, machined teeth/red-band painter), not a host overlay. Fixture posters are intentionally flat colors. See `screenshots-manifest.{md,json}` for every screen, size, file and hash.

Execution: corrected run held one bounded `pleya-heavy run` lease, ticket `00000000000000000001-1a245f230d1e46e787f899865d3a521f`; headless simctl/idb only, TV doctors input=idb/demo_login=false. Used pinned Flutter3.44/existing native-build-cache/KEEP_BUILDS=1. Initial readiness-only attempt omitted existing pyenv idb from harness PATH; preserved under `attempt-1-readiness/`, corrected before any app build/scenario. It is not an app crash or product failure. No old PASS artifact was used for this SHA.

Cleanup: owned iOS `0EF7D62F-941E-41B8-B289-F1257DBC78E4` and TV `2B32D66F-268C-4550-8A6A-0AE5FC13A308` initially Shutdown and restored Shutdown; final terminate found no running Verify process (runner already stopped it), shutdown exit0. See snapshots/cleanup/lease JSON. No Simulator GUI, macOS UI, physical device, Docker, release or push actions. No remaining execution blocker. Evidence is bounded simulator/fixture acceptance; physical Siri Remote touch/holds, real-backend/cache matrices, hardware overscan, release/AOT and performance/jank remain unproven.

## Retained representative images

One original per scenario is retained in `assets/2026-11-02-server-gap-native34/`; full33-image original evidence remains in the local bundle above. Selection and original hashes: `assets/2026-11-02-server-gap-native34/manifest.json`.

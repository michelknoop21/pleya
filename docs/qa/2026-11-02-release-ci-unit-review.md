# PR579 — independent late Flutter test-delta review

**SCOPED PASS — no Critical, Important or Minor findings.** Base/HEAD `c17e5b50e7398566d3569816c52ea3172a083f7c`. Only the new three-file test delta and final QA paragraph reviewed, with bounded relevant callers/evidence. No tests/reruns/builds/auth/PR approval/merge/source writes/delegation. Shells `login:false`; only this report written.

## Binding

Exact current three-file diff equals DIFF.patch SHA256 `382e74a3e431fe11ec1f69eabc8a61f1a948efd398c3b5ccf88b9b85743b2931`; all three source hashes and29 frozen evidence hashes match. The prior five source hashes and their original FREEZE/REPORT/DIFF artifacts remain exact, so the earlier scoped review is not invalidated. Final QA SHA256 `48af53581b33a1c7e5bb9de82045ddc4a239c5e196dbab5a04342dfd88964b2d` correctly distinguishes local repair from new complete CI still required.

## Findings and rationale

Critical: none. Important: none. Minor: none.

- `pleya_wire_contract_test.dart:72–74,259–260`: only the two Web-only cache management schemas join the existing explicit native-defer boundary. The actual shared manifest has154 fixtures and exactly those two schema fixtures; the exact count and unknown-schema accountability remain. Other eligible Dart parsers are unchanged. This does not remove Go/Web/contract validation or claim their complete CI has already passed.
- `tv_unified_activation_hidden_library_test.dart:32–33`: the fake's explicit Plex backend matches every existing item and resolver-server tuple. It supplies metadata now read by the real resolver rather than bypassing resolution. Hidden-source exclusion and visible-source positive assertions are unchanged.
- `watch_actions_test.dart:945–949`: only the local Pleya-copy fixture receives valid carried raw tmdb1 proof with the existing applied-source marker. Real connection/capability setup and429/401/409 injection, direct/card/only-source expectations and refused-write assertion remain unchanged. Production proof/trust/legacy behavior is untouched.
- `watch_actions_test.dart:1016–1032`: three negative cases remove raw proof while groupOf still supplies source.externalIds=tmdb1. They assert carried evidence is absent, no Pleya queued row/event, and the permitted Plex write persists. Saved logs show the actual injected refresh failure and IdentityLookupUnavailable during identity lookup in each case; these controls do not merely disable the whole action or simulate a proof result. Existing applied-copy-proof tests retain capability-transition/known-legacy boundaries, and title-copy tests retain rejection of shared-title-only claims.

Saved original CI nine failures and local199PASS/9FAIL reproduction are preserved. New three-file result209PASS/0FAIL/0SKIP is accounted for as208 original cases minus two explicitly deferred native parse attempts plus three proof-negative controls. Existing2+8 copy-proof tests pass; final ci_checks --with-unused passes without gate skips. Evidence was read, not repeated. No layout/native runtime acceptance is added.

Root may proceed with normal combined commithooks and one push of the eight source fixes plus reviewed counters/evidence. Full CI on that new head, ordinary mainmerge and the remaining matching-image/NAS/TestFlight gates are still required. This report does not relabel the failed old-head full run as green or grant release approval.

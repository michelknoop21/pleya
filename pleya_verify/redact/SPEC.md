<!-- anti-slop: off -->
# Redaction test vectors

`cases.json` is read by two tests that must both stay green:

- `test/utils/log_redaction_manager_parity_test.dart` (main Flutter app) —
  runs each vector through `LogRedactionManager.redact()`.
- `pleya_verify/runner/test/redact_test.dart` — runs each vector through
  `pleya_verify/runner/lib/src/redact.dart`'s `redact()`.

Both must produce `expected` for the same `input`. If a change to
`LogRedactionManager`'s static (non-registered) patterns needs a new
vector to prove it, add the vector here and update the runner's port in
the same change — the parity these two tests check is only as good as
this file's coverage of the app's rules.

## What isn't covered here

`LogRedactionManager.registerToken()`/`registerServerUrl()` track values at
runtime (the app's own session token, the configured server URL) and redact
those verbatim wherever they appear. The runner process never has that
registry — it only ever reads rendered log text after the fact — so there
is no port of that half, and no vector here exercises it.

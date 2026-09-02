<!-- anti-slop: off -->
# Pleya Verify

End-to-end verification for the Pleya app: real scenarios driven against a real macOS/iOS-sim/
tvOS-sim build, over a fixed transport contract, with a saved evidence bundle as the result. See
[`docs/architecture/pleya-verify.md`](../docs/architecture/pleya-verify.md) for the full design,
including the [security boundary](../docs/architecture/pleya-verify.md#security-grens-core-10)
(per-launch bearer token, loopback-only signin/seed, structural evidence redaction, bounded
subprocess execution), and
[`docs/testing/pleya-verify-for-agents.md`](../docs/testing/pleya-verify-for-agents.md) for how to
run and write scenarios.

## Layout

| Path | What it is |
|---|---|
| `contract/verify_api_v1.md` | The `/v1/*` transport spec both the app (`lib/automation/`) and the runner client implement against. |
| `fixture_server/` | Deterministic fake Plex-shaped backend a scenario seeds against. |
| `runner/` | The CLI (`bin/verify.dart`): parses/validates scenarios, drives a platform, writes the evidence bundle, decides PASS/FAILED/ERROR. |
| `scenarios/` | One `.yaml` per test case. See `scenarios/README.md`. |
| `geometry/SPEC.md` | Test-vector spec for the geometry assertion functions (`insideViewport`, `notOverlapping`, …). |
| `redact/SPEC.md` | Shared redaction test vectors, kept in parity between the app and the runner. |
| `mcp/` | Thin MCP (stdio) adapter over the CLI, for an agent session that wants structured tool calls instead of a subprocess. |
| `automation_ids.yaml` | Generated, authoritative catalog of automation ids a scenario may reference. |

## Quick start

```
cd pleya_verify/runner
dart run bin/verify.dart list scenarios --json
dart run bin/verify.dart validate ../scenarios/<name>.yaml
dart run bin/verify.dart run ../scenarios/<name>.yaml --json
```

tvOS scenarios need `idb` (`brew install facebook/fb/idb`) for real HID input; run
`scripts/tvos_sim.sh doctor` first to confirm it is wired up. macOS/iOS-sim scenarios need no
separate readiness check; a missing toolchain surfaces as an `ERROR` result from `run`.

## CI

`.github/workflows/pleya-verify.yml` runs three jobs that only call the CLI commands above, no
reimplemented scenario or driver logic:

- **`portable`** (Linux): `list scenarios --json` plus `validate` on every scenario file, no driver
  dispatch.
- **`macos-verify`** (macOS): `run` for `macos.smoke.boot` and `discover.hero.layout`.
- **`tvos-verify`** (macOS, `workflow_dispatch`/`schedule` only, not required): `run` for
  `tvos.smoke.boot`.

See [DEC-083](../docs/DECISIONS.md#dec-083-pleya-verify-ci-drie-gescheiden-gates-geen-tweede-execution-path)
for why `macos-verify` is not (yet) a required check.

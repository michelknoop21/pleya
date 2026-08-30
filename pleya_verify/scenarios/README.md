<!-- anti-slop: off -->
# Scenarios

`.yaml` scenario files for Pleya Verify, one per test case. Validate one with:

```
cd pleya_verify/runner
dart run bin/verify.dart validate ../scenarios/<name>.yaml
```

List all of them (used by CI and the MCP layer) with:

```
dart run bin/verify.dart list scenarios --json
```

Grammar and vocabulary: `pleya_verify/runner/lib/src/scenario/model.dart`
(the disjoint `setup`/`steps` verb lists) and
`pleya_verify/automation_ids.yaml` (which ids exist, and which are
instanceable as `id[instance]`).

Three of the four scenarios the Pleya Verify Definition of Done requires
(`tvos.sidebar.collapse`, `discover.hero.layout`, `media-detail.episode-refresh`)
land here in Fase 11. `tvos.library.filters` does not: the Pleya Server wire
contract carries no filter parameter or endpoint at all (G13 in
`docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md`, not scheduled before a catalog
phase or a contract question ahead of PS-7), so there is no real filter path
to prove yet. `tvos.library.sort.yaml` exercises the library header's Sort
control instead, a fully supported feature today, under its own, honest
name.

`tvos.library.filters` is formally **DEFERRED: blocked by Pleya Server
catalog/filter contract G13** ([DEC-063](../../docs/DECISIONS.md#dec-063-tvoslibraryfilters-is-deferred-geblokkeerd-door-het-pleya-server-cataloguscontract-g13)).
This is not a missing runner or driver capability; the scenario grammar and
the generic `assert.state`/geometry assertions can already carry it. It is a
product contract that does not exist yet. The requirement stays in the Fase
11 Definition of Done rather than being dropped, and becomes active again
once Pleya Server ships a real filter endpoint.

## CI (Fase 14, [DEC-066](../../docs/DECISIONS.md#dec-066-pleya-verify-ci-drie-gescheiden-gates-geen-tweede-execution-path))

`.github/workflows/pleya-verify.yml` runs three separate jobs, none of
which re-implement scenario or driver logic, they only call the CLI
commands above:

- **`portable`** (Linux, required-candidate): `list scenarios --json` plus
  `validate` on every file here, no driver dispatch.
- **`macos-verify`** (macOS): `macos.smoke.boot` and `discover.hero.layout`
  via `dart run bin/verify.dart run <scenario> --json`.
- **`tvos-verify`** (macOS, `workflow_dispatch`/`schedule` only, not
  required): `tvos.smoke.boot`.

Scenario selection there is deliberately small (one representative per
target/category), not the full regression set from Fase 11.

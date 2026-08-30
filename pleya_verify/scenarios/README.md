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
control instead — a fully supported feature today — under its own, honest
name. `tvos.library.filters` stays an open Fase 11 requirement until that
contract gap closes.

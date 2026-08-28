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

The four scenarios the Pleya Verify Definition of Done requires
(`tvos.sidebar.collapse`, `tvos.library.filters`, `discover.hero.layout`,
`media-detail.episode-refresh`) land here in Fase 11.

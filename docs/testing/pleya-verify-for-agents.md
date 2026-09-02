# Pleya Verify for agents

Imperative reference for driving Pleya Verify from an agent session. Read
`docs/architecture/pleya-verify.md` first if you need the "why"; this file is only the "how" and
the "don't".

## First command

Before running anything against a real target, check whether the target can actually run:

- **tvOS**: `scripts/tvos_sim.sh doctor` (or `doctor --json`). It reports whether `idb` is
  installed and whether it can inject HID input into the simulator. Without `idb`, tvOS input
  falls back to AppleScript, which requires an unlocked, awake screen and silently drops
  keystrokes if the screen is off. Do not run a tvOS scenario before this comes back clean.
- **macOS / iOS-simulator**: there is no separate readiness command. `dart run bin/verify.dart run
  <scenario.yaml>` builds and boots as part of the run; a missing toolchain or simulator surfaces
  as a `run`-time `ERROR`, not a silent skip.

Everything below assumes the working directory is `pleya_verify/runner/` (every subcommand resolves
`../scenarios`, `../automation_ids.yaml`, and `../..` for the repo root relative to that directory),
and that the Flutter SDK pinned in `.fvmrc` is on `PATH` (see CLAUDE.md, dependency section, for why
a different SDK silently breaks formatting/codegen expectations elsewhere in this repo).

## Running an existing scenario

```
cd pleya_verify/runner
dart run bin/verify.dart list scenarios --json   # what exists, and their paths
dart run bin/verify.dart validate ../scenarios/<name>.yaml --json   # cheap: no simulator, no driver
dart run bin/verify.dart run ../scenarios/<name>.yaml --json
```

`run --json` always emits one JSON envelope with `result` set to exactly one of `PASS`, `FAILED`, or
`ERROR`:

- `PASS` / `FAILED`: the scenario actually executed against a driver; `FAILED` means an assertion or
  a `wait_until` timed out. `bundle_dir` points at the evidence bundle
  (`.build/pleya-verify/<run-id>/`): `report.md`, `manifest.json`, `scenario.resolved.yaml`,
  `focus-trace.json`, `app.log`, `driver.log`, `fixture/requests.jsonl`, plus `screenshots/*.png`
  and `ui-tree/*.json` per `snapshot:` step.
  Read the bundle before concluding anything; a `FAILED` result without opening `report.md` and the
  relevant screenshot is a guess, not a finding.
- `ERROR`: the scenario never ran (missing file, parse/validation error, no driver for that
  `target:`). Fix the scenario or the environment, not the assertion.

The MCP layer (`pleya_verify/mcp/`) exposes `list_scenarios` and `run_scenario` as tools over
stdio, for a session that wants structured results without spawning a subprocess directly. Both
wrap the identical CLI subcommands above; `run_scenario`'s response includes a `reproduce` field
with the exact CLI invocation, so a result can always be checked by hand. There is no
`validate`-equivalent tool yet: validate a scenario via the CLI directly.

## Writing a new scenario

One `.yaml` file per test case in `pleya_verify/scenarios/`. Shape:

```yaml
name: <matches the file stem>
target: macos | ios-sim | tvos-sim
setup:
  - reset_app
  - seed: <fixture catalog name>
  - launch
  - sign_in: {base_url: "{{fixture}}", username: verify-owner, password: verify-password, setup_code: "{{fixture_setup_code}}"}
steps:
  - wait_until: {id: <automation id>, timeout: 30000}
  - assert: {id: <automation id>, insideViewport: true, state: {<field>: <value>}}
  - press: <up|down|left|right|select|menu|delete>       # tvOS only
  - snapshot: <name>                                      # writes screenshot + ui-tree
```

`setup:` and `steps:` accept disjoint verb lists on purpose (`pleya_verify/runner/lib/src/
scenario/model.dart`): `setup:` never presses a key and never asserts, `steps:` never seeds or signs
in. A verb in the wrong section is a `validate`-time error with file and line, not a silent no-op.

Every `id:` you reference must exist in `pleya_verify/automation_ids.yaml`
(`dart run bin/verify.dart validate` checks this without a simulator). If the id you need does not
exist yet, that is a real gap: register an `AutomationDeclaredNode` for it in the widget, do not
fall back to a label-based or geometry-only assertion to work around a missing id.

For a `state:` assertion, use the field the widget itself renders from (a `state:` callback
mirroring a real `bool`/`enum`), never a proxy that merely correlates with it. `assert:
{state: {collapsed: !isCollapsed}}` (asserting the boolean *without inverting the bug*) is exactly
the kind of false-PASS Fase 12 exists to catch; see `pleya_verify/scenarios/tvos.sidebar.collapse.yaml`
for a fully commented, worked example, including why that scenario asserts on `state.collapsed`
specifically instead of geometry alone.

For geometry assertions (`insideViewport`, `notOverlapping`, `minimumTapTarget`, `below`/`above`/
`leftOf`/`rightOf`, `sameRow`/`sameColumn`), see `pleya_verify/geometry/SPEC.md` for the full
function/argument table before guessing a shape.

## On failure

1. Open `report.md` and the relevant `screenshots/*.png` in the bundle before touching code. A
   `FAILED` scenario is evidence of a real behavior gap until proven otherwise, not evidence of a
   bad assertion.
2. If the fix is in product code: fix it, then rerun the exact scenario to confirm `PASS`, then run
   the wider suite the change could plausibly affect. Do not loosen the assertion to make it pass.
3. If the scenario itself was wrong (references a state that no longer exists, asserts something
   the product never promised), fix the scenario and say so explicitly. This is rare; treat it as
   the last resort, not the first guess.
4. Never edit `.build/pleya-verify/` by hand. It is generated evidence; a hand-edited bundle proves
   nothing.

## Never do this

- **Never drive tvOS input through `/v1/input/*`.** The gated engine fork claims every remote press
  before UIKit's responder chain runs (see CLAUDE.md, Gotchas section); a press synthesized over the
  automation transport does not exercise that path and proves nothing about a real Siri Remote.
  `TvosSimulatorDriver` only ever sends input through `scripts/tvos_sim.sh` (idb HID); do not add a
  tvOS scenario step or a driver change that routes around that.
- **Never treat `GET /v1/screenshot` as a visual source of truth.** It is a Flutter
  `RepaintBoundary` capture, diagnostic only (it skips platform compositing, mpv layers, and system
  chrome). A real PASS screenshot always comes from the platform/simulator capture
  (`xcrun simctl io … screenshot` or the macOS equivalent).
- **Never invent a fixture behavior to make a scenario pass.** If a scenario needs a capability the
  fixture or the product does not have yet (see `tvos.library.filters`, deferred by
  [DEC-080](../DECISIONS.md#dec-080-tvoslibraryfilters-is-deferred-geblokkeerd-door-het-pleya-server-cataloguscontract-g13)),
  defer the scenario explicitly rather than building a workaround that technically goes green.
- **Never claim UI/focus work is verified without running the relevant scenario(s) and reading the
  bundle**, unless the environment provably cannot run the target (no simulator, no macOS runner).
  In that case, say exactly what evidence is missing rather than reporting the work as verified.

# Pleya Verify MCP

An MCP (Model Context Protocol) stdio server over the existing Pleya Verify
CLI (`pleya_verify/runner/bin/verify.dart`).

## Architecture

MCP is a thin transport adapter. The CLI remains the single execution entry
point.

```
MCP tool call -> dart run bin/verify.dart <subcommand> --json (subprocess)
              -> existing runner engine, drivers, fixture server
              -> existing evidence bundle under .build/pleya-verify/<run-id>/
```

When an MCP tool and a person typing the CLI by hand run the same scenario,
they go through the exact same code from the CLI entrypoint down. The only
difference is who started the subprocess.

**What is deliberately *not* in this package:** scenario YAML parsing, the
`setup`/`steps` verb dispatch, fixture seeding, placeholder resolution
(`{{fixture}}`, `{{fixture_id:...}}`), geometry/state assertions, UI-tree or
focus-trace interpretation, screenshot validation, evidence bundle
construction, platform driver selection, app-instance discovery, and the
PASS/FAIL decision itself. All of that lives in
`pleya_verify/runner/lib/src/engine/` and `.../driver/`, unchanged by this
package. `lib/src/verify_cli.dart` only starts the CLI subprocess and reads
back the JSON envelope it already decided; it never opens a scenario file,
never talks to the fixture server, and never recomputes `passed`.

## Tools

### `list_scenarios`

Wraps `dart run bin/verify.dart list scenarios --json`, already documented
in `pleya_verify/scenarios/README.md` as "used by CI and the MCP layer".
Takes no arguments. Returns:

```json
{"scenarios": [{"name": "macos.smoke.boot", "path": "../scenarios/macos.smoke.boot.yaml"}, ...]}
```

`name` is the scenario's file stem (repository convention keeps it
identical to the scenario's own `name:` field), and is exactly what
`run_scenario` accepts.

### `run_scenario`

Input: `{"scenario": "<name from list_scenarios>"}`.

Resolves `scenario` against the current `list_scenarios` output (never
against a caller-supplied path, see **Security** below), then runs
`dart run bin/verify.dart run <resolved-path> --json` and passes the CLI's
JSON envelope straight through:

```json
{
  "ok": true,
  "result": "PASS",
  "scenario": "macos.smoke.boot",
  "target": "macos",
  "bundle_dir": ".build/pleya-verify/macos-smoke-boot-<timestamp>",
  "failure_message": null,
  "cli_exit_code": 0,
  "command": "cd pleya_verify/runner && dart run bin/verify.dart run ../scenarios/macos.smoke.boot.yaml --json"
}
```

`result` is one of:

- `PASS` / `FAILED`: the scenario actually ran; `ok` mirrors `result == "PASS"`.
- `ERROR`: a configuration/invocation problem (unknown scenario, a scenario
  file that fails to parse or validate, a target with no implemented
  driver) that stopped the CLI *before* or *during* dispatch. Never
  reported as `FAILED`: a scenario that never got a chance to assert
  anything is not the same claim as one that asserted something and lost.

If the CLI subprocess itself misbehaves (a non-zero exit with no
parseable JSON on stdout, a crash), the tool call fails with an MCP
`isError: true` result carrying that failure. That is a third, distinct
outcome from both `FAILED` and `ERROR`: the CLI never got to render a
verdict at all.

`bundle_dir` points at the same evidence bundle
(`manifest.json`, `report.md`, `screenshots/`, `ui-tree/`, `focus-trace.json`,
`fixture/requests.jsonl`, `app.log`, `driver.log`) the CLI always writes.
This package creates none of it.

## Agent usage

```
tools/call run_scenario {"scenario": "macos.smoke.boot"}
```

A representative response:

```json
{
  "ok": true,
  "result": "PASS",
  "scenario": "macos.smoke.boot",
  "target": "macos",
  "bundle_dir": ".build/pleya-verify/macos-smoke-boot-1788200000000",
  "failure_message": null,
  "cli_exit_code": 0,
  "command": "cd pleya_verify/runner && dart run bin/verify.dart run ../scenarios/macos.smoke.boot.yaml --json"
}
```

To reproduce the exact same run outside MCP (same scenario, same CLI
entrypoint, same evidence layout), copy the `command` field and run it from
the repository root:

```
cd pleya_verify/runner && dart run bin/verify.dart run ../scenarios/macos.smoke.boot.yaml --json
```

## Security and reliability

- **No path traversal.** `run_scenario`'s `scenario` argument is only ever
  matched against the file stems `list_scenarios` (the CLI's own
  `list scenarios --json`) currently reports. It is never concatenated into
  a filesystem path: an unknown name fails with a clear `VerifyCliUsageError`
  before any subprocess for `run` starts.
- **No shell interpolation.** Every subprocess call goes through
  `Process.run(..., runInShell: false)` with a plain `List<String>` argv
  (`lib/src/process_runner.dart`), so a scenario name can never be
  interpreted as shell syntax.
- **stdout carries protocol only.** The MCP stdio loop
  (`lib/src/mcp_server.dart`) writes nothing but JSON-RPC messages to
  stdout; anything diagnostic goes to stderr, so a stray print can never
  corrupt the next message a client tries to parse.
- **No credential logging of its own.** This package logs nothing about
  scenario content; whatever the CLI itself redacts (see
  `pleya_verify/runner/lib/src/redact.dart`) stays redacted. This layer
  only relays the CLI's already-redacted JSON output.
- **A broken subprocess can never present as PASS.** `VerifyCli.runScenario`
  distinguishes three outcomes: a real `PASS`/`FAILED` from the CLI, a
  configuration `ERROR` the CLI itself reported, and an infrastructure
  failure (`VerifyCliInfraError`) when the subprocess could not be trusted
  at all (non-zero exit with unparseable JSON, or JSON that is not the
  expected object). Only the first two ever reach a caller as a normal
  tool result; the third always surfaces as a failed tool call.

## Running it

```
cd pleya_verify/mcp
dart pub get
dart run bin/pleya_verify_mcp.dart
```

Speaks the MCP stdio transport: one JSON-RPC 2.0 message per line on stdin,
one per line back on stdout. Point an MCP-capable client at that command.

## Tests

```
cd pleya_verify/mcp
dart test
```

- `test/verify_cli_test.dart`, `test/run_scenario_tool_test.dart`: wrapper
  tests against a scripted `FakeProcessRunner`
  (`test/fake_process_runner.dart`), covering PASS/FAILED passthrough, the
  usage/infra/scenario-FAIL distinction, argv-not-shell-string, and stderr
  noise not corrupting stdout parsing.
- `test/mcp_server_test.dart`: drives the real newline-delimited JSON-RPC
  loop from `lib/src/mcp_server.dart` over an in-memory stream, the
  representative transport boundary, without spawning a process.
- `test/real_cli_integration_test.dart`: the one test that crosses the
  real subprocess boundary. `RealProcessRunner` against the actual
  `verify.dart list scenarios --json` entrypoint (cheap and deterministic;
  no simulator or `flutter build` needed for a listing call).

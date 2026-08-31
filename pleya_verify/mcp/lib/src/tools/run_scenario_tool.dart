import '../verify_cli.dart';
import 'tool.dart';

/// `run_scenario`: starts one existing Pleya Verify scenario through the
/// existing CLI and passes its `--json` result straight through.
///
/// This is the entire tool: no scenario, fixture, driver, or assertion
/// logic lives here. Everything after "start the CLI subprocess" is decided
/// by `pleya_verify/runner/bin/verify.dart` and the runner engine beneath
/// it. See `pleya_verify/mcp/README.md`.
Tool buildRunScenarioTool(VerifyCli cli) {
  return Tool(
    name: 'run_scenario',
    description:
        'Run one existing Pleya Verify scenario by name (its file stem, e.g. '
        '"macos.smoke.boot") through the real `verify.dart run --json` CLI and '
        'report the PASS/FAILED/ERROR result exactly as the CLI decided it, '
        'including the evidence bundle location and a pasteable CLI command to '
        're-run the same scenario outside MCP. Use `list_scenarios` first to see '
        'the exact names this accepts.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'scenario': {
          'type': 'string',
          'description': 'A scenario file stem from `list_scenarios`, e.g. "macos.smoke.boot".',
        },
      },
      'required': ['scenario'],
      'additionalProperties': false,
    },
    handler: (arguments) async {
      final scenario = arguments['scenario'];
      if (scenario is! String || scenario.isEmpty) {
        throw VerifyCliUsageError('"scenario" must be a non-empty string naming a known scenario');
      }
      final outcome = await cli.runScenario(scenario);
      return outcome.toJson();
    },
  );
}

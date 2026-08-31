import '../verify_cli.dart';
import 'tool.dart';

/// `list_scenarios`: the existing CLI's `list scenarios --json` (already
/// documented in `pleya_verify/scenarios/README.md` as "used by CI and the
/// MCP layer"), passed straight through. No second, hand-maintained
/// scenario registry lives in this package.
Tool buildListScenariosTool(VerifyCli cli) {
  return Tool(
    name: 'list_scenarios',
    description:
        'List the Pleya Verify scenarios that exist right now, as discovered by '
        'the real `verify.dart list scenarios --json` CLI. Each entry\'s "name" is '
        'exactly what `run_scenario` accepts.',
    inputSchema: {'type': 'object', 'properties': <String, Object?>{}, 'additionalProperties': false},
    handler: (arguments) async {
      final scenarios = await cli.listScenarios();
      return {
        'scenarios': [
          for (final s in scenarios) {'name': s.name, 'path': s.path},
        ],
      };
    },
  );
}

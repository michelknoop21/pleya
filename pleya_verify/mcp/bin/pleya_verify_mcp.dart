import 'dart:io';

import 'package:pleya_verify_mcp/src/mcp_server.dart';
import 'package:pleya_verify_mcp/src/process_runner.dart';
import 'package:pleya_verify_mcp/src/tools/list_scenarios_tool.dart';
import 'package:pleya_verify_mcp/src/tools/run_scenario_tool.dart';
import 'package:pleya_verify_mcp/src/verify_cli.dart';

/// Entry point for a stdio MCP client (`dart run bin/pleya_verify_mcp.dart`
/// from `pleya_verify/mcp/`). Wires the two tools to the existing Verify CLI
/// and starts the stdio loop. See `pleya_verify/mcp/README.md` for the
/// architecture this sits on top of.
Future<void> main(List<String> args) async {
  final mcpPackageDir = File(Platform.script.toFilePath()).parent.parent;
  final runnerPackageDir = '${mcpPackageDir.parent.path}/runner';

  final cli = VerifyCli(runner: const RealProcessRunner(), runnerPackageDir: runnerPackageDir);
  final server = McpServer(
    tools: [buildRunScenarioTool(cli), buildListScenariosTool(cli)],
    input: stdin,
    output: stdout,
    logError: (message) => stderr.writeln('[pleya-verify-mcp] $message'),
  );
  await server.run();
}

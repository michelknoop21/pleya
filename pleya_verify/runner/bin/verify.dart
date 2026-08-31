import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/driver/ios_simulator_driver.dart';
import 'package:pleya_verify_runner/src/driver/macos_driver.dart';
import 'package:pleya_verify_runner/src/driver/tvos_simulator_driver.dart';
import 'package:pleya_verify_runner/src/driver/verification_driver.dart';
import 'package:pleya_verify_runner/src/engine/run_scenario.dart';
import 'package:pleya_verify_runner/src/redact.dart';
import 'package:pleya_verify_runner/src/scenario/automation_id_catalog.dart';
import 'package:pleya_verify_runner/src/scenario/model.dart';
import 'package:pleya_verify_runner/src/scenario/parser.dart';
import 'package:pleya_verify_runner/src/scenario/validator.dart';

/// This package's root is every subcommand's working-directory assumption
/// (`dart run bin/verify.dart` from `pleya_verify/runner/`); the repo root
/// two levels up is where `.build/pleya-verify/` and `flutter build` live.
final Directory _repoRoot = Directory('../..');

/// The three targets a driver exists for from Fase 8 on. A fixed list, not
/// derived from anything scanned at runtime — there is no fourth target to
/// discover.
const List<String> knownTargets = ['macos', 'ios-sim', 'tvos-sim'];

/// Path to the generated automation-id catalog, resolved relative to this
/// package's root (`pleya_verify/runner/`), which is every subcommand's
/// working-directory assumption below.
final File _automationIdsFile = File('../automation_ids.yaml');

final Directory _defaultScenariosDir = Directory('../scenarios');

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exitCode = 64; // EX_USAGE
    return;
  }

  final jsonOutput = args.contains('--json');
  final positional = args.where((a) => a != '--json').toList();

  switch (positional.firstOrNull) {
    case 'validate':
      await _runValidate(positional.skip(1).toList(), jsonOutput: jsonOutput);
    case 'list':
      await _runList(positional.skip(1).toList(), jsonOutput: jsonOutput);
    case 'run':
      await _runScenarioCommand(positional.skip(1).toList(), jsonOutput: jsonOutput);
    default:
      _printUsage();
      exitCode = 64;
  }
}

void _printUsage() {
  stderr.writeln('''
Usage:
  dart run bin/verify.dart validate <scenario.yaml> [--json]
  dart run bin/verify.dart list scenarios [--dir <dir>] [--json]
  dart run bin/verify.dart list targets [--json]
  dart run bin/verify.dart run <scenario.yaml> [--json]
''');
}

/// The exact argv a contributor can paste to reproduce a `run` invocation
/// outside the MCP layer, kept as one place so the reproduced command can
/// never drift from what this subcommand actually accepts.
List<String> _runCommand(String scenarioPath, {required bool jsonOutput}) => [
  'run',
  'bin/verify.dart',
  'run',
  scenarioPath,
  if (jsonOutput) '--json',
];

/// The single JSON envelope every exit path of `run --json` produces (PASS,
/// FAILED, and every configuration/invocation error alike), so a caller
/// (the MCP layer included) never has to guess which shape it got back.
/// `result` is `PASS`/`FAILED` only when a scenario actually executed;
/// anything that short-circuits before or during dispatch (missing file,
/// parse error, validation error, no driver for the target) is `ERROR`,
/// never disguised as a scenario FAIL.
void _emitRunResult({
  required bool jsonOutput,
  required String scenarioPath,
  required int exitCodeValue,
  required String result,
  String? scenarioName,
  String? target,
  String? bundleDir,
  String? failureMessage,
  List<Map<String, Object?>>? errors,
  required String humanText,
  required bool humanIsError,
}) {
  if (jsonOutput) {
    stdout.writeln(
      jsonEncode({
        'ok': result == 'PASS',
        'result': result,
        'scenario': scenarioName,
        'target': target,
        'bundle_dir': bundleDir,
        'failure_message': failureMessage,
        if (errors != null) 'errors': errors,
        'exit_code': exitCodeValue,
        'command': _runCommand(scenarioPath, jsonOutput: jsonOutput),
      }),
    );
  } else if (humanIsError) {
    stderr.writeln(humanText);
  } else {
    stdout.writeln(humanText);
  }
  exitCode = exitCodeValue;
}

Future<void> _runScenarioCommand(List<String> args, {required bool jsonOutput}) async {
  if (args.isEmpty) {
    stderr.writeln('run requires a scenario file path');
    exitCode = 64;
    return;
  }
  final scenarioPath = args.first;
  try {
    await _runScenarioCommandBody(scenarioPath, jsonOutput: jsonOutput);
  } catch (e, st) {
    // Every exception the body below could throw and doesn't already turn
    // into a specific PASS/FAILED/ERROR envelope — a malformed
    // automation_ids.yaml, an unexpected I/O failure while reading the
    // scenario file, anything else — still has to answer with exactly the
    // one JSON object `--json` promises, never a raw stack trace on stdout
    // and never an uncaught Future error with no envelope at all. This is
    // the top-level backstop for that promise, not a substitute for a
    // narrower catch closer to where something can actually go wrong.
    _emitRunResult(
      jsonOutput: jsonOutput,
      scenarioPath: scenarioPath,
      exitCodeValue: 70, // EX_SOFTWARE
      result: 'ERROR',
      failureMessage: redact('$e'),
      humanText: 'run: unexpected error: ${redact('$e')}',
      humanIsError: true,
    );
    // Diagnostic only, stderr-only, and only the stack trace half — the
    // message itself already reached the caller above through
    // failure_message/humanText. Redacted for the same reason every other
    // failure message in this tool is: `$st` can quote source lines that
    // themselves quote a URL or header.
    stderr.writeln(redact('$st'));
  }
}

Future<void> _runScenarioCommandBody(String scenarioPath, {required bool jsonOutput}) async {
  final file = File(scenarioPath);
  if (!file.existsSync()) {
    _emitRunResult(
      jsonOutput: jsonOutput,
      scenarioPath: scenarioPath,
      exitCodeValue: 66,
      result: 'ERROR',
      failureMessage: '$scenarioPath: no such file',
      humanText: '$scenarioPath: no such file',
      humanIsError: true,
    );
    return;
  }

  Scenario scenario;
  try {
    scenario = parseScenarioFile(file);
  } on ScenarioParseException catch (e) {
    if (jsonOutput) {
      _emitRunResult(
        jsonOutput: true,
        scenarioPath: scenarioPath,
        exitCodeValue: 1,
        result: 'ERROR',
        errors: [
          {'path': e.error.sourcePath, 'line': e.error.line, 'message': e.error.message},
        ],
        humanText: '',
        humanIsError: true,
      );
    } else {
      _reportErrors(file.path, [e.error], jsonOutput: false);
      exitCode = 1;
    }
    return;
  }

  final catalog = AutomationIdCatalog.fromFile(_automationIdsFile);
  final validationErrors = validateScenario(scenario, catalog);
  if (validationErrors.isNotEmpty) {
    if (jsonOutput) {
      _emitRunResult(
        jsonOutput: true,
        scenarioPath: scenarioPath,
        exitCodeValue: 1,
        result: 'ERROR',
        scenarioName: scenario.name,
        target: scenario.target,
        errors: [
          for (final err in validationErrors) {'path': err.sourcePath, 'line': err.line, 'message': err.message},
        ],
        humanText: '',
        humanIsError: true,
      );
    } else {
      _reportErrors(file.path, validationErrors, jsonOutput: false);
      exitCode = 1;
    }
    return;
  }

  final VerificationDriver driver;
  switch (scenario.target) {
    case 'macos':
      driver = MacosDriver(repoRoot: _repoRoot);
    case 'ios-sim':
      driver = IosSimulatorDriver(repoRoot: _repoRoot);
    case 'tvos-sim':
      driver = TvosSimulatorDriver(repoRoot: _repoRoot);
    default:
      _emitRunResult(
        jsonOutput: jsonOutput,
        scenarioPath: scenarioPath,
        exitCodeValue: 64,
        result: 'ERROR',
        scenarioName: scenario.name,
        target: scenario.target,
        failureMessage: 'no driver implemented yet for target "${scenario.target}"',
        humanText: 'run: no driver implemented yet for target "${scenario.target}"',
        humanIsError: true,
      );
      return;
  }

  final result = await runScenario(
    scenario: scenario,
    scenarioSource: file.readAsStringSync(),
    driver: driver,
    repoRoot: _repoRoot,
  );

  _emitRunResult(
    jsonOutput: jsonOutput,
    scenarioPath: scenarioPath,
    exitCodeValue: result.passed ? 0 : 1,
    result: result.passed ? 'PASS' : 'FAILED',
    scenarioName: scenario.name,
    target: scenario.target,
    bundleDir: result.bundleDir.path,
    failureMessage: result.failureMessage,
    humanText: result.passed
        ? 'PASS: ${scenario.name}, evidence at ${result.bundleDir.path}'
        : 'FAILED: ${scenario.name}: ${result.failureMessage}\nevidence at ${result.bundleDir.path}',
    humanIsError: !result.passed,
  );
}

Future<void> _runValidate(List<String> args, {required bool jsonOutput}) async {
  if (args.isEmpty) {
    stderr.writeln('validate requires a scenario file path');
    exitCode = 64;
    return;
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('${args.first}: no such file');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  try {
    await _runValidateBody(file, jsonOutput: jsonOutput);
  } catch (e) {
    // Same backstop as `_runScenarioCommand`'s catch — a malformed
    // automation_ids.yaml or any other unexpected failure here must still
    // produce the one JSON error object `--json` promises, not an
    // uncaught Future error with nothing on stdout at all.
    _reportErrors(
      file.path,
      [ScenarioError(sourcePath: file.path, message: 'unexpected error: ${redact('$e')}')],
      jsonOutput: jsonOutput,
    );
    exitCode = 70; // EX_SOFTWARE
  }
}

Future<void> _runValidateBody(File file, {required bool jsonOutput}) async {
  Scenario scenario;
  try {
    scenario = parseScenarioFile(file);
  } on ScenarioParseException catch (e) {
    _reportErrors(file.path, [e.error], jsonOutput: jsonOutput);
    exitCode = 1;
    return;
  }

  final catalog = AutomationIdCatalog.fromFile(_automationIdsFile);
  final errors = validateScenario(scenario, catalog);

  if (errors.isEmpty) {
    if (jsonOutput) {
      stdout.writeln(jsonEncode({'ok': true, 'name': scenario.name, 'target': scenario.target}));
    } else {
      stdout.writeln('OK: ${scenario.name} (${scenario.target})');
    }
    exitCode = 0;
    return;
  }

  _reportErrors(file.path, errors, jsonOutput: jsonOutput);
  exitCode = 1;
}

void _reportErrors(String path, List<ScenarioError> errors, {required bool jsonOutput}) {
  if (jsonOutput) {
    stdout.writeln(
      jsonEncode({
        'ok': false,
        'errors': [
          for (final e in errors) {'path': e.sourcePath, 'line': e.line, 'message': e.message},
        ],
      }),
    );
    return;
  }
  for (final e in errors) {
    stderr.writeln(e.toString());
  }
}

Future<void> _runList(List<String> args, {required bool jsonOutput}) async {
  switch (args.firstOrNull) {
    case 'targets':
      if (jsonOutput) {
        stdout.writeln(jsonEncode(knownTargets));
      } else {
        for (final target in knownTargets) {
          stdout.writeln(target);
        }
      }
    case 'scenarios':
      var dir = _defaultScenariosDir;
      final dirFlagIndex = args.indexOf('--dir');
      if (dirFlagIndex != -1 && dirFlagIndex + 1 < args.length) {
        dir = Directory(args[dirFlagIndex + 1]);
      }
      final files = _findScenarioFiles(dir);
      if (jsonOutput) {
        stdout.writeln(jsonEncode(files));
      } else {
        if (files.isEmpty) {
          stdout.writeln('(no scenario files under ${dir.path})');
        }
        for (final f in files) {
          stdout.writeln(f);
        }
      }
    default:
      stderr.writeln('list requires a subcommand: targets | scenarios');
      exitCode = 64;
  }
}

List<String> _findScenarioFiles(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
      .map((f) => f.path)
      .toList()
    ..sort();
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

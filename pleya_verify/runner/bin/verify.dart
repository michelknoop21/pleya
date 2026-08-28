import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/driver/ios_simulator_driver.dart';
import 'package:pleya_verify_runner/src/driver/macos_driver.dart';
import 'package:pleya_verify_runner/src/driver/verification_driver.dart';
import 'package:pleya_verify_runner/src/engine/run_scenario.dart';
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

Future<void> _runScenarioCommand(List<String> args, {required bool jsonOutput}) async {
  if (args.isEmpty) {
    stderr.writeln('run requires a scenario file path');
    exitCode = 64;
    return;
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('${args.first}: no such file');
    exitCode = 66;
    return;
  }

  Scenario scenario;
  try {
    scenario = parseScenarioFile(file);
  } on ScenarioParseException catch (e) {
    _reportErrors(file.path, [e.error], jsonOutput: jsonOutput);
    exitCode = 1;
    return;
  }

  final catalog = AutomationIdCatalog.fromFile(_automationIdsFile);
  final validationErrors = validateScenario(scenario, catalog);
  if (validationErrors.isNotEmpty) {
    _reportErrors(file.path, validationErrors, jsonOutput: jsonOutput);
    exitCode = 1;
    return;
  }

  final VerificationDriver driver;
  switch (scenario.target) {
    case 'macos':
      driver = MacosDriver(repoRoot: _repoRoot);
    case 'ios-sim':
      driver = IosSimulatorDriver(repoRoot: _repoRoot);
    default:
      stderr.writeln('run: no driver implemented yet for target "${scenario.target}"');
      exitCode = 64;
      return;
  }

  final result = await runScenario(
    scenario: scenario,
    scenarioSource: file.readAsStringSync(),
    driver: driver,
    repoRoot: _repoRoot,
  );

  if (jsonOutput) {
    stdout.writeln(
      jsonEncode({
        'ok': result.passed,
        'result': result.passed ? 'PASS' : 'FAILED',
        'bundle': result.bundleDir.path,
        if (result.failureMessage != null) 'failureMessage': result.failureMessage,
      }),
    );
  } else if (result.passed) {
    stdout.writeln('PASS: ${scenario.name} — evidence at ${result.bundleDir.path}');
  } else {
    stderr.writeln('FAILED: ${scenario.name} — ${result.failureMessage}');
    stderr.writeln('evidence at ${result.bundleDir.path}');
  }
  exitCode = result.passed ? 0 : 1;
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

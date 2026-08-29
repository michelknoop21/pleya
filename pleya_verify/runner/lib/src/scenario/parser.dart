import 'dart:io';

import 'package:yaml/yaml.dart';

import 'model.dart';

/// Thrown by [parseScenarioFile]/[parseScenarioString] when the file cannot
/// be parsed into a [Scenario] at all (missing required top-level field, or
/// a `setup`/`steps` entry that isn't a bare verb or a single-key map).
/// Structural verb-vocabulary/id violations are a *valid* parse result
/// instead — see `validator.dart` — because those need the whole scenario
/// in hand (including the target) to check.
class ScenarioParseException implements Exception {
  final ScenarioError error;

  const ScenarioParseException(this.error);

  @override
  String toString() => 'ScenarioParseException: $error';
}

Scenario parseScenarioFile(File file) => parseScenarioString(file.readAsStringSync(), sourcePath: file.path);

Scenario parseScenarioString(String contents, {required String sourcePath}) {
  final YamlNode root = loadYamlNode(contents, sourceUrl: Uri.file(sourcePath));
  if (root is! YamlMap) {
    throw ScenarioParseException(
      ScenarioError(sourcePath: sourcePath, line: 1, message: 'top-level document must be a map'),
    );
  }

  final name = root['name'];
  if (name is! String) {
    throw ScenarioParseException(
      ScenarioError(sourcePath: sourcePath, line: _line(root), message: 'missing required field: name'),
    );
  }

  final target = root['target'];
  if (target is! String) {
    throw ScenarioParseException(
      ScenarioError(sourcePath: sourcePath, line: _line(root), message: 'missing required field: target'),
    );
  }

  final stepsNode = root['steps'];
  if (stepsNode is! YamlList) {
    throw ScenarioParseException(
      ScenarioError(
        sourcePath: sourcePath,
        line: _line(root),
        message: 'missing required field: steps (must be a list)',
      ),
    );
  }

  final setupNode = root['setup'];
  if (setupNode != null && setupNode is! YamlList) {
    // `root['setup']` unwraps a scalar to its plain Dart value, so casting
    // it to YamlNode for a line number is exactly the case this branch is
    // here to report — `setup: hallo` used to die on a raw _TypeError,
    // which `bin/verify.dart` does not catch, so the CLI's "one clean
    // file:line: message" contract broke on the malformed input it was
    // supposed to explain. Take the span from the key's own node instead.
    final keyNode = root.nodes.keys.whereType<YamlNode>().where((k) => k.value == 'setup').firstOrNull;
    throw ScenarioParseException(
      ScenarioError(
        sourcePath: sourcePath,
        line: _line(keyNode ?? root),
        message: 'setup must be a list',
      ),
    );
  }

  return Scenario(
    name: name,
    target: target,
    setup: setupNode == null ? const [] : _parseStepList(setupNode as YamlList, sourcePath),
    steps: _parseStepList(stepsNode, sourcePath),
    sourcePath: sourcePath,
  );
}

List<ScenarioStep> _parseStepList(YamlList list, String sourcePath) => [
  for (final item in list.nodes) _parseStep(item, sourcePath),
];

ScenarioStep _parseStep(YamlNode item, String sourcePath) {
  final line = _line(item);

  if (item is YamlScalar && item.value is String) {
    return ScenarioStep(verb: item.value as String, args: null, line: line);
  }

  if (item is YamlMap) {
    if (item.length != 1) {
      throw ScenarioParseException(
        ScenarioError(
          sourcePath: sourcePath,
          line: line,
          message: 'a setup/step entry must have exactly one verb key, found ${item.length}',
        ),
      );
    }
    final verb = item.keys.first;
    if (verb is! String) {
      throw ScenarioParseException(
        ScenarioError(sourcePath: sourcePath, line: line, message: 'verb key must be a string'),
      );
    }
    return ScenarioStep(verb: verb, args: _toPlain(item.nodes[verb]!), line: line);
  }

  throw ScenarioParseException(
    ScenarioError(
      sourcePath: sourcePath,
      line: line,
      message: 'a setup/step entry must be a bare verb or a single-key map',
    ),
  );
}

int _line(YamlNode node) => node.span.start.line + 1;

Object? _toPlain(YamlNode node) {
  if (node is YamlScalar) return node.value;
  if (node is YamlList) return [for (final e in node.nodes) _toPlain(e)];
  if (node is YamlMap) {
    return {for (final MapEntry(:key, :value) in node.nodes.entries) key.toString(): _toPlain(value)};
  }
  return null;
}

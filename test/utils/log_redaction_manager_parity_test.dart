import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/log_redaction_manager.dart';

/// The app-side half of the Fase 7 redact-parity check: runs the same
/// vectors `pleya_verify/runner/test/redact_test.dart` runs, through the
/// real `LogRedactionManager.redact()`, so a static pattern the app knows
/// and the runner's port (`pleya_verify/runner/lib/src/redact.dart`) misses
/// — or vice versa — shows up as a failure on whichever side hasn't been
/// updated. See pleya_verify/redact/SPEC.md for what this does and doesn't
/// cover.
void main() {
  setUp(LogRedactionManager.clearTrackedValues);

  final doc = jsonDecode(File('pleya_verify/redact/cases.json').readAsStringSync()) as Map<String, Object?>;
  final cases = doc['cases'] as List<Object?>;

  test('at least one vector per static LogRedactionManager rule', () {
    expect(cases.length, greaterThanOrEqualTo(15));
  });

  group('redact vectors (parity half: main app)', () {
    for (final raw in cases) {
      final testCase = raw as Map<String, Object?>;
      test(testCase['description'] as String, () {
        expect(LogRedactionManager.redact(testCase['input'] as String), testCase['expected']);
      });
    }
  });
}

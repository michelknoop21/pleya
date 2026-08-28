import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/redact.dart';
import 'package:test/test.dart';

void main() {
  final doc = jsonDecode(File('../redact/cases.json').readAsStringSync()) as Map<String, Object?>;
  final cases = doc['cases'] as List<Object?>;

  test('at least one vector per static LogRedactionManager rule', () {
    expect(cases.length, greaterThanOrEqualTo(15));
  });

  group('redact vectors (parity half: pleya_verify/runner)', () {
    for (final raw in cases) {
      final testCase = raw as Map<String, Object?>;
      test(testCase['description'] as String, () {
        expect(redact(testCase['input'] as String), testCase['expected']);
      });
    }
  });
}

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

  group('redactJson structural key matching', () {
    test('redacts a composite camelCase key ending in a secret word', () {
      expect(redactJson({'oldPassword': 'hunter2'}), {'oldPassword': '[REDACTED]'});
    });

    test('redacts a composite camelCase key with the secret word in the middle', () {
      expect(redactJson({'userAccessToken': 'eyJhbGciOi...'}), {'userAccessToken': '[REDACTED]'});
    });

    test('redacts a composite camelCase key made of two secret-adjacent words', () {
      expect(redactJson({'serverApiKey': 'sk-abc123'}), {'serverApiKey': '[REDACTED]'});
    });

    test('redacts the same composite name in kebab-case and snake_case too', () {
      expect(redactJson({'old-password': 'x'}), {'old-password': '[REDACTED]'});
      expect(redactJson({'old_password': 'x'}), {'old_password': '[REDACTED]'});
    });

    test('does not redact an unrelated key that merely contains a secret word as a substring', () {
      expect(redactJson({'tokenizerVersion': 3}), {'tokenizerVersion': 3});
      expect(redactJson({'passwordless': true}), {'passwordless': true});
    });

    test('redacts nested maps', () {
      expect(
        redactJson({
          'result': {'auth': {'oldPassword': 'hunter2', 'note': 'fine'}},
        }),
        {
          'result': {'auth': {'oldPassword': '[REDACTED]', 'note': 'fine'}},
        },
      );
    });

    test('redacts maps inside lists', () {
      expect(
        redactJson([
          {'userAccessToken': 'a'},
          {'note': 'fine'},
        ]),
        [
          {'userAccessToken': '[REDACTED]'},
          {'note': 'fine'},
        ],
      );
    });

    test('still redacts the exact bare field names the old exact-match rule already covered', () {
      expect(redactJson({'password': 'x', 'token': 'y', 'authorization': 'z'}), {
        'password': '[REDACTED]',
        'token': '[REDACTED]',
        'authorization': '[REDACTED]',
      });
    });
  });
}

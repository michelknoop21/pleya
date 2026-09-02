import 'dart:io';

import 'package:pleya_verify_runner/src/scenario/remote_keys.dart';
import 'package:test/test.dart';

/// The runner cannot import either of the other two copies of the remote
/// vocabulary — one is app Dart in a different package, one is bash — so this
/// parses them instead. A key that validates in a scenario and then dies at
/// `die "onbekende toets"` three minutes into a booted simulator, or comes
/// back as a 400 `unknownKey`, is exactly the failure the validator exists to
/// move forward in time; that only works while all three lists agree.
void main() {
  group('vocabulary stays in sync with the two other copies', () {
    test('scripts/tvos_sim.sh accepts every key remoteKeys advertises', () {
      final script = File('../../scripts/tvos_sim.sh').readAsStringSync();
      final body = _functionBody(script, 'hid_code_for');

      for (final key in remoteKeys) {
        // A case arm may list aliases (`select|enter|return)`), so match the
        // name as one alternative of an arm rather than anywhere in the file.
        expect(
          RegExp('(^|\\||\\s)${RegExp.escape(key)}(\\||\\))').hasMatch(body),
          isTrue,
          reason:
              "scripts/tvos_sim.sh's hid_code_for has no arm for '$key', so a scenario pressing it validates "
              'here and then dies in the simulator',
        );
      }
    });

    test('lib/automation/automation_input.dart accepts every key remoteKeys advertises', () {
      final source = File('../../lib/automation/automation_input.dart').readAsStringSync();
      final map = RegExp(
        r'const Map<String, LogicalKeyboardKey> automationKeyNames = \{(.*?)\};',
        dotAll: true,
      ).firstMatch(source);
      expect(map, isNotNull, reason: 'automationKeyNames not found — did it move or change shape?');

      final appKeys = RegExp("'([a-z_]+)':").allMatches(map!.group(1)!).map((m) => m.group(1)!).toSet();
      expect(
        appKeys,
        equals(remoteKeys),
        reason: 'the app-side /v1/input/key vocabulary and the runner-side one have drifted apart',
      );
    });
  });

  group('parsePressArgs', () {
    test('the scalar form stays the canonical short press', () {
      final press = parsePressArgs('down');
      expect(press.key, 'down');
      expect(press.hold, isNull);
      expect(press.isLongPress, isFalse);
    });

    test('the map form carries a hold', () {
      final press = parsePressArgs({'key': 'select', 'holdMs': 1200});
      expect(press.key, 'select');
      expect(press.hold, const Duration(milliseconds: 1200));
      expect(press.isLongPress, isTrue);
    });

    test('the map form without holdMs is an ordinary press', () {
      expect(parsePressArgs({'key': 'menu'}).isLongPress, isFalse);
    });

    test('an unknown key is rejected, and the message lists what is known', () {
      expect(
        () => parsePressArgs('sideways'),
        throwsA(
          isA<PressArgsException>()
              .having((e) => e.message, 'message', contains("unknown remote key 'sideways'"))
              .having((e) => e.message, 'message', contains('select')),
        ),
      );
    });

    test('an unknown key inside the map form is rejected the same way', () {
      expect(() => parsePressArgs({'key': 'sideways'}), throwsA(isA<PressArgsException>()));
    });

    test('a stray field is rejected rather than silently ignored', () {
      expect(
        () => parsePressArgs({'key': 'select', 'holdMS': 900}),
        throwsA(isA<PressArgsException>().having((e) => e.message, 'message', contains("'holdMS'"))),
      );
    });

    test('a non-positive or non-integer hold is rejected', () {
      for (final bad in [0, -1, '900', 1.5]) {
        expect(
          () => parsePressArgs({'key': 'select', 'holdMs': bad}),
          throwsA(isA<PressArgsException>()),
          reason: 'holdMs: $bad should not be accepted',
        );
      }
    });

    test('a bare list or number is rejected with the accepted shapes in the message', () {
      expect(
        () => parsePressArgs(['down']),
        throwsA(isA<PressArgsException>().having((e) => e.message, 'message', contains('press: {key: select'))),
      );
    });

    test('menu is in the vocabulary — Mijn Pleya cannot be audited without Back', () {
      expect(remoteKeys, contains('menu'));
      expect(parsePressArgs('menu').key, 'menu');
    });
  });
}

/// The body of a bash function, from `name() {` to its matching close brace.
String _functionBody(String script, String name) {
  final start = script.indexOf('$name() {');
  expect(start, isNonNegative, reason: 'bash function $name() not found in scripts/tvos_sim.sh');
  final open = script.indexOf('{', start);
  var depth = 1;
  var i = open + 1;
  while (depth > 0 && i < script.length) {
    if (script[i] == '{') depth++;
    if (script[i] == '}') depth--;
    i++;
  }
  return script.substring(open + 1, i - 1);
}

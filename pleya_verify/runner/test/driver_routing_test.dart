import 'dart:io';

import 'package:test/test.dart';

/// [C2], enforced by source scan rather than trust: a tvOS `press`/
/// `typeText`/`tap` must never route through the automation HTTP transport —
/// idb HID is the only valid input path (see the class doc on
/// `TvosSimulatorDriver`). Mirrors `test/no_bare_text_field_test.dart`'s
/// style: a plain text scan of the method body, not a full Dart parse.
void main() {
  test('TvosSimulatorDriver.press/typeText/tap never reference VerifyClient or http', () {
    final source = File('lib/src/driver/tvos_simulator_driver.dart').readAsStringSync();
    final forbidden = ['VerifyClient', 'http.', 'package:http'];

    for (final methodStart in const [
      'Future<void> press(String key) async {',
      'Future<void> typeText(String text) async {',
      'Future<void> tap(double x, double y) {',
    ]) {
      final startIndex = source.indexOf(methodStart);
      expect(startIndex, isNonNegative, reason: 'method signature not found (did it change?): $methodStart');

      final bodyStart = source.indexOf('{', startIndex) + 1;
      var depth = 1;
      var i = bodyStart;
      while (depth > 0) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') depth--;
        i++;
      }
      final body = source.substring(bodyStart, i - 1);

      for (final token in forbidden) {
        expect(
          body.contains(token),
          isFalse,
          reason:
              '$methodStart contains "$token" — tvOS input must go through tvos_sim.sh (idb HID), never the '
              'transport ([C2]). Body:\n$body',
        );
      }
    }
  });
}

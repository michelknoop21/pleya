import 'dart:io';

import 'package:test/test.dart';

/// Response-path files: everything that shapes a `/pleya/v1/*` body.
/// `fixture_clock.dart` is deliberately excluded — it's the one place a
/// fixed *start* moment lives, and it never calls `DateTime.now()` either
/// (see its own `_normalize`). `http_adapter.dart`'s `Random.secure()` is
/// excluded too: it mints the `/__verify` control token once at process
/// startup, which is security-relevant randomness, not response content —
/// no `/pleya/v1/*` body is built from it.
const _responsePathFiles = ['lib/src/pleya_fake_server.dart', 'lib/src/fixtures/named_fixtures.dart'];

void main() {
  test('no DateTime.now() or Random() in the response-shaping source files', () {
    final offenders = <String>[];
    for (final path in _responsePathFiles) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is expected to exist — update this test if it moved');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('DateTime.now(') || line.contains('Random(')) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Non-deterministic value(s) found in a response-path file — a fixture '
          'server must be deterministic: same requests in, same bytes out. Use '
          'a fixed literal or PleyaFakeServer.clock instead.\n${offenders.join('\n')}',
    );
  });
}

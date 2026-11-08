import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/app_logger.dart';

void main() {
  group('noticeCode', () {
    test('is exactly four uppercase hex characters', () {
      for (var i = 0; i < 50; i++) {
        expect(noticeCode(), matches(RegExp(r'^[0-9A-F]{4}$')));
      }
    });

    test('is not required to be unique across calls — just a correlation hint', () {
      // 65,536 possible values: a collision within a handful of calls is
      // expected and fine, not a bug. This documents that non-requirement
      // rather than asserting uniqueness.
      final codes = List.generate(20, (_) => noticeCode());
      expect(codes, everyElement(matches(RegExp(r'^[0-9A-F]{4}$'))));
    });
  });

  group('logNoticeError', () {
    test('returns the same well-formed code it logs with', () {
      final code = logNoticeError('test-context', Exception('boom'));
      expect(code, matches(RegExp(r'^[0-9A-F]{4}$')));
    });
  });

  group('redaction', () {
    // Through the real logger, as an uploaded log would carry it.
    String redactLogMessageForTest(String message) {
      MemoryLogOutput.clearLogs();
      appLogger.i(message);
      return MemoryLogOutput.getLogs().first.message;
    }

    const userId = '0191e27b-0000-7aaa-bbbb-123456789abc';

    test('the user id of a Pleya Server connection id stays out of a log', () {
      final out = redactLogMessageForTest('Skipping pleyaServer.0191e27a-4f8d-7c62-9b3a-2d5e8f1a6c00.$userId now');
      expect(out, isNot(contains(userId)));
      expect(out, contains('pleyaServer.0191e27a-4f8d-7c62-9b3a-2d5e8f1a6c00.[REDACTED]'));
    });

    test('Pleya Server tokens, tickets and stream_token query values are redacted', () {
      const token = 'ply1.eyJzdWIiOiIwMTkxIn0.c2ln';
      const ticket = 'plc1.eyJzdWIiOiIwMTkxIn0.c2ln';
      final out = redactLogMessageForTest('GET /stream/v?stream_token=$token&x=1 ticket $ticket');
      expect(out, isNot(contains('eyJzdWIiOiIwMTkxIn0')));
      expect(out, contains('stream_token=[REDACTED]&x=1'));
    });

    test('negative control: other text passes untouched', () {
      const plain = 'pleyaServer.srv connected; plex.tv ok';
      expect(redactLogMessageForTest(plain), plain);
    });
  });
}

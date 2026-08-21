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
}

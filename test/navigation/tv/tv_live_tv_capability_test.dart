import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/tv/tv_live_tv_capability.dart';

void main() {
  group('resolveLiveTvCapability', () {
    test('a fresh sighting is visible and gets stored', () {
      final result = resolveLiveTvCapability(remembered: false, available: true, conclusive: true);

      expect(result.visible, isTrue);
      expect(result.store, isTrue);
    });

    test('a sighting that is already remembered is visible and does not trigger a redundant write', () {
      final result = resolveLiveTvCapability(remembered: true, available: true, conclusive: true);

      expect(result.visible, isTrue);
      expect(result.store, isNull);
    });

    test('a conclusive negative retires a remembered capability', () {
      final result = resolveLiveTvCapability(remembered: true, available: false, conclusive: true);

      expect(result.visible, isFalse);
      expect(result.store, isFalse);
    });

    test('a conclusive negative with nothing remembered stays hidden and writes nothing', () {
      final result = resolveLiveTvCapability(remembered: false, available: false, conclusive: true);

      expect(result.visible, isFalse);
      expect(result.store, isNull);
    });

    test('a transient outage does not retire a remembered capability', () {
      final result = resolveLiveTvCapability(remembered: true, available: false, conclusive: false);

      expect(result.visible, isTrue);
      expect(result.store, isNull);
    });

    test('an inconclusive negative with nothing remembered stays hidden and writes nothing', () {
      final result = resolveLiveTvCapability(remembered: false, available: false, conclusive: false);

      expect(result.visible, isFalse);
      expect(result.store, isNull);
    });
  });
}

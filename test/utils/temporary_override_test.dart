import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/temporary_override.dart';

void main() {
  group('TemporaryOverride', () {
    test('re-entrant engage never clobbers the captured prior value', () {
      final override = TemporaryOverride<double>();
      expect(override.engage(1.0), isTrue); // user speed before hold
      expect(override.engage(2.0), isFalse); // second gesture start while boosted
      expect(override.release(), 1.0); // restore the ORIGINAL, not 2.0
      expect(override.isActive, isFalse);
    });

    test('double release is a no-op and re-arms for the next cycle', () {
      final override = TemporaryOverride<bool>();
      override.engage(true);
      expect(override.release(), isTrue);
      expect(override.release(), isNull);
      expect(override.engage(false), isTrue);
      expect(override.release(), isFalse);
    });
  });
}

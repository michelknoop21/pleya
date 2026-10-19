import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/formatters.dart';

void main() {
  const minute = 60 * 1000;

  test('the remaining time spaces the minutes unit off the number', () {
    expect(formatRemainingTime(48 * minute, 30 * minute), contains('18 min'));
    expect(formatRemainingTime(180 * minute, 70 * minute), contains('1h 50 min'));
    expect(formatRemainingTime(100 * minute, 40 * minute), contains('1h'));
  });

  test('nothing to resume gives null', () {
    expect(formatRemainingTime(null, 5 * minute), isNull);
    expect(formatRemainingTime(48 * minute, 0), isNull);
    expect(formatRemainingTime(48 * minute, 48 * minute), isNull);
  });
}

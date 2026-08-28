import 'package:pleya_verify_fixture_server/fixture_clock.dart';
import 'package:test/test.dart';

void main() {
  test('defaults to a fixed moment, not the wall clock', () {
    final a = FixtureClock();
    final b = FixtureClock();
    expect(a.now, b.now, reason: 'two default clocks built moments apart must still agree');
  });

  test('a custom start moment is honored', () {
    final start = DateTime.utc(2020, 3, 4, 5);
    final clock = FixtureClock(start);
    expect(clock.now, start);
  });

  test('advance moves the clock forward by exactly the given duration', () {
    final clock = FixtureClock(DateTime.utc(2026, 1, 1));
    clock.advance(const Duration(hours: 2));
    expect(clock.now, DateTime.utc(2026, 1, 1, 2));
  });

  test('advance rejects a negative duration instead of moving backward', () {
    final clock = FixtureClock();
    expect(() => clock.advance(const Duration(seconds: -1)), throwsArgumentError);
  });

  test('resetToStart restores the moment the clock was constructed with, not the default', () {
    final start = DateTime.utc(2025, 6, 1);
    final clock = FixtureClock(start);
    clock.advance(const Duration(days: 3));
    expect(clock.now, isNot(start));

    clock.resetToStart();

    expect(clock.now, start);
  });
}

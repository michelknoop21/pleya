import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/seerr/seerr_discovery_filters.dart';

void main() {
  test('year is an inclusive backend date window, including leap days', () {
    final window = seerrReleaseWindow(year: 2024, upcoming: false, today: DateTime(2026, 11, 5));
    expect(window.from, '2024-01-01');
    expect(window.through, '2024-12-31');
  });

  test('upcoming excludes today and intersects the selected year', () {
    final window = seerrReleaseWindow(year: 2026, upcoming: true, today: DateTime(2026, 11, 5, 23));
    expect(window.from, '2026-11-06');
    expect(window.through, '2026-12-31');
    final nextYear = seerrReleaseWindow(year: 2027, upcoming: true, today: DateTime(2026, 12, 31));
    expect(nextYear.from, '2027-01-01');
    expect(nextYear.through, '2027-12-31');
  });

  test('unfiltered discovery has no date limits', () {
    final window = seerrReleaseWindow(upcoming: false, today: DateTime(2026, 11, 5));
    expect(window.from, isNull);
    expect(window.through, isNull);
  });
}

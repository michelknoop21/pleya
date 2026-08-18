import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/seerr/seerr_request.dart';

void main() {
  group('seerrSeasonRanges', () {
    test('a single season stays a single number', () {
      expect(seerrSeasonRanges([3]), '3');
    });

    test('a consecutive run collapses to a range', () {
      expect(seerrSeasonRanges([18, 19, 20, 21, 22]), '18-22');
    });

    test('gaps are preserved rather than smoothed over', () {
      expect(seerrSeasonRanges([1, 2, 3, 7]), '1-3, 7');
      expect(seerrSeasonRanges([3, 7]), '3, 7');
    });

    test('unsorted and duplicate input still reads correctly', () {
      expect(seerrSeasonRanges([22, 18, 20, 19, 21, 18]), '18-22');
    });

    test('too many separate runs give up, so the caller can say how many', () {
      expect(seerrSeasonRanges([1, 3, 5, 7]), isNull);
      expect(seerrSeasonRanges([1, 3, 5, 7], maxGroups: 4), '1, 3, 5, 7');
    });

    test('no seasons is not a range', () {
      expect(seerrSeasonRanges([]), isNull);
    });
  });
}

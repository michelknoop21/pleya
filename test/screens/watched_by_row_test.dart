import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/media_detail/watched_by_row.dart';

void main() {
  String others(int n) => '$n others';
  String join(List<String> names) => WatchedByRow.joinNames(names, and: 'and', others: others);

  test('joinNames formats by count', () {
    expect(join([]), '');
    expect(join(['You']), 'You');
    expect(join(['You', 'Bob']), 'You and Bob');
    expect(join(['You', 'Bob', 'Carol']), 'You, Bob and Carol');
    expect(join(['You', 'Bob', 'Carol', 'Dan']), 'You, Bob and 2 others');
    expect(join(['You', 'Bob', 'Carol', 'Dan', 'Eve']), 'You, Bob and 3 others');
  });
}

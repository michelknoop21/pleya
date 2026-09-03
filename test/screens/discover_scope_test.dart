import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/discover_scope.dart';

void main() {
  test('the default scope is unfiltered, so Home is unchanged', () {
    expect(DiscoverScope.all.isFiltered, isFalse);
    for (final kind in MediaKind.values) {
      expect(DiscoverScope.all.admitsKind(kind), isTrue, reason: '$kind');
    }
  });

  test('Series admits shows, seasons and episodes', () {
    // Episodes matter: Verder kijken is a mixed row, and a half-watched episode
    // belongs on the Series landing while the film next to it does not.
    for (final kind in [MediaKind.show, MediaKind.season, MediaKind.episode]) {
      expect(DiscoverScope.series.admitsKind(kind), isTrue, reason: '$kind');
    }
    expect(DiscoverScope.series.admitsKind(MediaKind.movie), isFalse);
  });

  test('Films admits films and nothing else', () {
    expect(DiscoverScope.movies.admitsKind(MediaKind.movie), isTrue);
    for (final kind in [MediaKind.show, MediaKind.season, MediaKind.episode, MediaKind.clip]) {
      expect(DiscoverScope.movies.admitsKind(kind), isFalse, reason: '$kind');
    }
  });

  test('Series and Films never claim the same item', () {
    for (final kind in MediaKind.values) {
      expect(
        DiscoverScope.series.admitsKind(kind) && DiscoverScope.movies.admitsKind(kind),
        isFalse,
        reason: '$kind lands on both landings',
      );
    }
  });
}

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/item_watcher.dart';
import 'package:pleya/screens/media_detail/watched_by_row.dart';
import 'package:pleya/services/download_artwork_helpers.dart';

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

  // The invariant DEC-020 asks for and that this row was missing: an avatar URL
  // may carry a rotating token, and hashing the raw URL into a persistent disk
  // cache key would both leak it and invalidate the cache on every re-auth.
  // ProfileAvatar already did this; the watched-by cluster did not.
  group('avatar cache key', () {
    testWidgets('is derived from the token-free URL', (tester) async {
      const withToken = 'https://plex.tv/users/abc/avatar?c=1&X-Plex-Token=SECRET';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WatchedByRow(
              watchers: [ItemWatcher(id: '1', displayName: 'Bob', thumbUrl: withToken)],
            ),
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, isNotNull);
      expect(image.cacheKey, artworkStorageKey(withToken));
      expect(image.cacheKey, isNot(contains('SECRET')));
    });
  });

  group('rendering', () {
    testWidgets('nothing is drawn without watchers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WatchedByRow(watchers: [])),
        ),
      );
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('a watcher without an avatar falls back to initials', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WatchedByRow(
              watchers: [ItemWatcher(id: '1', displayName: 'Bob')],
            ),
          ),
        ),
      );
      // No network image at all, so no layout shift when a load would fail.
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('B'), findsOneWidget);
    });
  });
}

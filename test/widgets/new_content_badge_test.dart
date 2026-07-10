import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/widgets/new_content_badge.dart';

void main() {
  const nowMs = 1_700_000_000_000; // fixed "now" for determinism
  const nowSec = nowMs ~/ 1000;
  const twoDaysSec = 2 * 24 * 3600;
  const twentyDaysSec = 20 * 24 * 3600;

  group('newBadgeLabel', () {
    test('recently-added unwatched movie -> NEW', () {
      final item = MediaItem.plex(id: 'm1', kind: MediaKind.movie, addedAt: nowSec - twoDaysSec, viewCount: 0);
      expect(newBadgeLabel(item, nowMs: nowMs), 'NEW');
    });

    test('recently-added but already watched movie -> null', () {
      final item = MediaItem.plex(id: 'm2', kind: MediaKind.movie, addedAt: nowSec - twoDaysSec, viewCount: 1);
      expect(newBadgeLabel(item, nowMs: nowMs), isNull);
    });

    test('old movie -> null even if unwatched', () {
      final item = MediaItem.plex(id: 'm3', kind: MediaKind.movie, addedAt: nowSec - twentyDaysSec, viewCount: 0);
      expect(newBadgeLabel(item, nowMs: nowMs), isNull);
    });

    test('show with new unwatched episodes -> NEW EPISODE', () {
      final item = MediaItem.plex(
        id: 's1',
        kind: MediaKind.show,
        addedAt: nowSec - twoDaysSec,
        leafCount: 10,
        viewedLeafCount: 4,
      );
      expect(newBadgeLabel(item, nowMs: nowMs), 'NEW EPISODE');
    });

    test('fully-watched recent show -> null', () {
      final item = MediaItem.plex(
        id: 's2',
        kind: MediaKind.show,
        addedAt: nowSec - twoDaysSec,
        leafCount: 10,
        viewedLeafCount: 10,
      );
      expect(newBadgeLabel(item, nowMs: nowMs), isNull);
    });

    test('missing addedAt -> null', () {
      const item = MediaItem.plex(id: 'm4', kind: MediaKind.movie, viewCount: 0);
      expect(newBadgeLabel(item, nowMs: nowMs), isNull);
    });

    test('future addedAt (clock skew) -> null', () {
      final item = MediaItem.plex(id: 'm5', kind: MediaKind.movie, addedAt: nowSec + twoDaysSec, viewCount: 0);
      expect(newBadgeLabel(item, nowMs: nowMs), isNull);
    });

    test('addedAt already in milliseconds is handled', () {
      final item = MediaItem.plex(id: 'm6', kind: MediaKind.movie, addedAt: nowMs - twoDaysSec * 1000, viewCount: 0);
      expect(newBadgeLabel(item, nowMs: nowMs), 'NEW');
    });
  });
}

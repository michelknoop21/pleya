import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/local_server_match_service.dart';

void main() {
  MediaItem movie(String title, {int? year, MediaBackend backend = MediaBackend.plex, String id = 'x'}) =>
      MediaItem(id: id, backend: backend, kind: MediaKind.movie, title: title, year: year);

  MediaItem episode(String show, int season, int ep, {MediaBackend backend = MediaBackend.plex, String id = 'x'}) =>
      MediaItem(
        id: id,
        backend: backend,
        kind: MediaKind.episode,
        title: '$show s$season e$ep',
        grandparentTitle: show,
        parentIndex: season,
        index: ep,
      );

  group('normalizeTitle', () {
    test('drops year, case, and punctuation', () {
      expect(LocalServerSyncBridge.normalizeTitle('The Miniature Wife (2024)'), 'theminiaturewife');
      expect(LocalServerSyncBridge.normalizeTitle('the.miniature-wife'), 'theminiaturewife');
    });
  });

  group('pickConfidentMatch — movies', () {
    test('single title+year match wins', () {
      final local = movie('The Film', year: 2024);
      final match = LocalServerSyncBridge.pickConfidentMatch(local, [
        movie('The Film', year: 2024, id: 'srv-1'),
        movie('Other', year: 2024, id: 'srv-2'),
      ]);
      expect(match?.id, 'srv-1');
    });

    test('year mismatch rejects', () {
      final local = movie('The Film', year: 2024);
      expect(LocalServerSyncBridge.pickConfidentMatch(local, [movie('The Film', year: 1999, id: 's')]), isNull);
    });

    test('two title matches are ambiguous → no match', () {
      final local = movie('The Film');
      final match = LocalServerSyncBridge.pickConfidentMatch(local, [
        movie('The Film', id: 'a'),
        movie('the film', id: 'b'),
      ]);
      expect(match, isNull);
    });

    test('missing year on one side is tolerated', () {
      final local = movie('The Film');
      expect(LocalServerSyncBridge.pickConfidentMatch(local, [movie('The Film', year: 2024, id: 's')])?.id, 's');
    });
  });

  group('pickConfidentMatch — episodes', () {
    test('matches on show + season + episode', () {
      final local = episode('The Miniature Wife', 1, 5);
      final match = LocalServerSyncBridge.pickConfidentMatch(local, [
        episode('The Miniature Wife', 1, 4, id: 'wrong'),
        episode('The Miniature Wife', 1, 5, id: 'right'),
      ]);
      expect(match?.id, 'right');
    });

    test('wrong episode number does not match', () {
      final local = episode('Show', 1, 5);
      expect(LocalServerSyncBridge.pickConfidentMatch(local, [episode('Show', 1, 6, id: 's')]), isNull);
    });

    test('different show title does not match', () {
      final local = episode('Show A', 1, 5);
      expect(LocalServerSyncBridge.pickConfidentMatch(local, [episode('Show B', 1, 5, id: 's')]), isNull);
    });
  });
}

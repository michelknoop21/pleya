import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/system_shelf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShelfDeepLink.fromNative', () {
    test('a bare content id is a legacy link (Android, older tvOS builds)', () {
      final link = ShelfDeepLink.fromNative('pleya_srv_42')!;
      expect(link.contentId, 'pleya_srv_42');
      expect(link.action, ShelfLinkAction.legacy);
    });

    test('a map carries the action', () {
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1', 'action': 'play'})!.action, ShelfLinkAction.play);
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1', 'action': 'open'})!.action, ShelfLinkAction.open);
    });

    test('a map without or with an unknown action stays legacy', () {
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1'})!.action, ShelfLinkAction.legacy);
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1', 'action': 'x'})!.action, ShelfLinkAction.legacy);
    });

    test('rejects missing or empty ids', () {
      expect(ShelfDeepLink.fromNative(null), isNull);
      expect(ShelfDeepLink.fromNative(''), isNull);
      expect(ShelfDeepLink.fromNative({'action': 'play'}), isNull);
      expect(ShelfDeepLink.fromNative({'contentId': ''}), isNull);
    });
  });

  group('ShelfDeepLink.startsPlaybackFor', () {
    test('legacy keeps today\'s behaviour: always the player', () {
      const link = ShelfDeepLink('pleya_srv_1');
      expect(link.startsPlaybackFor(MediaKind.movie), isTrue);
      expect(link.startsPlaybackFor(MediaKind.episode), isTrue);
    });

    test('open always goes to the detail page', () {
      const link = ShelfDeepLink('pleya_srv_1', ShelfLinkAction.open);
      expect(link.startsPlaybackFor(MediaKind.movie), isFalse);
      expect(link.startsPlaybackFor(MediaKind.episode), isFalse);
    });

    test('play resumes playable items and falls back to detail otherwise', () {
      const link = ShelfDeepLink('pleya_srv_1', ShelfLinkAction.play);
      expect(link.startsPlaybackFor(MediaKind.movie), isTrue);
      expect(link.startsPlaybackFor(MediaKind.episode), isTrue);
      expect(link.startsPlaybackFor(MediaKind.clip), isTrue);
      expect(link.startsPlaybackFor(MediaKind.show), isFalse);
      expect(link.startsPlaybackFor(MediaKind.season), isFalse);
    });
  });

  group('warm start', () {
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<void> send(String channel, String method, Object? args) {
      return messenger.handlePlatformMessage(channel, codec.encodeMethodCall(MethodCall(method, args)), (_) {});
    }

    // Native parks each tap as the pending cold-start link and hands it out on
    // the first getInitialDeepLink, like SystemShelfPlugin / WatchNextPlugin.
    late Map<String, Object?> pending;
    late List<String> drained;
    setUp(() {
      pending = {};
      drained = [];
      for (final name in ['com.pleya/system_shelf', 'com.pleya/watch_next']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          if (call.method != 'getInitialDeepLink') return null;
          drained.add(name);
          return pending.remove(name);
        });
      }
    });
    tearDown(() {
      for (final name in ['com.pleya/system_shelf', 'com.pleya/watch_next']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
    });

    test('a native onShelfItemTap reaches onShelfItemTap with its action', () async {
      final service = SystemShelfService();
      final received = <ShelfDeepLink>[];
      service.onShelfItemTap = received.add;
      addTearDown(() => service.onShelfItemTap = null);

      await send('com.pleya/system_shelf', 'onShelfItemTap', {'contentId': 'pleya_srv_7', 'action': 'open'});
      await send('com.pleya/watch_next', 'onWatchNextTap', {'contentId': 'pleya_srv_8'});

      expect(received.map((l) => (l.contentId, l.action)), [
        ('pleya_srv_7', ShelfLinkAction.open),
        ('pleya_srv_8', ShelfLinkAction.legacy),
      ]);
    });

    test('a delivered tap drains the native pending link so a rebuild cannot replay it', () async {
      final service = SystemShelfService();
      final received = <ShelfDeepLink>[];
      service.onShelfItemTap = received.add;
      addTearDown(() => service.onShelfItemTap = null);

      final link = {'contentId': 'pleya_srv_7', 'action': 'play'};
      pending['com.pleya/system_shelf'] = link;
      await send('com.pleya/system_shelf', 'onShelfItemTap', link);

      expect(received, hasLength(1));
      expect(drained, ['com.pleya/system_shelf']);
      expect(pending, isEmpty);
    });

    test('an undelivered tap (no listener yet) stays pending for the cold-start read', () async {
      final service = SystemShelfService()..onShelfItemTap = null;

      pending['com.pleya/system_shelf'] = {'contentId': 'pleya_srv_7'};
      await send('com.pleya/system_shelf', 'onShelfItemTap', {'contentId': 'pleya_srv_7'});

      expect(drained, isEmpty);
      expect(pending, contains('com.pleya/system_shelf'));
      expect(service.onShelfItemTap, isNull);
    });
  });

  group('SystemShelfService.carouselItemsFor', () {
    MediaItem item(
      String id,
      MediaKind kind, {
      String? art,
      String? grandparentArt,
      String? thumb,
      String? grandparentTitle,
      int? parentIndex,
      int? index,
      int? durationMs,
      int? viewOffsetMs,
      int? viewCount,
    }) => MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: kind,
      title: id,
      serverId: 'srv',
      artPath: art,
      grandparentArtPath: grandparentArt,
      thumbPath: thumb,
      grandparentTitle: grandparentTitle,
      parentIndex: parentIndex,
      index: index,
      durationMs: durationMs,
      viewOffsetMs: viewOffsetMs,
      viewCount: viewCount,
      summary: 'summary $id',
      genres: const ['Drama', 'Thriller'],
      year: 2024,
      originallyAvailableAt: '2024-03-15',
    );

    List<Map<String, dynamic>> build(List<MediaItem> hero, List<MediaItem> cw, {bool hideSpoilers = false}) =>
        SystemShelfService.carouselItemsFor(hero, cw, (_) => _ImageClient(), hideSpoilers: hideSpoilers);

    test('hero first, then Continue Watching; a film in both keeps only its CW entry', () {
      final result = build(
        [item('h1', MediaKind.movie, art: '/a/h1'), item('both', MediaKind.movie, art: '/a/both')],
        [item('both', MediaKind.movie, art: '/a/both'), item('c1', MediaKind.movie, art: '/a/c1')],
      );
      expect(result.map((i) => i['contentId']), ['pleya_srv_h1', 'pleya_srv_both', 'pleya_srv_c1']);
      expect(result[0]['contextTitle'], t.discover.recentlyReleased);
      expect(result[1]['contextTitle'], startsWith(t.discover.continueWatching));
    });

    test('maps the carousel fields and asks for a 1920x1080 backdrop', () {
      final film = build([item('h1', MediaKind.movie, art: '/a/h1', durationMs: 5400000)], const []).single;
      expect(film['title'], 'h1');
      expect(film['summary'], 'summary h1');
      expect(film['genre'], 'Drama');
      expect(film['releaseDate'], '2024-03-15');
      expect(film['duration'], 5400000);
      expect(film['imageUri'], 'img:/a/h1@1920x1080');
    });

    test('an episode shows its series title, the show backdrop and a progress context line', () {
      final ep = build(const [], [
        item(
          'e1',
          MediaKind.episode,
          art: '/a/e1',
          grandparentArt: '/a/show',
          thumb: '/t/e1',
          grandparentTitle: 'Show',
          parentIndex: 2,
          index: 5,
          durationMs: 3000000,
          viewOffsetMs: 480000,
        ),
      ]).single;
      expect(ep['title'], 'Show');
      expect(ep['imageUri'], 'img:/a/show@1920x1080');
      expect(
        ep['contextTitle'],
        '${t.discover.continueWatching} · ${t.discover.playEpisode(season: 2, episode: 5)} · '
        '${t.discover.minutesLeft(minutes: 42)}',
      );
    });

    test('without a backdrop an episode falls back to its still; a film without one is dropped', () {
      final result = build(
        [item('poster-only', MediaKind.movie, thumb: '/t/poster')],
        [item('e1', MediaKind.episode, thumb: '/t/e1', grandparentTitle: 'Show', viewCount: 1)],
      );
      expect(result.map((i) => i['imageUri']), ['img:/t/e1@1920x1080']);
    });

    test('hidden spoilers: no still and no summary for an unwatched episode', () {
      final stillOnly = item('e1', MediaKind.episode, thumb: '/t/e1', grandparentTitle: 'Show');
      expect(build(const [], [stillOnly], hideSpoilers: true), isEmpty);

      final withBackdrop = item('e2', MediaKind.episode, grandparentArt: '/a/show', grandparentTitle: 'Show');
      final entry = build(const [], [withBackdrop], hideSpoilers: true).single;
      expect(entry['imageUri'], 'img:/a/show@1920x1080');
      expect(entry['summary'], isNull);
    });

    test('nothing with an image yields an empty carousel (the sectioned row stays)', () {
      expect(build([item('h1', MediaKind.movie)], [item('c1', MediaKind.movie)]), isEmpty);
    });

    test('release date falls back to January 1 of the year', () {
      final noDate = MediaItem(
        id: 'm',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'm',
        serverId: 'srv',
        artPath: '/a/m',
        year: 1999,
      );
      expect(build([noDate], const []).single['releaseDate'], '1999-01-01');
    });
  });
}

class _ImageClient implements MediaServerClient {
  @override
  String thumbnailUrl(String? path, {int? width, int? height}) => 'img:$path@${width}x$height';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

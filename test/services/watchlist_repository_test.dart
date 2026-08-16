import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/utils/external_ids.dart';

WatchlistScopeId scopeFor(MediaBackend backend, {String account = 'a', String user = 'u'}) =>
    WatchlistScopeId(profileId: 'profile-1', backend: backend, accountId: account, userId: user);

final plexScope = scopeFor(MediaBackend.plex);
final jellyfinScope = scopeFor(MediaBackend.jellyfin, account: 'jf-1', user: 'jf-u');
final otherJellyfinScope = scopeFor(MediaBackend.jellyfin, account: 'jf-2', user: 'jf-u');

WatchlistEntry entry({
  required String key,
  required WatchlistScopeId scope,
  String remoteKey = 'r',
  String? guid,
  ExternalIds externalIds = const ExternalIds(),
  String title = 'Title',
  int? addedAt,
}) {
  return WatchlistEntry(
    key: key,
    kind: MediaKind.movie,
    item: MediaItem(id: remoteKey, backend: MediaBackend.plex, kind: MediaKind.movie, title: title),
    guid: guid,
    externalIds: externalIds,
    memberships: [WatchlistMembership(scope: scope, remoteKey: remoteKey, addedAt: addedAt)],
  );
}

class _FakeSource implements WatchlistSource {
  _FakeSource({required this.scope, this.entries = const [], this.fails = false, this.acceptsItem = false});

  @override
  final WatchlistScopeId scope;
  final List<WatchlistEntry> entries;
  final bool fails;
  final bool acceptsItem;

  int fetches = 0;

  @override
  bool accepts(MediaItem item) => acceptsItem;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    fetches++;
    if (fails) throw const WatchlistScopeUnavailable('nope');
    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: item.id);

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

void main() {
  group('merge tiers', () {
    test('the same canonical key becomes one entry with two memberships', () {
      final merged = WatchlistRepository.mergeEntries([
        entry(key: 'plex:abc', scope: plexScope, remoteKey: 'abc'),
        entry(key: 'plex:abc', scope: jellyfinScope, remoteKey: 'jf-1'),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.memberships, hasLength(2));
    });

    test('a shared guid joins two entries whose keys differ', () {
      final merged = WatchlistRepository.mergeEntries([
        entry(key: 'plex:abc', scope: plexScope, guid: 'plex://movie/abc'),
        entry(key: 'imdb:tt1', scope: jellyfinScope, guid: 'plex://movie/abc'),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.key, 'plex:abc', reason: 'the first source decides identity');
      expect(merged.single.memberships.map((m) => m.scope), containsAll([plexScope, jellyfinScope]));
    });

    test('a shared external id joins them when neither key nor guid matches', () {
      final merged = WatchlistRepository.mergeEntries([
        entry(
          key: 'plex:abc',
          scope: plexScope,
          externalIds: const ExternalIds(imdb: 'tt0111161'),
        ),
        entry(
          key: 'imdb:tt0111161',
          scope: jellyfinScope,
          externalIds: const ExternalIds(imdb: 'tt0111161'),
        ),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.memberships, hasLength(2));
    });

    test('a third source matching on yet another tier still lands on the same title', () {
      final merged = WatchlistRepository.mergeEntries([
        entry(key: 'plex:abc', scope: plexScope, guid: 'plex://movie/abc'),
        entry(
          key: 'imdb:tt1',
          scope: jellyfinScope,
          guid: 'plex://movie/abc',
          externalIds: const ExternalIds(imdb: 'tt1'),
        ),
        entry(
          key: 'tmdb:9',
          scope: otherJellyfinScope,
          externalIds: const ExternalIds(imdb: 'tt1'),
        ),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.memberships, hasLength(3));
    });

    test('different titles stay apart even with lookalike ids', () {
      final merged = WatchlistRepository.mergeEntries([
        entry(key: 'tmdb:278', scope: plexScope, externalIds: const ExternalIds(tmdb: 278)),
        entry(key: 'tvdb:278', scope: jellyfinScope, externalIds: const ExternalIds(tvdb: 278)),
      ]);

      expect(merged, hasLength(2));
    });

    test('two Jellyfin servers holding the same favorite give two memberships, not one', () {
      final merged = WatchlistRepository.mergeEntries([
        entry(
          key: 'imdb:tt1',
          scope: jellyfinScope,
          remoteKey: 'a',
          externalIds: const ExternalIds(imdb: 'tt1'),
        ),
        entry(
          key: 'imdb:tt1',
          scope: otherJellyfinScope,
          remoteKey: 'b',
          externalIds: const ExternalIds(imdb: 'tt1'),
        ),
      ]);

      expect(merged.single.memberships.map((m) => m.remoteKey), ['a', 'b']);
    });

    test('preserves first-seen order, which is the source order', () {
      final merged = WatchlistRepository.mergeEntries([
        entry(key: 'a', scope: plexScope, title: 'First'),
        entry(key: 'b', scope: plexScope, title: 'Second'),
        entry(key: 'a', scope: jellyfinScope, title: 'First again'),
        entry(key: 'c', scope: plexScope, title: 'Third'),
      ]);

      expect(merged.map((e) => e.key), ['a', 'b', 'c']);
    });
  });

  group('fetch', () {
    test('asks every source and merges the answers', () async {
      final plex = _FakeSource(
        scope: plexScope,
        entries: [entry(key: 'plex:abc', scope: plexScope)],
      );
      final jellyfin = _FakeSource(
        scope: jellyfinScope,
        entries: [entry(key: 'imdb:tt1', scope: jellyfinScope)],
      );
      final repository = WatchlistRepository(sources: [plex, jellyfin]);

      final result = await repository.fetch();

      expect(result.entries, hasLength(2));
      expect(result.complete, isTrue);
      expect(result.failed, isEmpty);
      expect([plex.fetches, jellyfin.fetches], [1, 1]);
    });

    test('one failing source does not sink the others, and says so', () async {
      final plex = _FakeSource(scope: plexScope, fails: true);
      final jellyfin = _FakeSource(
        scope: jellyfinScope,
        entries: [entry(key: 'imdb:tt1', scope: jellyfinScope)],
      );

      final result = await WatchlistRepository(sources: [plex, jellyfin]).fetch();

      expect(result.entries, hasLength(1));
      expect(result.complete, isFalse);
      expect(result.failed.single.scope, plexScope);
    });

    test('the Plex source keeps its position, so its newest-first order survives', () async {
      final plex = _FakeSource(
        scope: plexScope,
        entries: [
          entry(key: 'p1', scope: plexScope),
          entry(key: 'p2', scope: plexScope),
        ],
      );
      final jellyfin = _FakeSource(
        scope: jellyfinScope,
        entries: [entry(key: 'j1', scope: jellyfinScope)],
      );

      final result = await WatchlistRepository(sources: [plex, jellyfin]).fetch();

      expect(result.entries.map((e) => e.key), ['p1', 'p2', 'j1']);
    });

    test('no sources at all is an empty but complete answer', () async {
      final result = await WatchlistRepository(sources: const []).fetch();

      expect(result.entries, isEmpty);
      expect(result.complete, isTrue);
    });
  });

  group('targetFor', () {
    final item = MediaItem(id: 'x', backend: MediaBackend.plex, kind: MediaKind.movie);

    test('picks the first source that accepts the item', () {
      final refuses = _FakeSource(scope: plexScope);
      final accepts = _FakeSource(scope: jellyfinScope, acceptsItem: true);

      expect(WatchlistRepository(sources: [refuses, accepts]).targetFor(item)?.scope, jellyfinScope);
    });

    test('answers null when nothing will take it', () {
      final repository = WatchlistRepository(sources: [_FakeSource(scope: plexScope)]);

      expect(repository.targetFor(item), isNull);
    });
  });
}

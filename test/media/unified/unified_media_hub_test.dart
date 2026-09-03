/// Covers [UnifiedMediaHub]'s own contract: hoofdstuk 17.2's merge key, the
/// stable-id rule of hoofdstuk 17.5/11.9, and the value-type guarantees the
/// projection layer above it relies on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';

MediaHub _hub({
  required String id,
  String? identifier,
  String title = 'Continue Watching',
  String type = 'mixed',
  String? libraryId,
  String? serverId = 'server-a',
  String? serverName = 'Plex Familie',
  List<MediaItem> items = const [],
}) => MediaHub(
  id: id,
  identifier: identifier,
  title: title,
  type: type,
  items: items,
  libraryId: libraryId,
  serverId: serverId,
  serverName: serverName,
);

UnifiedMediaGroup _group(String id, {String serverId = 'server-a'}) {
  final item = MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Dune',
    year: 2021,
    serverId: serverId,
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'group:$id',
    identity: canonicalIdentityOf(item)!,
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: selectRepresentativeWatchState({source.sourceKey: item}),
  );
}

void main() {
  group('UnifiedHubKind', () {
    test('reads the backend type tokens both backends actually emit', () {
      expect(UnifiedHubKind.fromHubType('movie'), UnifiedHubKind.movie);
      expect(UnifiedHubKind.fromHubType('Show'), UnifiedHubKind.show);
      expect(UnifiedHubKind.fromHubType('series'), UnifiedHubKind.show);
      expect(UnifiedHubKind.fromHubType('episode'), UnifiedHubKind.episode);
      expect(UnifiedHubKind.fromHubType('mixed'), UnifiedHubKind.mixed);
      expect(UnifiedHubKind.fromHubType('artist'), UnifiedHubKind.other);
      expect(UnifiedHubKind.fromHubType(null), UnifiedHubKind.other);
    });

    test('merging identical kinds keeps the kind, disagreement is mixed', () {
      expect(UnifiedHubKind.merged([UnifiedHubKind.movie, UnifiedHubKind.movie]), UnifiedHubKind.movie);
      expect(UnifiedHubKind.merged([UnifiedHubKind.movie, UnifiedHubKind.show]), UnifiedHubKind.mixed);
      expect(UnifiedHubKind.merged(const []), UnifiedHubKind.other);
    });
  });

  group('UnifiedHubKey', () {
    test('a hub with a backend identifier is not server-scoped, so it can merge', () {
      final key = UnifiedHubKey.forHub(_hub(id: '/hubs/home/continue', identifier: 'home.continue'));

      expect(key.backendIdentifier, 'home.continue');
      expect(key.serverScope, isNull);
      expect(key.libraryScope, isNull);
    });

    test('two servers reporting the same identifier produce the same key', () {
      final a = UnifiedHubKey.forHub(
        _hub(id: '/hubs/home/continue?a=1', identifier: 'home.continue', serverId: 'server-a'),
      );
      final b = UnifiedHubKey.forHub(
        _hub(id: 'home.continue', identifier: 'home.continue', serverId: 'server-b', serverName: 'Jellyfin'),
      );

      expect(a, b);
      expect(a.value, b.value);
      expect(a.hubId, b.hubId);
    });

    test('a hub without an identifier stays server-scoped: an opaque key proves nothing', () {
      final a = UnifiedHubKey.forHub(_hub(id: '/hubs/sections/3/recent', serverId: 'server-a'));
      final b = UnifiedHubKey.forHub(_hub(id: '/hubs/sections/3/recent', serverId: 'server-b'));

      expect(a.serverScope, 'server-a');
      expect(a, isNot(b));
    });

    test('a library-scoped hub stays server-scoped: a library id is server-local', () {
      final a = UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'tv.recentlyadded', libraryId: '3', serverId: 'a'));
      final b = UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'tv.recentlyadded', libraryId: '3', serverId: 'b'));

      expect(a.libraryScope, 'a/3');
      expect(a.serverScope, 'a');
      expect(a, isNot(b));
    });

    test('the identifier is case-sensitive, because it can embed a library id', () {
      final a = UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'library.AbC.recent'));
      final b = UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'library.abc.recent'));

      expect(a, isNot(b));
    });

    test('titles never enter the key, in either direction', () {
      final dutch = UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'home.recent', title: 'Onlangs toegevoegd'));
      final english = UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'home.recent', title: 'Recently Added'));
      final lookalike = UnifiedHubKey.forHub(
        _hub(id: 'y', identifier: 'movie.recentlyreleased', title: 'Recently Added'),
      );

      expect(dutch, english, reason: 'a translated title must not split one row in two');
      expect(english, isNot(lookalike), reason: 'two rows that read alike are still two rows');
    });

    test('narrowing pins the key to one server and one backend row', () {
      final key = UnifiedHubKey.forHub(_hub(id: '/hubs/byw/1', identifier: 'home.becausewatched'));
      final narrowed = key.narrowedTo(serverId: 'server-a', backendRowKey: '/hubs/byw/1');
      final sibling = key.narrowedTo(serverId: 'server-a', backendRowKey: '/hubs/byw/2');

      expect(narrowed.serverScope, 'server-a');
      expect(narrowed.recommendationReason, '/hubs/byw/1');
      expect(narrowed, isNot(sibling));
      expect(narrowed, isNot(key));
    });
  });

  group('UnifiedMediaHub', () {
    test('hub id is derived from the key and repeats byte-identically', () {
      final key = UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'home.continue'));

      final first = UnifiedMediaHub.fromKey(
        key: key,
        title: 'Continue Watching',
        kind: UnifiedHubKind.mixed,
        groups: [_group('1')],
      );
      final second = UnifiedMediaHub.fromKey(
        key: UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'home.continue')),
        title: 'Verder kijken',
        kind: UnifiedHubKind.mixed,
        groups: [_group('2')],
      );

      expect(first.hubId, second.hubId);
      expect(first.hubId, key.hubId);
    });

    test('a synthesized row keys on its slug, not on its translated label', () {
      final english = UnifiedMediaHub.synthesized(
        slug: 'continueWatching',
        title: 'Continue Watching',
        kind: UnifiedHubKind.mixed,
        groups: [_group('1')],
      );
      final dutch = UnifiedMediaHub.synthesized(
        slug: 'continueWatching',
        title: 'Verder kijken',
        kind: UnifiedHubKind.mixed,
        groups: [_group('1')],
      );

      expect(english.hubId, dutch.hubId);
      expect(english.hubId, UnifiedMediaHub.synthesizedHubId('continueWatching'));
      expect(english.serverName, isNull);
      expect(english.isServerSpecific, isFalse);
    });

    test('groups and contributing row ids are unmodifiable', () {
      final hub = UnifiedMediaHub.synthesized(
        slug: 'allMovies',
        title: 'Alle films',
        kind: UnifiedHubKind.movie,
        groups: [_group('1')],
        viewAll: UnifiedHubViewAll.allMovies,
        contributingRowIds: const ['server-a:home.movies'],
      );

      expect(() => hub.groups.add(_group('2')), throwsUnsupportedError);
      expect(() => hub.contributingRowIds.add('x'), throwsUnsupportedError);
      expect(hub.viewAll, UnifiedHubViewAll.allMovies);
    });

    test('a server-specific row carries its server name, a global row does not', () {
      final serverRow = UnifiedMediaHub.fromKey(
        key: UnifiedHubKey.forHub(_hub(id: '/hubs/sections/3/recent', identifier: null)),
        title: 'Recently Added',
        kind: UnifiedHubKind.movie,
        groups: [_group('1')],
        serverName: 'Plex Familie',
      );
      final globalRow = UnifiedMediaHub.fromKey(
        key: UnifiedHubKey.forHub(_hub(id: 'x', identifier: 'home.continue')),
        title: 'Continue Watching',
        kind: UnifiedHubKind.mixed,
        groups: [_group('1')],
      );

      expect(serverRow.isServerSpecific, isTrue);
      expect(serverRow.serverName, 'Plex Familie');
      expect(globalRow.isServerSpecific, isFalse);
    });
  });
}

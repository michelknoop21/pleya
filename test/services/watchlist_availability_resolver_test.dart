import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/watchlist/watchlist_availability_resolver.dart';
import 'package:pleya/utils/external_ids.dart';

import 'fake_favorites_client.dart';

/// A client that only knows how to answer [findByIdentity].
class _MatchingClient extends FakeFavoritesClient {
  _MatchingClient({this.match, this.throws = false}) : super(favorites: const []);

  final MediaItem? match;
  final bool throws;

  int lookups = 0;

  @override
  Future<MediaItem?> findByIdentity(MediaIdentity identity) async {
    lookups++;
    if (throws) throw StateError('server down mid-flight');
    return match;
  }
}

MediaItem serverItem(String serverId, {String id = 'item-1'}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel', serverId: serverId);

WatchlistEntry entry({String key = 'plex:abc', String? guid = 'plex://movie/abc', String title = 'Sintel'}) {
  return WatchlistEntry(
    key: key,
    kind: MediaKind.movie,
    item: MediaItem(id: 'abc', backend: MediaBackend.plex, kind: MediaKind.movie, title: title, year: 2010),
    guid: guid,
    externalIds: const ExternalIds(imdb: 'tt1727587'),
    memberships: [
      WatchlistMembership(
        scope: WatchlistScopeId(profileId: 'profile-1', backend: MediaBackend.plex, accountId: 'a', userId: 'u'),
        remoteKey: 'abc',
      ),
    ],
  );
}

EligibleServer server(
  String id, {
  MediaBackend backend = MediaBackend.plex,
  MediaItem? match,
  bool online = true,
  bool throws = false,
  bool noClient = false,
}) {
  return (
    serverId: ServerId(id),
    backend: backend,
    client: noClient || !online ? null : _MatchingClient(match: match, throws: throws),
    online: online,
  );
}

void main() {
  late AppDatabase db;
  late PlexApiCache cache;
  var clock = DateTime.utc(2026, 8, 16, 12);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    cache = PlexApiCache.instance;
    clock = DateTime.utc(2026, 8, 16, 12);
  });

  tearDown(() async => db.close());

  WatchlistAvailabilityResolver resolverFor(List<EligibleServer> servers) =>
      WatchlistAvailabilityResolver(profileId: 'profile-1', serversFor: () => servers, cache: cache, now: () => clock);

  group('coverage', () {
    test('a match on the only server is complete coverage', () async {
      final match = serverItem('s1');
      final result = await resolverFor([server('s1', match: match)]).resolve(entry());

      expect(result.match?.serverId, 's1');
      expect(result.coverageComplete, isTrue);
    });

    test('nothing found while every server answered is a complete miss', () async {
      final result = await resolverFor([server('s1'), server('s2')]).resolve(entry());

      expect(result.match, isNull);
      expect(result.coverageComplete, isTrue);
    });

    test('an offline server still counts in the denominator', () async {
      final result = await resolverFor([server('s1'), server('s2', online: false)]).resolve(entry());

      expect(result.match, isNull);
      expect(result.coverageComplete, isFalse, reason: 'the offline server may be the one holding it');
    });

    test('a server that errors mid-flight counts as not checked', () async {
      final result = await resolverFor([server('s1', throws: true), server('s2')]).resolve(entry());

      expect(result.coverageComplete, isFalse);
    });

    test('a local folder is not eligible, so it cannot make coverage unreachable', () async {
      final result = await resolverFor([
        server('s1'),
        server('local-1', backend: MediaBackend.local, online: false),
      ]).resolve(entry());

      expect(result.coverageComplete, isTrue);
    });

    test('an identity with nothing to match on costs no request', () async {
      final s1 = server('s1');
      final blank = WatchlistEntry(
        key: 'k',
        kind: MediaKind.movie,
        item: MediaItem(id: 'x', backend: MediaBackend.plex, kind: MediaKind.movie),
        memberships: entry().memberships,
      );

      final result = await resolverFor([s1]).resolve(blank);

      expect(result.match, isNull);
      expect(result.coverageComplete, isTrue);
      expect((s1.client! as _MatchingClient).lookups, 0);
    });
  });

  group('server choice', () {
    test('is deterministic: the first server in order wins', () async {
      final first = server('s1', match: serverItem('s1'));
      final second = server('s2', match: serverItem('s2'));

      final result = await resolverFor([first, second]).resolve(entry());

      expect(result.match?.serverId, 's1');
    });

    test('stops asking once a server answered yes', () async {
      final first = server('s1', match: serverItem('s1'));
      final second = server('s2', match: serverItem('s2'));

      await WatchlistAvailabilityResolver(
        profileId: 'profile-1',
        serversFor: () => [first, second],
        cache: cache,
        maxConcurrent: 1,
        now: () => clock,
      ).resolve(entry());

      expect((second.client! as _MatchingClient).lookups, 0);
    });
  });

  group('cache', () {
    test('a warm hit skips the network', () async {
      final first = server('s1', match: serverItem('s1'));
      await resolverFor([first]).resolve(entry());

      final second = server('s1', match: serverItem('s1'));
      final result = await resolverFor([second]).resolve(entry());

      expect(result.match?.serverId, 's1');
      expect((second.client! as _MatchingClient).lookups, 0);
    });

    test('a hit naming a server that went offline is revalidated, not trusted', () async {
      await resolverFor([server('s1', match: serverItem('s1'))]).resolve(entry());

      final result = await resolverFor([server('s1', online: false)]).resolve(entry());

      expect(result.match, isNull, reason: 'the cached match points at a server that cannot serve it now');
      expect(result.coverageComplete, isFalse);
    });

    test('a hit naming a server that left the profile is re-resolved', () async {
      await resolverFor([server('s1', match: serverItem('s1'))]).resolve(entry());

      final replacement = server('s2', match: serverItem('s2'));
      final result = await resolverFor([replacement]).resolve(entry());

      expect(result.match?.serverId, 's2');
      expect((replacement.client! as _MatchingClient).lookups, 1);
    });

    test('a positive answer expires after a week', () async {
      await resolverFor([server('s1', match: serverItem('s1'))]).resolve(entry());

      clock = clock.add(const Duration(days: 8));
      final again = server('s1', match: serverItem('s1'));
      await resolverFor([again]).resolve(entry());

      expect((again.client! as _MatchingClient).lookups, 1);
    });

    test('a complete miss is cached, and expires after six hours', () async {
      await resolverFor([server('s1')]).resolve(entry());

      final warm = server('s1');
      await resolverFor([warm]).resolve(entry());
      expect((warm.client! as _MatchingClient).lookups, 0);

      clock = clock.add(const Duration(hours: 7));
      final cold = server('s1');
      await resolverFor([cold]).resolve(entry());
      expect((cold.client! as _MatchingClient).lookups, 1);
    });

    test('an incomplete miss is never cached', () async {
      await resolverFor([server('s1'), server('s2', online: false)]).resolve(entry());

      final retry = server('s1');
      await resolverFor([retry, server('s2', online: false)]).resolve(entry());

      expect((retry.client! as _MatchingClient).lookups, 1, reason: 'a temporary outage must not freeze a miss');
    });

    test('answers are keyed per profile', () async {
      await resolverFor([server('s1', match: serverItem('s1'))]).resolve(entry());

      final otherProfile = server('s1', match: serverItem('s1'));
      await WatchlistAvailabilityResolver(
        profileId: 'profile-2',
        serversFor: () => [otherProfile],
        cache: cache,
        now: () => clock,
      ).resolve(entry());

      expect((otherProfile.client! as _MatchingClient).lookups, 1);
    });

    test('invalidate clears the warm answers', () async {
      final resolver = resolverFor([server('s1', match: serverItem('s1'))]);
      await resolver.resolve(entry());
      await resolver.invalidate();

      final again = server('s1', match: serverItem('s1'));
      await resolverFor([again]).resolve(entry());

      expect((again.client! as _MatchingClient).lookups, 1);
    });
  });
}

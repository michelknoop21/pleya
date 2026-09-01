import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/source_resolver.dart';

/// A client whose only implemented member is [findAllByIdentity].
class _MatchingClient implements MediaServerClient {
  _MatchingClient({this.matches = const [], this.throws = false});

  final List<MediaItem> matches;
  final bool throws;
  int lookups = 0;

  /// `eligibleSourceServers` reads this to decide identity eligibility, so it
  /// has to be a real answer rather than a `noSuchMethod` throw.
  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    lookups++;
    if (throws) throw StateError('server down mid-flight');
    return matches;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(String serverId, {String id = 'item-1', String? libraryId}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  year: 2010,
  serverId: serverId,
  libraryId: libraryId,
);

/// The shape Plex's *title-fallback* branch of `findAllByIdentity` produces:
/// a library id, and no server id at all, because `_candidatesWithGuids` maps
/// with `PlexMappers.mediaItemFromJson(raw)` and passes none. Any filter that
/// keys on `item.serverId` fails open on exactly this shape.
MediaItem _unstampedItem({required String libraryId, String id = 'item-1'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  year: 2010,
  libraryId: libraryId,
);

const _identity = MediaIdentity(guid: 'plex://movie/abc', title: 'Sintel', year: 2010, kind: MediaKind.movie);

EligibleSourceServer _server(
  String id, {
  MediaBackend backend = MediaBackend.plex,
  List<MediaItem> matches = const [],
  bool online = true,
  bool hasAuthError = false,
  bool throws = false,
}) {
  return (
    serverId: ServerId(id),
    backend: backend,
    client: online ? _MatchingClient(matches: matches, throws: throws) : null,
    online: online,
    hasAuthError: hasAuthError,
  );
}

void main() {
  late AppDatabase db;
  late PlexApiCache cache;
  var clock = DateTime.utc(2026, 8, 29, 12);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    cache = PlexApiCache.instance;
    clock = DateTime.utc(2026, 8, 29, 12);
  });

  tearDown(() async => db.close());

  SourceAllResolver resolverFor(List<EligibleSourceServer> servers, {Set<String> hidden = const {}}) =>
      SourceAllResolver(
        profileId: 'profile-1',
        serversFor: () => servers,
        hiddenLibraryKeysFor: () => hidden,
        cache: cache,
        now: () => clock,
      );

  group('coverage', () {
    test('the same film on three servers yields three concrete sources', () async {
      final servers = [
        _server('s1', matches: [_item('s1')]),
        _server('s2', matches: [_item('s2')]),
        _server('s3', matches: [_item('s3')]),
      ];

      final result = await resolverFor(servers).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), unorderedEquals(['s1', 's2', 's3']));
      expect(result.coverage.isComplete, isTrue);
      expect(result.coverage.expectedServerIds, {'s1', 's2', 's3'});
      expect(result.coverage.checkedServerIds, {'s1', 's2', 's3'});
    });

    test('an offline expected server makes coverage incomplete', () async {
      final result = await resolverFor([
        _server('s1', matches: [_item('s1')]),
        _server('s2', online: false),
      ]).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), ['s1']);
      expect(result.coverage.isComplete, isFalse);
      expect(result.coverage.uncheckedServerIds, {'s2'});
      expect(result.coverage.uncheckedReasons['s2'], UncheckedSourceReason.offline);
    });

    test('an auth-errored server is distinguished from a plain offline one', () async {
      final result = await resolverFor([
        _server('s1', matches: [_item('s1')]),
        _server('s2', online: false, hasAuthError: true),
      ]).resolveAllSourcesForGroup(_identity);

      expect(result.coverage.uncheckedReasons['s2'], UncheckedSourceReason.authError);
    });

    test('a server that errors mid-flight is unchecked with lookupFailed, not silently dropped', () async {
      final result = await resolverFor([
        _server('s1', matches: [_item('s1')]),
        _server('s2', throws: true),
      ]).resolveAllSourcesForGroup(_identity);

      expect(result.coverage.isComplete, isFalse);
      expect(result.coverage.uncheckedReasons['s2'], UncheckedSourceReason.lookupFailed);
    });

    test('a backend without catalogue identity is never expected, so it cannot block coverage', () async {
      final result = await resolverFor([
        _server('s1', matches: [_item('s1')]),
        _server('local-1', backend: MediaBackend.local, online: false),
      ]).resolveAllSourcesForGroup(_identity);

      expect(result.coverage.isComplete, isTrue);
      expect(result.coverage.expectedServerIds, {'s1'});
    });

    test(
      'a server absent from serversFor() (hidden/profile-inaccessible) contributes nothing and is never asked',
      () async {
        // Only s1 is visible to this profile — a hidden server never even
        // reaches the resolver, matching hoofdstuk 1.1 point 2: visibility
        // closes before the fan-out, not inside it.
        final result = await resolverFor([
          _server('s1', matches: [_item('s1')]),
        ]).resolveAllSourcesForGroup(_identity);

        expect(result.items.map((i) => i.serverId), ['s1']);
        expect(result.coverage.expectedServerIds, {'s1'});
      },
    );

    test('an identity with nothing to match on costs no request and is vacuously complete', () async {
      final s1 = _server('s1', matches: [_item('s1')]);
      const blank = MediaIdentity();

      final result = await resolverFor([s1]).resolveAllSourcesForGroup(blank);

      expect(result.items, isEmpty);
      expect(result.coverage.isComplete, isTrue);
      expect((s1.client! as _MatchingClient).lookups, 0);
    });
  });

  group('cache', () {
    test('a warm hit skips the network', () async {
      final first = _server('s1', matches: [_item('s1')]);
      await resolverFor([first]).resolveAllSourcesForGroup(_identity);

      final second = _server('s1', matches: [_item('s1')]);
      final result = await resolverFor([second]).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), ['s1']);
      expect((second.client! as _MatchingClient).lookups, 0);
    });

    test('an incomplete negative is never cached', () async {
      await resolverFor([_server('s1'), _server('s2', online: false)]).resolveAllSourcesForGroup(_identity);

      final retry = _server('s1');
      await resolverFor([retry, _server('s2', online: false)]).resolveAllSourcesForGroup(_identity);

      expect((retry.client! as _MatchingClient).lookups, 1, reason: 'a temporary outage must not freeze a miss');
    });

    test('a complete miss is cached, and expires after six hours', () async {
      await resolverFor([_server('s1')]).resolveAllSourcesForGroup(_identity);

      final warm = _server('s1');
      await resolverFor([warm]).resolveAllSourcesForGroup(_identity);
      expect((warm.client! as _MatchingClient).lookups, 0);

      clock = clock.add(const Duration(hours: 7));
      final cold = _server('s1');
      await resolverFor([cold]).resolveAllSourcesForGroup(_identity);
      expect((cold.client! as _MatchingClient).lookups, 1);
    });

    test('a positive answer expires after a week', () async {
      await resolverFor([
        _server('s1', matches: [_item('s1')]),
      ]).resolveAllSourcesForGroup(_identity);

      clock = clock.add(const Duration(days: 8));
      final again = _server('s1', matches: [_item('s1')]);
      await resolverFor([again]).resolveAllSourcesForGroup(_identity);

      expect((again.client! as _MatchingClient).lookups, 1);
    });

    test('a hit naming a server that went offline is revalidated, not trusted', () async {
      await resolverFor([
        _server('s1', matches: [_item('s1')]),
      ]).resolveAllSourcesForGroup(_identity);

      final result = await resolverFor([_server('s1', online: false)]).resolveAllSourcesForGroup(_identity);

      expect(result.items, isEmpty, reason: 'the cached source points at a server that cannot serve it now');
    });

    test('invalidate clears the warm answers', () async {
      final resolver = resolverFor([
        _server('s1', matches: [_item('s1')]),
      ]);
      await resolver.resolveAllSourcesForGroup(_identity);
      await resolver.invalidate();

      final again = _server('s1', matches: [_item('s1')]);
      await resolverFor([again]).resolveAllSourcesForGroup(_identity);

      expect((again.client! as _MatchingClient).lookups, 1);
    });

    test('answers are keyed per profile', () async {
      await resolverFor([
        _server('s1', matches: [_item('s1')]),
      ]).resolveAllSourcesForGroup(_identity);

      final otherProfile = _server('s1', matches: [_item('s1')]);
      await SourceAllResolver(
        profileId: 'profile-2',
        serversFor: () => [otherProfile],
        cache: cache,
        now: () => clock,
      ).resolveAllSourcesForGroup(_identity);

      expect((otherProfile.client! as _MatchingClient).lookups, 1);
    });
  });

  /// B8's resolverhelft. The card can say "1 bron" honestly and the resolver
  /// then add a hidden library as a second picker row — the search half of the
  /// same row is closed in `DataAggregationService`, this is the other side.
  ///
  /// Every case here filters *before* the answer is kept, so the seven-day
  /// positive cache can never serve a hidden source back.
  group('hidden libraries', () {
    test('A: a hidden second copy drops out, the visible one stays', () async {
      final result = await resolverFor(
        [
          _server('s1', matches: [_item('s1', libraryId: 'lib-visible')]),
          _server('s2', matches: [_item('s2', libraryId: 'lib-hidden')]),
        ],
        hidden: {'s2:lib-hidden'},
      ).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), ['s1']);
      expect(
        result.coverage.isComplete,
        isTrue,
        reason: 's2 was asked and answered; its answer was filtered, which is not a coverage gap',
      );
    });

    test('B: a title only a hidden library holds resolves to no source at all', () async {
      final result = await resolverFor(
        [
          _server('s1', matches: [_item('s1', libraryId: 'lib-hidden')]),
        ],
        hidden: {'s1:lib-hidden'},
      ).resolveAllSourcesForGroup(_identity);

      expect(result.items, isEmpty);
    });

    test('B: two hidden libraries on one server both drop, a third visible one survives', () async {
      final result = await resolverFor(
        [
          _server(
            's1',
            matches: [
              _item('s1', id: 'a', libraryId: 'lib-a'),
              _item('s1', id: 'b', libraryId: 'lib-b'),
              _item('s1', id: 'c', libraryId: 'lib-c'),
            ],
          ),
        ],
        hidden: {'s1:lib-a', 's1:lib-c'},
      ).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.id), ['b']);
    });

    test('a hidden key only bites on its own server', () async {
      final result = await resolverFor(
        [
          _server('s1', matches: [_item('s1', libraryId: 'lib-1')]),
          _server('s2', matches: [_item('s2', libraryId: 'lib-1')]),
        ],
        hidden: {'s2:lib-1'},
      ).resolveAllSourcesForGroup(_identity);

      expect(
        result.items.map((i) => i.serverId),
        ['s1'],
        reason: 'two servers can both call a library "lib-1"; the key names one of them',
      );
    });

    test('an item with a library id but no server id is still filtered', () async {
      final result = await resolverFor(
        [
          _server('s1', matches: [_unstampedItem(libraryId: 'lib-hidden')]),
        ],
        hidden: {'s1:lib-hidden'},
      ).resolveAllSourcesForGroup(_identity);

      expect(
        result.items,
        isEmpty,
        reason:
            "Plex's title-fallback branch stamps no server id, so the answering "
            'server must supply it — filtering on item.serverId would fail open here',
      );
    });

    test('G: an item in no library at all is kept, whatever is hidden', () async {
      final result = await resolverFor(
        [
          _server('s1', matches: [_item('s1')]),
        ],
        hidden: {'s1:lib-hidden', 's1:lib-other'},
      ).resolveAllSourcesForGroup(_identity);

      expect(
        result.items.map((i) => i.serverId),
        ['s1'],
        reason: 'a Plex Discover hit belongs to no library, so no hidden key can name it',
      );
    });

    test('H: with nothing hidden the answer is exactly what it was', () async {
      final result = await resolverFor([
        _server('s1', matches: [_item('s1', libraryId: 'lib-1')]),
        _server('s2', matches: [_item('s2', libraryId: 'lib-2')]),
      ]).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), unorderedEquals(['s1', 's2']));
      expect(result.coverage.isComplete, isTrue);
    });

    test('D: hiding a library after a warm positive does not serve the cached source', () async {
      await resolverFor([
        _server('s1', matches: [_item('s1', libraryId: 'lib-hidden')]),
      ]).resolveAllSourcesForGroup(_identity);

      final afterHide = _server('s1', matches: [_item('s1', libraryId: 'lib-hidden')]);
      final result = await resolverFor([afterHide], hidden: {'s1:lib-hidden'}).resolveAllSourcesForGroup(_identity);

      expect(result.items, isEmpty, reason: 'the seven-day row was written under the visible fingerprint');
      expect((afterHide.client! as _MatchingClient).lookups, 1, reason: 'the hidden fingerprint is a different row');
    });

    test('D: a warm negative written while hidden is not served once visible again', () async {
      await resolverFor(
        [
          _server('s1', matches: [_item('s1', libraryId: 'lib-x')]),
        ],
        hidden: {'s1:lib-x'},
      ).resolveAllSourcesForGroup(_identity);

      final afterUnhide = _server('s1', matches: [_item('s1', libraryId: 'lib-x')]);
      final result = await resolverFor([afterUnhide]).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), ['s1']);
    });

    test('E: unhiding lands back on the row the visible resolve already wrote', () async {
      final first = _server('s1', matches: [_item('s1', libraryId: 'lib-x')]);
      await resolverFor([first]).resolveAllSourcesForGroup(_identity);

      await resolverFor(
        [
          _server('s1', matches: [_item('s1', libraryId: 'lib-x')]),
        ],
        hidden: {'s1:lib-x'},
      ).resolveAllSourcesForGroup(_identity);

      final back = _server('s1', matches: [_item('s1', libraryId: 'lib-x')]);
      final result = await resolverFor([back]).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), ['s1'], reason: 'the source comes back when the library does');
      expect((back.client! as _MatchingClient).lookups, 0, reason: 'and it comes back off the row it was written to');
    });

    test('F: two visibility sets on one profile never share a row', () async {
      await resolverFor(
        [
          _server(
            's1',
            matches: [_item('s1', id: 'a', libraryId: 'lib-a')],
          ),
        ],
        hidden: {'s1:lib-b'},
      ).resolveAllSourcesForGroup(_identity);

      final other = _server(
        's1',
        matches: [_item('s1', id: 'a', libraryId: 'lib-a')],
      );
      final result = await resolverFor([other], hidden: {'s1:lib-a'}).resolveAllSourcesForGroup(_identity);

      expect(result.items, isEmpty);
      expect((other.client! as _MatchingClient).lookups, 1);
    });

    test('F: the same hidden set in a different order is the same row', () async {
      await resolverFor(
        [
          _server('s1', matches: [_item('s1', libraryId: 'lib-keep')]),
        ],
        hidden: {'s1:lib-a', 's1:lib-b', 's1:lib-c'},
      ).resolveAllSourcesForGroup(_identity);

      final warm = _server('s1', matches: [_item('s1', libraryId: 'lib-keep')]);
      await resolverFor([warm], hidden: {'s1:lib-c', 's1:lib-a', 's1:lib-b'}).resolveAllSourcesForGroup(_identity);

      expect(
        (warm.client! as _MatchingClient).lookups,
        0,
        reason: 'the fingerprint depends on the set, not on iteration order',
      );
    });

    test('F: two profiles with different visibility do not share a row', () async {
      await resolverFor([
        _server('s1', matches: [_item('s1', libraryId: 'lib-x')]),
      ]).resolveAllSourcesForGroup(_identity);

      final otherProfile = _server('s1', matches: [_item('s1', libraryId: 'lib-x')]);
      final result = await SourceAllResolver(
        profileId: 'profile-2',
        serversFor: () => [otherProfile],
        hiddenLibraryKeysFor: () => {'s1:lib-x'},
        cache: cache,
        now: () => clock,
      ).resolveAllSourcesForGroup(_identity);

      expect(result.items, isEmpty);
      expect((otherProfile.client! as _MatchingClient).lookups, 1);
    });

    test('a resolver given no visibility context behaves as it did before', () async {
      final result = await SourceAllResolver(
        profileId: 'profile-1',
        serversFor: () => [
          _server('s1', matches: [_item('s1', libraryId: 'lib-1')]),
        ],
        cache: cache,
        now: () => clock,
      ).resolveAllSourcesForGroup(_identity);

      expect(result.items.map((i) => i.serverId), ['s1']);
    });
  });

  group('bounded fan-out', () {
    test('never asks more than maxConcurrent servers at once', () async {
      var active = 0;
      var maxActive = 0;
      final servers = [
        for (var i = 0; i < 6; i++)
          (
            serverId: ServerId('s$i'),
            backend: MediaBackend.plex,
            client: _CountingClient(
              onCall: () async {
                active++;
                if (active > maxActive) maxActive = active;
                await Future<void>.delayed(const Duration(milliseconds: 5));
                active--;
                return [_item('s$i')];
              },
            ),
            online: true,
            hasAuthError: false,
          ),
      ];

      final result = await SourceAllResolver(
        profileId: 'profile-1',
        serversFor: () => servers,
        cache: cache,
        maxConcurrent: 2,
        now: () => clock,
      ).resolveAllSourcesForGroup(_identity);

      expect(result.items, hasLength(6));
      expect(maxActive, lessThanOrEqualTo(2));
    });
  });

  group('cancellation (hoofdstuk 14.5)', () {
    List<EligibleSourceServer> countingServers(int count, {required void Function() onCall}) => [
      for (var i = 0; i < count; i++)
        (
          serverId: ServerId('s$i'),
          backend: MediaBackend.plex,
          client: _CountingClient(
            onCall: () async {
              onCall();
              return [_item('s$i')];
            },
          ),
          online: true,
          hasAuthError: false,
        ),
    ];

    SourceAllResolver boundedResolver(List<EligibleSourceServer> servers) => SourceAllResolver(
      profileId: 'profile-1',
      serversFor: () => servers,
      cache: cache,
      maxConcurrent: 2,
      now: () => clock,
    );

    test('choosing a source stops the servers that had not been asked yet', () async {
      var calls = 0;
      final servers = countingServers(6, onCall: () => calls++);

      final result = await boundedResolver(servers).resolveAllSourcesForGroup(_identity, isCancelled: () => true);

      // One batch of two ran; the remaining four were never asked.
      expect(calls, 2);
      expect(result.items, hasLength(2));
    });

    test('a cancelled run reports the servers it never reached as unchecked', () async {
      final servers = countingServers(6, onCall: () {});

      final result = await boundedResolver(servers).resolveAllSourcesForGroup(_identity, isCancelled: () => true);

      expect(result.coverage.isComplete, isFalse);
      expect(result.coverage.checkedServerIds, hasLength(2));
      expect(result.coverage.uncheckedCount, 4);
      expect(result.coverage.uncheckedReasons.values, everyElement(UncheckedSourceReason.lookupFailed));
    });

    test('a cancelled run is never cached, so the next open re-asks', () async {
      var calls = 0;
      final servers = countingServers(6, onCall: () => calls++);
      final resolver = boundedResolver(servers);

      await resolver.resolveAllSourcesForGroup(_identity, isCancelled: () => true);
      expect(calls, 2);

      final full = await resolver.resolveAllSourcesForGroup(_identity);

      expect(calls, 8);
      expect(full.coverage.isComplete, isTrue);
      expect(full.items, hasLength(6));
    });

    test('a predicate that never fires leaves the exhaustive behaviour untouched', () async {
      var calls = 0;
      final servers = countingServers(6, onCall: () => calls++);

      final result = await boundedResolver(servers).resolveAllSourcesForGroup(_identity, isCancelled: () => false);

      expect(calls, 6);
      expect(result.coverage.isComplete, isTrue);
    });
  });

  // A19: the coverage denominator is the profile's topology, not the clients
  // that happen to exist. Every test here asks the same question — did this
  // server get to count as "should have answered"?
  group('A19: expected-server denominator', () {
    MediaServerClient? clientForNone(ServerId _) => null;

    test('an expected server with no live client is still expected, and unchecked', () async {
      final servers = eligibleSourceServers(
        expectedServerIds: const ['s1', 's2'],
        visibleServerIds: const ['s1'],
        clientFor: (id) => id.value == 's1' ? _MatchingClient(matches: [_item('s1')]) : null,
        isOnline: (id) => id.value == 's1',
        authErrorServerIds: const {},
      );

      final result = await resolverFor(servers).resolveAllSourcesForGroup(_identity);

      expect(result.coverage.expectedServerIds, {'s1', 's2'});
      expect(result.coverage.checkedServerIds, {'s1'});
      expect(result.coverage.isComplete, isFalse);
      expect(result.coverage.uncheckedReasons['s2'], UncheckedSourceReason.offline);
    });

    test('a client map that has forgotten the server does not shrink the denominator', () {
      // The pre-fase-9 shape: build the list from live clients only. The
      // expected server is simply not in it, and coverage would call itself
      // complete on one answer out of two.
      final fromClientsOnly = eligibleSourceServers(
        expectedServerIds: const [],
        visibleServerIds: const ['s1'],
        clientFor: clientForNone,
        isOnline: (_) => false,
        authErrorServerIds: const {},
      );
      final fromTopology = eligibleSourceServers(
        expectedServerIds: const ['s1', 's2'],
        visibleServerIds: const ['s1'],
        clientFor: clientForNone,
        isOnline: (_) => false,
        authErrorServerIds: const {},
      );

      expect(fromClientsOnly.map((s) => s.serverId.value), ['s1']);
      expect(fromTopology.map((s) => s.serverId.value), ['s1', 's2']);
    });

    test('an expected server that is online but never answers is unchecked, not absent', () async {
      final servers = eligibleSourceServers(
        expectedServerIds: const ['s1', 's2'],
        visibleServerIds: const ['s1', 's2'],
        clientFor: (id) =>
            id.value == 's1' ? _MatchingClient(matches: [_item('s1')]) : _MatchingClient(throws: true),
        isOnline: (_) => true,
        authErrorServerIds: const {},
      );

      final result = await resolverFor(servers).resolveAllSourcesForGroup(_identity);

      expect(result.coverage.isComplete, isFalse);
      expect(result.coverage.uncheckedReasons['s2'], UncheckedSourceReason.lookupFailed);
    });

    test('an auth-errored expected server says so instead of reading as plain offline', () async {
      final servers = eligibleSourceServers(
        expectedServerIds: const ['s1', 's2'],
        visibleServerIds: const ['s1'],
        clientFor: (id) => id.value == 's1' ? _MatchingClient(matches: [_item('s1')]) : null,
        isOnline: (id) => id.value == 's1',
        authErrorServerIds: const {'s2'},
      );

      final result = await resolverFor(servers).resolveAllSourcesForGroup(_identity);

      expect(result.coverage.uncheckedReasons['s2'], UncheckedSourceReason.authError);
    });

    test('a server the profile does not expect and does not see never enters the denominator', () {
      // Visibility closes upstream (hoofdstuk 1.1 point 2): a hidden server
      // appears in neither set, so there is nothing here to re-admit it.
      final servers = eligibleSourceServers(
        expectedServerIds: const ['s1'],
        visibleServerIds: const ['s1'],
        clientFor: clientForNone,
        isOnline: (_) => false,
        authErrorServerIds: const {},
      );

      expect(servers.map((s) => s.serverId.value), ['s1']);
    });

    test('a visible server the expectation has not caught up with is added, not dropped', () {
      // The union is one-directional on purpose: it can only add a live
      // server mid-bind, never re-admit one the profile hides.
      final servers = eligibleSourceServers(
        expectedServerIds: const ['s1'],
        visibleServerIds: const ['s1', 's2'],
        clientFor: clientForNone,
        isOnline: (_) => false,
        authErrorServerIds: const {},
      );

      expect(servers.map((s) => s.serverId.value), ['s1', 's2']);
    });

    test('every expected server answering is complete', () async {
      final servers = eligibleSourceServers(
        expectedServerIds: const ['s1', 's2'],
        visibleServerIds: const ['s1', 's2'],
        clientFor: (id) => _MatchingClient(matches: [_item(id.value)]),
        isOnline: (_) => true,
        authErrorServerIds: const {},
      );

      final result = await resolverFor(servers).resolveAllSourcesForGroup(_identity);

      expect(result.coverage.isComplete, isTrue);
      expect(result.items, hasLength(2));
    });

    // The helper above is only the honest answer if it is the one production
    // actually uses. Two screens build a resolver, both from the same five
    // lines, and the failure mode is silent: hand-rolling the list back to
    // `manager.serverIds` compiles, passes every behaviour test in this file,
    // and quietly restores the lie. This guards the call sites the way
    // `test/no_bare_text_field_test.dart` guards the text fields.
    test('every SourceAllResolver in lib/ takes its server list from eligibleSourceServers', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = entity.path.replaceAll(r'\', '/');
        final source = entity.readAsStringSync();
        if (!source.contains('SourceAllResolver(')) continue;
        for (final match in RegExp(r'serversFor:\s*([\s\S]{0,40})').allMatches(source)) {
          if (!match.group(1)!.contains('eligibleSourceServers(')) {
            offenders.add('$relative: serversFor does not call eligibleSourceServers');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A19: the coverage denominator must come from the profile topology. '
            'Build the list with eligibleSourceServers() instead of from the live client map.\n'
            '${offenders.join('\n')}',
      );
    });

    test('a clientless expected server has no known backend, and counts anyway', () {
      // "We do not know what it is and it never answered" has to read as a
      // gap. Reporting it as a backend that cannot carry identity would
      // exempt it from coverage entirely.
      final servers = eligibleSourceServers(
        expectedServerIds: const ['s2'],
        visibleServerIds: const [],
        clientFor: clientForNone,
        isOnline: (_) => false,
        authErrorServerIds: const {},
      );

      expect(isIdentityEligibleBackend(servers.single.backend), isTrue);
      expect(servers.single.client, isNull);
      expect(servers.single.online, isFalse);
    });
  });
}

class _CountingClient implements MediaServerClient {
  _CountingClient({required this.onCall});

  final Future<List<MediaItem>> Function() onCall;

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) => onCall();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

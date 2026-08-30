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

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    lookups++;
    if (throws) throw StateError('server down mid-flight');
    return matches;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(String serverId, {String id = 'item-1'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  year: 2010,
  serverId: serverId,
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

  SourceAllResolver resolverFor(List<EligibleSourceServer> servers) =>
      SourceAllResolver(profileId: 'profile-1', serversFor: () => servers, cache: cache, now: () => clock);

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
}

class _CountingClient implements MediaServerClient {
  _CountingClient({required this.onCall});

  final Future<List<MediaItem>> Function() onCall;

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) => onCall();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

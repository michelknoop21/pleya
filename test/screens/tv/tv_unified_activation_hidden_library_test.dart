import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/screens/tv/tv_unified_activation.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/source_resolver.dart';

/// B8 case C, at the seam that actually feeds the picker.
///
/// `resolveAllSourcesForGroup` returning the right items is necessary but not
/// sufficient: what the source picker renders is whatever
/// `UnifiedActivationEnvironment.resolveMoreSources` hands back, which is the
/// resolution run through `_sourcesFromResolution`. This drives that whole
/// path, so a future refactor that moves the filter out of the resolver and
/// into a caller cannot pass the resolver's own tests and still leak here.
class _MatchingClient implements MediaServerClient {
  _MatchingClient(this.matches);

  final List<MediaItem> matches;

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async => matches;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(String serverId, {required String libraryId, String id = 'i1'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  year: 2010,
  serverId: serverId,
  serverName: serverId,
  libraryId: libraryId,
);

void main() {
  late AppDatabase db;
  late PlexApiCache cache;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    cache = PlexApiCache.instance;
  });

  tearDown(() async => db.close());

  /// The group the card shows: one visible source on s1, which is the honest
  /// "1 bron" the catalog page merged.
  UnifiedMediaGroup groupOnS1() {
    final source = UnifiedMediaSource.fromItem(_item('s1', libraryId: 'lib-visible'));
    return UnifiedMediaGroup(
      groupId: 'g1',
      identity: CanonicalMediaIdentity.movie(title: 'Sintel', year: 2010),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
  }

  SourceAllResolver resolver({required Set<String> hidden, required List<MediaItem> s2Matches}) => SourceAllResolver(
    profileId: 'profile-1',
    serversFor: () => [
      (
        serverId: ServerId('s1'),
        backend: MediaBackend.plex,
        client: _MatchingClient([_item('s1', libraryId: 'lib-visible')]),
        online: true,
        hasAuthError: false,
      ),
      (
        serverId: ServerId('s2'),
        backend: MediaBackend.plex,
        client: _MatchingClient(s2Matches),
        online: true,
        hasAuthError: false,
      ),
    ],
    hiddenLibraryKeysFor: () => hidden,
    cache: cache,
  );

  Future<List<UnifiedMediaSource>> resolveThroughPicker(SourceAllResolver r) async {
    final environment = buildUnifiedActivationEnvironment(
      group: groupOnS1(),
      health: unifiedServerHealth(isOnline: (_) => true, authErrorServerIds: const {}),
      catalogServerIds: const {'s1', 's2'},
      availabilityRevision: ValueNotifier<int>(0),
      resolver: r,
    );
    return (await environment.resolveMoreSources!(() => false));
  }

  test('C: a duplicate in a hidden library never becomes a picker row', () async {
    final sources = await resolveThroughPicker(
      resolver(
        hidden: {'s2:lib-hidden'},
        s2Matches: [_item('s2', id: 'i2', libraryId: 'lib-hidden')],
      ),
    );

    expect(
      sources.map((s) => s.serverId),
      ['s1'],
      reason: 'the card says one source; the fan-out may not quietly add a second from a library the user hid',
    );
  });

  test('the same duplicate in a visible library does become a picker row', () async {
    final sources = await resolveThroughPicker(
      resolver(
        hidden: const {},
        s2Matches: [_item('s2', id: 'i2', libraryId: 'lib-open')],
      ),
    );

    expect(
      sources.map((s) => s.serverId),
      unorderedEquals(['s1', 's2']),
      reason: 'the negative control: without a hidden key the row is exactly the one B8 is about',
    );
  });
}

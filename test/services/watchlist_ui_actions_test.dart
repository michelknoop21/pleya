import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/providers/watchlist_store.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/services/watchlist_actions.dart';
import 'package:pleya/services/watchlist_ui_actions.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/notice_layer.dart';

final scope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'acc', userId: 'usr');

MediaItem movie({String id = 'm1', String? guid = 'plex://movie/abc', MediaKind kind = MediaKind.movie}) {
  return MediaItem(id: id, backend: MediaBackend.plex, kind: kind, title: 'Sintel', guid: guid, serverId: 'server_1');
}

WatchlistEntry entryFor(MediaItem item, {String key = 'plex:abc'}) {
  return WatchlistEntry(
    key: key,
    kind: item.kind,
    item: item,
    guid: item.guid,
    memberships: [WatchlistMembership(scope: scope, remoteKey: 'abc')],
  );
}

/// Records what it was asked to do, and can be told to fail.
class _RecordingSource implements WatchlistSource {
  _RecordingSource({this.userId = 'usr', this.failOnRemove = false, this.failOnAdd = false, this.acceptsAll = true});

  final String userId;
  final bool failOnRemove;
  final bool failOnAdd;
  final bool acceptsAll;

  int fetches = 0;
  final added = <MediaItem>[];
  final removed = <WatchlistMembership>[];

  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'acc', userId: userId);

  @override
  bool accepts(MediaItem item) => acceptsAll;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    fetches++;
    return const [];
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async {
    added.add(item);
    if (failOnAdd) throw StateError('add refused');
    return WatchlistMembership(scope: scope, remoteKey: 'abc');
  }

  @override
  Future<void> remove(WatchlistMembership membership) async {
    removed.add(membership);
    if (failOnRemove) throw StateError('remove refused');
  }

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  // A notice keeps an auto-dismiss timer, and the test framework fails a test
  // that leaves one pending.
  tearDown(resetNotices);

  setUp(() async {
    resetNotices();
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async => db.close());

  WatchlistProvider providerWith(_RecordingSource source) {
    return WatchlistProvider(
      snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
      repository: WatchlistRepository(sources: [source]),
    );
  }

  /// Pumps a bare tree that carries the two providers, and hands back a context
  /// below them.
  Future<BuildContext> pumpWith(
    WidgetTester tester, {
    required WatchlistProvider provider,
    required WatchlistStore store,
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<WatchlistProvider>.value(value: provider),
            ChangeNotifierProvider<WatchlistStore>.value(value: store),
          ],
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  captured = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
    return captured;
  }

  group('isOnList', () {
    test('an optimistic patch outranks the fetched list', () {
      final store = WatchlistStore();
      addTearDown(store.dispose);
      final provider = providerWith(_RecordingSource());
      addTearDown(provider.dispose);

      final item = movie();
      expect(WatchlistUiActions.isOnList(store: store, provider: provider, item: item), isFalse);

      store.patch('plex:abc', onList: true);
      expect(WatchlistUiActions.isOnList(store: store, provider: provider, item: item), isTrue);
    });

    test('a title with no guid and no external id is never on the list', () {
      final store = WatchlistStore();
      addTearDown(store.dispose);

      expect(WatchlistUiActions.isOnList(store: store, provider: null, item: movie(guid: null)), isFalse);
    });
  });

  group('canOffer', () {
    test('adding needs a source that will take the title', () {
      final willTake = providerWith(_RecordingSource());
      final willNotTake = providerWith(_RecordingSource(acceptsAll: false));
      addTearDown(willTake.dispose);
      addTearDown(willNotTake.dispose);

      expect(WatchlistUiActions.canOffer(provider: willTake, item: movie(), onList: false), isTrue);
      expect(WatchlistUiActions.canOffer(provider: willNotTake, item: movie(), onList: false), isFalse);
    });

    test('only movies and shows', () {
      final provider = providerWith(_RecordingSource());
      addTearDown(provider.dispose);

      for (final kind in [MediaKind.movie, MediaKind.show]) {
        expect(
          WatchlistUiActions.canOffer(
            provider: provider,
            item: movie(kind: kind),
            onList: false,
          ),
          isTrue,
          reason: '$kind belongs on a watchlist',
        );
      }
      for (final kind in [MediaKind.episode, MediaKind.season, MediaKind.collection, MediaKind.track]) {
        expect(
          WatchlistUiActions.canOffer(
            provider: provider,
            item: movie(kind: kind),
            onList: false,
          ),
          isFalse,
          reason: '$kind does not',
        );
      }
    });

    test('removing is only offered when the entry with the memberships is in hand', () async {
      final source = _RecordingSource();
      final provider = providerWith(source);
      addTearDown(provider.dispose);

      // The patch says the title is on the list, but nothing has been loaded,
      // so there is no membership to remove and the action stays hidden rather
      // than failing on press.
      expect(WatchlistUiActions.canOffer(provider: provider, item: movie(), onList: true), isFalse);

      await provider.addToWatchlist(movie(), isOffline: false);
      expect(WatchlistUiActions.canOffer(provider: provider, item: movie(), onList: true), isTrue);
    });

    test('without a provider there is nothing to offer', () {
      expect(WatchlistUiActions.canOffer(provider: null, item: movie(), onList: false), isFalse);
    });
  });

  group('toggle', () {
    testWidgets('adds through the source and flips the store, without a refetch', (tester) async {
      final source = _RecordingSource();
      final provider = providerWith(source);
      final store = WatchlistStore();
      addTearDown(provider.dispose);
      addTearDown(store.dispose);

      final context = await pumpWith(tester, provider: provider, store: store);
      final outcome = await WatchlistUiActions.toggle(context, movie());
      await tester.pump();

      expect(outcome, WatchlistOutcome.added);
      expect(source.added, hasLength(1));
      expect(store.isOnWatchlistByKey('plex:abc'), isTrue);
      // The list is patched in memory; asking the source again would put a
      // spinner over a list that is already right.
      expect(source.fetches, 0);
      expect(provider.entryForKey('plex:abc'), isNotNull);
    });

    testWidgets('a second toggle removes the entry it just added', (tester) async {
      final source = _RecordingSource();
      final provider = providerWith(source);
      final store = WatchlistStore();
      addTearDown(provider.dispose);
      addTearDown(store.dispose);

      final context = await pumpWith(tester, provider: provider, store: store);
      await WatchlistUiActions.toggle(context, movie());
      await tester.pump();
      final outcome = await WatchlistUiActions.toggle(context, movie());
      await tester.pump();

      expect(outcome, WatchlistOutcome.removed);
      expect(source.removed.single.remoteKey, 'abc');
      expect(store.isOnWatchlistByKey('plex:abc'), isFalse);
      expect(provider.entryForKey('plex:abc'), isNull);
      expect(source.fetches, 0);
    });

    testWidgets('a failed removal that compensated cleanly leaves the entry in place', (tester) async {
      final source = _RecordingSource(failOnRemove: true);
      final provider = providerWith(source);
      final store = WatchlistStore();
      addTearDown(provider.dispose);
      addTearDown(store.dispose);

      await pumpWith(tester, provider: provider, store: store);
      final outcome = await provider.removeFromWatchlist(entryFor(movie()), isOffline: false);

      // The one source failed before anything came off, so there was nothing to
      // compensate and the start state is intact. No refetch is owed.
      expect(outcome, WatchlistOutcome.failed);
      expect(source.fetches, 0);
    });

    testWidgets('a removal that went half way refetches and says so', (tester) async {
      // First source lets go of the title, second refuses, and putting the
      // first one back fails too. Nobody chose the state the list is in now,
      // so it is read back from the sources rather than guessed at.
      final first = _RecordingSource(userId: 'usr', failOnAdd: true);
      final second = _RecordingSource(userId: 'other', failOnRemove: true);
      final provider = WatchlistProvider(
        snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
        repository: WatchlistRepository(sources: [first, second]),
      );
      final store = WatchlistStore();
      addTearDown(provider.dispose);
      addTearDown(store.dispose);

      final context = await pumpWith(tester, provider: provider, store: store);
      final entry = WatchlistEntry(
        key: 'plex:abc',
        kind: MediaKind.movie,
        item: movie(),
        guid: 'plex://movie/abc',
        memberships: [
          WatchlistMembership(scope: first.scope, remoteKey: 'abc'),
          WatchlistMembership(scope: second.scope, remoteKey: 'abc'),
        ],
      );

      final outcome = await tester.runAsync(() => provider.removeFromWatchlist(entry, isOffline: false));
      WatchlistUiActions.report(context, outcome!, announce: false);
      await tester.pump();

      expect(outcome, WatchlistOutcome.partiallyFailed);
      expect(first.removed, hasLength(1));
      expect(second.removed, hasLength(1));
      expect(first.added, hasLength(1), reason: 'the compensating write was attempted');
      expect(first.fetches, 1, reason: 'the list is read back rather than guessed at');
      expect(find.text(t.watchlist.partiallyFailed), findsOneWidget);
    });

    testWidgets('offline is refused and the user is told', (tester) async {
      final source = _RecordingSource();
      final provider = providerWith(source);
      final store = WatchlistStore();
      addTearDown(provider.dispose);
      addTearDown(store.dispose);

      final context = await pumpWith(tester, provider: provider, store: store);
      final outcome = await provider.addToWatchlist(movie(), isOffline: true);
      WatchlistUiActions.report(context, outcome, announce: true);
      await tester.pump();

      expect(outcome, WatchlistOutcome.offlineRejected);
      expect(source.added, isEmpty);
      expect(find.text(t.watchlist.offlineRejected), findsOneWidget);
    });
  });
}

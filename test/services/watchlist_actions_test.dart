import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist_actions.dart';
import 'package:pleya/utils/watchlist_notifier.dart';

final plexScope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');
final jellyfinScope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.jellyfin, accountId: 'jf', userId: 'jfu');

MediaItem item({String? guid = 'plex://movie/abc'}) =>
    MediaItem(id: 'abc', backend: MediaBackend.plex, kind: MediaKind.movie, guid: guid, title: 'Sintel');

WatchlistEntry entryWith(List<WatchlistScopeId> scopes) => WatchlistEntry(
  key: 'plex:abc',
  kind: MediaKind.movie,
  item: item(),
  guid: 'plex://movie/abc',
  memberships: [for (final scope in scopes) WatchlistMembership(scope: scope, remoteKey: 'r-${scope.backend.id}')],
);

class _RecordingSource implements WatchlistSource {
  _RecordingSource({required this.scope, this.acceptsItem = true, this.failRemove = false, this.failAdd = false});

  @override
  final WatchlistScopeId scope;
  final bool acceptsItem;
  final bool failRemove;
  final bool failAdd;

  final List<String> calls = [];

  @override
  bool accepts(MediaItem item) => acceptsItem;

  @override
  Future<List<WatchlistEntry>> fetch() async => const [];

  @override
  Future<WatchlistMembership> add(MediaItem item) async {
    calls.add('add');
    if (failAdd) throw StateError('add failed');
    return WatchlistMembership(scope: scope, remoteKey: item.id);
  }

  @override
  Future<void> remove(WatchlistMembership membership) async {
    calls.add('remove');
    if (failRemove) throw StateError('remove failed');
  }

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

/// A private notifier so the tests do not race the app-wide singleton.
class _TestNotifier extends WatchlistNotifier {
  _TestNotifier() : super.forTesting();

  final List<WatchlistEvent> events = [];

  @override
  void notify(WatchlistEvent event) => events.add(event);
}

void main() {
  late _TestNotifier notifier;

  setUp(() => notifier = _TestNotifier());

  group('add', () {
    test('routes to the source that accepts the item', () async {
      final refuses = _RecordingSource(scope: plexScope, acceptsItem: false);
      final accepts = _RecordingSource(scope: jellyfinScope);

      final outcome = await WatchlistActions.add(
        repository: WatchlistRepository(sources: [refuses, accepts]),
        item: item(),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.added);
      expect(refuses.calls, isEmpty);
      expect(accepts.calls, ['add']);
    });

    test('patches first and confirms after, so the icon flips on tap', () async {
      await WatchlistActions.add(
        repository: WatchlistRepository(sources: [_RecordingSource(scope: plexScope)]),
        item: item(),
        isOffline: false,
        notifier: notifier,
      );

      expect(notifier.events.map((e) => (e.changeType, e.optimistic)), [
        (WatchlistChangeType.added, true),
        (WatchlistChangeType.added, false),
      ]);
    });

    test('reverts the patch when the write fails', () async {
      final outcome = await WatchlistActions.add(
        repository: WatchlistRepository(sources: [_RecordingSource(scope: plexScope, failAdd: true)]),
        item: item(),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.failed);
      expect(notifier.events.last.changeType, WatchlistChangeType.removed);
    });

    test('an item no source will take is unsupported, not failed', () async {
      final outcome = await WatchlistActions.add(
        repository: WatchlistRepository(sources: [_RecordingSource(scope: plexScope, acceptsItem: false)]),
        item: item(),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.unsupported);
      expect(notifier.events, isEmpty);
    });

    test('an item without any identity is unsupported before a source is asked', () async {
      final source = _RecordingSource(scope: plexScope);

      final outcome = await WatchlistActions.add(
        repository: WatchlistRepository(sources: [source]),
        item: MediaItem(id: 'x', backend: MediaBackend.plex, kind: MediaKind.movie),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.unsupported);
      expect(source.calls, isEmpty);
    });

    test('offline is refused, not queued', () async {
      final source = _RecordingSource(scope: plexScope);

      final outcome = await WatchlistActions.add(
        repository: WatchlistRepository(sources: [source]),
        item: item(),
        isOffline: true,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.offlineRejected);
      expect(source.calls, isEmpty);
      expect(notifier.events, isEmpty);
    });
  });

  group('remove', () {
    test('touches every membership, without asking which copy', () async {
      final plex = _RecordingSource(scope: plexScope);
      final jellyfin = _RecordingSource(scope: jellyfinScope);

      final outcome = await WatchlistActions.remove(
        sources: [plex, jellyfin],
        entry: entryWith([plexScope, jellyfinScope]),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.removed);
      expect(plex.calls, ['remove']);
      expect(jellyfin.calls, ['remove']);
    });

    test('compensates the successful step when a later one fails', () async {
      final plex = _RecordingSource(scope: plexScope);
      final jellyfin = _RecordingSource(scope: jellyfinScope, failRemove: true);

      final outcome = await WatchlistActions.remove(
        sources: [plex, jellyfin],
        entry: entryWith([plexScope, jellyfinScope]),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.failed);
      expect(plex.calls, ['remove', 'add'], reason: 'the Plex removal has to be put back');
      expect(notifier.events.last.changeType, WatchlistChangeType.added);
    });

    test('reports partiallyFailed when the compensation also fails', () async {
      final plex = _RecordingSource(scope: plexScope, failAdd: true);
      final jellyfin = _RecordingSource(scope: jellyfinScope, failRemove: true);

      final outcome = await WatchlistActions.remove(
        sources: [plex, jellyfin],
        entry: entryWith([plexScope, jellyfinScope]),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.partiallyFailed);
      expect(plex.calls, ['remove', 'add']);
      expect(
        notifier.events.last.changeType,
        WatchlistChangeType.removed,
        reason: 'the Plex copy really is gone, so the UI must not claim it came back',
      );
    });

    test('does not pretend to remove from a source the profile no longer has', () async {
      final plex = _RecordingSource(scope: plexScope);

      final outcome = await WatchlistActions.remove(
        sources: [plex],
        entry: entryWith([plexScope, jellyfinScope]),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.removed);
      expect(plex.calls, ['remove']);
    });

    test('an entry with no reachable source is unsupported', () async {
      final outcome = await WatchlistActions.remove(
        sources: [_RecordingSource(scope: jellyfinScope)],
        entry: entryWith([plexScope]),
        isOffline: false,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.unsupported);
      expect(notifier.events, isEmpty);
    });

    test('offline is refused, so a replay cannot delete a title added by hand', () async {
      final plex = _RecordingSource(scope: plexScope);

      final outcome = await WatchlistActions.remove(
        sources: [plex],
        entry: entryWith([plexScope]),
        isOffline: true,
        notifier: notifier,
      );

      expect(outcome, WatchlistOutcome.offlineRejected);
      expect(plex.calls, isEmpty);
    });

    test('the first failure stops the walk instead of soldiering on', () async {
      final plex = _RecordingSource(scope: plexScope, failRemove: true);
      final jellyfin = _RecordingSource(scope: jellyfinScope);

      await WatchlistActions.remove(
        sources: [plex, jellyfin],
        entry: entryWith([plexScope, jellyfinScope]),
        isOffline: false,
        notifier: notifier,
      );

      expect(jellyfin.calls, isEmpty);
    });
  });
}

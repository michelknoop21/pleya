import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/continue_watching_hidden_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/tv/tv_unified_context_actions.dart';
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/watch_actions.dart';
import 'package:pleya/utils/watch_state_notifier.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// The one path every menu takes out of Verder kijken (DEC-144 fase 3). On a
/// source that cannot remove server-side this used to throw `UnsupportedError`
/// out of the tvOS menu; it now hides the title on this device.
class _Client implements MediaServerClient {
  _Client(this._id, this.backend, this.capabilities);

  final String _id;
  int removals = 0;

  @override
  ServerId get serverId => ServerId(_id);

  @override
  String? get serverName => _id;

  @override
  final MediaBackend backend;

  @override
  final ServerCapabilities capabilities;

  @override
  Future<void> removeFromContinueWatching(MediaItem item) async {
    if (!capabilities.continueWatchingRemoval) throw UnsupportedError('Jellyfin cannot remove from Continue Watching');
    removals++;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(String id, String serverId, MediaBackend backend) =>
    MediaItem(id: id, backend: backend, kind: MediaKind.movie, title: 'Dune', serverId: serverId, serverName: serverId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  /// Loaded inside `runAsync`: the store reads shared preferences, and that
  /// read does not complete on the fake clock `testWidgets` runs under.
  Future<ContinueWatchingHiddenProvider> newHidden(WidgetTester tester) async {
    final hidden = (await tester.runAsync(() async {
      final provider = ContinueWatchingHiddenProvider();
      await provider.ensureInitialized();
      return provider;
    }))!;
    addTearDown(hidden.dispose);
    return hidden;
  }

  Future<BuildContext> pump(WidgetTester tester, List<_Client> clients, ContinueWatchingHiddenProvider hidden) async {
    final manager = MultiServerManager();
    for (final c in clients) {
      manager.debugRegisterClientForTesting(c);
    }
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<ContinueWatchingHiddenProvider>.value(value: hidden),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return context;
  }

  testWidgets('Jellyfin: hidden on this device, no server call, no throw, and the row is told', (tester) async {
    final jellyfin = _Client('zolder', MediaBackend.jellyfin, ServerCapabilities.jellyfin);
    final hidden = await newHidden(tester);
    final context = await pump(tester, [jellyfin], hidden);
    final events = <WatchStateEvent>[];
    final sub = WatchStateNotifier().stream.listen(events.add);
    addTearDown(sub.cancel);

    final item = _item('m1', 'zolder', MediaBackend.jellyfin);
    final outcome = await tester.runAsync(() => WatchActions.removeFromContinueWatching(context, item));
    await tester.pump();

    expect(outcome, ContinueWatchingRemoval.hiddenOnDevice);
    expect(jellyfin.removals, 0);
    expect(hidden.keys, {item.globalKey});
    expect(events.map((e) => e.changeType), [WatchStateChangeType.removedFromContinueWatching]);
  });

  testWidgets('Plex: removed on the server, nothing hidden locally', (tester) async {
    final plex = _Client('nas', MediaBackend.plex, ServerCapabilities.plex);
    final hidden = await newHidden(tester);
    final context = await pump(tester, [plex], hidden);

    final outcome = await tester.runAsync(
      () => WatchActions.removeFromContinueWatching(context, _item('m1', 'nas', MediaBackend.plex)),
    );

    expect(outcome, ContinueWatchingRemoval.removedOnServer);
    expect(plex.removals, 1);
    expect(hidden.count, 0);
  });

  testWidgets('the menu row follows the capabilities of the group it is opened on', (tester) async {
    final plex = _Client('nas', MediaBackend.plex, ServerCapabilities.plex);
    final jellyfin = _Client('zolder', MediaBackend.jellyfin, ServerCapabilities.jellyfin);
    final hidden = await newHidden(tester);
    final context = await pump(tester, [plex, jellyfin], hidden);

    UnifiedMediaGroup group(List<MediaItem> items) {
      final sources = items.map(UnifiedMediaSource.fromItem).toList();
      return UnifiedMediaGroup(
        groupId: 'g',
        identity: CanonicalMediaIdentity.movie(title: 'Dune', year: null),
        sources: sources,
        representativeSourceKey: sources.first.sourceKey,
        watchState: UnifiedWatchState(
          representativeSourceKey: sources.first.sourceKey,
          isWatched: false,
          hasActiveProgress: true,
        ),
      );
    }

    SourceAvailability online(UnifiedMediaSource _) => SourceAvailability.online;

    final jellyfinOnly = continueWatchingRemovalPresentationFor(
      context,
      group([_item('m1', 'zolder', MediaBackend.jellyfin)]),
      online,
    );
    expect(jellyfinOnly.label, 'Hide from Continue Watching');
    expect(jellyfinOnly.scope, 'On this device only');

    final merged = continueWatchingRemovalPresentationFor(
      context,
      group([_item('m1', 'nas', MediaBackend.plex), _item('m2', 'zolder', MediaBackend.jellyfin)]),
      online,
    );
    expect(merged.label, 'Remove from Continue Watching');
    expect(merged.scope, 'nas on the server, zolder here only');
  });

  // The fan-out the unified menu runs (TV and iPhone). A source that cannot
  // remove server-side and cannot be reached either has nothing to wait for:
  // it is hidden now, never queued, whether it is offline or refused the
  // sign-in. The scope line promised "here only" for both.
  for (final availability in [SourceAvailability.offline, SourceAvailability.authError]) {
    testWidgets('fan-out: an ${availability.name} Jellyfin source is hidden on the device, the Plex one removed', (
      tester,
    ) async {
      final plex = _Client('nas', MediaBackend.plex, ServerCapabilities.plex);
      final jellyfin = _Client('zolder', MediaBackend.jellyfin, ServerCapabilities.jellyfin);
      final hidden = await newHidden(tester);
      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(plex)
        ..debugRegisterClientForTesting(jellyfin);
      final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(multiServer.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<ContinueWatchingHiddenProvider>.value(value: hidden),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      final plexItem = _item('m1', 'nas', MediaBackend.plex);
      final jellyfinItem = _item('m2', 'zolder', MediaBackend.jellyfin);
      final sources = [plexItem, jellyfinItem].map(UnifiedMediaSource.fromItem).toList();
      final group = UnifiedMediaGroup(
        groupId: 'g',
        identity: CanonicalMediaIdentity.movie(title: 'Dune', year: null),
        sources: sources,
        representativeSourceKey: sources.first.sourceKey,
        watchState: UnifiedWatchState(
          representativeSourceKey: sources.first.sourceKey,
          isWatched: false,
          hasActiveProgress: true,
        ),
      );

      await tester.runAsync(
        () => runUnifiedGroupAction(
          context,
          action: UnifiedGroupAction.removeFromContinueWatching,
          group: group,
          availabilityFor: (source) => source.item.serverId == 'zolder' ? availability : SourceAvailability.online,
        ),
      );
      await tester.pump();

      expect(plex.removals, 1);
      expect(jellyfin.removals, 0, reason: 'the unsupported call is never made');
      expect(hidden.keys, {jellyfinItem.globalKey});
    });
  }
}

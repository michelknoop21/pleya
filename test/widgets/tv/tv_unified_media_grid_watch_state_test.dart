/// A catalog card follows this session's marks on every source it holds.
///
/// Owner report on build 447: a film finished on Plex also lives on Pleya
/// Server. The copy write reached the server, and so did a manual mark from the
/// card's menu, yet the card in Alle films kept showing the state of the library
/// snapshot it was loaded from. The grid now resolves each group against
/// [WatchStateStore], the same layer every other card reads.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/watch_state_notifier.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_artwork.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';

const _pleyaServer = 'pleya-physical';

/// What a Pleya Server client reports as `cacheServerId`: the account's
/// connection, not the server.
const _pleyaConnection = 'pleyaServer.pleya-physical.account';

MediaItem _movie(String id, MediaBackend backend, String serverId) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.movie,
  title: 'Heart of the Beast',
  year: 2026,
  durationMs: 6299840,
  serverId: serverId,
);

final _plex = _movie('60112', MediaBackend.plex, 'plex-machine');
final _pleya = _movie('01a1b549', MediaBackend.pleyaServer, _pleyaServer);

/// One card for [items], read from a snapshot taken before the viewing.
UnifiedMediaGroup _group([List<MediaItem>? items]) {
  final sources = [
    for (final item in items ?? [_pleya, _plex]) UnifiedMediaSource.fromItem(item),
  ];
  return UnifiedMediaGroup(
    groupId: 'heart',
    identity: CanonicalMediaIdentity.movie(title: 'Heart of the Beast', year: 2026),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
  );
}

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<List<UnifiedMediaGroup>> pumpGrid(WidgetTester tester, UnifiedMediaGroup group) async {
    final menus = <UnifiedMediaGroup>[];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => WatchStateStore()..setActiveClientScopesByServer({_pleyaServer: _pleyaConnection}),
        child: TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: Scaffold(
                body: TvUnifiedMediaGrid(
                  groups: [group],
                  onActivate: (_) {},
                  onContextMenu: menus.add,
                  hasMore: false,
                  isLoadingMore: false,
                  onLoadMore: () {},
                  precache: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return menus;
  }

  testWidgets('a mark on the Pleya Server copy reaches the card and its menu', (tester) async {
    final menus = await pumpGrid(tester, _group());
    expect(find.byType(TvCatalogWatchedBadge), findsNothing, reason: 'the snapshot predates the viewing');

    // What `WatchCopyWriter.write` and `WatchActions` emit for that copy.
    WatchStateNotifier().notifyWatched(item: _pleya, cacheServerId: _pleyaConnection, isCopy: true);
    await tester.pumpAndSettle();

    expect(find.byType(TvCatalogWatchedBadge), findsOneWidget);
    tester.widget<TvUnifiedMediaCard>(find.byType(TvUnifiedMediaCard)).onContextMenu!();
    expect(menus.single.watchState.isWatched, isTrue, reason: 'the menu would offer to mark it watched again');
  });

  testWidgets('a Pleya Server copy on a card of its own follows the copy write', (tester) async {
    await pumpGrid(tester, _group([_pleya]));

    WatchStateNotifier().notifyWatched(item: _pleya, cacheServerId: _pleyaConnection, isCopy: true);
    await tester.pumpAndSettle();

    expect(find.byType(TvCatalogWatchedBadge), findsOneWidget);
  });
}

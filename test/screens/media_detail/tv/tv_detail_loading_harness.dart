/// The detail page against a client whose pages can be held back or fail.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_hero_widgets.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_page.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/watch_state_notifier.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/pressable.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size loadingPanel = Size(1038, 584);

MediaItem loadingShow() => MediaItem(
  id: 'show',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.show,
  title: 'MobLand',
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem loadingMovie(List<MediaRole> roles) => MediaItem(
  id: 'movie',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: 'Toy Story',
  durationMs: 6000000,
  roles: roles,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem loadingSeason(int n, {int leafs = 3}) => MediaItem(
  id: 'season_$n',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.season,
  title: 'Season $n',
  index: n,
  parentId: 'show',
  leafCount: leafs,
  viewedLeafCount: 0,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem loadingEpisode(int season, int n, {int? viewCount}) => MediaItem(
  id: 'e$season-$n',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.episode,
  title: 'Episode $n',
  index: n,
  parentIndex: season,
  parentId: 'season_$season',
  grandparentId: 'show',
  durationMs: 3000000,
  viewCount: viewCount,
  serverId: 'server_1',
  serverName: 'Server',
);

class LoadingClient implements MediaServerClient {
  LoadingClient({
    MediaItem? item,
    List<MediaItem>? seasons,
    Map<String, List<MediaItem>>? episodes,
    this.onDeck,
    this.fileInfo,
  }) : item = item ?? loadingShow(),
       seasons = seasons ?? [loadingSeason(1), loadingSeason(2)],
       episodes =
           episodes ??
           {
             'season_1': [for (var i = 1; i <= 3; i++) loadingEpisode(1, i)],
             'season_2': [for (var i = 1; i <= 3; i++) loadingEpisode(2, i)],
           };

  final MediaItem item;
  final List<MediaItem> seasons;
  final Map<String, List<MediaItem>> episodes;
  final MediaItem? onDeck;
  final MediaFileInfo? fileInfo;

  /// A page of this parent waits here.
  final gates = <String, Completer<void>>{};

  /// The next read of these parents throws.
  final failOnce = <String>{};

  /// The next page after the first of any parent throws.
  var failNextLaterPage = false;
  var seasonsFail = false;

  /// What the server says it holds per parent, when it is more than it sends.
  final totals = <String, int>{};

  final pages = <String>[];
  final fileInfoFor = <String>[];

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'Server';
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: watched ? item.copyWith(viewCount: 1, viewOffsetMs: 0) : item, onDeckEpisode: onDeck);
  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    if (seasonsFail && parentId == 'show') throw StateError('seasons did not load');
    return parentId == 'show' ? seasons : episodes[parentId] ?? const [];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final offset = start ?? 0;
    pages.add('$parentId@$offset');
    await gates[parentId]?.future;
    if (failOnce.remove(parentId)) throw StateError('page did not load');
    if (offset > 0 && failNextLaterPage) {
      failNextLaterPage = false;
      throw StateError('page did not load');
    }
    final all = parentId == 'show' ? seasons : episodes[parentId] ?? const <MediaItem>[];
    if (offset >= all.length) return LibraryPage<MediaItem>(items: const [], totalCount: all.length, offset: offset);
    final end = (offset + (totals.containsKey(parentId) ? 2 : (size ?? all.length))).clamp(0, all.length);
    return LibraryPage<MediaItem>(
      items: all.sublist(offset, end),
      totalCount: totals[parentId] ?? all.length,
      offset: offset,
    );
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => const [];

  /// What [markWatched] turns the item into: no position left, one more play.
  var watched = false;

  @override
  Future<void> markWatched(MediaItem item) async {
    WatchStateNotifier().notifyWatched(item: item, isNowWatched: true, cacheServerId: 'server_1');
  }

  @override
  Future<MediaItem?> fetchItem(String id) async =>
      watched ? this.item.copyWith(viewCount: 1, viewOffsetMs: 0) : this.item;

  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    fileInfoFor.add(item.id);
    return fileInfo;
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => const [];
  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage<MediaItem>(
    items: [
      MediaItem(
        id: 'credit_$personId',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Credit of $personId',
        serverId: 'server_1',
      ),
    ],
    totalCount: 1,
    offset: 0,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? get detailFocus => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pumpAndSettle();
}

/// One step, without waiting for a page that is held back.
Future<void> stepKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Pumps the real screen, as the shell does, and waits for it to settle.
Future<void> pumpDetail(WidgetTester tester, LoadingClient client, {String? episode}) async {
  tester.view.physicalSize = loadingPanel;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await SettingsService.getInstance();
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final provider = MultiServerProvider(manager, DataAggregationService(manager));
  addTearDown(provider.dispose);

  await tester.pumpWidget(
    TranslationProvider(
      child: ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: MaterialApp(
          builder: (context, child) => withProfileNavigationScope(
            child: InputModeTracker(
              child: MainScreenFocusScope(
                focusSidebar: () {},
                focusContent: () {},
                isSidebarFocused: false,
                sideNavigationWidth: 0,
                child: TvDisplayMetrics(
                  size: loadingPanel,
                  child: OverlaySheetHost(child: withNoticeLayer()(context, child)),
                ),
              ),
            ),
          ),
          theme: monoTheme(dark: true),
          home: TvNestedRouteScope(
            dismiss: ([_]) {},
            markResult: (_) {},
            child: MediaDetailScreen(metadata: client.item, initialEpisodeId: episode),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

TvDetailPage page(WidgetTester tester) => tester.widget<TvDetailPage>(find.byType(TvDetailPage));

Iterable<String> episodeRow(WidgetTester tester) => page(tester).sections.single.itemIds;

Pressable playButton(WidgetTester tester) => tester.widget<Pressable>(
  find.ancestor(of: find.byType(TvDetailRoundButton).first, matching: find.byType(Pressable)).first,
);

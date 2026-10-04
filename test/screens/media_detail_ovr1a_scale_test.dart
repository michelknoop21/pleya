import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/notice_layer.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';

/// OVR1a on the detail surface (DEC-109): the ten-foot scale is a property of
/// the panel a viewer sits in front of, not of whatever content box a nested
/// TV route happens to receive. `media_detail_screen.dart` used to read
/// `TvLayoutConstants.scaleForSize` off its own (possibly shell-shortened)
/// content box; this pins it to `TvLayoutConstants.scaleOf`, which reads
/// `TvDisplayMetrics` — the full window a real `TvNestedSurface` publishes —
/// before ever falling back to `MediaQuery`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetNotices);

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('the fallback title scales off the published panel size, not a shorter nested content box', (
    tester,
  ) async {
    await SettingsService.getInstance();

    const title = 'A Fallback Title Long Enough To Prove The Point';
    final movie = MediaItem(id: 'movie_1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: title);

    // The panel (`TvDisplayMetrics`) sits exactly at the reference height, so
    // its scale is 1.0; the nested content box a real `TvNestedSurface` would
    // hand this screen — shorter by the topnav band — floors to 0.85. If both
    // landed on the same number this test would prove nothing, which is
    // exactly the failure mode of testing this without a real nested shell.
    // 900 is still generous room for the foreground content, unlike a tiny
    // box that would starve the reveal entirely.
    const panelSize = Size(1038, 1080);
    const nestedBoxSize = Size(1038, 900);
    final panelScale = TvLayoutConstants.scaleForSize(panelSize);
    final boxScale = TvLayoutConstants.scaleForSize(nestedBoxSize);
    expect(panelScale, isNot(closeTo(boxScale, 0.001)));

    tester.view.physicalSize = panelSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: withProfileNavigationScope(
            // Mirrors what `TvNestedSurface` actually does: `TvDisplayMetrics`
            // published around the full panel, a `MediaQuery` override inside
            // it narrowing what the nested route itself sees to its (shorter)
            // content box.
            child: TvDisplayMetrics(
              size: panelSize,
              child: TvNestedRouteScope(
                dismiss: ([_]) {},
                markResult: (_) {},
                child: MediaQuery(
                  data: MediaQueryData(size: nestedBoxSize),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox.fromSize(
                      size: nestedBoxSize,
                      child: MediaDetailScreen(metadata: movie),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final titleText = tester.widget<Text>(find.text(title));
    expect(titleText.style?.fontSize, isNotNull);
    // DENS1: the title is HIG Title 1 (76 pt) on the panel's point grid; the
    // nested box would give 76 * 900 / 1080.
    expect(titleText.style!.fontSize, closeTo(TvHig.title1 * panelSize.height / 1080, 0.05));
    // DENS1: the action row is 60 pt, above tvOS's 56 pt button minimum; the
    // old `46 * scaleOf` made it 72 pt on an Apple TV.
    expect(tester.getSize(find.byType(FilledButton).first).height, closeTo(60 * panelSize.height / 1080, 0.05));
  });

  testWidgets('SYS-3c/SYS-3e: the detail rail and its reservation read the scale the detail screen does', (
    tester,
  ) async {
    await SettingsService.getInstance();

    // Dezelfde twee dozen als de OVR1a-test hierboven: het paneel staat exact
    // op de referentiehoogte (schaal 1.0), de geneste doos is korter door de
    // topnav-band en klemt op 0.85. Vielen ze samen, dan bewees deze test
    // niets.
    const panelSize = Size(1038, 1080);
    const nestedBoxSize = Size(1038, 900);
    final panelScale = TvLayoutConstants.scaleForSize(panelSize);
    final boxScale = TvBrowseRailLayout.scaleForSize(nestedBoxSize);
    expect(panelScale, isNot(closeTo(boxScale, 0.001)));

    tester.view.physicalSize = panelSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Show/season/episode + _FakeMediaServerClient/MultiServerProvider
    // wiring, overgenomen van
    // test/screens/media_detail_screen_test.dart:564-625: zonder hubs mount
    // de rail niet.
    final show = MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      serverId: 'server_1',
      serverName: 'Server',
    );
    final season1 = MediaItem(
      id: 'season_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 1',
      index: 1,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final season2 = MediaItem(
      id: 'season_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 2',
      index: 2,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode1 = MediaItem(
      id: 'episode_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 1',
      index: 1,
      parentId: season1.id,
      parentIndex: season1.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode2 = MediaItem(
      id: 'episode_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 2',
      index: 1,
      parentId: season2.id,
      parentIndex: season2.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final client = _FakeMediaServerClient(
      show: show,
      childrenByParent: {
        show.id: [season1, season2],
        season1.id: [episode1],
        season2.id: [episode2],
      },
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: TvDisplayMetrics(
                size: panelSize,
                child: TvNestedRouteScope(
                  dismiss: ([_]) {},
                  markResult: (_) {},
                  child: MediaQuery(
                    data: const MediaQueryData(size: nestedBoxSize),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox.fromSize(
                        size: nestedBoxSize,
                        child: MediaDetailScreen(metadata: show),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // `find.byType(SizedBox).first` under `TvBrowseRail` is not the hubstrip
    // here: measured with `tester.widgetList<SizedBox>(...).map((s) =>
    // s.height)`, the first entry is 259.3 (an outer layout box), while
    // `TvBrowseRailLayout.hubStripHeightForScale(boxScale)` (30.6 at
    // boxScale 0.85) shows up further down the list, confirming the rail
    // itself renders at the box scale. The brief's suggested fallback
    // ('Server' text at fontSize 15 * scale) also does not apply on this
    // route: `TvBrowseRail(showServerName: ...)` is never passed by
    // `media_detail_screen.dart`, so it defaults to false and that text
    // never mounts (`find.text('Server')` finds zero widgets here). The hub
    // title itself is driven by the same `scale` (`fontSize: 18 * scale` in
    // `_buildHubHeader`) and always renders: with two seasons the season
    // chips own the season name, so the hub title falls back to the
    // localized "Episodes" label.
    // Since VIS2 that label is the heading of the chip row on the rail's
    // header line, and since DENS1 it is HIG Body on the panel's point grid
    // (29 pt at 1080); on the nested box it would be 29 * 900 / 1080.
    final hubTitle = tester.widget<Text>(find.text('Episodes'));
    expect(
      hubTitle.style?.fontSize,
      closeTo(TvHig.body * panelSize.height / 1080, 0.05),
      reason: 'the rail scales off the nested box while the screen above it scales off the panel',
    );
    // SYS-3e: what the screen reserves for the rail has to be what the rail
    // draws. The foreground's bottom edge sits `railTopPadding - gap` (12 - 4)
    // into the rail block, both at the panel scale. With the reservation on
    // the box scale it sat 32.3 px in, over the season chips, and the rail
    // hung 1.2 px less of its bottom padding off the edge than it draws.
    final railBlock = tester.getRect(find.ancestor(of: find.byType(TvBrowseRail), matching: find.byType(Column)).first);
    final foreground = tester.getRect(
      find.ancestor(of: find.text('The Show'), matching: find.byType(Positioned)).first,
    );
    expect(foreground.bottom - railBlock.top, closeTo(8 * panelScale, 0.5));
    expect(
      railBlock.bottom,
      closeTo(nestedBoxSize.height + TvBrowseRailLayout.railBottomPaddingForScale(panelScale), 0.5),
    );
  });
}

/// Minimal fake, trimmed from
/// test/screens/media_detail_screen_test.dart:3403-3499 down to the fields
/// this test's fixture (show/season/episode wiring, no pending-descendants
/// or per-parent error/future overrides) actually exercises; `noSuchMethod`
/// covers everything else the interface declares.
class _FakeMediaServerClient implements MediaServerClient {
  final MediaItem show;
  final Map<String, List<MediaItem>> childrenByParent;
  final childrenPageCalls = <({String parentId, int? start, int? size})>[];
  final fetchItemCalls = <String>[];

  _FakeMediaServerClient({required this.show, required this.childrenByParent});

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => const [];

  final String id = 'server_1';
  final String name = 'Server';

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => name;

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async {
    return (item: show, onDeckEpisode: null);
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    return childrenByParent[parentId] ?? const [];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    childrenPageCalls.add((parentId: parentId, start: start, size: size));
    final all = childrenByParent[parentId] ?? const <MediaItem>[];
    final offset = start ?? 0;
    final limit = size ?? all.length;
    final end = (offset + limit).clamp(0, all.length).toInt();
    final items = offset >= all.length ? const <MediaItem>[] : all.sublist(offset, end);
    return LibraryPage(items: items, totalCount: all.length, offset: offset);
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => const [];

  @override
  Future<MediaItem?> fetchItem(String id) async {
    fetchItemCalls.add(id);
    if (id == show.id) return show;
    for (final items in childrenByParent.values) {
      for (final item in items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

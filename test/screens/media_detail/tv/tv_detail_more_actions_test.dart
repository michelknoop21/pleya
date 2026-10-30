/// Meer acties (northstar 12) through the real screen: a side panel on the
/// media menu's own entries, with the file's tracks and the sources on top.
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
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_action_panel.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/track_preference_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/file_info_bottom_sheet.dart';
import 'package:pleya/widgets/media_context_menu.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size _panel = Size(1038, 584);
const double _pt = 584 / 1080;

MediaItem _movie({MediaBackend backend = MediaBackend.jellyfin, int? offset}) => MediaItem(
  id: 'movie',
  backend: backend,
  kind: MediaKind.movie,
  title: 'Puss in Boots',
  guid: 'plex://movie/1',
  summary: 'A cat with one life left.',
  durationMs: 6000000,
  viewOffsetMs: offset,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaFileInfo _tracks() => MediaFileInfo(
  audioTracks: [
    MediaAudioTrack(id: 1, languageCode: 'eng', codec: 'eac3', channels: 6, selected: true),
    MediaAudioTrack(id: 2, languageCode: 'nld', codec: 'aac', channels: 2, selected: false),
  ],
  subtitleTracks: [MediaSubtitleTrack(id: 7, languageCode: 'nld', selected: false, forced: false)],
);

class _Manager extends MultiServerManager {
  _Manager({required this.owner});

  final bool owner;

  @override
  bool canManageServerMetadata(ServerId serverId) => owner;
}

class _Client implements MediaServerClient {
  _Client(this.movie, {this.extras = const [], this.fileInfo, this.lateFileInfo});

  final MediaItem movie;
  final List<MediaItem> extras;
  final MediaFileInfo? fileInfo;
  final Future<MediaFileInfo?>? lateFileInfo;

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'Server';
  @override
  MediaBackend get backend => movie.backend;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: movie, onDeckEpisode: null);
  @override
  Future<List<MediaItem>> fetchExtras(String id) async => extras;
  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) => lateFileInfo ?? Future.value(fileInfo);
  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => const [];
  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => const LibraryPage<MediaItem>(items: [], totalCount: 0, offset: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? get _focus => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pumpAndSettle();
}

Iterable<String> _rows(WidgetTester tester) =>
    tester.widget<TvDetailActionPanel>(find.byType(TvDetailActionPanel).last).rows.map((row) => row.id);

TvDetailActionRow _row(WidgetTester tester, String id) =>
    tester.widget<TvDetailActionPanel>(find.byType(TvDetailActionPanel).last).rows.firstWhere((row) => row.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TrackPreferenceStore.resetForTesting();
    TrackPreferenceStore.deviceNameProvider = () async => 'Test';
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    _Client client, {
    bool owner = false,
    UnifiedMediaRouteContext? unified,
    Future<void> Function(BuildContext)? onChangeSource,
    bool underShell = true,
  }) async {
    tester.view.physicalSize = _panel;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await SettingsService.getInstance();
    final manager = _Manager(owner: owner)..debugRegisterClientForTesting(client);
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
                    size: _panel,
                    child: underShell
                        ? OverlaySheetHost(child: withNoticeLayer()(context, child))
                        : withNoticeLayer()(context, child),
                  ),
                ),
              ),
            ),
            theme: monoTheme(dark: true),
            // As in the app: the sheet host is the shell's, above the route, so
            // this page's rebuild does not reach what stands in it.
            home: Builder(
              builder: (context) {
                final page = MediaDetailScreen(
                  metadata: client.movie,
                  unifiedRouteContext: unified,
                  onChangeSource: onChangeSource,
                );
                return underShell ? TvNestedRouteScope(dismiss: ([_]) {}, markResult: (_) {}, child: page) : page;
              },
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

  /// RIGHT along the round actions until ⋮ has the focus, then Select.
  Future<void> openPanel(WidgetTester tester) async {
    for (var i = 0; i < 8 && _focus != 'detail_more'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focus, 'detail_more');
    await _press(tester, LogicalKeyboardKey.enter);
    expect(find.byType(TvDetailActionPanel), findsOneWidget);
  }

  testWidgets('⋮ opens a panel down the right side, the focus on its first row in a white pill', (tester) async {
    await pumpDetail(tester, _Client(_movie(), fileInfo: _tracks()));
    await openPanel(tester);

    expect(find.text('More actions'), findsOneWidget);
    final panel = tester.getRect(find.byType(TvDetailActionPanel));
    expect(panel.width / _pt, closeTo(639, 1));
    expect((_panel.width - panel.right) / _pt, closeTo(33, 1));
    expect(panel.top / _pt, closeTo(33, 1));
    expect((_panel.height - panel.bottom) / _pt, closeTo(33, 1));

    expect(_focus, 'action_row_audio');
    final value = tester.getRect(
      find.descendant(of: find.byType(TvDetailActionPanel), matching: find.text('English (EAC3 5.1)')),
    );
    expect(
      (tester.getRect(find.widgetWithText(AnimatedContainer, 'Audio stream')).right - value.right) / _pt,
      closeTo(24, 1),
    );
    final row = tester.getRect(find.widgetWithText(AnimatedContainer, 'Audio stream'));
    expect(row.height / _pt, closeTo(63, 0.5));
    expect(row.center.dy / _pt, closeTo(251 * 0.96, 6), reason: 'the first row of 12');
    final pill = tester.widget<AnimatedContainer>(find.widgetWithText(AnimatedContainer, 'Audio stream'));
    expect((pill.decoration! as BoxDecoration).color, Colors.white);
  });

  testWidgets('a page on its own opens the panel in its own host', (tester) async {
    await pumpDetail(tester, _Client(_movie(), fileInfo: _tracks()), underShell: false);
    await openPanel(tester);

    expect(_focus, 'action_row_audio');
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TvDetailActionPanel), findsNothing);
    expect(_focus, 'detail_more');
  });

  testWidgets('the rows follow 12, with the value right of the label', (tester) async {
    final trailer = MediaItem(
      id: 'trailer',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.clip,
      title: 'Trailer',
      raw: const {'ExtraType': 'Trailer'},
      serverId: 'server_1',
    );
    await pumpDetail(tester, _Client(_movie(), extras: [trailer], fileInfo: _tracks()));
    await openPanel(tester);

    expect(_rows(tester), ['audio', 'subtitles', 'play_trailer', 'watch', 'rate', 'play_version', 'fileinfo']);
    expect(_row(tester, 'audio').value, 'English (EAC3 5.1)');
    expect(_row(tester, 'subtitles').value, 'Off');
  });

  testWidgets('no row without something to choose: a file without tracks has no track rows', (tester) async {
    await pumpDetail(tester, _Client(_movie()));
    await openPanel(tester);

    expect(_rows(tester), isNot(contains('audio')));
    expect(_rows(tester), isNot(contains('subtitles')));
  });

  testWidgets('tracks that arrive with the panel open show up in it, in the shell host', (tester) async {
    final info = Completer<MediaFileInfo?>();
    await pumpDetail(tester, _Client(_movie(), lateFileInfo: info.future));
    await openPanel(tester);
    expect(_rows(tester), isNot(contains('audio')));
    expect(
      find.ancestor(of: find.byType(TvDetailActionPanel), matching: find.byType(MediaDetailScreen)),
      findsNothing,
      reason: 'the shell host stands above the page, as in the app',
    );

    info.complete(_tracks());
    await tester.pumpAndSettle();

    expect(_row(tester, 'audio').value, 'English (EAC3 5.1)');
    expect(_row(tester, 'subtitles').value, 'Off');
  });

  testWidgets('the focus stays in: every arrow answers, the ends stop the press', (tester) async {
    await pumpDetail(tester, _Client(_movie(), fileInfo: _tracks()));
    await openPanel(tester);
    final rows = _rows(tester).toList();

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focus, 'action_row_${rows.first}');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focus, 'action_row_${rows.first}');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus, 'action_row_${rows.first}');

    for (final row in rows.skip(1)) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focus, 'action_row_$row');
    }
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, 'action_row_${rows.last}', reason: 'no wrap round to the first row');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focus, 'action_row_${rows[rows.length - 2]}');
  });

  testWidgets('Menu closes the panel and puts the focus back on ⋮', (tester) async {
    await pumpDetail(tester, _Client(_movie(), fileInfo: _tracks()));
    await openPanel(tester);

    await _press(tester, LogicalKeyboardKey.escape);

    expect(find.byType(TvDetailActionPanel), findsNothing);
    expect(_focus, 'detail_more');
    expect(find.byType(MediaDetailScreen), findsOneWidget);
  });

  testWidgets('picking an audio track stores it, stays in the panel and the row says the new one', (tester) async {
    final movie = _movie();
    await pumpDetail(tester, _Client(movie, fileInfo: _tracks()));
    await openPanel(tester);

    await _press(tester, LogicalKeyboardKey.enter);
    expect(find.text('Audio stream'), findsOneWidget);
    expect(_rows(tester), ['track_1', 'track_2']);
    expect(_focus, 'detail_track_selected', reason: 'the page opens on the track in use');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.enter);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byType(TvDetailActionPanel), findsOneWidget);
    expect(_row(tester, 'audio').value, 'Dutch (AAC Stereo)');
    expect(_focus, 'action_row_audio');
    final stored = await tester.runAsync(() => TrackPreferenceStore.read(movie));
    expect(stored?.audioLanguage, 'nld');

    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TvDetailActionPanel), findsNothing);
    expect(_focus, 'detail_more');
  });

  testWidgets('subtitles go on and off the same way, and Menu leaves a page without a choice', (tester) async {
    final movie = _movie();
    await pumpDetail(tester, _Client(movie, fileInfo: _tracks()));
    await openPanel(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);

    await _press(tester, LogicalKeyboardKey.enter);
    expect(_rows(tester), ['track_off', 'track_7']);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_focus, 'action_row_subtitles');
    expect(_row(tester, 'subtitles').value, 'Off');

    await _press(tester, LogicalKeyboardKey.enter);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.enter);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(_row(tester, 'subtitles').value, 'Dutch');
    final stored = await tester.runAsync(() => TrackPreferenceStore.read(movie));
    expect(stored?.subtitleLanguage, 'nld');
  });

  testWidgets('a row runs its action with the panel gone, and the focus comes back to ⋮', (tester) async {
    await pumpDetail(tester, _Client(_movie(), fileInfo: _tracks()));
    await openPanel(tester);
    for (var i = 0; i < _rows(tester).toList().indexOf('fileinfo'); i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }

    await _press(tester, LogicalKeyboardKey.enter);

    expect(find.byType(TvDetailActionPanel), findsNothing);
    expect(find.byType(FileInfoBottomSheet), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(FileInfoBottomSheet), findsNothing);
    expect(_focus, 'detail_more');
  });

  testWidgets('nothing the media menu offers falls off, and Beheren holds what takes rights', (tester) async {
    await pumpDetail(tester, _Client(_movie(backend: MediaBackend.plex), fileInfo: _tracks()), owner: true);
    await openPanel(tester);

    final menuState = tester.state<MediaContextMenuState>(find.byType(MediaContextMenu).first);
    final menu = menuState.menuActions(tester.element(find.byType(MediaContextMenu).first)).map((a) => a.value).toSet();
    expect(menu, containsAll(['delete_media', 'match', 'unmatch']));

    final top = _rows(tester).toSet();
    expect(top, contains('manage'));
    for (var i = 0; i < top.toList().indexOf('manage'); i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.enter);

    expect(find.text('Manage'), findsOneWidget);
    final managed = _rows(tester).toSet();
    expect(managed, containsAll(['match', 'unmatch', 'delete_media']));
    expect(top.union(managed).containsAll(menu), isTrue, reason: '${menu.difference(top.union(managed))}');

    await _press(tester, LogicalKeyboardKey.escape);
    expect(_focus, 'action_row_manage');
  });

  testWidgets('without rights there is no Beheren and nothing of what it holds', (tester) async {
    await pumpDetail(tester, _Client(_movie(backend: MediaBackend.plex), fileInfo: _tracks()));
    await openPanel(tester);

    expect(_rows(tester), isNot(contains('manage')));
    for (final id in ['edit_metadata', 'match', 'unmatch', 'delete_media']) {
      expect(_rows(tester), isNot(contains(id)));
    }
  });

  group('a unified title', () {
    UnifiedMediaRouteContext unified({List<String> sources = const ['server_1:movie', 'server_2:movie']}) =>
        UnifiedMediaRouteContext(
          groupId: 'g',
          identity: CanonicalMediaIdentity.movie(title: 'Puss in Boots', year: 2022),
          sourceKey: 'server_1:movie',
          availableSourceKeys: sources,
          coverage: SourceCoverageState.complete(sources.toSet()),
          intent: UnifiedActivationIntent.details,
        );

    testWidgets('the source is a row with the picker behind it, and the panel goes first', (tester) async {
      final contexts = <BuildContext>[];
      await pumpDetail(
        tester,
        _Client(_movie(), fileInfo: _tracks()),
        unified: unified(),
        onChangeSource: (context) async => contexts.add(context),
      );
      await openPanel(tester);

      expect(_row(tester, 'source').value, 'Server');
      for (var i = 0; i < _rows(tester).toList().indexOf('source'); i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.enter);

      expect(contexts, hasLength(1));
      expect(find.byType(TvDetailActionPanel), findsNothing);
      expect(contexts.single.findAncestorWidgetOfExactType<MediaDetailScreen>(), isNotNull);
    });

    testWidgets('one source is nothing to choose', (tester) async {
      await pumpDetail(
        tester,
        _Client(_movie(), fileInfo: _tracks()),
        unified: unified(sources: const ['server_1:movie']),
        onChangeSource: (_) async {},
      );
      await openPanel(tester);

      expect(_rows(tester), isNot(contains('source')));
    });
  });
}

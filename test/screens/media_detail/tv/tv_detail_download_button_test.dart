/// Android TV keeps the download button on the round row (Apple TV has none),
/// and the row has to say what the download is doing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
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
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/models/download_models.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/loading_indicator_box.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size _panel = Size(1038, 584);

final MediaItem _film = MediaItem(
  id: 'movie',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: 'Toy Story',
  durationMs: 6000000,
  serverId: 'server_1',
  serverName: 'Server',
);

class _Downloads extends ChangeNotifier implements DownloadProvider {
  _Downloads({this.progress, this.queueing = false, this.downloaded = false});

  DownloadProgress? progress;
  final bool queueing;
  final bool downloaded;

  @override
  DownloadProgress? getProgress(String globalKey) => progress;
  @override
  bool isQueueing(String globalKey) => queueing;
  @override
  bool isDownloaded(String globalKey) => downloaded;
  @override
  bool hasSyncRule(String globalKey) => false;
  @override
  String syncRuleKeyForClient(MediaServerClient client, String ratingKey, {ServerId? serverId}) => ratingKey;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MediaServerClient {
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
      (item: _film, onDeckEpisode: null);
  @override
  Future<List<MediaItem>> fetchExtras(String id) async => const [];
  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async => null;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetTVOverride(true);
    TvDetectionService.debugSetAppleTVOverride(false);
  });

  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetTVOverride(null);
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<void> pumpDetail(WidgetTester tester, _Downloads downloads) async {
    tester.view.physicalSize = _panel;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await SettingsService.getInstance();
    final manager = MultiServerManager()..debugRegisterClientForTesting(_Client());
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
          ],
          child: MaterialApp(
            builder: (context, child) => withProfileNavigationScope(
              child: InputModeTracker(
                child: MainScreenFocusScope(
                  focusSidebar: () {},
                  focusContent: () {},
                  isSidebarFocused: false,
                  sideNavigationWidth: 0,
                  child: TvDisplayMetrics(size: _panel, child: withNoticeLayer()(context, child)),
                ),
              ),
            ),
            theme: monoTheme(dark: true),
            home: TvNestedRouteScope(
              dismiss: ([_]) {},
              markResult: (_) {},
              child: MediaDetailScreen(metadata: _film),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  DownloadProgress state(DownloadStatus status, {int progress = 0}) =>
      DownloadProgress(globalKey: _film.globalKey, status: status, progress: progress);

  testWidgets('a running download shows how far it is, and follows along', (tester) async {
    final downloads = _Downloads(progress: state(DownloadStatus.downloading, progress: 40));
    await pumpDetail(tester, downloads);

    double? shown() => tester
        .widgetList<CircularProgressIndicator>(find.byType(CircularProgressIndicator))
        .map((indicator) => indicator.value)
        .firstWhere((value) => value != 1.0);
    expect(shown(), closeTo(0.4, 0.001));
    expect(find.byIcon(Symbols.download_rounded), findsNothing);

    downloads
      ..progress = state(DownloadStatus.downloading, progress: 70)
      ..notifyListeners();
    await tester.pump();
    expect(shown(), closeTo(0.7, 0.001));
  });

  for (final (name, status, icon) in [
    ('queued', DownloadStatus.queued, Symbols.schedule_rounded),
    ('paused', DownloadStatus.paused, Symbols.pause_circle_outline_rounded),
    ('failed', DownloadStatus.failed, Symbols.error_outline_rounded),
    ('cancelled', DownloadStatus.cancelled, Symbols.cancel_rounded),
    ('partial', DownloadStatus.partial, Symbols.downloading_rounded),
  ]) {
    testWidgets('$name has its own icon', (tester) async {
      await pumpDetail(tester, _Downloads(progress: state(status)));

      expect(find.byIcon(icon), findsOneWidget);
    });
  }

  testWidgets('nothing going on is the plain download icon', (tester) async {
    await pumpDetail(tester, _Downloads());

    expect(find.byIcon(Symbols.download_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('building the queue spins, and a press has nothing to do yet', (tester) async {
    await pumpDetail(tester, _Downloads(queueing: true));

    expect(find.byType(LoadingIndicatorBox), findsOneWidget);
    expect(find.byIcon(Symbols.download_rounded), findsNothing);
  });

  testWidgets('a finished download keeps the icon and says it can go', (tester) async {
    await pumpDetail(tester, _Downloads(downloaded: true));

    expect(find.byIcon(Symbols.download_rounded), findsOneWidget);
    expect(find.bySemanticsLabel(t.downloads.deleteDownload), findsOneWidget);
  });
}

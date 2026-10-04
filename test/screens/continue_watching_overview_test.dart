/// The full Verder kijken overview (DEC-144 fase 2, mockups 38 D / 23 / 40):
/// the same projected list, sectioned the same way, on iPhone, desktop and TV.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/continue_watching_hidden_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/screens/home/mobile_continue_watching_screen.dart';
import 'package:pleya/screens/hub_detail_screen.dart';
import 'package:pleya/screens/tv/tv_continue_watching_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';
import 'package:pleya/widgets/tv/tv_view_all_action.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

const _minute = 60 * 1000;
final _now = DateTime.now();
int _secondsAgo(Duration d) => _now.subtract(d).millisecondsSinceEpoch ~/ 1000;

MediaItem _episode(
  String id, {
  required String show,
  int? viewOffsetMs,
  int? lastViewedAt,
  ContinueWatchingKind? kind,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode $id',
  grandparentTitle: show,
  grandparentId: '$show-id',
  parentId: '$show-s1',
  parentIndex: 1,
  index: 2,
  durationMs: 48 * _minute,
  viewOffsetMs: viewOffsetMs,
  lastViewedAt: lastViewedAt,
  continueWatchingKind: kind,
  serverId: 'server_1',
  serverName: 'server_1',
);

MediaItem _movie(String id, {required String title, int? viewOffsetMs, int? lastViewedAt}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  durationMs: 120 * _minute,
  viewOffsetMs: viewOffsetMs,
  lastViewedAt: lastViewedAt,
  continueWatchingKind: ContinueWatchingKind.resume,
  serverId: 'server_1',
  serverName: 'server_1',
);

/// Four items, one per section, plus a next episode of a long-silent series
/// that must not be filed under Eerder begonnen.
final List<MediaItem> _onDeck = [
  _episode(
    'e-resume',
    show: 'The Bear',
    viewOffsetMs: 30 * _minute,
    lastViewedAt: _secondsAgo(const Duration(days: 2)),
    kind: ContinueWatchingKind.resume,
  ),
  _movie(
    'f-resume',
    title: 'Oppenheimer',
    viewOffsetMs: 30 * _minute,
    lastViewedAt: _secondsAgo(const Duration(days: 1)),
  ),
  _episode(
    'e-next',
    show: 'Andor',
    lastViewedAt: _secondsAgo(const Duration(days: 400)),
    kind: ContinueWatchingKind.nextUp,
  ),
  _movie(
    'f-old',
    title: 'Interstellar',
    viewOffsetMs: 20 * _minute,
    lastViewedAt: _secondsAgo(const Duration(days: 300)),
  ),
];

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  @override
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: _onDeck, succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<OnDeckAggregationResult> getLatestShowsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: const <MediaHub>[], succeededServerIds: serverIds ?? const {'server_1'});
}

class _FakeClient implements MediaServerClient {
  @override
  final ServerId serverId = ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider discover;
  late HomeLayoutProvider homeLayout;
  late TvHomeProjectionProvider homeProjection;
  late ContinueWatchingHiddenProvider hidden;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    multiServer = MultiServerProvider(manager, _FakeAggregationService(manager));
    hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    libraries = LibrariesProvider();
    hidden = ContinueWatchingHiddenProvider();
    await hidden.ensureInitialized();
    discover = DiscoverProvider(
      multiServer,
      hiddenLibraries,
      libraries,
      isProfileBinding: () => false,
      hiddenContinueWatching: hidden,
    );
    homeLayout = HomeLayoutProvider();
    homeProjection = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: 'Continue Watching',
      latestMoviesTitle: 'Recently Released',
    );
  });

  tearDown(() {
    homeProjection.dispose();
    homeLayout.dispose();
    discover.dispose();
    hidden.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  Future<void> pump(WidgetTester tester, Widget screen, {Size size = const Size(393, 852)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ChangeNotifierProvider<HomeLayoutProvider>.value(value: homeLayout),
          ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: homeProjection),
          ChangeNotifierProvider<ContinueWatchingHiddenProvider>.value(value: hidden),
        ],
        child: MaterialApp(theme: monoTheme(dark: true), home: screen),
      ),
    );
    await tester.pump();
    await tester.runAsync(discover.load);
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  test('the provider holds the whole list and counts it', () async {
    await discover.load();
    expect(discover.continueWatchingCount, 4);
    expect(discover.allContinueWatching.map((i) => i.id), ['e-resume', 'f-resume', 'e-next', 'f-old']);
    expect(discover.onDeck, hasLength(4), reason: 'four fits the row');
  });

  testWidgets('iPhone: four sections, each item once, Eerder begonnen for the old film only', (tester) async {
    await pump(tester, const MobileContinueWatchingScreen());
    for (final label in ['RESUME SERIES', 'RESUME FILMS', 'NEXT EPISODES', 'STARTED EARLIER']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('The Bear'), findsOneWidget);
    expect(find.text('Oppenheimer'), findsOneWidget);
    expect(find.text('Andor'), findsOneWidget, reason: 'a next episode of a silent series is not old');
    expect(find.text('Interstellar'), findsOneWidget);
    expect(find.textContaining('18min left · 2 days ago'), findsOneWidget);
    expect(find.textContaining('Next episode'), findsOneWidget);
    expect(find.text('4'), findsOneWidget, reason: 'the count beside the title');
  });

  testWidgets('desktop: the hub detail groups Verder kijken into the same sections', (tester) async {
    await pump(
      tester,
      HubDetailScreen(
        hub: MediaHub(
          id: 'cw',
          identifier: '_continue_watching_',
          title: 'Continue Watching · 4',
          type: 'mixed',
          items: _onDeck,
          size: 4,
        ),
        isInContinueWatching: true,
      ),
      size: const Size(1200, 800),
    );
    for (final label in ['Resume series', 'Resume films', 'Next episodes', 'Started earlier']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('S1 E2 · 18min left'), findsOneWidget);
    expect(find.text('S1 E2 · Next episode'), findsOneWidget);
  });

  testWidgets('TV: stacked bands with their counts, and DOWN steps to the next band', (tester) async {
    // Under the shell a content route sits on the shell's Material; the
    // harness stands in for it.
    await pump(tester, const Scaffold(body: TvContinueWatchingScreen()), size: const Size(1038, 584));
    for (final label in ['Resume series', 'Resume films', 'Next episodes', 'Started earlier']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byType(TvUnifiedMediaCard), findsNWidgets(4));

    final first = tester.widget<TvUnifiedMediaCard>(find.byType(TvUnifiedMediaCard).first);
    first.focusNode!.requestFocus();
    await tester.pump();
    expect(first.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final second = tester.widget<TvUnifiedMediaCard>(find.byType(TvUnifiedMediaCard).at(1));
    expect(second.focusNode!.hasFocus, isTrue, reason: 'DOWN off Series hervatten lands on Films hervatten');
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('iPhone: a hidden title leaves its section, is counted under Hidden items, and comes back', (
    tester,
  ) async {
    await pump(tester, const MobileContinueWatchingScreen());
    expect(find.textContaining('Hidden items'), findsNothing, reason: 'no entry while nothing is hidden');

    await tester.runAsync(() => hidden.hide(_onDeck.last));
    await settle(tester);
    expect(find.text('Interstellar'), findsNothing);
    expect(find.text('STARTED EARLIER'), findsNothing, reason: 'an empty section disappears');
    expect(find.text('Hidden items · 1'), findsOneWidget);

    await tester.runAsync(() => hidden.restore(_onDeck.last.globalKey));
    await settle(tester);
    expect(find.text('Interstellar'), findsOneWidget);
    expect(find.textContaining('Hidden items'), findsNothing);
  });

  testWidgets('desktop: the sectioned detail carries the same Hidden items entry', (tester) async {
    await tester.runAsync(() => hidden.hide(_onDeck.last));
    await pump(
      tester,
      HubDetailScreen(
        hub: MediaHub(
          id: 'cw',
          identifier: '_continue_watching_',
          title: 'Continue Watching',
          type: 'mixed',
          items: _onDeck.take(3).toList(),
          size: 3,
        ),
        isInContinueWatching: true,
      ),
      size: const Size(1200, 1000),
    );
    expect(find.text('Hidden items · 1'), findsOneWidget);
  });

  testWidgets('TV: DOWN off the last band lands on Hidden items', (tester) async {
    await tester.runAsync(() => hidden.hide(_onDeck.last));
    await pump(tester, const Scaffold(body: TvContinueWatchingScreen()), size: const Size(1038, 584));
    expect(find.byType(TvUnifiedMediaCard), findsNWidgets(3));
    expect(find.text('Hidden items · 1'), findsOneWidget);

    final last = tester.widget<TvUnifiedMediaCard>(find.byType(TvUnifiedMediaCard).last);
    last.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final action = tester.widget<TvViewAllAction>(find.byType(TvViewAllAction));
    expect(action.focusNode!.hasFocus, isTrue);
  });
}

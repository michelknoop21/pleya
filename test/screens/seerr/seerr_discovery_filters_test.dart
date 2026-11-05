import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_screen.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/seerr/seerr_discover_screen.dart';
import 'package:pleya/screens/tv/tv_seerr_discover_view.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    fake = FakeSeerr();
    for (final route in ['movies', 'tv', 'trending', 'movies/upcoming', 'tv/upcoming']) {
      fake.on('GET /discover/$route', {
        'page': 1,
        'totalPages': 1,
        'results': [
          {'id': 603, 'mediaType': 'movie', 'title': 'Title 603'},
        ],
      });
    }
    fake.on('GET /genres/movie', const []);
    fake.on('GET /genres/tv', const []);
    fake.on('GET /watchproviders/movies', const []);
    fake.on('GET /watchproviders/tv', const []);
    provider = await seerrProvider(fake);
  });

  tearDown(() {
    provider.dispose();
  });

  Future<void> open(WidgetTester tester, Size size) async {
    final pixelRatio = size.width < 600 ? 3.0 : 2.0;
    tester.view.physicalSize = size * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    await pumpSeerr(
      tester,
      provider,
      const SeerrDiscoverScreen(),
      host: TvDetectionService.isTVSync(),
      theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS),
    );
    await seerrSettle(tester);
  }

  Future<void> filters(WidgetTester tester) async {
    final phoneChip = seerrNode(AutomationIds.catalogChipFilters, 'requests');
    if (phoneChip.evaluate().isNotEmpty) {
      await tester.ensureVisible(phoneChip);
      await seerrSettle(tester);
      await tester.tap(phoneChip);
    } else {
      await tester.tap(seerrNode(AutomationIds.catalogChipFilters));
    }
    await seerrSettle(tester);
  }

  Future<void> revealYear(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      seerrNode(AutomationIds.seerrDiscoverFilter, 'year'),
      120,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );
    await seerrSettle(tester);
  }

  for (final size in [const Size(320, 568), const Size(393, 852), const Size(768, 1024), const Size(1024, 768)]) {
    testWidgets('year reaches the discovery backend at $size', (tester) async {
      await open(tester, size);
      await filters(tester);
      if (size.width > 600) {
        await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'kind.movies'));
        await seerrSettle(tester);
      }
      await revealYear(tester);
      await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year'));
      await seerrSettle(tester);
      final year = DateTime.now().year + 10;
      await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year.$year'));
      await seerrSettle(tester);

      final query = fake.sent('GET', '/discover/movies').last.query;
      expect(query['primaryReleaseDateGte'], '$year-01-01');
      expect(query['primaryReleaseDateLte'], '$year-12-31');
      expect(query['sortBy'], 'popularity.desc');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV requests readiness follows the visible loading state', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final held = [
      for (final route in ['movies', 'tv', 'trending', 'movies/upcoming', 'tv/upcoming'])
        fake.hold('GET /discover/$route'),
    ];
    await open(tester, const Size(1920, 1080));
    final screen = find.byWidgetPredicate(
      (widget) => widget is AutomationScreen && widget.id == AutomationIds.screenRequests,
    );
    expect(screen, findsOneWidget);
    expect(tester.widget<TvSeerrDiscoverView>(find.byType(TvSeerrDiscoverView)).isLoading, isTrue);
    expect(tester.widget<AutomationScreen>(screen).readiness().isReady, isFalse);
    for (final response in held) {
      response.complete(
        FakeSeerr.json({
          'page': 1,
          'totalPages': 1,
          'results': [
            {'id': 603, 'mediaType': 'movie', 'title': 'Title 603'},
          ],
        }),
      );
    }
    await seerrSettle(tester);
    expect(tester.widget<TvSeerrDiscoverView>(find.byType(TvSeerrDiscoverView)).isLoading, isFalse);
    expect(tester.widget<AutomationScreen>(screen).readiness().isReady, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small phone filters support large text and reduced motion', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await open(tester, const Size(320, 568));
    await filters(tester);
    final year = seerrNode(AutomationIds.seerrDiscoverFilter, 'year');
    await revealYear(tester);
    await tester.tap(year);
    await seerrSettle(tester);
    expect(seerrNode(AutomationIds.seerrDiscoverFilter, 'year.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the screen keeps the year window when its grid loads the next page', (tester) async {
    fake.routes['GET /discover/movies'] = (request) {
      final page = int.parse(request.url.queryParameters['page']!);
      return FakeSeerr.json({
        'page': page,
        'totalPages': 2,
        'results': [
          {'id': 600 + page, 'mediaType': 'movie', 'title': 'Page $page'},
        ],
      });
    };
    await open(tester, const Size(393, 852));
    await filters(tester);
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year'));
    await seerrSettle(tester);
    final year = DateTime.now().year + 10;
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year.$year'));
    await tester.pumpAndSettle();
    final filtered = fake
        .sent('GET', '/discover/movies')
        .where((call) => call.query.containsKey('primaryReleaseDateGte'));
    expect(filtered.map((call) => call.query['page']), containsAll(['1', '2']));
    for (final call in filtered) {
      expect(call.query['primaryReleaseDateGte'], '$year-01-01');
      expect(call.query['primaryReleaseDateLte'], '$year-12-31');
      expect(call.query['sortBy'], 'popularity.desc');
    }
  });

  testWidgets('a genuinely empty filtered result keeps a way to clear the selection', (tester) async {
    fake.on('GET /discover/movies', {'page': 1, 'totalPages': 1, 'results': []});
    await open(tester, const Size(393, 852));
    await filters(tester);
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year'));
    await seerrSettle(tester);
    final year = DateTime.now().year + 10;
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year.$year'));
    await tester.pumpAndSettle();
    expect(find.text(t.unifiedCatalog.states.filterEmptyTitle), findsOneWidget);
    expect(find.text(t.unifiedCatalog.states.clearFilters), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trending uses its own endpoint and removes unsupported year choices', (tester) async {
    await open(tester, const Size(393, 852));
    await filters(tester);
    final before = fake.sent('GET', '/discover/trending').length;
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'source.trending'));
    await seerrSettle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter));
    await seerrSettle(tester);
    expect(fake.sent('GET', '/discover/trending').length, before + 1);
    expect(fake.sent('GET', '/discover/trending').last.query, {'page': '1'});
    expect(seerrNode(AutomationIds.seerrDiscoverFilter, 'year'), findsNothing);
    expect(seerrNode(AutomationIds.seerrDiscoverFilter, 'sort'), findsNothing);
  });

  testWidgets('rating keeps the selected year and adds a backend vote floor', (tester) async {
    await open(tester, const Size(393, 852));
    await filters(tester);
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year'));
    await seerrSettle(tester);
    final year = DateTime.now().year + 10;
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'year.$year'));
    await seerrSettle(tester);
    await filters(tester);
    await tester.ensureVisible(seerrNode(AutomationIds.seerrDiscoverFilter, 'sort'));
    await seerrSettle(tester);
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'sort'));
    await seerrSettle(tester);
    await tester.tap(find.text(t.libraries.sortLabels.rating));
    await seerrSettle(tester);
    final query = fake.sent('GET', '/discover/movies').last.query;
    expect(query['sortBy'], 'vote_average.desc');
    expect(query['voteCountGte'], '100');
    expect(query['primaryReleaseDateGte'], '$year-01-01');
    expect(query['primaryReleaseDateLte'], '$year-12-31');
    expect(find.textContaining('$year'), findsWidgets);
  });

  testWidgets('upcoming preserves genre, provider and a deliberately chosen rating sort', (tester) async {
    fake.on('GET /genres/movie', [
      {'id': 28, 'name': 'Action'},
    ]);
    fake.on('GET /watchproviders/movies', [
      {'id': 8, 'name': 'Netflix'},
    ]);
    await open(tester, const Size(393, 852));
    await filters(tester);
    await tester.ensureVisible(find.text('Action'));
    await seerrSettle(tester);
    await tester.tap(find.text('Action'));
    await seerrSettle(tester);
    await tester.ensureVisible(find.text('Netflix'));
    await seerrSettle(tester);
    await tester.tap(find.text('Netflix'));
    await seerrSettle(tester);
    final sort = seerrNode(AutomationIds.seerrDiscoverFilter, 'sort');
    await tester.ensureVisible(sort);
    await seerrSettle(tester);
    await tester.tap(sort);
    await seerrSettle(tester);
    await tester.tap(find.text(t.libraries.sortLabels.rating));
    await seerrSettle(tester);
    await filters(tester);
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'source.upcoming'));
    await seerrSettle(tester);
    final query = fake.sent('GET', '/discover/movies').last.query;
    expect(query['genre'], '28');
    expect(query['watchProviders'], '8');
    expect(query['watchRegion'], isNotEmpty);
    expect(query['sortBy'], 'vote_average.desc');
    expect(query['voteCountGte'], '100');
    expect(query['primaryReleaseDateGte'], isNotNull);
  });

  testWidgets('cancelling an incompatible source change preserves the current discovery', (tester) async {
    await open(tester, const Size(393, 852));
    await filters(tester);
    final before = fake.sent('GET', '/discover/trending').length;
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'source.trending'));
    await seerrSettle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(t.common.cancel)));
    await seerrSettle(tester);
    expect(fake.sent('GET', '/discover/trending').length, before);
    expect(seerrNode(AutomationIds.seerrDiscoverFilter, 'year'), findsOneWidget);
  });

  testWidgets('upcoming sends future movie dates and preserves explicit popularity sorting', (tester) async {
    await open(tester, const Size(393, 852));
    await tester.ensureVisible(seerrNode(AutomationIds.catalogChipSort, 'requests'));
    await seerrSettle(tester);
    await tester.tap(seerrNode(AutomationIds.catalogChipSort, 'requests'));
    await seerrSettle(tester);
    await tester.tap(find.text(t.libraries.sortLabels.rating));
    await seerrSettle(tester);
    await tester.ensureVisible(seerrNode(AutomationIds.catalogChipSort, 'requests'));
    await seerrSettle(tester);
    await tester.tap(seerrNode(AutomationIds.catalogChipSort, 'requests'));
    await seerrSettle(tester);
    await tester.tap(find.text(t.seerr.popularMovies));
    await seerrSettle(tester);
    await filters(tester);
    await tester.tap(seerrNode(AutomationIds.seerrDiscoverFilter, 'source.upcoming'));
    await seerrSettle(tester);
    final query = fake.sent('GET', '/discover/movies').last.query;
    final from = DateTime.parse(query['primaryReleaseDateGte']!);
    final now = DateTime.now();
    expect(from.isAfter(DateTime(now.year, now.month, now.day)), isTrue);
    expect(query['sortBy'], 'popularity.desc');

    final clear = seerrNode(AutomationIds.seerrDiscoverFilter, 'clear');
    await tester.ensureVisible(clear);
    await seerrSettle(tester);
    await tester.tap(clear);
    await seerrSettle(tester);
    final reset = fake.sent('GET', '/discover/movies').last.query;
    expect(reset.containsKey('primaryReleaseDateGte'), isFalse);
    expect(reset.containsKey('primaryReleaseDateLte'), isFalse);
    expect(reset['sortBy'], 'popularity.desc');
  });
}

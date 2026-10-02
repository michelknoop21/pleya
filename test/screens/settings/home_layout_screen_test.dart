import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/screens/settings/home_layout_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _verifyOn = bool.fromEnvironment('PLEYA_VERIFY');

class _DiscoverRows extends ChangeNotifier implements DiscoverProvider {
  @override
  List<MediaHub> get hubs => const [
    MediaHub(
      id: 'films',
      identifier: 'recent.movies',
      title: 'Recent toegevoegd',
      type: 'movie',
      items: [],
      serverId: 'zolder',
      serverName: 'Zolder',
    ),
    MediaHub(
      id: 'series',
      identifier: 'recent.shows',
      title: 'Recent toegevoegd',
      type: 'show',
      items: [],
      serverId: 'zolder',
      serverName: 'Zolder',
    ),
    MediaHub(
      id: 'latest-shows',
      identifier: 'home.latestshows',
      title: 'Recent toegevoegde series',
      type: 'show',
      items: [],
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('TV-kop en rijacties blijven binnen de veilige paginamarge', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    resetSharedPreferencesForTest();
    final layout = HomeLayoutProvider();
    await layout.ensureInitialized();
    addTearDown(layout.dispose);
    final discover = _DiscoverRows();
    addTearDown(discover.dispose);

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ],
          child: MaterialApp(theme: monoTheme(dark: true), home: const HomeLayoutScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getRect(find.text(t.settings.homeLayout)).left, greaterThanOrEqualTo(48));
    expect(tester.getRect(find.byType(Switch).first).right, lessThanOrEqualTo(1920 - 48));
    if (_verifyOn) {
      final declared = AutomationRegistry.instance.snapshot()['declared'] as List<dynamic>;
      expect(declared.where((node) => node['id'] == 'my_pleya.section.content[home_layout]'), hasLength(1));
    }
  });

  testWidgets('gelijke rijtitels tonen films en series als afzonderlijke context', (tester) async {
    resetSharedPreferencesForTest();
    final layout = HomeLayoutProvider();
    await layout.ensureInitialized();
    addTearDown(layout.dispose);
    final discover = _DiscoverRows();
    addTearDown(discover.dispose);

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ],
          child: const MaterialApp(home: HomeLayoutScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recent toegevoegd'), findsNWidgets(2));
    expect(find.text('${t.search.filters.movies} · Zolder'), findsOneWidget);
    expect(find.text('${t.search.filters.shows} · Zolder'), findsOneWidget);
    expect(find.text(t.search.filters.shows), findsNothing);
  });
}

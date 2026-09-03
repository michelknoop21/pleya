/// `watch-together-a`: Samen Kijken's not-in-session page on TV.
///
/// The failure this guards is specific and was measured, not guessed. The TV
/// branch was first written inside `_NotInSessionView`, which
/// `WatchTogetherScreen` mounts through `SliverFillRemaining` — so a
/// `TvPageSurface`, being a `SingleChildScrollView`, ended up nested inside the
/// scaffold's own scrollable and was laid out with no height at all. The
/// evidence was unambiguous: the section's node was registered in
/// `/v1/ui_tree` and reported no bounds. The branch therefore lives in
/// `WatchTogetherScreen.build`, above the sliver scaffold, and the first test
/// below is what keeps it there: it fails with a zero-height surface exactly
/// the way the simulator did.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/watch_together/screens/watch_together_screen.dart';
import 'package:pleya/widgets/focused_scroll_scaffold.dart';
import 'package:pleya/widgets/tv/tv_menu_grid.dart';
import 'package:pleya/widgets/tv/tv_page_surface.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpScreen(WidgetTester tester, {required bool tv}) async {
    TvDetectionService.debugSetAppleTVOverride(tv);
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider<WatchTogetherProvider>(create: (_) => WatchTogetherProvider())],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: const WatchTogetherScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('on TV the page is the scroll, and it has a height', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpScreen(tester, tv: true);

    // The shell's sliver scaffold is not built at all: that is the whole point
    // of branching above it rather than inside the view.
    expect(find.byType(FocusedScrollScaffold), findsNothing);

    final surface = find.byType(TvPageSurface);
    expect(surface, findsOneWidget);

    // The regression itself. A `TvPageSurface` under `SliverFillRemaining`
    // laid out at zero, and the tiles inside it were registered with no
    // bounds — visible in the tree, unreachable on the remote.
    final size = tester.getSize(surface);
    expect(size.height, greaterThan(0));
    expect(size.width, greaterThan(0));

    for (final tile in tester.widgetList<TvMenuTile>(find.byType(TvMenuTile))) {
      expect(tester.getSize(find.byWidget(tile)).height, greaterThan(0), reason: tile.item.key);
    }
  });

  testWidgets('the two actions are tiles, and the empty state says what goes there', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpScreen(tester, tv: true);

    final keys = tester.widgetList<TvMenuTile>(find.byType(TvMenuTile)).map((t) => t.item.key).toList();
    expect(keys, containsAll(<String>['watch_together_create', 'watch_together_join']));

    expect(find.text(t.watchTogether.createSessionHint), findsOneWidget);
    expect(find.text(t.watchTogether.joinSessionHint), findsOneWidget);

    // With no saved rooms the page still ends in something readable rather
    // than in nothing.
    expect(find.text(t.watchTogether.noRecentRooms), findsOneWidget);
    expect(find.text(t.watchTogether.noRecentRoomsHint), findsOneWidget);

    // And the second, centred heading the audit measured is gone: the page
    // heading is the only place the title appears.
    expect(find.text(t.watchTogether.title), findsOneWidget);
  });

  testWidgets('off TV nothing changes: the sliver scaffold is still the page', (tester) async {
    await pumpScreen(tester, tv: false);

    expect(find.byType(FocusedScrollScaffold), findsOneWidget);
    expect(find.byType(TvPageSurface), findsNothing);
  });
}

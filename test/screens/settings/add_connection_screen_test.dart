import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/screens/settings/add_connection_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_menu_grid.dart';

void main() {
  testWidgets('TV-picker toont alle zes bestaande routes in het gedeelde raster', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final profile = Profile.local(id: 'owner', displayName: 'Michel', createdAt: DateTime(2026));

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: AddConnectionScreen(targetProfile: profile),
        ),
      ),
    );
    await tester.pump();

    final grid = tester.widget<TvMenuGrid>(find.byType(TvMenuGrid));
    expect(grid.columns, 2);
    expect(grid.keys, ['plex', 'jellyfin', 'pleya_server', 'local_folder', 'pleya_share', 'borrow']);
    expect(find.text(t.addServer.addConnectionTitle), findsOneWidget);
    expect(find.text(t.addServer.borrowFromAnotherProfile), findsOneWidget);
  });

  testWidgets('zonder doelprofiel blijven de vijf globale routes beschikbaar', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(theme: monoTheme(dark: true), home: const AddConnectionScreen()),
      ),
    );
    final grid = tester.widget<TvMenuGrid>(find.byType(TvMenuGrid));
    expect(grid.keys, ['plex', 'jellyfin', 'pleya_server', 'local_folder', 'pleya_share']);
    expect(find.text(t.addServer.borrowFromAnotherProfile), findsNothing);
  });

  testWidgets('pointerplatform houdt de bestaande lijstpresentatie', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(theme: monoTheme(dark: true), home: const AddConnectionScreen()),
      ),
    );
    expect(find.byType(TvMenuGrid), findsNothing);
    expect(find.text(t.addServer.signInWithPlexCard), findsOneWidget);
  });

  testWidgets('geslaagde onderliggende route sluit de TV-picker via zijn eigen scope', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    Object? result;

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: navigator,
          theme: monoTheme(dark: true),
          home: TvNestedRouteScope(
            dismiss: ([value]) => result = value,
            markResult: (_) {},
            child: const AddConnectionScreen(),
          ),
        ),
      ),
    );

    final grid = tester.widget<TvMenuGrid>(find.byType(TvMenuGrid));
    grid.sections.single.items.first.onSelect!();
    navigator.currentState!.pop(true);
    await tester.pump();
    expect(result, true);
  });
}

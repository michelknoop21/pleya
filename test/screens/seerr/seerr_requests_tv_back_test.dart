/// Menu on Alle aanvragen and Mijn aanvragen on TV. The page is a pushed route
/// above the shell, so nothing but the page itself can close it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

void main() {
  setUp(() async {
    TvDetectionService.debugSetAppleTVOverride(true);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> openPushed(WidgetTester tester, {List<Map<String, dynamic>>? rows}) async {
    final fake = FakeSeerr()
      ..on('GET /request', seerrPage(rows ?? [seerrRequestJson(1), seerrRequestJson(2)]))
      ..on('GET /request/count', {'total': 2, 'pending': 2, 'approved': 0, 'available': 5});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = await seerrProvider(fake, userId: 7, permissions: seerrPermRequest);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeerrRequestsScreen())),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await seerrSettle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(SeerrRequestsScreen), findsOneWidget);
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  testWidgets('Menu on a request card closes the page', (tester) async {
    await openPushed(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrRequestCard(1)');

    await menu(tester);

    expect(find.byType(SeerrRequestsScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('with the rail open Menu closes the rail first, and the next one closes the page', (tester) async {
    await openPushed(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);

    await menu(tester);
    expect(find.byKey(tvCatalogFilterRailKey), findsNothing);
    expect(find.byType(SeerrRequestsScreen), findsOneWidget, reason: 'one layer per press');

    await menu(tester);
    expect(find.byType(SeerrRequestsScreen), findsNothing);
  });

  testWidgets('Menu on the action of an empty list closes the page', (tester) async {
    await openPushed(tester, rows: const []);

    await menu(tester);

    expect(find.byType(SeerrRequestsScreen), findsNothing);
  });
}

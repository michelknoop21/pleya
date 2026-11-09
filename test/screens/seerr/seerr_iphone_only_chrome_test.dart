/// The compact request list and the own-chrome title page belong to the
/// iPhone. An iPad keeps the inline approve/decline buttons and the standard
/// app bar; the title page there still has its bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/screens/seerr/seerr_media_detail_screen.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/desktop_app_bar.dart';
import 'package:pleya/widgets/seerr_request_row.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

void main() {
  late FakeSeerr fake;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    fake = FakeSeerr()
      ..on('GET /request', seerrPage([seerrRequestJson(1), seerrRequestJson(2, requestedBy: 9)]))
      ..on('GET /request/count', {'total': 2, 'pending': 2, 'approved': 0, 'available': 5})
      ..on('GET /movie/603', {
        'id': 603,
        'title': 'Charge',
        'mediaInfo': {'status': 1, 'requests': []},
      })
      ..on('GET /movie/603/recommendations', {'results': []});
  });

  // Physical size and ratio, so the logical size reads as the device does.
  const iphone = (Size(1170, 2532), 3.0);
  const ipad = (Size(2048, 2732), 2.0);

  Future<void> pump(WidgetTester tester, (Size, double) device, Widget Function() screen) async {
    tester.view.physicalSize = device.$1;
    tester.view.devicePixelRatio = device.$2;
    addTearDown(tester.view.reset);
    final provider = await seerrProvider(fake, userId: 7, permissions: seerrPermManage);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      screen(),
      host: false,
      theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS),
    );
    await seerrSettle(tester);
  }

  Widget requests() => const SeerrRequestsScreen();
  Widget detail() => SeerrMediaDetailScreen(
    media: SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge'),
  );

  testWidgets('an iPad request row keeps the inline approve button for a manager', (tester) async {
    await pump(tester, ipad, requests);
    final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();
    expect(rows.last.onApprove, isNotNull);
  });

  testWidgets('an iPhone request row moves the actions into the sheet', (tester) async {
    await pump(tester, iphone, requests);
    final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();
    expect(rows.last.onApprove, isNull);
    expect(rows.last.onMore, isNotNull);
  });

  testWidgets('the title page keeps its app bar on an iPad', (tester) async {
    await pump(tester, ipad, detail);
    expect(find.byType(CustomAppBar), findsOneWidget);
  });

  testWidgets('the title page has no standard app bar on an iPhone', (tester) async {
    await pump(tester, iphone, detail);
    expect(find.byType(CustomAppBar), findsNothing);
  });

  testWidgets('the Mac container is no iPhone, also in a phone-sized window', (tester) async {
    TvDetectionService.debugSetIOSAppOnMacOverride(true);
    addTearDown(() => TvDetectionService.debugSetIOSAppOnMacOverride(null));
    await pump(tester, iphone, detail);
    expect(find.byType(CustomAppBar), findsOneWidget);
  });
}

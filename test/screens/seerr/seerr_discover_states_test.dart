/// Ontdekken mounted whole against a scripted Seerr (Requests 2.0, family 1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_screen.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/seerr/seerr_discover_screen.dart';
import 'package:pleya/screens/seerr/seerr_media_detail_screen.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/widgets/seerr_poster_card.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;

  Map<String, dynamic> page(List<int> ids) => {
    'page': 1,
    'totalPages': 1,
    'results': [
      for (final id in ids) {'id': id, 'mediaType': 'movie', 'title': 'Title $id'},
    ],
  };

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    fake = FakeSeerr()
      ..on('GET /discover/trending', page([603]))
      ..on('GET /discover/movies', page(const []))
      ..on('GET /discover/tv', page(const []))
      ..on('GET /discover/movies/upcoming', page(const []))
      ..on('GET /watchproviders/movies', const [])
      ..on('GET /movie/603/recommendations', page(const []));
  });

  Future<void> open(WidgetTester tester, {MemorySeerrStore? store}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake, store: store);
    addTearDown(provider.dispose);
    await pumpSeerr(tester, provider, const SeerrDiscoverScreen(), host: false);
    await seerrSettle(tester);
  }

  SeerrPosterCard card(WidgetTester tester) => tester.widget<SeerrPosterCard>(find.byType(SeerrPosterCard).first);

  testWidgets('without a requests server there is nothing to retry, only something to set up', (tester) async {
    provider = SeerrProvider(httpClient: fake.client, store: MemorySeerrStore());
    addTearDown(provider.dispose);
    await pumpSeerr(tester, provider, const SeerrDiscoverScreen(), host: false);
    await tester.pump();

    expect(find.text(t.seerr.notConfigured), findsOneWidget);
    expect(find.text(t.seerr.setUp), findsOneWidget);
    expect(find.text(t.common.retry), findsNothing);
    expect(fake.calls, isEmpty);
  });

  testWidgets('coming back from a title, its card says what the title page learned', (tester) async {
    fake.on('GET /movie/603', {
      'id': 603,
      'title': 'Title 603',
      'mediaInfo': {'status': 2},
    });
    await open(tester);
    expect(card(tester).media.status, SeerrMediaStatus.unknown);

    await tester.tap(find.byType(SeerrPosterCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(SeerrMediaDetailScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(SeerrMediaDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SeerrMediaDetailScreen), findsNothing);
    expect(card(tester).media.tmdbId, 603);
    expect(card(tester).media.status, SeerrMediaStatus.pending);
  });

  testWidgets('a profile switch drops what the old account loaded and asks again', (tester) async {
    final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
    final slow = fake.hold('GET /discover/trending');
    await open(tester, store: store);

    fake.on('GET /discover/trending', page([777]));
    await provider.onActiveProfileChanged('user-2');
    await seerrSettle(tester);
    slow.complete(FakeSeerr.json(page([603])));
    await seerrSettle(tester);

    expect(card(tester).media.tmdbId, 777);
    expect(find.text('Title 603'), findsNothing);
  });
  testWidgets('desktop requests automation follows actual loading and opens the inbox', (tester) async {
    final slow = fake.hold('GET /discover/trending');
    await open(tester);
    final screen = find.byWidgetPredicate(
      (widget) => widget is AutomationScreen && widget.id == AutomationIds.screenRequests,
    );
    expect(screen, findsOneWidget);
    expect(tester.widget<AutomationScreen>(screen).readiness().state, AutomationReadinessState.loading);
    slow.complete(FakeSeerr.json(page([603])));
    await seerrSettle(tester);
    expect(tester.widget<AutomationScreen>(screen).readiness().isReady, isTrue);
    final inbox = seerrNode(AutomationIds.seerrSearchInbox);
    expect(inbox, findsOneWidget);
    await tester.tap(inbox);
    await seerrSettle(tester);
    expect(find.byType(SeerrRequestsScreen), findsOneWidget);
  });
}

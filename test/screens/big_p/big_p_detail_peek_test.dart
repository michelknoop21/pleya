import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/automation/automation_route_observer.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/navigation/profile_navigation_scope.dart';
import 'package:pleya/screens/big_p/big_p_detail_peek.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/big_p/fake_assistant_controller.dart';
import 'big_p_mobile_fixtures.dart';

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;
  late GlobalKey<NavigatorState> nav;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = FakeAssistantController();
    answerLibraryTitles(c);
    session = BigPMobileSession(c);
    nav = GlobalKey<NavigatorState>();
    addTearDown(() {
      session.dispose();
      c.dispose();
    });
  });

  /// The profile navigator as ProfileSessionScreen builds it: its observer
  /// in the scope, Home with the host as the first route.
  Future<void> pump(WidgetTester tester, {bool withSession = true}) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final observer = AutomationRouteObserver();
    final app = MaterialApp(
      theme: monoTheme(dark: true),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: ProfileNavigationScope(
            navigatorKey: nav,
            routeObserver: observer,
            mainScaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
            child: Navigator(
              key: nav,
              observers: [observer],
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Stack(
                  fit: StackFit.expand,
                  children: [
                    Scaffold(body: Text('home')),
                    BigPMobileHost(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: withSession ? ChangeNotifierProvider<BigPMobileSession>.value(value: session, child: app) : app,
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// What the host's _openTitle does, with the route mediaDetailRoute builds
  /// off TV around a stand-in page.
  Future<void> openSintel(WidgetTester tester) async {
    session.openedTitle(nasTarget('s', 'Sintel', 2010).item.globalKey);
    nav.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => const Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(body: Text('detail')),
            BigPDetailPeek(),
          ],
        ),
      ),
    );
    await settle(tester);
  }

  String peekText(int n) => t.assistant.mobile.moreTitles(n: n);

  test('mediaDetailRoute puts the peek over the page off TV', () {
    final route = mediaDetailRoute(
      metadata: MediaItem(id: 's', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel'),
    );
    final page = (route as MaterialPageRoute<bool>).builder(_NoContext());
    expect(page, isA<Stack>());
    expect((page as Stack).children.last, isA<BigPDetailPeek>());
  });

  testWidgets('after opening, the peek is on the detail route with the titles left', (tester) async {
    await pump(tester);
    await openSintel(tester);
    expect(session.stage, BigPStage.peek);
    expect(find.text('detail'), findsOneWidget);
    expect(peekText(2), 'Nog 2 titels');
    expect(find.text(peekText(2)), findsOneWidget);
  });

  testWidgets('back to the first route parks Big P and keeps the answer', (tester) async {
    await pump(tester);
    await openSintel(tester);
    nav.currentState!.pop();
    await settle(tester);
    expect(session.stage, BigPStage.parked);
    expect(c.state, AssistantSurfaceState.result);
    expect(c.displays, hasLength(1));
    expect(session.remainingTitles, 2);
    expect(find.text(peekText(2)), findsNothing);
  });

  testWidgets('a tap on the peek pops and opens the balloon with the same answer', (tester) async {
    await pump(tester);
    final displays = c.displays;
    await openSintel(tester);
    await tester.tap(find.text(peekText(2)));
    await settle(tester);
    expect(find.text('detail'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(session.stage, BigPStage.out);
    expect(c.resets, 0);
    expect(c.displays, same(displays));
    expect(find.byKey(const ValueKey('bigp-dim')), findsOneWidget);
    expect(find.text('Drie nog niet.'), findsOneWidget);
  });

  testWidgets('a route over the detail page (the player) hides the peek', (tester) async {
    await pump(tester);
    await openSintel(tester);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ColoredBox(color: Colors.black)));
    await settle(tester);
    expect(find.text(peekText(2)), findsNothing);
    expect(session.stage, BigPStage.peek);
  });

  testWidgets('without a session there is no peek', (tester) async {
    await pump(tester, withSession: false);
    await openSintel(tester);
    expect(find.text('detail'), findsOneWidget);
    expect(find.byType(BigPDetailPeek), findsOneWidget);
    expect(find.text(peekText(2)), findsNothing);
  });
}

/// The route builder ignores its context.
class _NoContext extends Fake implements BuildContext {}

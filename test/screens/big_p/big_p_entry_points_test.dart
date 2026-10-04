// The ways to summon Big P on iPhone and iPad besides the face button: the
// My Pleya tile, "Vraag het Big P" in Zoeken and a long-press on a library,
// plus the settings row where the model is chosen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/big_p/big_p_ask_row.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/screens/libraries/mobile_libraries_screen.dart';
import 'package:pleya/screens/my_pleya_screen.dart';
import 'package:pleya/screens/search_screen.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_navigation_helper.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/widgets/big_p/big_p_portrait.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import '../../widgets/big_p/fake_assistant_controller.dart';
import 'big_p_mobile_fixtures.dart';

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await StorageService.getInstance();
    await SettingsService.getInstance();
    c = FakeAssistantController();
    session = BigPMobileSession(c);
    addTearDown(() {
      session.dispose();
      c.dispose();
    });
  });

  /// As ProfileSessionScreen provides them: the controller, and on iPhone
  /// and iPad the session beside it.
  Widget withBigP(Widget child, {bool withSession = true}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AssistantController>.value(value: c),
      if (withSession) ChangeNotifierProvider<BigPMobileSession>.value(value: session),
    ],
    child: child,
  );

  /// A phone: `PlatformDetector.isPhone` reads the real viewport.
  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    addTearDown(tester.view.reset);
  }

  group('My Pleya', () {
    Future<void> pump(WidgetTester tester, {bool withSession = true}) async {
      phone(tester);
      await tester.pumpWidget(
        TranslationProvider(
          child: withBigP(
            MaterialApp(
              theme: monoTheme(dark: true),
              home: MyPleyaScreen(onOpenTab: (_) {}),
            ),
            withSession: withSession,
          ),
        ),
      );
      await tester.pump();
    }

    Finder tile() => find.byWidgetPredicate(
      (w) => w is AutomationNode && w.id == AutomationIds.myPleyaTile && w.instance == 'assistant',
    );

    testWidgets('the tile is there only while Big P is available, and asks once as it shows', (tester) async {
      c.availability = AssistantAvailability.hidden;
      await pump(tester);
      expect(c.refreshes, 1);
      expect(tile(), findsNothing);

      c
        ..availability = AssistantAvailability.ready
        ..emit();
      await tester.pump();
      expect(tile(), findsOneWidget);
      expect(find.descendant(of: tile(), matching: find.byType(BigPPortrait)), findsOneWidget);
      expect(c.refreshes, 1, reason: 'once on appear, not per build');

      await tester.tap(tile());
      expect(session.stage, BigPStage.out);
      expect(session.pendingContext, isNull);
    });

    testWidgets('no session (not iPhone or iPad): no tile', (tester) async {
      await pump(tester, withSession: false);
      expect(tile(), findsNothing);
    });
  });

  group('Zoeken', () {
    Future<GlobalKey<State<SearchScreen>>> pump(WidgetTester tester) async {
      phone(tester);
      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(
          FakeSearchServer([
            MediaItem(
              id: 'dune',
              backend: MediaBackend.plex,
              kind: MediaKind.movie,
              title: 'Dune',
              serverId: 'nas',
              serverName: 'NAS',
            ),
          ]),
        );
      final servers = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(servers.dispose);
      final hidden = HiddenLibrariesProvider();
      addTearDown(hidden.dispose);
      final key = GlobalKey<State<SearchScreen>>();
      await tester.pumpWidget(
        TranslationProvider(
          child: withBigP(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
                ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
              ],
              child: MaterialApp(
                theme: monoTheme(dark: true),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(disableAnimations: true),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SearchScreen(key: key),
                        const BigPMobileHost(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return key;
    }

    Future<void> search(WidgetTester tester, GlobalKey<State<SearchScreen>> key, String query) async {
      (key.currentState! as SearchInputFocusable).setSearchQuery(query);
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();
    }

    testWidgets('the row hands the query over and the host asks it at once', (tester) async {
      final key = await pump(tester);
      await search(tester, key, 'dune');
      expect(find.text('Dune'), findsOneWidget);
      expect(find.byType(BigPAskRow), findsOneWidget);
      expect(find.text(t.assistant.mobile.searchAsk), findsOneWidget);
      expect(find.descendant(of: find.byType(BigPAskRow), matching: find.text('dune')), findsOneWidget);

      await tester.tap(find.byType(BigPAskRow));
      await tester.pump();
      await tester.pump();
      expect(session.stage, BigPStage.out);
      expect(c.submitted, ['dune']);
      expect(session.takeQuestion(), isNull, reason: 'asked once');
    });

    testWidgets('hidden: no row', (tester) async {
      c.availability = AssistantAvailability.hidden;
      final key = await pump(tester);
      await search(tester, key, 'dune');
      expect(find.text('Dune'), findsOneWidget);
      expect(find.byType(BigPAskRow), findsNothing);
    });

    testWidgets('not set up: Big P comes out but the question is not sent', (tester) async {
      c.availability = AssistantAvailability.needsSetup;
      final key = await pump(tester);
      await search(tester, key, 'dune');
      await tester.tap(find.byType(BigPAskRow));
      await tester.pump();
      await tester.pump();
      expect(session.stage, BigPStage.out);
      expect(c.submitted, isEmpty);
    });
  });

  group('Bibliotheken', () {
    Future<void> pump(WidgetTester tester, List<MediaLibrary> fixture) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late LibrariesProvider libraries;
      late HiddenLibrariesProvider hidden;
      await tester.runAsync(() async {
        libraries = LibrariesProvider();
        hidden = HiddenLibrariesProvider();
        await libraries.updateLibraryOrder(fixture);
      });
      addTearDown(libraries.dispose);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: withBigP(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
                ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
              ],
              child: MaterialApp(
                theme: monoTheme(dark: true),
                home: MobileLibrariesScreen(onBack: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    MediaLibrary films({String? serverId = 'nas'}) => MediaLibrary(
      id: '7',
      backend: MediaBackend.plex,
      title: 'Films',
      kind: MediaKind.movie,
      serverId: serverId,
      serverName: 'NAS',
    );

    testWidgets('a long-press summons Big P with this library as context', (tester) async {
      await pump(tester, [films()]);
      await tester.longPress(find.text('Films'));
      expect(session.stage, BigPStage.out);
      expect(session.pendingContext?.serverId, 'nas');
      expect(session.pendingContext?.libraryId, '7');
    });

    testWidgets('a library without a server: no long-press', (tester) async {
      await pump(tester, [films(serverId: null)]);
      await tester.longPress(find.text('Films'));
      expect(session.stage, BigPStage.parked);
    });

    testWidgets('Big P hidden: no long-press', (tester) async {
      c.availability = AssistantAvailability.hidden;
      await pump(tester, [films()]);
      await tester.longPress(find.text('Films'));
      expect(session.stage, BigPStage.parked);
    });
  });

  group('Instellingen', () {
    testWidgets('the Big P row exists only with the rollout flag and opens the model settings', (tester) async {
      expect(assistantSettingsTile(rolloutEnabled: false), isNull);
      final routes = <Route<dynamic>>[];
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            navigatorObservers: [_Pushes(routes)],
            home: Scaffold(body: assistantSettingsTile(rolloutEnabled: true)),
          ),
        ),
      );
      expect(find.text(t.assistant.tileTitle), findsOneWidget);
      routes.clear();
      await tester.tap(find.text(t.assistant.tileTitle));
      expect(routes.single, isA<MaterialPageRoute<dynamic>>());
      final page = (routes.single as MaterialPageRoute<dynamic>).builder(tester.element(find.byType(Scaffold).first));
      expect(page, isA<AssistantSettingsScreen>());
    });
  });

  group('a title from the answer', () {
    testWidgets('that pushes nothing parks Big P instead of leaving an unseen peek', (tester) async {
      final opened = <MediaItem>[];
      BigPMobileHost.openDetails = (context, item) async {
        opened.add(item);
        return MediaNavigationResult.unsupported;
      };
      addTearDown(() => BigPMobileHost.openDetails = navigateToMediaItemDetails);
      answerLibraryTitles(c);
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TranslationProvider(
          child: withBigP(
            MaterialApp(
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: const Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
                ),
              ),
            ),
          ),
        ),
      );
      session.summon();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(BigPMatchCard, 'Sintel'));
      await tester.pump();
      expect(opened.single.title, 'Sintel');
      expect(session.stage, BigPStage.parked);
      expect(c.answer, isNotEmpty, reason: 'the answer stays for the next summon');
    });

    testWidgets('that opens a page keeps the peek while it is open', (tester) async {
      final done = <void Function()>[];
      BigPMobileHost.openDetails = (context, item) {
        final route = MaterialPageRoute<void>(builder: (_) => const Scaffold());
        done.add(() => Navigator.of(context).removeRoute(route));
        return Navigator.of(context).push(route).then((_) => MediaNavigationResult.navigated);
      };
      addTearDown(() => BigPMobileHost.openDetails = navigateToMediaItemDetails);
      answerLibraryTitles(c);
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TranslationProvider(
          child: withBigP(
            MaterialApp(
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: const Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
                ),
              ),
            ),
          ),
        ),
      );
      session.summon();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(BigPMatchCard, 'Sintel'));
      await tester.pumpAndSettle();
      expect(session.stage, BigPStage.peek);
    });
  });
}

class _Pushes extends NavigatorObserver {
  _Pushes(this.routes);

  final List<Route<dynamic>> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route);
}

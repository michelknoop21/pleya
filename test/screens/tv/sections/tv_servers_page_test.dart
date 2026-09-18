/// SYS-1e: Mijn Pleya ▸ Servers stays inside the TV shell.
///
/// Same defect as SYS-1d and the "Over" ▸ Licenties tile: `TvServersPage` is
/// mounted through `tvMyPleyaNestedRoute`, which has no `Navigator` of its
/// own, so a bare `Navigator.push` from either "Add connection" or "Pleya
/// Share" resolves to the profile navigator above the shell and draws over
/// `TvTopNavigation` entirely.
///
/// Pumped against the production `TvRootShell` and `TvTopNavigation`, the same
/// harness `tv_libraries_screen_test.dart` uses for the SYS-1d fix.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/tv/sections/tv_servers_page.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

import '../../../test_helpers/prefs.dart';

/// A registry whose stream is an ordinary one — see `connections_section_test`
/// for why: a drift query stream needs a real event loop `testWidgets`'s
/// fake-async zone never turns.
class _SeededRegistry extends ConnectionRegistry {
  _SeededRegistry(super.db, this._seed);

  final List<Connection> _seed;

  @override
  Stream<List<Connection>> watchConnections() => Stream<List<Connection>>.value(_seed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('SYS-1e: opening a server action from Servers keeps the TV shell mounted', () {
    late AppDatabase db;
    late ActiveProfileProvider activeProfile;
    late PlexHomeService plexHome;
    late MultiServerManager manager;
    late MultiServerProvider multiServer;
    late TvNavigationCoordinator coordinator;
    late FocusMemoryTracker navNodes;
    late FocusScopeNode navScope;
    late FocusScopeNode contentScope;

    setUp(() async {
      resetSharedPreferencesForTest();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final connections = ConnectionRegistry(db);
      final profileConnections = ProfileConnectionRegistry(db);
      final storage = await StorageService.getInstance();
      plexHome = PlexHomeService(
        connections: connections,
        profileConnections: profileConnections,
        storage: storage,
        plexHomeUserFetcher: (_) async => const [],
      );
      activeProfile = ActiveProfileProvider(
        registry: ProfileRegistry(db),
        plexHome: plexHome,
        connections: connections,
        storage: storage,
      );
      manager = MultiServerManager();
      multiServer = MultiServerProvider(manager, DataAggregationService(manager));
      coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
      navNodes = FocusMemoryTracker(debugLabelPrefix: 'sys1eNav');
      navScope = FocusScopeNode(debugLabel: 'nav');
      contentScope = FocusScopeNode(debugLabel: 'content');
    });

    tearDown(() async {
      multiServer.dispose();
      await activeProfile.resetForTesting();
      activeProfile.dispose();
      await plexHome.dispose();
      await db.close();
      coordinator.dispose();
      navNodes.dispose();
      navScope.dispose();
      contentScope.dispose();
    });

    Future<Object?> pushViaRegistry(TvNestedRoute route) {
      final destination = coordinator.active;
      return coordinator.pushNested(destination, route).result;
    }

    Future<void> pumpInShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final registry = _SeededRegistry(db, const []);
      tvContentRouteRegistry.attach(pushViaRegistry);
      addTearDown(() => tvContentRouteRegistry.detach(pushViaRegistry));

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              Provider<ConnectionRegistry>.value(value: registry),
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: InputModeTracker(
                child: TvRootShell(
                  coordinator: coordinator,
                  contentFocus: TvContentFocusAuthority(),
                  navNodes: navNodes,
                  navFocusScope: navScope,
                  contentFocusScope: contentScope,
                  isNavFocused: false,
                  profile: null,
                  onSelectDestination: (_) {},
                  onFocusDestination: coordinator.activate,
                  onFocusContent: ({bool restorePreviousFocus = true}) {},
                  onFocusNav: () {},
                  onOpenProfiles: () {},
                  onOverlaySheetOpenChanged: (_) {},
                  onKeyEvent: (_) => KeyEventResult.ignored,
                  selectLibrary: null,
                  openSettings: null,
                  dismissNestedRoute: ([_]) {},
                  child: const TvServersPage(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> activateByLabel(WidgetTester tester, String label) async {
      final focus = Focus.maybeOf(tester.element(find.text(label)), scopeOk: true)!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    testWidgets('opening Add connection keeps the TV shell mounted', (tester) async {
      await pumpInShell(tester);

      await activateByLabel(tester, t.connections.addConnection);

      // Hoofdstuk 33's shared shell is binding on all eight references; a
      // kale Navigator.push draws a new route over TvRootShell entirely and
      // takes the bar with it, which is exactly SYS-1's symptom.
      expect(find.byType(TvTopNavigation), findsOneWidget);
    });

    testWidgets('opening Pleya Share keeps the TV shell mounted', (tester) async {
      await pumpInShell(tester);

      await activateByLabel(tester, t.pleyaShare.hostTitle);

      expect(find.byType(TvTopNavigation), findsOneWidget);
    });
  });
}

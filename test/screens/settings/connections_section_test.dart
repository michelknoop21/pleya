import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/settings/connection_sources_screen.dart';
import 'package:pleya/screens/settings/connections_section.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/settings_section.dart';

import '../../test_helpers/prefs.dart';

PleyaServerConnection _server({String serverId = 'srv-1', String name = 'Zolder'}) => PleyaServerConnection(
  id: 'pleyaServer.$serverId',
  baseUrl: 'http://nas.lan:8832',
  serverId: serverId,
  serverName: name,
  userName: 'michel',
  refreshToken: 'rt-1',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

LocalFolderConnection _folder({String id = 'local-1', String name = 'Films lokaal'}) => LocalFolderConnection(
  id: id,
  directoryUri: '/tmp/$id',
  displayName: name,
  libraryType: 'movies',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// A registry whose stream is an ordinary one.
///
/// A drift query stream needs a real event loop, and `testWidgets` runs its
/// body in a fake-async zone where that never turns. Writes still go to the
/// real in-memory database; only the watching is replaced.
class _SeededRegistry extends ConnectionRegistry {
  _SeededRegistry(super.db, this._seed);

  final List<Connection> _seed;

  @override
  Stream<List<Connection>> watchConnections() => Stream<List<Connection>>.value(_seed);
}

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late ActiveProfileProvider activeProfile;
  late PlexHomeService plexHome;
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;

  setUp(() async {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
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
    hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
  });

  tearDown(() async {
    hiddenLibraries.dispose();
    multiServer.dispose();
    await activeProfile.resetForTesting();
    activeProfile.dispose();
    await plexHome.dispose();
    await db.close();
  });

  /// Seeds the registry and pumps the section.
  ///
  /// The seeding runs through [WidgetTester.runAsync] because a drift write is
  /// real I/O, and `testWidgets` runs its body in a fake-async zone where real
  /// I/O never completes. That is also why the cleanup tests next door are
  /// plain `test` cases rather than widget ones.
  Future<void> pumpSection(
    WidgetTester tester, {
    List<Connection> seed = const [],
    bool appleTv = false,
    ConnectionSourceKind? sources,
  }) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TvDetectionService.debugSetAppleTVOverride(appleTv ? true : null);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await tester.runAsync(() async {
      for (final connection in seed) {
        await connections.upsert(connection);
      }
    });
    final registry = _SeededRegistry(db, seed);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            Provider<ConnectionRegistry>.value(value: registry),
            Provider<ProfileConnectionRegistry>.value(value: profileConnections),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            // A-24b: the section, or one of the source pages it opens.
            home: sources == null
                ? Scaffold(body: ListView(children: const [ConnectionsSection()]))
                : ConnectionSourcesScreen(kind: sources),
          ),
        ),
      ),
    );
    // Give the registry stream a real moment to deliver, then draw it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  // The reported bug in one sentence: the list filtered on local folders and
  // Pleya Share, so a Pleya Server appeared in neither and had no way out.
  // A-24b (series `ios/12`): the section has a row per kind of source, and
  // the rows themselves live on the page that row opens.
  group('a Pleya Server is manageable where Connections says it is', () {
    testWidgets('a Pleya Server gives the section its manage row and the remove row', (tester) async {
      await pumpSection(tester, seed: [_server()]);

      expect(find.text(t.settingsStudio.existingSources.toUpperCase()), findsOneWidget);
      expect(find.text(t.settingsStudio.managePleyaServer), findsOneWidget);
      expect(find.text(t.settingsStudio.removeSource), findsOneWidget);
      expect(find.text(t.settingsStudio.managePlex), findsNothing, reason: 'no Plex account on this device');
    });

    testWidgets('a source on this device only gives the remove row', (tester) async {
      await pumpSection(tester, seed: [_folder()]);

      expect(find.text(t.settingsStudio.managePleyaServer), findsNothing);
      expect(find.text(t.settingsStudio.removeSource), findsOneWidget);
    });

    testWidgets('without any source there is no empty card, only the ways to add one', (tester) async {
      await pumpSection(tester);

      expect(find.text(t.settingsStudio.existingSources.toUpperCase()), findsNothing);
      expect(find.text(t.connections.addConnection.toUpperCase()), findsOneWidget);
      for (final row in [
        t.settingsStudio.linkPlex,
        t.settingsStudio.addJellyfin,
        t.settingsStudio.addEmby,
        t.settingsStudio.addPleyaServer,
        t.pleyaShare.hostTitle,
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
    });

    testWidgets('its page lists it, the expired session stated on the row', (tester) async {
      manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
      await pumpSection(tester, seed: [_server()], sources: ConnectionSourceKind.pleyaServer);

      expect(find.text('Zolder'), findsOneWidget);
      expect(find.textContaining(t.connections.reauthRequired), findsOneWidget);
    });

    testWidgets('the row says nothing about signing in while the session is fine', (tester) async {
      await pumpSection(tester, seed: [_server()], sources: ConnectionSourceKind.pleyaServer);

      expect(find.textContaining(t.connections.reauthRequired), findsNothing);
    });

    testWidgets('the remove page lists servers and sources on this device', (tester) async {
      await pumpSection(tester, seed: [_server(), _folder()], sources: ConnectionSourceKind.removable);

      expect(find.text('Zolder'), findsOneWidget);
      expect(find.text('Films lokaal'), findsOneWidget);
    });
  });

  group('a remote can reach the disconnect', () {
    Finder rowFor(String title) => find.ancestor(of: find.text(title), matching: find.byType(FocusableWrapper));

    testWidgets('the row is a focus stop and its delete asks to confirm', (tester) async {
      await pumpSection(tester, seed: [_server()], appleTv: true, sources: ConnectionSourceKind.removable);

      final row = rowFor('Zolder');
      expect(row, findsOneWidget, reason: 'a delete that a D-pad cannot land on is not connection management');

      // The wrapper owns its focus node when none is handed in, so the row is
      // a focus stop by construction; what still has to be shown is that
      // activating it does something.
      await tester.tap(find.descendant(of: row, matching: find.byType(IconButton)));
      // A dialog is a route with an entrance animation, so it needs frames.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.text(t.connections.disconnectServerConfirm(name: 'Zolder')),
        findsOneWidget,
        reason: 'select on the focused row must lead somewhere, not merely look focusable',
      );
    });

    testWidgets('an expired session does not disable the disconnect', (tester) async {
      manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
      await pumpSection(tester, seed: [_server()], appleTv: true, sources: ConnectionSourceKind.removable);

      // The whole point: you must not have to sign in to a server in order to
      // get rid of it.
      final row = rowFor('Zolder');
      expect(row, findsOneWidget);
      expect(
        tester.widget<FocusableWrapper>(row).onSelect,
        isNotNull,
        reason: 'you must not have to sign in to a server in order to get rid of it',
      );
    });

    testWidgets('SELECT on the focused row opens the same confirm a tap does', (tester) async {
      await pumpSection(tester, seed: [_server()], appleTv: true, sources: ConnectionSourceKind.removable);

      final row = rowFor('Zolder');
      final focusNode = tester.widget<Focus>(find.descendant(of: row, matching: find.byType(Focus)).first).focusNode!;
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // A dialog is a route with an entrance animation, so it needs frames.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.text(t.connections.disconnectServerConfirm(name: 'Zolder')),
        findsOneWidget,
        reason:
            'a remote landing SELECT on the row, not just a mouse landing on its delete button, must reach onRemove',
      );
    });
  });

  // The regression test on "sometimes the line is double": a separator keyed
  // to list position draws one either side of a collapsed StreamBuilder, and
  // two collapsed builders in a row stack two separators on top of each
  // other. Counting every SettingsRows' separatorRects across the whole
  // section proves that never happens, for every shape the two streams can
  // take.
  group('no separator stands next to another with nothing visible between them', () {
    int totalSeparators() {
      var total = 0;
      for (final element in find.byType(SettingsRows).evaluate()) {
        total += (element.renderObject! as RenderSettingsRows).separatorRects.length;
      }
      return total;
    }

    // The section: seven ways to add (no active profile, so no borrowing)
    // make six lines; the sources card adds one line per row after its first.
    testWidgets('neither a server nor a source', (tester) async {
      await pumpSection(tester);
      expect(totalSeparators(), 6);
    });

    testWidgets('a server only', (tester) async {
      await pumpSection(tester, seed: [_server()]);
      // Pleya Server and the remove row: one line.
      expect(totalSeparators(), 7);
    });

    testWidgets('a source only', (tester) async {
      await pumpSection(tester, seed: [_folder()]);
      expect(totalSeparators(), 6);
    });

    testWidgets('a server and a source side by side', (tester) async {
      await pumpSection(tester, seed: [_server(), _folder()]);
      expect(totalSeparators(), 7);
    });

    testWidgets('the remove page draws one line between each two sources', (tester) async {
      await pumpSection(
        tester,
        seed: [
          _server(serverId: 'srv-1', name: 'Zolder'),
          _server(serverId: 'srv-2', name: 'Kelder'),
          _folder(id: 'local-1', name: 'Films lokaal'),
          _folder(id: 'local-2', name: 'Series lokaal'),
        ],
        sources: ConnectionSourceKind.removable,
      );
      expect(totalSeparators(), 3);
    });
  });

  group('each kind of source has its own page (A-24b, series ios/12)', () {
    JellyfinConnection jellyfin({bool emby = false}) => JellyfinConnection(
      id: emby ? 'emby/1' : 'jf/1',
      baseUrl: 'https://media.local',
      serverName: emby ? 'Emby' : 'Jellyfin',
      serverMachineId: emby ? 'emby' : 'jf',
      userId: 'u',
      userName: 'u',
      accessToken: 'tok',
      deviceId: 'd',
      isEmby: emby,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    test('Jellyfin and Emby are told apart; servers and device sources are removable', () {
      expect(connectionSourceMatches(ConnectionSourceKind.jellyfin, jellyfin()), isTrue);
      expect(connectionSourceMatches(ConnectionSourceKind.jellyfin, jellyfin(emby: true)), isFalse);
      expect(connectionSourceMatches(ConnectionSourceKind.emby, jellyfin(emby: true)), isTrue);
      expect(connectionSourceMatches(ConnectionSourceKind.pleyaServer, _server()), isTrue);
      expect(connectionSourceMatches(ConnectionSourceKind.removable, _folder()), isTrue);
      expect(connectionSourceMatches(ConnectionSourceKind.removable, jellyfin()), isFalse);
    });

    testWidgets('an Emby source gives the Emby row and not the Jellyfin one', (tester) async {
      await pumpSection(tester, seed: [jellyfin(emby: true)]);
      expect(find.text(t.settingsStudio.manageEmby), findsOneWidget);
      expect(find.text(t.settingsStudio.manageJellyfin), findsNothing);
    });
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
  Future<void> pumpSection(WidgetTester tester, {List<Connection> seed = const [], bool appleTv = false}) async {
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
            home: Scaffold(body: ListView(children: const [ConnectionsSection()])),
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
  group('a Pleya Server is manageable where Connections says it is', () {
    testWidgets('it is listed with its own heading', (tester) async {
      await pumpSection(tester, seed: [_server()]);

      expect(find.text(t.connections.pleyaServers), findsOneWidget);
      expect(find.text('Zolder'), findsOneWidget);
    });

    testWidgets('it does not sit under "sources on this device"', (tester) async {
      await pumpSection(tester, seed: [_server()]);

      expect(
        find.text(t.connections.localSources),
        findsNothing,
        reason: 'a Pleya Server is an account on a server elsewhere, not a source on this device',
      );
    });

    testWidgets('both blocks appear side by side when there is one of each', (tester) async {
      await pumpSection(tester, seed: [_server(), _folder()]);

      expect(find.text(t.connections.pleyaServers), findsOneWidget);
      expect(find.text(t.connections.localSources), findsOneWidget);
      expect(find.text('Zolder'), findsOneWidget);
      expect(find.text('Films lokaal'), findsOneWidget);
    });

    testWidgets('an expired session is stated on the row, not only in the top bar', (tester) async {
      manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
      await pumpSection(tester, seed: [_server()]);

      expect(find.textContaining(t.connections.reauthRequired), findsOneWidget);
    });

    testWidgets('the row says nothing about signing in while the session is fine', (tester) async {
      await pumpSection(tester, seed: [_server()]);

      expect(find.textContaining(t.connections.reauthRequired), findsNothing);
    });
  });

  group('a remote can reach the disconnect', () {
    Finder rowFor(String title) => find.ancestor(of: find.text(title), matching: find.byType(FocusableWrapper));

    testWidgets('the row is a focus stop and its delete asks to confirm', (tester) async {
      await pumpSection(tester, seed: [_server()], appleTv: true);

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
      await pumpSection(tester, seed: [_server()], appleTv: true);

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

    testWidgets('neither a server nor a source', (tester) async {
      await pumpSection(tester);
      // Just "add connection" and "share host": one line between the two.
      expect(totalSeparators(), 1);
    });

    testWidgets('a server only', (tester) async {
      await pumpSection(tester, seed: [_server()]);
      // add / share / servers-block: two lines, and none inside the
      // single-row servers block.
      expect(totalSeparators(), 2);
    });

    testWidgets('a source only', (tester) async {
      await pumpSection(tester, seed: [_folder()]);
      expect(totalSeparators(), 2);
    });

    testWidgets('a server and a source side by side', (tester) async {
      await pumpSection(tester, seed: [_server(), _folder()]);
      // add / share / servers-block / sources-block: three lines, and none
      // inside either single-row block.
      expect(totalSeparators(), 3);
    });

    testWidgets('multiple servers and multiple sources', (tester) async {
      await pumpSection(
        tester,
        seed: [
          _server(serverId: 'srv-1', name: 'Zolder'),
          _server(serverId: 'srv-2', name: 'Kelder'),
          _folder(id: 'local-1', name: 'Films lokaal'),
          _folder(id: 'local-2', name: 'Series lokaal'),
        ],
      );
      // The three outer lines, plus one inside the two-row servers block and
      // one inside the two-row sources block.
      expect(totalSeparators(), 5);
    });
  });
}

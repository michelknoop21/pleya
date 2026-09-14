import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/tv/tv_offline_home_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';

PleyaServerConnection _server({String serverId = 'srv-1', String name = 'Zolder'}) => PleyaServerConnection(
  id: 'pleyaServer.$serverId',
  baseUrl: 'http://nas.lan:8832',
  serverId: serverId,
  serverName: name,
  userName: 'michel',
  refreshToken: 'rt-1',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// A registry whose stream is an ordinary one, matching
/// `connections_section_test.dart`'s `_SeededRegistry`: a drift query stream
/// needs a real event loop, and `testWidgets` never turns one.
class _SeededRegistry extends ConnectionRegistry {
  _SeededRegistry(super.db, this._seed);

  final List<Connection> _seed;

  @override
  Stream<List<Connection>> watchConnections() => Stream<List<Connection>>.value(_seed);
}

void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late MultiServerProvider multiServer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    manager = MultiServerManager();
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
  });

  tearDown(() async {
    multiServer.dispose();
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<Connection> seed = const [],
    bool isReconnecting = false,
    VoidCallback? onReconnect,
    VoidCallback? onManageServers,
  }) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            Provider<ConnectionRegistry>.value(value: _SeededRegistry(db, seed)),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: TvOfflineHomeScreen(
                isReconnecting: isReconnecting,
                onReconnect: onReconnect ?? () {},
                onManageServers: onManageServers ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows the offline title and both actions', (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.tvOfflineHome.title), findsOneWidget);
    expect(find.text(t.common.reconnect), findsOneWidget);
    expect(find.text(t.tvOfflineHome.manageServers), findsOneWidget);
  });

  testWidgets('reconnect fires the callback', (tester) async {
    var tapped = false;
    await pumpScreen(tester, onReconnect: () => tapped = true);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('reconnect does nothing while already reconnecting', (tester) async {
    var tapped = false;
    await pumpScreen(tester, isReconnecting: true, onReconnect: () => tapped = true);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('lists a known server with an offline status', (tester) async {
    await pumpScreen(tester, seed: [_server()]);

    expect(find.text('Zolder'), findsOneWidget);
    expect(find.textContaining(t.common.offline), findsOneWidget);
  });

  testWidgets('a server with an expired session says so instead of "offline"', (tester) async {
    manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
    await pumpScreen(tester, seed: [_server()]);

    expect(find.textContaining(t.connections.reauthRequired), findsOneWidget);
  });

  testWidgets('no server known draws no "Servers" heading', (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.tvMyPleya.servers), findsNothing);
  });
}

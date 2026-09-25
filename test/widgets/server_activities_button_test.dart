import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/server_activities_button.dart';
import 'package:provider/provider.dart';

class _AuthorityManager extends MultiServerManager {
  bool canManage = false;

  @override
  bool canManageServerMetadata(ServerId serverId) => canManage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  Future<ServerActivitiesButtonState> pumpButton(WidgetTester tester, MultiServerManager manager) async {
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    final buttonKey = GlobalKey<ServerActivitiesButtonState>();
    addTearDown(() {
      multiServerProvider.dispose();
      manager.dispose();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: multiServerProvider,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(body: ServerActivitiesButton(key: buttonKey)),
          ),
        ),
      ),
    );
    return buttonKey.currentState!;
  }

  testWidgets('togglePanel opens and closes the server activities overlay', (tester) async {
    final button = await pumpButton(tester, MultiServerManager());

    button.togglePanel();
    await tester.pump();
    await tester.pump();

    expect(find.text(t.serverTasks.title), findsOneWidget);
    expect(find.text(t.serverTasks.noTasks), findsOneWidget);

    button.togglePanel();
    await tester.pump();

    expect(find.text(t.serverTasks.title), findsNothing);
  });

  group('stop button for a cancellable server task', () {
    late AppDatabase db;
    setUpAll(() => PlexApiCache.initialize(db = AppDatabase.forTesting(NativeDatabase.memory())));
    tearDownAll(() => db.close());

    /// Opens the panel with one cancellable Plex task. Close the returned
    /// panel at the end so its poll timer does not outlive the test.
    Future<ServerActivitiesButtonState> openPanelWithTask(WidgetTester tester, {required bool canManage}) async {
      final manager = _AuthorityManager()..canManage = canManage;
      manager.debugRegisterClientForTesting(
        PlexClient.forTesting(
          config: PlexConfig(
            baseUrl: 'https://plex.example',
            token: 'token',
            clientIdentifier: 'client-id',
            product: 'Pleya',
            version: '1.0.0',
          ),
          serverId: ServerId('server-1'),
          serverName: 'Plex',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'MediaContainer': {
                  'Activity': [
                    {
                      'uuid': 'task-1',
                      'type': 'library.update',
                      'title': 'Scanning Movies',
                      'progress': 40,
                      'cancellable': true,
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );
      final button = await pumpButton(tester, manager);

      button.togglePanel();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('Scanning Movies'), findsOneWidget);
      return button;
    }

    testWidgets('is hidden for a profile without owner rights on the server', (tester) async {
      final button = await openPanelWithTask(tester, canManage: false);
      expect(find.byTooltip(t.common.cancel), findsNothing);
      button.togglePanel();
    });

    testWidgets('is shown to the owner', (tester) async {
      final button = await openPanelWithTask(tester, canManage: true);
      expect(find.byTooltip(t.common.cancel), findsOneWidget);
      button.togglePanel();
    });
  });
}

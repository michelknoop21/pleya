import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/downloads/downloads_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/widgets/mobile/mobile_dense_title_row.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/glass_phone.dart';
import 'package:pleya/theme/mono_theme.dart';

class _FakeConnectionRegistry extends ConnectionRegistry {
  _FakeConnectionRegistry(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DownloadProvider downloadProvider;
  late MultiServerProvider multiServerProvider;
  late MultiServerManager serverManager;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);

    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();

    serverManager = MultiServerManager();
    multiServerProvider = MultiServerProvider(serverManager, DataAggregationService(serverManager));
  });

  tearDown(() async {
    downloadProvider.dispose();
    multiServerProvider.dispose();
    await db.close();
  });

  Future<void> pumpDownloads(WidgetTester tester, {required TargetPlatform platform, Key? key}) async {
    await tester.pumpWidget(
      InputModeTracker(
        child: MultiProvider(
          providers: [
            Provider<ConnectionRegistry>.value(value: _FakeConnectionRegistry(db)),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            // monoTheme carries the MonoTokens extension the shared widgets read;
            // a bare ThemeData leaves tokens(context) null.
            theme: monoTheme(dark: true).copyWith(platform: platform),
            home: DownloadsScreen(key: key),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone tab root has a working explicit back action without a pushed route', (tester) async {
    await glassPhone(tester, glass: false);
    var returned = false;
    await tester.pumpWidget(
      InputModeTracker(
        child: MultiProvider(
          providers: [
            Provider<ConnectionRegistry>.value(value: _FakeConnectionRegistry(db)),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            theme: glassPhoneTheme(),
            home: DownloadsScreen(onBack: () => returned = true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final back = find.byWidgetPredicate(
      (widget) => widget is AutomationNode && widget.id == AutomationIds.navigationBack,
    );
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pump();
    expect(returned, isTrue);
  });

  testWidgets('right from Movies focuses and opens Sync Rules action', (tester) async {
    final screenKey = GlobalKey<DownloadsScreenState>();

    await pumpDownloads(tester, platform: TargetPlatform.macOS, key: screenKey);
    // Desktop keeps its standard bar with the tabs in it (A-06 is iPhone only).
    expect(find.byType(MobileDenseTitleRow), findsNothing);
    expect(tester.getRect(find.byType(AppBar)).height, kToolbarHeight);

    final state = screenKey.currentState!;
    state.tabController.index = 2;
    state.getTabChipFocusNode(2).requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Sync rules'), findsOneWidget);
  });

  testWidgets('iPhone: one 48 pt Dense Library row with the title and Sync rules, tab chips below (A-06)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpDownloads(tester, platform: TargetPlatform.iOS);

    expect(find.byType(MobileDenseTitleRow), findsOneWidget);
    expect(tester.getRect(find.byType(AppBar)).height, 48);
    final title = tester.getRect(find.text(t.downloads.title));
    final syncRules = tester.getRect(find.byTooltip(t.downloads.activeSyncRules));
    expect((syncRules.center.dy - title.center.dy).abs(), lessThan(8));
    expect(syncRules.left, greaterThan(title.right));
    expect(tester.getTopLeft(find.text(t.downloads.manage)).dy, greaterThanOrEqualTo(48));
  });
}

/// Mijn activiteit delen: on the TV page and on the phone's Geavanceerd page,
/// only for a server with the route, and never silently wrong.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/item_watcher.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/providers/trackers_provider.dart';
import 'package:pleya/providers/trakt_account_provider.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/tv/tv_menu_grid.dart';
import 'package:pleya/widgets/tv/tv_settings_categories.dart';
import 'package:pleya/widgets/tv/tv_settings_rows.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/notice_layer.dart';
import '../../test_helpers/prefs.dart';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => null;

  @override
  bool get hasMultipleProfiles => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HouseholdActivityClient {
  _Client({this.capable = true, this.stored = true, this.failSave = false});

  final bool capable;
  bool? stored;
  final bool failSave;
  final saved = <bool>[];
  var reads = 0;

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'NAS';
  @override
  MediaBackend get backend => MediaBackend.pleyaServer;
  @override
  ServerCapabilities get capabilities => ServerCapabilities(itemActivity: capable, ownActivityLine: true);
  @override
  Future<List<ItemWatcher>> fetchHouseholdActivity(String itemId) async => const [];
  @override
  Future<bool?> fetchActivitySharing() async {
    reads++;
    return stored;
  }

  @override
  Future<bool> saveActivitySharing(bool share) async {
    if (failSave) throw StateError('no');
    saved.add(share);
    return share;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  setUpAll(() => db = AppDatabase.forTesting(NativeDatabase.memory()));

  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<void> pump(WidgetTester tester, _Client? client, {required Widget Function(Widget) wrap}) async {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await tester.runAsync(() => SettingsService.getInstance());
    final manager = MultiServerManager();
    if (client != null) manager.debugRegisterClientForTesting(client);
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<TraktAccountProvider>(
              create: (_) => TraktAccountProvider(kidsProfileCheck: () async => false),
            ),
            ChangeNotifierProvider<TrackersProvider>(create: (_) => TrackersProvider()),
            ChangeNotifierProvider<SeerrProvider>(create: (_) => SeerrProvider()),
            ChangeNotifierProvider<TautulliProvider>(create: (_) => TautulliProvider()),
            ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
            Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
            ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile()),
          ],
          child: MaterialApp(theme: monoTheme(dark: true), builder: noticeLayer, home: wrap(const SettingsScreen())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('on TV', () {
    Future<void> pumpAdvanced(WidgetTester tester, _Client? client) async {
      const canvas = Size(1038, 584);
      tester.view.physicalSize = canvas;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      TvDetectionService.debugSetAppleTVOverride(true);
      await pump(
        tester,
        client,
        wrap: (child) => InputModeTracker(
          child: TvDisplayMetrics(size: canvas, child: child),
        ),
      );
      tester.state<TvSettingsCategoriesState>(find.byType(TvSettingsCategories)).choose('advanced');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    TvMenuItem? row(WidgetTester tester) => tester
        .widgetList<TvSettingsRowList>(find.byType(TvSettingsRowList))
        .expand((list) => list.items)
        .where((item) => item.title == t.settings.shareActivity)
        .firstOrNull;

    Future<void> select(WidgetTester tester) async {
      await tester.runAsync(() async {
        row(tester)!.onSelect!();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }

    testWidgets('the row stands under Privacy with the server\'s value, and Select saves', (tester) async {
      final client = _Client();
      await pumpAdvanced(tester, client);

      expect(find.text(t.settings.privacy.toUpperCase(), skipOffstage: false), findsOneWidget);
      expect(row(tester)!.toggled, isTrue);
      expect(row(tester)!.value, t.common.on);

      await select(tester);

      expect(client.saved, [false]);
      expect(row(tester)!.toggled, isFalse);
      await unmount(tester);
    });

    testWidgets('a restricted user starts off and can turn it on', (tester) async {
      final client = _Client(stored: false);
      await pumpAdvanced(tester, client);
      expect(row(tester)!.toggled, isFalse);

      await select(tester);

      expect(client.saved, [true]);
      expect(row(tester)!.toggled, isTrue);
      await unmount(tester);
    });

    testWidgets('a failed save shows the old state and a message', (tester) async {
      await pumpAdvanced(tester, _Client(failSave: true));

      await select(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(row(tester)!.toggled, isTrue);
      expect(find.text(t.settings.shareActivitySaveFailed), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a read that failed says so, and Select tries again', (tester) async {
      final client = _Client(stored: null);
      await pumpAdvanced(tester, client);
      expect(row(tester)!.value, t.settings.shareActivityUnreadable);
      expect(row(tester)!.toggled, isNull);

      client.stored = true;
      await select(tester);

      expect(client.reads, 2);
      expect(row(tester)!.toggled, isTrue);
      expect(client.saved, isEmpty);
      await unmount(tester);
    });

    testWidgets('a server without the capability has no row and is not asked', (tester) async {
      final client = _Client(capable: false);
      await pumpAdvanced(tester, client);

      expect(row(tester), isNull);
      expect(client.reads, 0);
      await unmount(tester);
    });

    testWidgets('no Pleya Server at all: no row', (tester) async {
      await pumpAdvanced(tester, null);

      expect(row(tester), isNull);
      await unmount(tester);
    });
  });

  group('on a phone', () {
    Future<void> openAdvanced(WidgetTester tester, _Client client) async {
      tester.view.physicalSize = const Size(375 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, client, wrap: (child) => child);
      await tester.tap(find.text(t.settings.advanced));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    }

    testWidgets('Geavanceerd carries the switch, and a failed save leaves it', (tester) async {
      final client = _Client(failSave: true);
      await openAdvanced(tester, client);

      final tile = find.widgetWithText(SettingSwitchRow, t.settings.shareActivity);
      expect(tile, findsOneWidget);
      expect(tester.widget<SettingSwitchRow>(tile).value, isTrue);

      tester.widget<SettingSwitchRow>(tile).onChanged!(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.widget<SettingSwitchRow>(tile).value, isTrue);
      expect(find.text(t.settings.shareActivitySaveFailed), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a server without the capability leaves Privacy out', (tester) async {
      await openAdvanced(tester, _Client(capable: false));

      expect(find.byType(SettingSwitchRow).evaluate().map((e) => (e.widget as SettingSwitchRow).title), isEmpty);
      await unmount(tester);
    });
  });
}

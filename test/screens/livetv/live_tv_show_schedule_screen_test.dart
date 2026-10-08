/// The Live TV show schedule: relative times in the user's language
/// (TVUX-76), and what the loader does when the schedule fetch fails at the
/// transport (TVUX-77).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/live_tv_support.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/noop_live_tv_support.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/models/livetv_program.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/livetv/live_tv_show_schedule_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/formatters.dart';
import 'package:pleya/widgets/loading_indicator_box.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _show = 'Nieuwsuur';

int _epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

class _ScheduleSupport extends NoopLiveTvSupport {
  const _ScheduleSupport(this.programs);

  final List<LiveTvProgram> programs;

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) async => programs;
}

class _ScheduleClient implements MediaServerClient {
  _ScheduleClient(this.programs);

  final List<LiveTvProgram> programs;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  LiveTvSupport get liveTv => _ScheduleSupport(programs);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    await initializeDateFormatting('en');
    await initializeDateFormatting('nl');
    // nl is a deferred library; load it here, outside the fake-async zone.
    await LocaleSettings.setLocale(AppLocale.nl);
    LocaleSettings.setLocaleSync(AppLocale.en);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    JellyfinApiCache.initialize(db);
    PlexApiCache.initialize(db);
  });

  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await db.close();
  });

  Future<void> pumpSchedule(WidgetTester tester, MediaServerClient client) async {
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: LiveTvShowScheduleScreen(showTitle: _show, serverId: client.serverId, channels: const []),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('TVUX-76: the relative times follow the app language', (tester) async {
    LocaleSettings.setLocaleSync(AppLocale.nl);
    final now = DateTime.now();
    final tomorrowNoon = DateTime(now.year, now.month, now.day + 1, 12);

    await pumpSchedule(
      tester,
      _ScheduleClient([
        // Half a minute of slack either way keeps the whole-minute counts
        // still while the test runs.
        LiveTvProgram(
          title: _show,
          beginsAt: _epoch(now.subtract(const Duration(minutes: 10))),
          endsAt: _epoch(now.add(const Duration(minutes: 20, seconds: 30))),
        ),
        LiveTvProgram(
          title: _show,
          beginsAt: _epoch(now.add(const Duration(minutes: 30, seconds: 30))),
          endsAt: _epoch(now.add(const Duration(minutes: 60))),
        ),
        LiveTvProgram(
          title: _show,
          beginsAt: _epoch(tomorrowNoon),
          endsAt: _epoch(tomorrowNoon.add(const Duration(minutes: 30))),
        ),
      ]),
    );

    expect(find.text('20 min over'), findsOneWidget);
    expect(find.text('Begint over 30 min'), findsOneWidget);
    expect(find.text('Morgen om ${formatClockTime(tomorrowNoon, is24Hour: false)}'), findsOneWidget);
    expect(find.textContaining('min left'), findsNothing);
    expect(find.textContaining('Starting in'), findsNothing);
    expect(find.textContaining(' at '), findsNothing);
  });

  // TVUX-77. Simulated runtime, not a device or a live server: the production
  // screen and the production client, with only the socket replaced by one
  // that refuses every request.
  group('TVUX-77: a schedule fetch that fails at the transport', () {
    Future<http.Response> refuse(http.Request request) async => throw const SocketException('Connection refused');

    void expectLoaderEnded(WidgetTester tester) {
      expect(tester.takeException(), isNull);
      expect(find.byType(LoadingIndicatorBox), findsNothing);
      expect(find.text(t.liveTv.noPrograms), findsOneWidget);
    }

    testWidgets('Jellyfin: the loader ends on the empty state', (tester) async {
      final client = JellyfinClient.forTesting(
        connection: JellyfinConnection(
          id: 'srv-1/user-1',
          baseUrl: 'https://jf.example.com',
          serverName: 'Home',
          serverMachineId: 'srv-1',
          userId: 'user-1',
          userName: 'michel',
          accessToken: 'tok',
          deviceId: 'dev',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        httpClient: MockClient(refuse),
      );
      addTearDown(client.close);

      await pumpSchedule(tester, client);
      await tester.pump(const Duration(seconds: 30));

      expectLoaderEnded(tester);
    });

    testWidgets('Plex: the loader ends on the empty state', (tester) async {
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'tok',
          clientIdentifier: 'client',
          product: 'Pleya',
          version: '1',
          machineIdentifier: 'machine-1',
        ),
        serverId: ServerId('machine-1'),
        httpClient: MockClient(refuse),
        epgProviders: const [(identifier: 'provider-a', gridEndpoint: '/provider-a/grid')],
      );
      addTearDown(client.close);

      await pumpSchedule(tester, client);
      await tester.pump(const Duration(seconds: 30));

      expectLoaderEnded(tester);
    });
  });
}

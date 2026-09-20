import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_signin.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/main.dart' show rootNavigatorKey;
import 'package:pleya/navigation/profile_navigation_scope.dart';
import 'package:pleya/profiles/active_profile_binder.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya_verify_fixture_server/http_adapter.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// Shows nothing until a profile is active, then mounts the same
/// register-a-navigator-with-profileNavigationRegistry contract
/// `lib/navigation/profile_session_screen.dart`'s private
/// `_ProfileSessionNavigator` uses — not the real widget (it drags in the
/// whole profile shell), just its attach/detach seam, which is exactly what
/// this test is proving the existence of.
class _ProfileGate extends StatelessWidget {
  const _ProfileGate();

  @override
  Widget build(BuildContext context) {
    final activeProfile = context.watch<ActiveProfileProvider>();
    if (activeProfile.active == null) return const SizedBox.shrink();
    return const _TestProfileNavigator();
  }
}

class _TestProfileNavigator extends StatefulWidget {
  const _TestProfileNavigator();

  @override
  State<_TestProfileNavigator> createState() => _TestProfileNavigatorState();
}

class _TestProfileNavigatorState extends State<_TestProfileNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _mainScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _routeObserver = RouteObserver<PageRoute<dynamic>>();

  @override
  void initState() {
    super.initState();
    profileNavigationRegistry.attachNavigator(_navigatorKey);
    profileNavigationRegistry.attachMainScaffoldMessenger(_mainScaffoldMessengerKey);
  }

  @override
  void dispose() {
    profileNavigationRegistry.detachNavigator(_navigatorKey);
    profileNavigationRegistry.detachMainScaffoldMessenger(_mainScaffoldMessengerKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProfileNavigationScope(
      navigatorKey: _navigatorKey,
      routeObserver: _routeObserver,
      mainScaffoldMessengerKey: _mainScaffoldMessengerKey,
      child: Navigator(
        key: _navigatorKey,
        observers: [_routeObserver],
        onGenerateRoute: (settings) => MaterialPageRoute<void>(builder: (_) => const SizedBox()),
      ),
    );
  }
}

class _FakeSeerrProvider extends SeerrProvider {
  static const expectedBaseUrl = 'http://127.0.0.1:47500/seerr';
  static const expectedApiKey = 'verify-seerr-key';
  static const testedSession = SeerrSession(
    baseUrl: expectedBaseUrl,
    authMode: SeerrAuthMode.apiKey,
    apiKey: expectedApiKey,
    permissions: SeerrPermission.admin,
  );

  @override
  Future<SeerrTestResult> test({
    required String baseUrl,
    required SeerrAuthMode mode,
    String? apiKey,
    String? email,
    String? password,
    String? plexToken,
  }) async {
    if (baseUrl != expectedBaseUrl || mode != SeerrAuthMode.apiKey || apiKey != expectedApiKey) {
      throw StateError('unexpected Seerr test arguments');
    }
    return (version: '1.33.2', displayName: 'verify-admin', permissions: SeerrPermission.admin, session: testedSession);
  }

  @override
  Future<void> commit(SeerrSession session) async {
    if (!identical(session, testedSession)) throw StateError('unexpected Seerr session');
  }
}

/// `ActiveProfileBinder.rebindIfActive` reaching a live server starts
/// `MultiServerManager`'s real connectivity monitoring
/// (`Connectivity().onConnectivityChanged`), which has no platform-channel
/// implementation under `flutter test` and throws `MissingPluginException`
/// as an unhandled zone error, failing the test even though nothing this
/// test actually asserts on is wrong. No existing test exercises this path
/// (they all use local-only/empty connections), so there's no precedent to
/// follow — this fakes the platform interface `connectivity_plus` itself
/// exposes for exactly this purpose.
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late ProfileRegistry profiles;
  late PlexHomeService plexHome;
  late ActiveProfileProvider activeProfile;
  late MultiServerManager manager;
  late MultiServerProvider multiServerProvider;
  late ActiveProfileBinder binder;
  late PleyaFakeServer fakeServer;
  late FixtureHttpServer fixtureAdapter;
  HttpOverrides? previousOverrides;
  late ConnectivityPlatform previousConnectivityPlatform;

  setUp(() async {
    resetSharedPreferencesForTest();
    // handleAutomationSignIn makes a real loopback HTTP call to
    // fixtureAdapter — TestWidgetsFlutterBinding fakes every HttpClient
    // request with a 400 otherwise. Restored in tearDown.
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    previousConnectivityPlatform = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();

    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
    profiles = ProfileRegistry(db);
    final storage = await StorageService.getInstance();
    plexHome = PlexHomeService(connections: connections, profileConnections: profileConnections, storage: storage);
    activeProfile = ActiveProfileProvider(
      registry: profiles,
      plexHome: plexHome,
      connections: connections,
      storage: storage,
    );
    manager = MultiServerManager();
    multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    binder = ActiveProfileBinder(
      activeProfile: activeProfile,
      connections: connections,
      profileConnections: profileConnections,
      serverManager: manager,
      multiServerProvider: multiServerProvider,
      pinPrompt: (_, {String? errorMessage}) async => null,
      shouldDeferInitialBind: (_) async => false,
    );

    fakeServer = PleyaFakeServer(setupRequired: true);
    fixtureAdapter = FixtureHttpServer(server: fakeServer, controlToken: 'irrelevant-for-pleya-v1');
    await fixtureAdapter.start();
  });

  tearDown(() async {
    await fixtureAdapter.stop();
    binder.dispose();
    multiServerProvider.dispose();
    // Not covered by multiServerProvider.dispose() — the real /v1/signin
    // flow reaches rebindIfActive(), which starts real connectivity
    // monitoring (Connectivity().onConnectivityChanged) pointed at the
    // fixture server. Left running, it keeps the test process alive
    // indefinitely instead of exiting after the test body completes.
    manager.dispose();
    await activeProfile.resetForTesting();
    activeProfile.dispose();
    await plexHome.dispose();
    await db.close();
    HttpOverrides.global = previousOverrides;
    ConnectivityPlatform.instance = previousConnectivityPlatform;
  });

  testWidgets('signin creates the first profile; only afterward is /v1/open usable', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ConnectionRegistry>.value(value: connections),
          Provider<ProfileRegistry>.value(value: profiles),
          Provider<ProfileConnectionRegistry>.value(value: profileConnections),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
          Provider<ActiveProfileBinder>.value(value: binder),
        ],
        child: MaterialApp(navigatorKey: rootNavigatorKey, home: const _ProfileGate()),
      ),
    );
    await tester.pump();

    // 1. Before signin: no active profile, and the profile-session seam
    // does not exist yet — /v1/open must fail clearly on it, not crash.
    // This call gives up on the profile-session wait (timeoutMs) before ever
    // reaching the readiness-poll loop. The wait is a real Future.delayed, so it
    // needs runAsync like the second call below.
    expect(activeProfile.active, isNull);
    late Map<String, Object?> openBefore;
    await tester.runAsync(() async {
      openBefore = await handleAutomationOpen({'screen': AutomationIds.screenMain, 'timeoutMs': 50});
    });
    expect(openBefore['ok'], isFalse);
    expect(openBefore['error'], contains('no profile session'));

    // 2. /v1/signin against the fixture — a fresh server, so this exercises
    // the setup path (info.auth.setup_required decides that, not the caller).
    // Uses rootNavigatorKey's context: no profile exists yet for
    // profileNavigationRegistry to have attached to.
    late Map<String, Object?> signinResult;
    await tester.runAsync(() async {
      signinResult = await handleAutomationSignIn({
        'base_url': 'http://127.0.0.1:${fixtureAdapter.port}',
        'username': 'verify-owner',
        'password': 'verify-password',
        'setup_code': fakeServer.setupCode,
      });
    });

    expect(signinResult['ok'], isTrue, reason: signinResult['error']?.toString() ?? signinResult.toString());

    // 3. A profile now exists. Mounting the profile-session navigator is
    // reactive (Provider notifyListeners -> _ProfileGate rebuild), so it
    // needs one more pump before profileNavigationRegistry sees it.
    expect(activeProfile.active, isNotNull);
    await tester.pump();

    // This call reaches handleAutomationOpen's readiness-poll loop (real
    // Future.delayed(100ms) ticks), which needs the real event loop, not
    // the fake clock testWidgets otherwise runs the test body on.
    late Map<String, Object?> openAfter;
    await tester.runAsync(() async {
      openAfter = await handleAutomationOpen({'screen': AutomationIds.screenMain, 'timeoutMs': 50});
    });
    // screen.main never actually mounts an AutomationScreen in this minimal
    // harness, so this still fails — but on a *readiness timeout*, not on
    // "no profile session": the seam existed and was used.
    expect(openAfter['ok'], isFalse);
    expect(openAfter['error'], contains('timeout'), reason: openAfter.toString());
    expect(profileNavigationRegistry.navigator, isNotNull);
  });

  testWidgets('seed_seerr waits for the first profile session to mount after sign-in', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ConnectionRegistry>.value(value: connections),
          Provider<ProfileRegistry>.value(value: profiles),
          Provider<ProfileConnectionRegistry>.value(value: profileConnections),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
          Provider<ActiveProfileBinder>.value(value: binder),
          ChangeNotifierProvider<SeerrProvider>(create: (_) => _FakeSeerrProvider()),
        ],
        child: MaterialApp(navigatorKey: rootNavigatorKey, home: const _ProfileGate()),
      ),
    );
    await tester.pump();

    late Map<String, Object?> signinResult;
    await tester.runAsync(() async {
      signinResult = await handleAutomationSignIn({
        'base_url': 'http://127.0.0.1:${fixtureAdapter.port}',
        'username': 'verify-owner',
        'password': 'verify-password',
        'setup_code': fakeServer.setupCode,
      });
    });
    expect(signinResult['ok'], isTrue, reason: signinResult.toString());
    expect(profileNavigationRegistry.navigator, isNull);

    final seedFuture = handleAutomationSeedSeerr({
      'base_url': _FakeSeerrProvider.expectedBaseUrl,
      'api_key': _FakeSeerrProvider.expectedApiKey,
    });
    await tester.pump();
    expect(profileNavigationRegistry.navigator, isNotNull);
    await tester.pump(const Duration(milliseconds: 100));

    late Map<String, Object?> seedResult;
    await tester.runAsync(() async => seedResult = await seedFuture);
    expect(seedResult['ok'], isTrue, reason: seedResult.toString());
  });

  Future<void> pumpProfileGate(WidgetTester tester, {required bool withSeerr}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ConnectionRegistry>.value(value: connections),
          Provider<ProfileRegistry>.value(value: profiles),
          Provider<ProfileConnectionRegistry>.value(value: profileConnections),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
          Provider<ActiveProfileBinder>.value(value: binder),
          if (withSeerr) ChangeNotifierProvider<SeerrProvider>(create: (_) => _FakeSeerrProvider()),
        ],
        child: MaterialApp(navigatorKey: rootNavigatorKey, home: const _ProfileGate()),
      ),
    );
    await tester.pump();
    late Map<String, Object?> signinResult;
    await tester.runAsync(() async {
      signinResult = await handleAutomationSignIn({
        'base_url': 'http://127.0.0.1:${fixtureAdapter.port}',
        'username': 'verify-owner',
        'password': 'verify-password',
        'setup_code': fakeServer.setupCode,
      });
    });
    expect(signinResult['ok'], isTrue, reason: signinResult.toString());
    expect(profileNavigationRegistry.navigator, isNull);
  }

  testWidgets('/v1/open waits for the first profile session to mount after sign-in', (tester) async {
    await pumpProfileGate(tester, withSeerr: false);

    // Straight after signin, before the session screen exists: the wait, not an immediate
    // "no profile session", and then the readiness timeout of a screen this harness lacks.
    // Both polls are Future.delayed timers of the fake clock, so the test drives them with
    // pump and lets real time pass in between for the DateTime.now() deadline.
    final openFuture = handleAutomationOpen({'screen': AutomationIds.screenMain, 'timeoutMs': 50});
    await tester.pump();
    expect(profileNavigationRegistry.navigator, isNotNull);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 100));

    final openResult = await openFuture;
    expect(openResult['ok'], isFalse);
    expect(openResult['error'], contains('timeout waiting'), reason: openResult.toString());
  });

  testWidgets('seed_seerr answers ok:false, not a thrown error, when the session has no SeerrProvider', (tester) async {
    await pumpProfileGate(tester, withSeerr: false);

    final seedFuture = handleAutomationSeedSeerr({
      'base_url': _FakeSeerrProvider.expectedBaseUrl,
      'api_key': _FakeSeerrProvider.expectedApiKey,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    late Map<String, Object?> seedResult;
    await tester.runAsync(() async => seedResult = await seedFuture);
    expect(seedResult['ok'], isFalse);
    expect(seedResult['error'], contains('seerr connect failed'), reason: seedResult.toString());
  });

  group('rejectNonLoopbackBaseUrl', () {
    test('accepts a literal loopback origin with a port — the only shape {{fixture}} ever produces', () {
      expect(rejectNonLoopbackBaseUrl('http://127.0.0.1:47500'), isNull);
    });

    test('accepts the IPv6 loopback literal', () {
      expect(rejectNonLoopbackBaseUrl('http://[::1]:47500'), isNull);
    });

    test('rejects https, even to a loopback host', () {
      expect(rejectNonLoopbackBaseUrl('https://127.0.0.1:47500'), contains('scheme'));
    });

    test('rejects an arbitrary internet host', () {
      expect(rejectNonLoopbackBaseUrl('http://example.com:80'), contains('loopback'));
    });

    test('rejects a LAN address', () {
      expect(rejectNonLoopbackBaseUrl('http://192.168.1.5:32400'), contains('loopback'));
    });

    test('rejects the cloud metadata service address', () {
      expect(rejectNonLoopbackBaseUrl('http://169.254.169.254/latest/meta-data/'), contains('loopback'));
    });

    test('rejects the hostname "localhost" — a literal IP only, never a name to resolve', () {
      expect(rejectNonLoopbackBaseUrl('http://localhost:47500'), contains('loopback'));
    });

    test('rejects an unparseable URL', () {
      expect(rejectNonLoopbackBaseUrl('not a url'), isNotNull);
    });
  });

  group('SSRF boundary: base_url is rejected before any network call or context wait', () {
    // No widget is pumped in either test below — proving the rejection
    // happens before `_waitForRootContext()` even runs, let alone before
    // any HTTP request. A version of this check that ran after the context
    // wait or the probe would report a different, misleading error instead.
    test('handleAutomationSignIn rejects a non-loopback base_url', () async {
      final result = await handleAutomationSignIn({
        'base_url': 'http://169.254.169.254/latest/meta-data/',
        'username': 'verify-owner',
        'password': 'verify-password',
      });
      expect(result['ok'], isFalse);
      expect(result['error'], contains('loopback'));
    });

    test('handleAutomationConnectionsSeed rejects a non-loopback base_url', () async {
      final result = await handleAutomationConnectionsSeed({
        'base_url': 'https://attacker.example.com',
        'server_id': 'srv',
        'server_name': 'Evil',
        'user_name': 'someone',
        'refresh_token': 'token',
      });
      expect(result['ok'], isFalse);
      expect(result['error'], contains('scheme'));
    });

    test('handleAutomationSeedSeerr rejects a non-loopback base_url', () async {
      final result = await handleAutomationSeedSeerr({
        'base_url': 'http://169.254.169.254/latest/meta-data/',
        'api_key': 'not-sent',
      });
      expect(result['ok'], isFalse);
      expect(result['error'], contains('loopback'));
    });
  });
}

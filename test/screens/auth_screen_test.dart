import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/plex/plex_home_user.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/screens/auth_screen.dart';
import 'package:pleya/screens/tv/tv_auth_view.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test_helpers/prefs.dart';

class _RecordingUrlLauncher extends UrlLauncherPlatform {
  int launches = 0;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches++;
    return true;
  }
}

void main() {
  setUp(resetSharedPreferencesForTest);

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpAuthScreen(
    WidgetTester tester, {
    required bool appleTv,
    Size size = const Size(1920, 1080),
    MockClient? pinClient,
    Future<PlexAuthService> Function()? pinServiceFactoryOverride,
    Future<PlexAuthService> Function()? connectServiceFactoryOverride,
    Future<bool?> Function(BuildContext context)? jellyfinRoute,
    VoidCallback? onConnectServiceCreate,
    ConnectionRegistry? connections,
    PlexHomeService? plexHome,
    Duration plexPollTimeout = const Duration(minutes: 5),
  }) async {
    TvDetectionService.debugSetAppleTVOverride(appleTv);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<PlexAuthService> pinServiceFactory() async =>
        pinServiceFactoryOverride?.call() ??
        PlexAuthService.forTesting(
          http: MediaServerHttpClient(client: pinClient ?? MockClient((_) async => http.Response('{}', 200))),
        );
    Future<PlexAuthService> connectServiceFactory() async {
      onConnectServiceCreate?.call();
      if (connectServiceFactoryOverride != null) return connectServiceFactoryOverride();
      return PlexAuthService.forTesting(
        http: MediaServerHttpClient(client: MockClient((_) async => http.Response('{}', 200))),
      );
    }

    Widget home = AuthScreen(
      plexPinAuthServiceFactory: pinServiceFactory,
      plexConnectAuthServiceFactory: connectServiceFactory,
      jellyfinRoute: jellyfinRoute,
      plexPollTimeout: plexPollTimeout,
    );
    if (connections != null && plexHome != null) {
      home = MultiProvider(
        providers: [
          Provider<ConnectionRegistry>.value(value: connections),
          Provider<PlexHomeService>.value(value: plexHome),
        ],
        child: home,
      );
    }

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(theme: monoTheme(dark: true), home: home),
      ),
    );
    await tester.pump();
  }

  Future<({AppDatabase db, ConnectionRegistry connections, PlexHomeService plexHome})> createAuthProviders() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(db);
    final profileConnections = ProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => const [],
    );
    addTearDown(() async {
      await plexHome.dispose();
      await db.close();
    });
    return (db: db, connections: connections, plexHome: plexHome);
  }

  MockClient claimedPinClient({String token = 'claimed-token', void Function()? onCreatePin}) {
    return MockClient((request) async {
      if (request.method == 'POST') {
        onCreatePin?.call();
        return http.Response(jsonEncode({'id': 1, 'code': 'ABCD'}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'authToken': token}), 200, headers: {'content-type': 'application/json'});
    });
  }

  group('Apple TV platform boundary', () {
    testWidgets('Apple TV owns the full viewport outside the legacy max-width container', (tester) async {
      await pumpAuthScreen(tester, appleTv: true);

      expect(find.byType(TvAuthView), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(TvAuthView),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.constraints?.maxWidth == 800,
            description: 'legacy maxWidth 800 container',
          ),
        ),
        findsNothing,
      );
      expect(tester.getSize(find.byType(TvAuthView)), const Size(1920, 1080));
    });

    testWidgets('non-Apple-TV keeps the existing wide auth tree', (tester) async {
      await pumpAuthScreen(tester, appleTv: false);

      expect(find.byType(TvAuthView), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.constraints?.maxWidth == 800,
          description: 'legacy maxWidth 800 container',
        ),
        findsOneWidget,
      );
    });
  });

  group('Apple TV backend choices', () {
    testWidgets('SELECT on Plex starts QR without opening url_launcher', (tester) async {
      final pollResponse = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'id': 1, 'code': 'ABCD'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return pollResponse.future;
      });
      final launcher = _RecordingUrlLauncher();
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      await pumpAuthScreen(tester, appleTv: true, pinClient: client);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-auth-panel-qr')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-auth-panel-qr')), matching: find.text(t.auth.scanQRToSignIn)),
        findsOneWidget,
      );
      expect(launcher.launches, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      pollResponse.complete(
        http.Response(jsonEncode({'authToken': null}), 200, headers: {'content-type': 'application/json'}),
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('DOWN and SELECT invokes the Jellyfin route exactly once', (tester) async {
      var routeCalls = 0;
      await pumpAuthScreen(
        tester,
        appleTv: true,
        jellyfinRoute: (_) async {
          routeCalls++;
          return false;
        },
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(routeCalls, 1);
      expect(find.byType(TvAuthView), findsOneWidget);
      expect(tester.binding.focusManager.primaryFocus?.debugLabel, t.auth.connectToJellyfin);
    });

    testWidgets('Jellyfin stays reachable during polling and a late Plex claim is ignored', (tester) async {
      final pollResponse = Completer<http.Response>();
      var routeCalls = 0;
      var connectServiceCreates = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'id': 1, 'code': 'ABCD'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return pollResponse.future;
      });
      await pumpAuthScreen(
        tester,
        appleTv: true,
        pinClient: client,
        onConnectServiceCreate: () => connectServiceCreates++,
        jellyfinRoute: (_) async {
          routeCalls++;
          return false;
        },
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('tv-auth-panel-qr')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(routeCalls, 1);
      expect(find.byKey(const ValueKey('tv-auth-panel-initial')), findsOneWidget);

      pollResponse.complete(
        http.Response(jsonEncode({'authToken': 'late-token'}), 200, headers: {'content-type': 'application/json'}),
      );
      await tester.pump();

      expect(connectServiceCreates, 1, reason: 'only the debug verify service was created; no token exchange started');
      expect(find.byType(TvAuthView), findsOneWidget);
      expect(tester.binding.takeException(), isNull);
    });

    testWidgets('Menu at root keeps auth mounted with valid focus', (tester) async {
      await pumpAuthScreen(tester, appleTv: true);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byType(TvAuthView), findsOneWidget);
      expect(tester.binding.focusManager.primaryFocus?.hasFocus, isTrue);
      expect(tester.binding.takeException(), isNull);
    });
  });

  group('Apple TV authentication status', () {
    testWidgets('claimed token shows loading, blocks a second attempt, then offers no-server recovery and retry', (
      tester,
    ) async {
      final providers = await createAuthProviders();
      final userResponse = Completer<http.Response>();
      var createPinCalls = 0;
      var connectFactoryCalls = 0;

      Future<PlexAuthService> connectFactory() async {
        connectFactoryCalls++;
        if (connectFactoryCalls == 1) {
          return PlexAuthService.forTesting(
            http: MediaServerHttpClient(client: MockClient((_) async => http.Response('{}', 200))),
          );
        }
        return PlexAuthService.forTesting(
          http: MediaServerHttpClient(
            client: MockClient((request) async {
              if (request.url.path.endsWith('/user')) return userResponse.future;
              return http.Response('[]', 200, headers: {'content-type': 'application/json'});
            }),
          ),
        );
      }

      await pumpAuthScreen(
        tester,
        appleTv: true,
        pinClient: claimedPinClient(onCreatePin: () => createPinCalls++),
        connectServiceFactoryOverride: connectFactory,
        connections: providers.connections,
        plexHome: providers.plexHome,
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-auth-panel-authenticating')), findsOneWidget);
      expect(createPinCalls, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(createPinCalls, 1, reason: 'disabled backend rows cannot start a second PIN attempt');

      userResponse.complete(
        http.Response(
          jsonEncode({'username': 'Owner', 'email': 'owner@example.com', 'uuid': 'plex-owner'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-auth-panel-noServersFound')), findsOneWidget);
      expect(find.text(t.serverSelection.noServersFoundTitle), findsOneWidget);
      expect(find.text(t.serverSelection.noServersFoundTryJellyfin), findsOneWidget);

      await tester.tap(find.text(t.auth.tryAgain));
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-auth-panel-initial')), findsOneWidget);
      expect(tester.binding.focusManager.primaryFocus?.hasFocus, isTrue);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        anyOf(t.auth.signInWithPlex, t.auth.connectToJellyfin),
      );
    });

    testWidgets('network failure maps to recovery and retry restores the initial backend choice', (tester) async {
      final providers = await createAuthProviders();
      var connectFactoryCalls = 0;

      Future<PlexAuthService> connectFactory() async {
        connectFactoryCalls++;
        return PlexAuthService.forTesting(
          http: MediaServerHttpClient(
            client: MockClient(
              (_) async => http.Response(
                connectFactoryCalls == 1 ? '{}' : 'failure',
                connectFactoryCalls == 1 ? 200 : 500,
                headers: {'content-type': 'application/json'},
              ),
            ),
          ),
        );
      }

      await pumpAuthScreen(
        tester,
        appleTv: true,
        pinClient: claimedPinClient(),
        connectServiceFactoryOverride: connectFactory,
        connections: providers.connections,
        plexHome: providers.plexHome,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-auth-panel-networkError')), findsOneWidget);
      expect(find.text(t.serverSelection.networkErrorTitle), findsOneWidget);

      await tester.tap(find.text(t.auth.tryAgain));
      await tester.pump();
      expect(find.byKey(const ValueKey('tv-auth-panel-initial')), findsOneWidget);
      expect(tester.binding.focusManager.primaryFocus?.hasFocus, isTrue);
    });

    testWidgets('timeout shows the real recovery copy and can retry without exposing a code or clock', (tester) async {
      var createPinCalls = 0;
      await pumpAuthScreen(
        tester,
        appleTv: true,
        pinClient: claimedPinClient(token: '', onCreatePin: () => createPinCalls++),
        plexPollTimeout: Duration.zero,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-auth-panel-timedOut')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tv-auth-panel-timedOut')),
          matching: find.text(t.auth.authenticationTimeout),
        ),
        findsOneWidget,
      );
      expect(find.text('ABCD'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+:\d+')), findsNothing);
      expect(find.text(t.auth.connectToJellyfin), findsOneWidget);

      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('tv-auth-panel-timedOut')), matching: find.text(t.auth.tryAgain)),
      );
      await tester.pump(const Duration(milliseconds: 101));
      await tester.pump();
      expect(createPinCalls, 2);
    });
  });

  group('handheld and desktop auth remain unchanged', () {
    for (final surface in <({String name, Size size, double maxWidth})>[
      (name: 'wide', size: const Size(1200, 800), maxWidth: 800),
      (name: 'narrow', size: const Size(390, 844), maxWidth: 400),
    ]) {
      testWidgets('${surface.name} keeps browser primary and QR secondary', (tester) async {
        await pumpAuthScreen(tester, appleTv: false, size: surface.size);
        await tester.pump();

        expect(find.byType(TvAuthView), findsNothing);
        expect(
          find.ancestor(of: find.text(t.auth.signInWithPlex), matching: find.byType(FilledButton)),
          findsOneWidget,
        );
        expect(find.ancestor(of: find.text(t.auth.showQRCode), matching: find.byType(OutlinedButton)), findsOneWidget);
        expect(
          find.byWidgetPredicate((widget) => widget is Container && widget.constraints?.maxWidth == surface.maxWidth),
          findsOneWidget,
        );
      });
    }
  });

  test('initial profile is built from the refreshed Plex Home cache', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(db);
    final profileConnections = ProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => [
        PlexHomeUser(
          id: 1,
          uuid: 'home-user-a',
          title: 'Home User',
          thumb: '',
          hasPassword: false,
          restricted: false,
          updatedAt: null,
          admin: true,
          guest: false,
          protected: false,
        ),
      ],
    );
    addTearDown(() async {
      await plexHome.dispose();
      await db.close();
    });

    final account = PlexAccountConnection(
      id: 'plex-account-a',
      accountToken: 'account-token',
      clientIdentifier: 'client-a',
      accountLabel: 'Plex',
      createdAt: DateTime(2026, 1, 1),
    );
    await connections.upsert(account);
    await plexHome.refresh(account);

    final profile = initialPlexHomeProfileFromCache(plexHome, account);

    expect(profile, isNotNull);
    expect(profile!.id, plexHomeProfileId(accountConnectionId: account.id, homeUserUuid: 'home-user-a'));
    expect(profile.parentConnectionId, account.id);
    expect(profile.displayName, 'Home User');
  });

  test('multiple Plex Home profiles require the profile gate instead of auto-activation', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(db);
    final profileConnections = ProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => [
        for (final (id, uuid, title) in [(1, 'owner', 'Owner'), (2, 'kids', 'Kids')])
          PlexHomeUser(
            id: id,
            uuid: uuid,
            title: title,
            thumb: '',
            hasPassword: false,
            restricted: false,
            updatedAt: null,
            admin: id == 1,
            guest: false,
            protected: false,
          ),
      ],
    );
    addTearDown(() async {
      await plexHome.dispose();
      await db.close();
    });
    final account = PlexAccountConnection(
      id: 'plex-account-many',
      accountToken: 'account-token',
      clientIdentifier: 'client-many',
      accountLabel: 'Plex',
      createdAt: DateTime(2026, 1, 1),
    );
    await connections.upsert(account);
    await plexHome.refresh(account);

    expect(initialPlexHomeProfileFromCache(plexHome, account), isNull);
    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: null,
        hasProfiles: false,
        accountHasHomeUsers: true,
        requireProfileSelectionOnOpen: false,
      ),
      isTrue,
    );
  });

  test('cancelled or invalid profile selection keeps auth mounted and stops loading', () {
    final profile = Profile.local(id: 'owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1));

    expect(shouldContinueAfterInitialProfileSelection(selected: false, activeProfile: profile), isFalse);
    expect(shouldContinueAfterInitialProfileSelection(selected: true, activeProfile: null), isFalse);
    expect(shouldContinueAfterInitialProfileSelection(selected: true, activeProfile: profile), isTrue);
  });

  test('initial profile selection is required when home users exist but no profile is active', () {
    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: null,
        hasProfiles: false,
        accountHasHomeUsers: true,
        requireProfileSelectionOnOpen: false,
      ),
      isTrue,
    );
  });

  test('initial profile selection is skipped when a profile was auto-selected', () {
    final profile = Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1));

    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: profile,
        hasProfiles: true,
        accountHasHomeUsers: true,
        requireProfileSelectionOnOpen: false,
      ),
      isFalse,
    );
  });

  test('initial profile selection is required when the launch setting is enabled', () {
    final profile = Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1));

    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: profile,
        hasProfiles: true,
        accountHasHomeUsers: true,
        requireProfileSelectionOnOpen: true,
      ),
      isTrue,
    );
  });

  test('initial profile selection is skipped when no profiles are available', () {
    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: null,
        hasProfiles: false,
        accountHasHomeUsers: false,
        requireProfileSelectionOnOpen: false,
      ),
      isFalse,
    );
  });

  group('auth i18n strings', () {
    test('recovery and help text strings are defined', () {
      expect(t.auth.chooseHowToSignIn, isNotEmpty);
      expect(t.auth.chooseHowToSignInDescription, isNotEmpty);
      expect(t.auth.tryAgain, isNotEmpty);
      // STR4: the brand-header tagline was hardcoded English on every locale.
      expect(t.auth.tagline, isNotEmpty);
      expect(t.serverSelection.noServersFoundTitle, isNotEmpty);
      expect(t.serverSelection.noServersFoundDescription, isNotEmpty);
      expect(t.serverSelection.noServersFoundTryJellyfin, isNotEmpty);
      expect(t.serverSelection.noServersFoundRetryPlex, isNotEmpty);
      expect(t.serverSelection.networkErrorTitle, isNotEmpty);
      expect(t.serverSelection.networkErrorDescription, isNotEmpty);
      expect(t.serverSelection.failedToLoadServersDescription, isNotEmpty);
    });
  });
}

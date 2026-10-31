import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/plex/plex_home_user.dart';
import 'package:pleya/profiles/active_profile_binder.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_activation.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/profile/pin_entry_dialog.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:pleya/widgets/notice/notice.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

// A-23c: a Plex token the handoff proved for the profile replaces its PIN on the Apple TV.

const _token = 'tok-anna';

final _anna = Profile.plexHome(
  id: 'plex-anna',
  displayName: 'Anna',
  parentConnectionId: 'plex-1',
  plexHomeUserUuid: 'u-anna',
  plexProtected: true,
  createdAt: DateTime(2026),
);

final _localAnna = Profile.local(
  id: 'local-anna',
  displayName: 'Anna',
  pinHash: computePinHash('1234'),
  createdAt: DateTime(2026),
);

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late PlexHomeService plexHome;
  late ActiveProfileProvider active;
  late MultiServerManager manager;
  late MultiServerProvider multiServerProvider;
  late ActiveProfileBinder binder;

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
      plexHomeUserFetcher: (_) async => const <PlexHomeUser>[],
    );
    final profiles = ProfileRegistry(db);
    active = ActiveProfileProvider(registry: profiles, plexHome: plexHome, connections: connections, storage: storage);
    manager = MultiServerManager();
    multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    binder = ActiveProfileBinder(
      activeProfile: active,
      connections: connections,
      profileConnections: profileConnections,
      serverManager: manager,
      multiServerProvider: multiServerProvider,
      pinPrompt: (_, {String? errorMessage}) async => null,
    );
    await connections.upsert(
      PlexAccountConnection(
        id: 'plex-1',
        accountToken: 'account-token',
        clientIdentifier: 'client-plex-1',
        accountLabel: 'Plex',
        createdAt: DateTime(2026),
      ),
    );
    await profiles.upsert(_localAnna);
    await profileConnections.upsert(
      const ProfileConnection(
        profileId: 'local-anna',
        connectionId: 'plex-1',
        userIdentifier: 'u-anna',
        userToken: 'tok-on-file',
      ),
    );
    await active.initialize();
  });

  tearDown(() async {
    binder.dispose();
    multiServerProvider.dispose();
    await active.resetForTesting();
    active.dispose();
    await plexHome.dispose();
    await db.close();
  });

  Future<bool?> activate(
    WidgetTester tester,
    Profile profile, {
    required bool Function() mayActivate,
    String? token,
    void Function()? onPinCancelled,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ConnectionRegistry>.value(value: connections),
          Provider<ProfileConnectionRegistry>.value(value: profileConnections),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: active),
          Provider<ActiveProfileBinder>.value(value: binder),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return tester.runAsync(
      () => activateProfileWithPin(
        context,
        profile,
        mayActivate: mayActivate,
        verifiedPlexUserToken: token,
        onPinCancelled: onPinCancelled,
      ),
    );
  }

  group('activateProfileWithPin with a proven Plex token', () {
    testWidgets('a Plex Home profile switches without a PIN and keeps the token for the binder', (tester) async {
      final ok = await activate(tester, _anna, mayActivate: () => true, token: _token);
      expect(ok, isTrue);
      expect(active.activeId, 'plex-anna');
      final row = await tester.runAsync(() => profileConnections.get('plex-anna', 'plex-1'));
      expect(row?.userToken, _token);
      expect(row?.userIdentifier, 'u-anna');
      expect(binder.consumePlexHomePreVerified('plex-anna'), isTrue);
      expect(binder.consumeUserInitiatedActivation('plex-anna'), isTrue);
    });

    testWidgets('a phone that gave up: nothing is saved, nothing marked, nothing switched', (tester) async {
      final ok = await activate(tester, _anna, mayActivate: () => false, token: _token);
      expect(ok, isFalse);
      expect(active.activeId, isNull);
      expect(await tester.runAsync(() => profileConnections.get('plex-anna', 'plex-1')), isNull);
      expect(binder.consumePlexHomePreVerified('plex-anna'), isFalse);
      expect(binder.consumeUserInitiatedActivation('plex-anna'), isFalse);
    });

    testWidgets('a token that cannot be saved still switches, unmarked, so the binder asks the PIN', (tester) async {
      profileConnections = _FailingProfileConnectionRegistry(db);
      final ok = await activate(tester, _anna, mayActivate: () => true, token: _token);
      expect(ok, isTrue);
      expect(active.activeId, 'plex-anna');
      expect(binder.consumePlexHomePreVerified('plex-anna'), isFalse);
    });

    testWidgets('a local profile switches without its PIN and its join row stays as it was', (tester) async {
      final ok = await activate(tester, _localAnna, mayActivate: () => true, token: _token);
      expect(ok, isTrue);
      expect(active.activeId, 'local-anna');
      final row = await tester.runAsync(() => profileConnections.get('local-anna', 'plex-1'));
      expect(row?.userToken, 'tok-on-file');
    });

    testWidgets('a local profile is not switched when the phone gave up', (tester) async {
      final ok = await activate(tester, _localAnna, mayActivate: () => false, token: _token);
      expect(ok, isFalse);
      expect(active.activeId, isNull);
    });
  });

  group('activateProfileWithPin reports a cancelled PIN', () {
    Future<BuildContext> mountSwitch(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: active),
            Provider<ActiveProfileBinder>.value(value: binder),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      noticeController.debugReset();
      addTearDown(noticeController.debugReset);
      return context;
    }

    final plain = Profile.local(id: 'plain-local', displayName: 'Local', createdAt: DateTime(2026));

    testWidgets('a failed UI profile switch notice expires', (tester) async {
      final context = await mountSwitch(tester);
      active.markBindingFinished(success: false);
      bool? ok;
      unawaited(switchProfileFromUi(context, plain).then((v) => ok = v));
      await tester.pumpAndSettle();
      expect(ok, isFalse);
      expect(noticeController.visible.single.notice.level, NoticeLevel.error);
      await tester.pump(const Duration(seconds: 7));
      expect(noticeController.visible, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      expect(noticeController.visible, isEmpty);
    });

    testWidgets('successful UI switch clears prior switch failure and keeps unrelated errors', (tester) async {
      final context = await mountSwitch(tester);
      active.markBindingFinished(success: false);
      bool? ok;
      unawaited(switchProfileFromUi(context, plain).then((v) => ok = v));
      await tester.pumpAndSettle();
      expect(ok, isFalse);
      noticeController.show(const Notice(level: NoticeLevel.error, title: 'Unrelated', groupKey: 'unrelated'));
      active.markBindingFinished(success: true);
      unawaited(switchProfileFromUi(context, plain).then((v) => ok = v));
      await tester.pumpAndSettle();
      expect(ok, isTrue);
      expect(noticeController.visible.map((n) => n.notice.title), ['Unrelated']);
    });

    testWidgets('cancelling a UI profile switch shows no failure notice', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConnectionRegistry>.value(value: connections),
            Provider<ProfileConnectionRegistry>.value(value: profileConnections),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: active),
            Provider<ActiveProfileBinder>.value(value: binder),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      noticeController.debugReset();
      addTearDown(noticeController.debugReset);
      bool? ok;
      unawaited(switchProfileFromUi(context, _localAnna).then((v) => ok = v));
      await tester.pumpAndSettle();
      expect(find.byType(PinEntryDialog), findsOneWidget);
      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();
      expect(ok, isFalse);
      expect(noticeController.visible, isEmpty);
      expect(active.activeId, isNull);
    });

    testWidgets('backing out of the PIN dialog calls onPinCancelled and does not switch', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConnectionRegistry>.value(value: connections),
            Provider<ProfileConnectionRegistry>.value(value: profileConnections),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: active),
            Provider<ActiveProfileBinder>.value(value: binder),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      var cancelled = 0;
      bool? ok;
      unawaited(activateProfileWithPin(context, _localAnna, onPinCancelled: () => cancelled++).then((v) => ok = v));
      await tester.pumpAndSettle();
      expect(find.byType(PinEntryDialog), findsOneWidget);
      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();
      expect(ok, isFalse);
      expect(cancelled, 1);
      expect(active.activeId, isNull);
    });

    testWidgets('backing out of a Plex Home PIN dialog calls onPinCancelled and does not switch', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConnectionRegistry>.value(value: connections),
            Provider<ProfileConnectionRegistry>.value(value: profileConnections),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: active),
            Provider<ActiveProfileBinder>.value(value: binder),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      PackageInfo.setMockInitialValues(
        appName: 'Pleya',
        packageName: 'nl.michelknoop.pleya',
        version: '2.8.0',
        buildNumber: '1',
        buildSignature: '',
      );
      var cancelled = 0;
      bool? ok;
      unawaited(activateProfileWithPin(context, _anna, onPinCancelled: () => cancelled++).then((v) => ok = v));
      // The connection lookup and PlexAuthService.create run on real async time.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.byType(PinEntryDialog), findsOneWidget);
      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();
      expect(ok, isFalse);
      expect(cancelled, 1);
      expect(active.activeId, isNull);
    });

    testWidgets('a refusal by mayActivate is not a cancelled PIN', (tester) async {
      var cancelled = 0;
      final ok = await activate(
        tester,
        _localAnna,
        mayActivate: () => false,
        token: _token,
        onPinCancelled: () => cancelled++,
      );
      expect(ok, isFalse);
      expect(cancelled, 0);
    });
  });

  test('only activateProfileWithPin may skip the PIN of a local profile', () {
    final callers = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && file.readAsStringSync().contains(RegExp(r'pinProven\s*:'))) file.path,
    ];
    expect(callers, ['lib/profiles/profile_activation.dart']);
  });

  group('ActiveProfileProvider.activate', () {
    test('a protected local profile still needs its PIN unless the caller proved the user', () async {
      expect(await active.activate(_localAnna), isFalse);
      expect(await active.activate(_localAnna, pin: '0000'), isFalse);
      expect(await active.activate(_localAnna, pinProven: true), isTrue);
    });
  });
}

class _FailingProfileConnectionRegistry extends ProfileConnectionRegistry {
  _FailingProfileConnectionRegistry(super.db);

  @override
  Future<void> upsert(ProfileConnection pc, {bool makeDefault = false, bool freshLogin = false}) =>
      Future.error(StateError('disk full'));
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/plex/plex_home_user.dart';
import 'package:pleya/profiles/active_profile_binder.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/screens/profile/borrow_connection_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

final _jellyfin = JellyfinConnection(
  id: 'jf-machine/dad',
  baseUrl: 'https://jellyfin.local',
  serverName: 'Jellyfin',
  serverMachineId: 'jf-machine',
  userId: 'dad',
  userName: 'Dad',
  accessToken: 'access-dad',
  deviceId: 'device-1',
  isAdministrator: true,
  createdAt: DateTime(2026, 1, 1),
  lastAuthenticatedAt: DateTime(2026, 1, 1),
);

final _dad = Profile.local(id: 'dad', displayName: 'Dad', createdAt: DateTime(2026, 1, 1));
final _kid = Profile.local(id: 'kid', displayName: 'Kid', createdAt: DateTime(2026, 1, 2));

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  test('recordBorrowedConnection always writes a borrowed row', () async {
    final registry = _RecordingProfileConnections();
    await recordBorrowedConnection(
      registry,
      targetProfileId: 'kid',
      connectionId: 'plex.account',
      userToken: 'minted',
      userIdentifier: 'home-uuid',
    );
    expect(registry.upserts.single.borrowed, isTrue);
    expect(registry.upserts.single.profileId, 'kid');
    expect(registry.upserts.single.tokenAcquiredAt, isNotNull);
  });

  testWidgets('borrowing a Jellyfin connection writes the copy as borrowed', (tester) async {
    final profileConnections = _RecordingProfileConnections()
      ..rows = [
        ProfileConnection(profileId: 'dad', connectionId: _jellyfin.id, userToken: 'tok-dad', userIdentifier: 'dad'),
      ];

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            Provider<ProfileRegistry>.value(value: _FakeProfiles()),
            Provider<ProfileConnectionRegistry>.value(value: profileConnections),
            Provider<ConnectionRegistry>.value(value: _FakeConnections()),
            Provider<PlexHomeService>.value(value: _FakePlexHome()),
            Provider<ActiveProfileBinder>.value(value: _FakeBinder()),
          ],
          child: InputModeTracker(
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: BorrowConnectionScreen(targetProfile: _kid),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsOneWidget);
    await tester.tap(find.byType(Card));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    final row = profileConnections.upserts.single;
    expect(row.profileId, 'kid');
    expect(row.connectionId, _jellyfin.id);
    expect(row.userToken, 'tok-dad');
    expect(row.borrowed, isTrue);
    // Let the success snackbar time out.
    await tester.pump(const Duration(seconds: 10));
  });
}

class _RecordingProfileConnections implements ProfileConnectionRegistry {
  List<ProfileConnection> rows = const [];
  final upserts = <ProfileConnection>[];

  @override
  Future<List<ProfileConnection>> listAll() async => rows;

  @override
  Future<void> upsert(ProfileConnection pc, {bool makeDefault = false, bool freshLogin = false}) async {
    upserts.add(pc);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConnections implements ConnectionRegistry {
  @override
  Future<List<Connection>> list() async => [_jellyfin];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfiles implements ProfileRegistry {
  @override
  Future<List<Profile>> list() async => [_dad, _kid];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlexHome implements PlexHomeService {
  @override
  Future<void> start() async {}

  @override
  Map<String, List<PlexHomeUser>> get current => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBinder implements ActiveProfileBinder {
  @override
  Future<void> rebindIfActive(String profileId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

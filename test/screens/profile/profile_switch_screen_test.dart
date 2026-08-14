import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/screens/profile/profile_switch_screen.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('D-pad can focus profile actions and open the manage menu', (tester) async {
    final harness = await _Harness.create(
      profiles: [Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1))],
    );

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text('Owner'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ProfileTile:local-owner');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ProfileActions:local-owner');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text(t.profiles.manage), findsOneWidget);
    expect(find.text(t.profiles.delete), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('orders profiles by recent usage from storage', (tester) async {
    final harness = await _Harness.create(
      profiles: [
        Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1)),
        Profile.local(id: 'local-kids', displayName: 'Kids', createdAt: DateTime(2026, 1, 2)),
      ],
      beforeProviders: (storage) => storage.markProfileUsed('local-kids', DateTime(2026, 1, 3)),
    );

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Kids')).dy, lessThan(tester.getTopLeft(find.text('Owner')).dy));
  });

  testWidgets('a stream that has not emitted yet shows a spinner, not "no profiles"', (tester) async {
    // `watchProfilesView` only emits once all four of its inputs have produced
    // a value. One silent input used to render as a permanent empty state.
    final harness = await _Harness.create(profileStream: const Stream<List<Profile>>.empty());

    await tester.pumpWidget(harness.build());
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t.messages.noProfilesAvailable), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a stream that never emits eventually reports a failure with a retry', (tester) async {
    final harness = await _Harness.create(profileStream: const Stream<List<Profile>>.empty());

    await tester.pumpWidget(harness.build());
    await tester.pump();
    await tester.pump();
    // Past the settle deadline the spinner is a dead end — under
    // `requireSelection` there is nothing to press but quit.
    await tester.pump(const Duration(seconds: 6));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(t.states.errorTitle), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
  });

  testWidgets('an empty system shows the add-profile button without scrolling', (tester) async {
    final harness = await _Harness.create();

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text(t.messages.noProfilesAvailable), findsOneWidget);

    final button = find.text(t.profiles.addPleyaProfile);
    expect(button, findsOneWidget);
    // The button used to sit in its own sliver below a viewport-filling empty
    // state — visible only after something scrolled it up.
    final viewportHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(viewportHeight));
  });

  testWidgets('the empty state scrolls instead of overflowing on a short viewport', (tester) async {
    tester.view.physicalSize = const Size(1400, 620);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final harness = await _Harness.create();

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(t.profiles.addPleyaProfile), findsOneWidget);
  });

  testWidgets('an empty stream while the provider holds profiles is an error, not an empty state', (tester) async {
    final harness = await _Harness.create(
      profiles: const [],
      providerProfiles: [Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1))],
    );

    await tester.pumpWidget(harness.build());
    // Not pumpAndSettle: the spinner animates forever, so settling would run
    // the clock past the deadline this test is about.
    await tester.pump();
    await tester.pump();

    // The two sources disagree for a moment whenever the last profile is
    // deleted, so a single frame of disagreement must not read as broken.
    expect(find.text(t.states.errorTitle), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));

    expect(find.text(t.states.errorTitle), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
    expect(find.text(t.messages.noProfilesAvailable), findsNothing);
  });
}

/// Wiring shared by every picker test: an in-memory database, fake registries,
/// and the providers [ProfileSwitchScreen] reads from.
class _Harness {
  final _FakeProfileRegistry profiles;
  final _FakeConnectionRegistry connections;
  final _FakeProfileConnectionRegistry profileConnections;
  final PlexHomeService plexHome;
  final ActiveProfileProvider activeProfile;

  _Harness({
    required this.profiles,
    required this.connections,
    required this.profileConnections,
    required this.plexHome,
    required this.activeProfile,
  });

  /// [profiles] backs the picker's own stream. [providerProfiles], when given,
  /// backs [ActiveProfileProvider] from a *separate* registry so the two
  /// sources of truth can be made to disagree.
  static Future<_Harness> create({
    List<Profile> profiles = const [],
    Stream<List<Profile>>? profileStream,
    List<Profile>? providerProfiles,
    Future<void> Function(StorageService storage)? beforeProviders,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = _FakeConnectionRegistry(db);
    final profileConnections = _FakeProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    await beforeProviders?.call(storage);

    PlexHomeService newPlexHome() => PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => const [],
    );

    final plexHome = newPlexHome();
    final registry = _FakeProfileRegistry(db, profiles);
    final activeProfile = providerProfiles == null
        ? ActiveProfileProvider(registry: registry, plexHome: plexHome, connections: connections, storage: storage)
        : _StubActiveProfileProvider(
            registry: registry,
            plexHome: plexHome,
            connections: connections,
            storage: storage,
            profiles: providerProfiles,
          );

    addTearDown(() async {
      activeProfile.dispose();
      await plexHome.dispose();
      await db.close();
    });

    return _Harness(
      profiles: _FakeProfileRegistry(db, profiles, watchOverride: profileStream),
      connections: connections,
      profileConnections: profileConnections,
      plexHome: plexHome,
      activeProfile: activeProfile,
    );
  }

  Widget build({bool requireSelection = false}) {
    return TranslationProvider(
      child: MultiProvider(
        providers: [
          Provider<ProfileRegistry>.value(value: profiles),
          Provider<ProfileConnectionRegistry>.value(value: profileConnections),
          Provider<ConnectionRegistry>.value(value: connections),
          Provider<PlexHomeService>.value(value: plexHome),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: ProfileSwitchScreen(requireSelection: requireSelection),
        ),
      ),
    );
  }
}

/// [ActiveProfileProvider] with a fixed profile list. The picker only reads
/// `profiles` and `activeId`, and initializing the real provider would start
/// [PlexHomeService]'s hourly refresh timer for the rest of the test.
class _StubActiveProfileProvider extends ActiveProfileProvider {
  final List<Profile> _stubProfiles;

  _StubActiveProfileProvider({
    required super.registry,
    required super.plexHome,
    required super.connections,
    required super.storage,
    required List<Profile> profiles,
  }) : _stubProfiles = profiles;

  @override
  List<Profile> get profiles => _stubProfiles;
}

class _FakeProfileRegistry extends ProfileRegistry {
  final List<Profile> _profiles;
  final Stream<List<Profile>>? _watchOverride;

  _FakeProfileRegistry(super.db, this._profiles, {Stream<List<Profile>>? watchOverride})
    : _watchOverride = watchOverride;

  @override
  Stream<List<Profile>> watchProfiles() => _watchOverride ?? Stream.value(_profiles);

  @override
  Future<List<Profile>> list() async => _profiles;
}

class _FakeConnectionRegistry extends ConnectionRegistry {
  _FakeConnectionRegistry(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);

  @override
  Future<List<Connection>> list() async => const [];
}

class _FakeProfileConnectionRegistry extends ProfileConnectionRegistry {
  _FakeProfileConnectionRegistry(super.db);

  @override
  Stream<List<ProfileConnection>> watchAll() => Stream.value(const []);
}

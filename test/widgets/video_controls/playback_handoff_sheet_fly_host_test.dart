import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/models/plex/plex_home.dart';
import 'package:pleya/profiles/active_plex_identity.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/video_controls/sheets/playback_handoff_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/watch_together_fakes.dart';

/// No active profile: the sheet looks up no Plex identity and no token.
class _NoProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Future<void> initialize() async {}

  @override
  Profile? get active => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoAccounts extends Fake implements ConnectionRegistry {
  @override
  Future<List<PlexAccountConnection>> listPlexAccounts() async => const [];
}

class _FakeProfileConnections extends Fake implements ProfileConnectionRegistry {}

class _FakePlexHome extends Fake implements PlexHomeService {}

/// An iPhone that listens for Pleya Fly (or hosts a full session) and sees one Apple TV.
class _Phone extends CompanionRemoteProvider {
  _Phone({required this.handoffOnly});

  final bool handoffOnly;
  final joined = <String>[];

  @override
  bool get isHost => true;

  @override
  bool get isHandoffOnlyHost => handoffOnly;

  @override
  Future<bool> ensureCryptoReady(
    PlexHome? home, {
    required ConnectionRegistry connections,
    required ActiveProfileProvider activeProfile,
    required ProfileConnectionRegistry profileConnections,
    ActivePlexIdentity? identity,
    PlexAccountConnection? account,
    PlexHomeResolver? plexHomeForConnection,
  }) async => true;

  @override
  Stream<List<DiscoveredHost>>? discoverHosts() => Stream.value([
    DiscoveredHost(authContextId: 'ctx', clientId: 'tv', name: 'Woonkamer', platform: 'tvOS', port: 1, ips: const []),
  ]);

  @override
  void stopDiscovery() {}

  @override
  Future<void> connectToDiscoveredHost(DiscoveredHost host) async => joined.add(host.name);

  @override
  Future<PlaybackHandoffOutcome> handOffPlayback(
    PlaybackHandoffRequest request, {
    Duration timeout = const Duration(seconds: 20),
    void Function(String profile, bool pin)? onSwitching,
  }) async => PlaybackHandoffOutcome.failed;

  @override
  Future<void> leaveSession() async {}
}

// A-23d: an iPhone that listens for Pleya Fly is a host, but only a
// handoff-only one; the A-23 sheet must still hand over to the Apple TV.
// A full host session of the phone keeps the old refusal.
void main() {
  Future<_Phone> tapTv(WidgetTester tester, {required bool handoffOnly}) async {
    final player = FakeSyncPlayer(playing: true, duration: const Duration(minutes: 90));
    addTearDown(player.dispose);
    final phone = _Phone(handoffOnly: handoffOnly);
    addTearDown(phone.dispose);
    final profile = _NoProfile();
    addTearDown(profile.dispose);

    late BuildContext hostContext;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: phone),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
          Provider<ConnectionRegistry>.value(value: _NoAccounts()),
          Provider<ProfileConnectionRegistry>.value(value: _FakeProfileConnections()),
          Provider<PlexHomeService>.value(value: _FakePlexHome()),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    unawaited(
      OverlaySheetController.of(hostContext).show<void>(
        builder: (_) => PlaybackHandoffSheet(player: player, serverId: 'srv', itemId: '1', title: 'Film'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Woonkamer'), findsOneWidget);
    await tester.tap(find.text('Woonkamer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return phone;
  }

  testWidgets('listening for Pleya Fly does not block a fly to the Apple TV', (tester) async {
    final phone = await tapTv(tester, handoffOnly: true);
    expect(phone.joined, ['Woonkamer']);
    await _drain(tester);
  });

  testWidgets('a full host session of the phone still refuses', (tester) async {
    final phone = await tapTv(tester, handoffOnly: false);
    expect(phone.joined, isEmpty);
    await _drain(tester);
  });
}

/// Lets the failure notice and the sheet's search timer run out.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 30));
}

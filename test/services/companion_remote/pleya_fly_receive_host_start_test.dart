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
import 'package:pleya/services/companion_remote/companion_remote_host_controller.dart';
import 'package:provider/provider.dart';

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

/// Derives its identity only when [identity] completes, and records host starts.
class _SlowIdentityPhone extends CompanionRemoteProvider {
  final identity = Completer<void>();
  final starts = <bool>[];

  @override
  Future<bool> ensureCryptoReady(
    PlexHome? home, {
    required ConnectionRegistry connections,
    required ActiveProfileProvider activeProfile,
    required ProfileConnectionRegistry profileConnections,
    ActivePlexIdentity? identity,
    PlexAccountConnection? account,
    PlexHomeResolver? plexHomeForConnection,
  }) async {
    await this.identity.future;
    return true;
  }

  @override
  Future<void> startHostServer({bool handoffOnly = false}) async => starts.add(handoffOnly);
}

// A-23d: the user opens Pleya and swipes it away while the phone still derives
// its identity. The pause withdraws the wish for a Pleya Fly host; the start
// that resumes afterwards must not ask for it again and bind a socket iOS takes.
void main() {
  testWidgets('a pause while the identity is derived keeps the fly host from starting', (tester) async {
    final phone = _SlowIdentityPhone();
    addTearDown(phone.dispose);
    final profile = _NoProfile();
    addTearDown(profile.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: phone),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
          Provider<ConnectionRegistry>.value(value: _NoAccounts()),
          Provider<ProfileConnectionRegistry>.value(value: _FakeProfileConnections()),
          Provider<PlexHomeService>.value(value: _FakePlexHome()),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final started = startPleyaFlyReceiveHost(context);
    await tester.pump();
    await phone.stopHandoffOnlyHost();
    phone.identity.complete();

    expect(await started, isFalse);
    expect(phone.starts, isEmpty);
    expect(phone.canStartHandoffOnlyHost, isFalse);
  });

  testWidgets('without a pause the fly host starts after the identity', (tester) async {
    final phone = _SlowIdentityPhone();
    addTearDown(phone.dispose);
    final profile = _NoProfile();
    addTearDown(profile.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: phone),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
          Provider<ConnectionRegistry>.value(value: _NoAccounts()),
          Provider<ProfileConnectionRegistry>.value(value: _FakeProfileConnections()),
          Provider<PlexHomeService>.value(value: _FakePlexHome()),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final started = startPleyaFlyReceiveHost(context);
    await tester.pump();
    phone.identity.complete();
    await started;
    expect(phone.starts, [true]);
  });
}

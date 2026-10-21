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
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_pleya_fly_sub_view.dart';
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

/// An Apple TV that sees one iPhone; joining it waits for [join] and then fails.
class _Tv extends CompanionRemoteProvider {
  final join = Completer<void>();

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
    DiscoveredHost(authContextId: 'ctx', clientId: 'phone', name: 'iPhone', platform: 'iOS', port: 1, ips: const []),
  ]);

  @override
  void stopDiscovery() {}

  @override
  Future<void> connectToDiscoveredHost(DiscoveredHost host) async {
    await join.future;
    throw StateError('no route');
  }

  @override
  Future<void> leaveSession() async {}
}

// A-23d: a fly outlives the panel that started it, and a reopened panel adopts
// its sender. After that fly fails, a search in the reopened panel must use
// the panel that is open now, not the closed one whose context is gone.
void main() {
  testWidgets('a search after an adopted fly failed finds the phones again', (tester) async {
    final tv = _Tv();
    addTearDown(tv.dispose);
    final profile = _NoProfile();
    addTearDown(profile.dispose);

    late BuildContext panelA;
    late BuildContext panelB;
    Widget host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<CompanionRemoteProvider>.value(value: tv),
        ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
        Provider<ConnectionRegistry>.value(value: _NoAccounts()),
        Provider<ProfileConnectionRegistry>.value(value: _FakeProfileConnections()),
        Provider<PlexHomeService>.value(value: _FakePlexHome()),
      ],
      child: child,
    );

    await tester.pumpWidget(
      host(
        KeyedSubtree(
          key: const ValueKey('a'),
          child: Builder(
            builder: (c) {
              panelA = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final sender = tvPleyaFlySender(panelA, onViewFailed: () {});
    await tester.runAsync(sender.search);
    expect(sender.hosts, hasLength(1));
    final running = sender.handOff(sender.hosts.single, serverId: 'srv', itemId: '1', positionMs: 0, title: 'Film');
    await tester.pump();

    // Panel A closes during the fly; panel B opens and adopts the sender.
    sender.release();
    await tester.pumpWidget(
      host(
        KeyedSubtree(
          key: const ValueKey('b'),
          child: Builder(
            builder: (c) {
              panelB = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(panelA.mounted, isFalse);
    expect(identical(tvPleyaFlySender(panelB, onViewFailed: () {}), sender), isTrue);

    tv.join.complete();
    await tester.runAsync(() => running);
    expect(sender.busy, isFalse);
    expect(sender.handingTo, isNull);

    await tester.runAsync(sender.search);
    expect(sender.hosts.map((h) => h.name), ['iPhone'], reason: 'the search used the closed panel');

    await tester.pumpWidget(const SizedBox.shrink());
    sender.release();
    await tester.pump(const Duration(seconds: 30));
  });
}

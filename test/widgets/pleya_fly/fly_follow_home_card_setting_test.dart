// Pleya Fly Meenemen (A-23e): the Home card follows "Pleya Fly ontvangen"
// while Home stays mounted. Switched on after the mount, the puller starts
// then; switched off, it stops and the card goes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/fly_follow_puller.dart';
import 'package:pleya/services/companion_remote/pleya_fly_follow.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/pleya_fly/fly_follow_card.dart';

import '../../test_helpers/prefs.dart';

class _FakeTransport implements FlyFollowTransport {
  final hosts = StreamController<List<DiscoveredHost>>.broadcast();
  bool _listening = false;

  @override
  Future<Stream<List<DiscoveredHost>>?> discover() async {
    _listening = true;
    return hosts.stream;
  }

  @override
  void stopDiscovery() => _listening = false;

  @override
  bool get listening => _listening;

  @override
  bool begin() => true;

  @override
  void end() {}

  @override
  Future<void> connect(DiscoveredHost host) async {}

  @override
  Future<FlyFollowAnswer> ask({required bool peek}) async => const FlyFollowAnswer.offer(
    FlyFollowOffer(
      serverId: 'srv-1',
      itemId: 'item-9',
      positionMs: 4602000,
      title: 'Dune: Part Two',
      from: 'Woonkamer',
    ),
  );

  @override
  Future<void> leave() async {}
}

final _tv = DiscoveredHost(
  authContextId: 'ctx',
  clientId: 'tv-1',
  name: 'Woonkamer',
  platform: 'tvOS',
  port: 1,
  ips: const ['10.0.0.2'],
  playing: true,
);

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocale(AppLocale.nl);
  });

  testWidgets('switching Pleya Fly ontvangen on after the mount starts the puller and shows the card', (tester) async {
    final settings = (await tester.runAsync(SettingsService.getInstance))!;
    expect(settings.read(SettingsService.enablePleyaFlyReceive), isFalse);
    final transport = _FakeTransport();
    addTearDown(transport.hosts.close);
    var pullers = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: FlyFollowHomeCard(
            receiveSupported: () => true,
            createPuller: () {
              pullers++;
              return FlyFollowPuller(transport: transport, resolveItem: (_, _) async => null, join: (_) async {});
            },
          ),
        ),
      ),
    );
    expect(pullers, 0, reason: 'off at the mount: nothing listens');

    await tester.runAsync(() => settings.write(SettingsService.enablePleyaFlyReceive, true));
    await tester.pump();
    expect(pullers, 1);
    expect(transport.listening, isTrue);

    await tester.runAsync(() async {
      transport.hosts.add([_tv]);
      await pumpEventQueue();
    });
    await tester.pump();
    expect(find.text('Speelt op Woonkamer'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);

    await tester.runAsync(() => settings.write(SettingsService.enablePleyaFlyReceive, false));
    await tester.pump();
    expect(find.text('Speelt op Woonkamer'), findsNothing);
    expect(transport.listening, isFalse);
    expect(pullers, 1);
  });

  testWidgets('on at the mount, the puller starts right away', (tester) async {
    final settings = (await tester.runAsync(SettingsService.getInstance))!;
    await tester.runAsync(() => settings.write(SettingsService.enablePleyaFlyReceive, true));
    final transport = _FakeTransport();
    addTearDown(transport.hosts.close);

    await tester.pumpWidget(
      MaterialApp(
        home: FlyFollowHomeCard(
          receiveSupported: () => true,
          createPuller: () =>
              FlyFollowPuller(transport: transport, resolveItem: (_, _) async => null, join: (_) async {}),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(transport.listening, isTrue);
  });
}

// Pleya Fly Meenemen (A-23e, 45-h): the Home card in each state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/fly_follow_puller.dart';
import 'package:pleya/services/companion_remote/pleya_fly_follow.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/pleya_fly/fly_follow_card.dart';

final _tv = DiscoveredHost(
  authContextId: 'ctx',
  clientId: 'tv-1',
  name: 'Woonkamer',
  platform: 'tvOS',
  port: 1,
  ips: const ['10.0.0.2'],
  playing: true,
);

const _offer = FlyFollowOffer(
  serverId: 'srv-1',
  itemId: 'item-9',
  positionMs: 4602000,
  title: 'Dune: Part Two',
  from: 'Woonkamer',
);

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.nl));

  Future<int> pumpCard(WidgetTester tester, FlyFollowCard card, {bool taking = false}) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: FlyFollowCardView(card: card, taking: taking, onTake: () => taps++),
        ),
      ),
    );
    if (find.text('Meenemen').evaluate().isNotEmpty) await tester.tap(find.text('Meenemen'));
    return taps;
  }

  testWidgets('a followable title: Speelt op, title, position and the Meenemen button', (tester) async {
    final taps = await pumpCard(tester, FlyFollowCard(tv: _tv, title: 'Dune: Part Two', offer: _offer));
    expect(find.text('Speelt op Woonkamer'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('bij 1:16:42'), findsOneWidget);
    expect(find.text('Meenemen'), findsOneWidget);
    expect(taps, 1);
  });

  testWidgets('negative control: a profile that cannot reach the server has no button', (tester) async {
    final taps = await pumpCard(
      tester,
      FlyFollowCard(tv: _tv, title: 'Dune: Part Two', offer: _offer, block: FlyFollowCardBlock.unreachable),
    );
    expect(find.text('Meenemen'), findsNothing);
    expect(find.text(t.flyFollow.unreachable), findsOneWidget);
    expect(taps, 0);
  });

  testWidgets('live TV, a local folder or Pleya Share: the title with the reason', (tester) async {
    await pumpCard(tester, FlyFollowCard(tv: _tv, title: 'NPO 1', block: FlyFollowCardBlock.unsupported));
    expect(find.text('NPO 1'), findsOneWidget);
    expect(find.text(t.flyFollow.unsupported), findsOneWidget);
    expect(find.text('Meenemen'), findsNothing);
  });

  testWidgets('while taking, the button does not take a second tap', (tester) async {
    final taps = await pumpCard(tester, FlyFollowCard(tv: _tv, title: 'Dune: Part Two', offer: _offer), taking: true);
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

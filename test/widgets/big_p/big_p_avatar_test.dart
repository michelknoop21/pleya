import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:pleya/widgets/big_p/big_p_rig.dart';

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Center(child: child),
  ),
);

/// The engine caps a frame at 50 ms like the prototype, so advance in real frames.
Future<void> _run(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

BigPAvatarState _state(WidgetTester tester) => tester.state<BigPAvatarState>(find.byType(BigPAvatar));

void main() {
  group('BigPAvatar presentation per mood', () {
    const expected = {
      BigPMood.idle: ('rest', 'rest', 'idle'),
      BigPMood.listening: ('rest', 'o', 'listening'),
      BigPMood.working: ('wijzen', 'rest', 'working'),
      BigPMood.success: ('duim_presenteren', 'laugh', 'success'),
      BigPMood.error: ('rest', 'o', 'worried'),
      BigPMood.attentive: ('rest', 'rest', 'attentive'),
    };
    for (final MapEntry(key: mood, value: (pose, mouth, face)) in expected.entries) {
      testWidgets('$mood shows $pose / mouth-$mouth / $face', (tester) async {
        await tester.pumpWidget(_host(BigPAvatar(mood: mood, entrance: false), reduced: true));
        await tester.pump();
        expect(find.byKey(ValueKey('bigp-pose-$pose')), findsOneWidget);
        expect(find.byKey(ValueKey('bigp-mouth-$mouth')), findsOneWidget);
        expect(find.byKey(ValueKey('bigp-face-$face')), findsOneWidget);
      });
    }

    testWidgets('error uses the worried brows (inner ends raised)', (tester) async {
      await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.error, entrance: false), reduced: true));
      expect(kStateWorried.bl, [-14, -16]);
      expect(kStateWorried.br, [-14, 16]);
      expect(_state(tester).expression, 'worried');
    });

    testWidgets('working with pointAt on the left uses the three-quarter pose without face layer', (tester) async {
      await tester.pumpWidget(
        _host(const BigPAvatar(mood: BigPMood.working, pointAt: Alignment.centerLeft, entrance: false), reduced: true),
      );
      expect(find.byKey(const ValueKey('bigp-pose-wijzen_links')), findsOneWidget);
      expect(find.byKey(const ValueKey('bigp-face-working')), findsNothing);
    });

    testWidgets('success cheers first, then swaps mid-squash to the thumbs-up pose', (tester) async {
      await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.idle, entrance: false)));
      await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.success, entrance: false)));
      await _run(tester, 100);
      expect(find.byKey(const ValueKey('bigp-pose-rest')), findsOneWidget); // first half of the swap
      await _run(tester, 100);
      expect(find.byKey(const ValueKey('bigp-pose-juichen')), findsOneWidget);
      expect(_state(tester).activeHops, 1);
      await _run(tester, 2000);
      expect(find.byKey(const ValueKey('bigp-pose-duim_presenteren')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('talkingText drives mouth changes and closes afterwards', (tester) async {
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.idle, entrance: false)));
    await tester.pumpWidget(
      _host(const BigPAvatar(mood: BigPMood.idle, entrance: false, talkingText: 'Twee taken op Zolder lopen weer.')),
    );
    final seen = <String>{};
    for (var i = 0; i < 40; i++) {
      await _run(tester, 40);
      seen.add(_state(tester).shownMouth);
    }
    expect(seen.length, greaterThanOrEqualTo(3), reason: 'mouths seen: $seen');
    expect(seen, contains('small'));
    await _run(tester, 3000);
    expect(_state(tester).shownMouth, 'rest');
    await tester.pumpWidget(const SizedBox());
  });

  test('talk plan: syllable rhythm, stress on names, closed between sentences', () {
    final plan = BigPTalkPlan.build('Hoi Michel. Klaar.');
    expect(plan.windows, hasLength(2));
    expect(plan.events.where((e) => e.stress), isNotEmpty);
    final gap = (plan.windows[0].$2 + plan.windows[1].$1) / 2;
    expect(plan.talkingAt(gap), isFalse);
    final calm = BigPTalkPlan.build('Dat lukte niet: Zolder is niet bereikbaar.', calm: true);
    expect(calm.events.where((e) => e.stress || e.mouth == 'big'), isEmpty);
  });

  testWidgets('nodSignal triggers one nod', (tester) async {
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.attentive, entrance: false)));
    expect(_state(tester).activePulses, 0);
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.attentive, entrance: false, nodSignal: 1)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_state(tester).activePulses, 1);
    await _run(tester, 600);
    expect(_state(tester).activePulses, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('working: nodSignal raises the finger for a finished step', (tester) async {
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.working, entrance: false)));
    await _run(tester, 400);
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.working, entrance: false, nodSignal: 1)));
    await _run(tester, 300);
    expect(find.byKey(const ValueKey('bigp-pose-vinger_presenteren')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('animated by default: entrance hop and a running ticker', (tester) async {
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.idle)));
    await _run(tester, 100);
    expect(_state(tester).activeHops, 1);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion: no loops, no hops, no scheduled frames', (tester) async {
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.idle), reduced: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(_state(tester).activeHops, 0);
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.success), reduced: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byKey(const ValueKey('bigp-pose-duim_presenteren')), findsOneWidget); // no cheer gesture, no hop
    final settled = _state(tester).rigTransform.clone();
    await tester.pump(const Duration(seconds: 2));
    expect(_state(tester).rigTransform, settled);
  });

  testWidgets('reduced motion while talking: half-open mouth, then stops ticking', (tester) async {
    await tester.pumpWidget(_host(const BigPAvatar(mood: BigPMood.idle, talkingText: 'Klaar.'), reduced: true));
    await _run(tester, 100);
    expect(_state(tester).shownMouth, 'small');
    await _run(tester, 1000);
    await tester.pump();
    expect(_state(tester).shownMouth, 'rest');
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  group('BigPPortrait', () {
    double browTop(WidgetTester tester) =>
        tester.widget<Positioned>(find.byKey(const ValueKey('bigp-portrait-brow-l'))).top!;

    testWidgets('reacts once on focus and does not loop', (tester) async {
      await tester.pumpWidget(_host(const BigPPortrait(focused: false)));
      await tester.pump();
      final rest = browTop(tester);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(_host(const BigPPortrait(focused: true)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(browTop(tester), lessThan(rest));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(browTop(tester), rest);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('reduced motion: no reaction', (tester) async {
      await tester.pumpWidget(_host(const BigPPortrait(focused: false), reduced: true));
      await tester.pumpWidget(_host(const BigPPortrait(focused: true), reduced: true));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}

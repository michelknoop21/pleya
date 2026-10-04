import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_option_card.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';

import '../../screens/tv/assistant/tv_assistant_test_support.dart';

/// Big P's cards on a phone: a tap does what Select does on TV.
void main() {
  const option = AssistantRequestOption(
    seerrId: 'movie:101',
    title: 'Aurora Drift',
    year: 2024,
    kind: 'movie',
    posterUrl: '',
    overview: 'A crew drifts past the edge of a frozen sea.',
    status: 'not_requested',
  );
  const match = AssistantTitleMatch(
    matchId: 'm',
    title: 'Aurora Drift',
    year: 2024,
    kind: 'movie',
    confidence: 'high',
    targets: [],
    snippet: 'Een expeditie op Spitsbergen.',
  );

  Future<void> pump(WidgetTester tester, Widget child) =>
      pumpTvFrame(tester, FakeAssistantController(), Center(child: SizedBox(width: 760, child: child)));

  testWidgets('a tap on a chip selects it', (tester) async {
    var taps = 0;
    await pump(tester, BigPChip(label: 'Wat kijk ik vanavond?', onSelect: () => taps++));
    await tester.tap(find.byType(BigPChip));
    expect(taps, 1);
  });

  testWidgets('a tap on a button presses it; a disabled one stays inert', (tester) async {
    var taps = 0;
    await pump(
      tester,
      Column(
        children: [
          BigPButton(key: const Key('on'), label: 'Aanvragen', onPressed: () => taps++),
          BigPButton(key: const Key('off'), label: 'Aanmaken', enabled: false, onPressed: () => taps += 10),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('on')));
    await tester.tap(find.byKey(const Key('off')));
    expect(taps, 1);
  });

  testWidgets('a tap on a match card selects it', (tester) async {
    var taps = 0;
    await pump(tester, BigPMatchCard(match: match, index: 0, onSelect: () => taps++));
    await tester.tap(find.byType(BigPMatchCard));
    expect(taps, 1);
  });

  testWidgets('a tap on an option card selects it', (tester) async {
    var taps = 0;
    await pump(tester, BigPOptionCard(option: option, index: 0, onSelect: () => taps++));
    await tester.tap(find.byType(BigPOptionCard));
    expect(taps, 1);
  });

  testWidgets('BigPScale falls back to TvHig without an ancestor and overrides with one', (tester) async {
    late double fallback, tv, scaled;
    await pump(
      tester,
      Builder(
        builder: (context) {
          fallback = BigPScale.of(context);
          tv = TvHig.of(context);
          return BigPScale(
            pt: 0.53,
            child: Builder(
              builder: (context) {
                scaled = BigPScale.of(context);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(fallback, tv);
    expect(scaled, 0.53);
  });
}

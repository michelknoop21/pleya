import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_option_card.dart';

import '../../../test_helpers/golden.dart';
import 'tv_assistant_test_support.dart';

/// BIGP-UI1: in the summoned panel (cards of 490 pt) the status label sat
/// next to the title and cut it to "Aurora (2…". There the label moves to the
/// second line, so title and year keep the full width; the surface keeps
/// mockup 38's row.
void main() {
  setUpAll(loadAppFontsForGoldens);

  const option = AssistantRequestOption(
    seerrId: 'movie:101',
    title: 'Aurora Drift',
    year: 2024,
    kind: 'movie',
    posterUrl: '',
    overview: 'A crew drifts past the edge of a frozen sea while the radio keeps calling them home.',
    status: 'partially_available',
  );

  /// [scale] 1 is 1080p, 2 is 2160p: TvHig reads the screen height.
  Future<(bool cut, double height)> pumpCard(
    WidgetTester tester, {
    required bool compact,
    required double scale,
    double width = 490,
  }) async {
    await pumpTvFrame(
      tester,
      FakeAssistantController(),
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: Size(1920 * scale, 1080 * scale)),
          // A Column, as in the panel: the card takes its own height.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width * scale,
                child: BigPOptionCard(option: option, index: 0, onSelect: () {}, compact: compact),
              ),
            ],
          ),
        ),
      ),
    );
    final title = tester.renderObject<RenderParagraph>(find.textContaining('Aurora Drift', findRichText: true).first);
    return (title.didExceedMaxLines, tester.getSize(find.byType(BigPOptionCard)).height);
  }

  for (final (label, scale) in const [('1080p', 1.0), ('2160p', 2.0)]) {
    testWidgets('summoned panel at $label: title and year fit, label on the second line, same height', (tester) async {
      final (cut, height) = await pumpCard(tester, compact: true, scale: scale);
      expect(cut, isFalse);
      expect(find.text(' (${option.year})'), findsOneWidget, reason: 'the year stays next to the title');
      expect(find.text(t.seerr.partiallyAvailable), findsOneWidget);
      // The surface card (800 pt panel, mockup 38 row) is the reference height.
      final (_, surfaceHeight) = await pumpCard(tester, compact: false, scale: scale, width: 760);
      expect(height, surfaceHeight);
    });
  }

  testWidgets('a summoned match card is as tall with a status as without one', (tester) async {
    Future<double> height(AssistantRequestOption? request) async {
      await pumpTvFrame(
        tester,
        FakeAssistantController(),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 490,
              child: BigPMatchCard(
                match: AssistantTitleMatch(
                  matchId: 'm',
                  title: 'Aurora Drift',
                  year: 2024,
                  kind: 'movie',
                  confidence: 'high',
                  targets: const [],
                  request: request,
                  snippet: 'Een expeditie op Spitsbergen.',
                ),
                index: 0,
                onSelect: () {},
                compact: true,
              ),
            ),
          ],
        ),
      );
      return tester.getSize(find.byType(BigPMatchCard)).height;
    }

    expect(await height(option), await height(null));
    // The year stands with the kind, so the title has the whole line.
    expect(find.textContaining('· 2024'), findsOneWidget);
  });
}

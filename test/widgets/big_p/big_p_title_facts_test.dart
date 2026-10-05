/// T8: the facts line on Big P's title cards. What is known shows, what is
/// not is left out, and the card is no taller for it: the facts take the
/// plot's lines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/formatters.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_option_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_title_facts.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';

import '../../screens/big_p/big_p_mobile_fixtures.dart';

AssistantTitleMatch _match({TitleFacts? facts, String title = 'Tears of Steel', String snippet = 'Een plot.'}) =>
    AssistantTitleMatch(
      matchId: 'tos',
      title: title,
      year: 2012,
      kind: 'movie',
      confidence: 'high',
      targets: [nasTarget('tos', title, 2012)],
      snippet: snippet,
      facts: facts,
    );

String _min(int minutes) => formatDurationTextual(minutes * 60000);

void main() {
  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    final dispatcher = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localeTestValue = const Locale('nl', 'NL');
    addTearDown(dispatcher.clearLocaleTestValue);
  });

  /// [card] at [width] in the balloon's scale (0.53) or the TV's (1).
  Future<void> pump(WidgetTester tester, Widget card, {double width = 340, double pt = 0.53}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: BigPScale(
              pt: pt,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('age, runtime, two genres, score and the services of the region', (tester) async {
    await pump(
      tester,
      BigPMatchCard(
        match: _match(facts: nlFacts),
        index: 0,
        onSelect: () {},
      ),
    );
    expect(find.text('6'), findsOneWidget, reason: 'the Kijkwijzer rating for NL');
    expect(find.text('${_min(105)} · Animatie · Familie'), findsOneWidget, reason: 'two genres, not three');
    expect(find.text('7.8'), findsOneWidget);
    expect(find.text(t.assistant.match.watchOn(services: 'Netflix, Disney Plus +1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing known: no facts line and no filler', (tester) async {
    await pump(tester, BigPMatchCard(match: _match(), index: 0, onSelect: () {}));
    expect(BigPTitleFacts.lineCount(null), 0);
    expect(find.descendant(of: find.byType(BigPTitleFacts), matching: find.byType(Text)), findsNothing);
    expect(find.text('Een plot.'), findsOneWidget, reason: 'the plot keeps its lines');
  });

  testWidgets('only what is known: a runtime alone, no badge, no score, no services', (tester) async {
    const facts = TitleFacts(runtimeMin: 90, sources: {'server'});
    await pump(
      tester,
      BigPMatchCard(
        match: _match(facts: facts),
        index: 0,
        onSelect: () {},
      ),
    );
    expect(find.text(_min(90)), findsOneWidget);
    expect(BigPTitleFacts.lineCount(facts), 1);
    expect(find.textContaining('Te zien op'), findsNothing);
  });

  testWidgets('services of another region do not show', (tester) async {
    const facts = TitleFacts(
      providers: {
        'US': ['Hulu'],
      },
      sources: {'tmdb'},
    );
    expect(BigPTitleFacts.lineCount(facts), 0);
    await pump(
      tester,
      BigPMatchCard(
        match: _match(facts: facts),
        index: 0,
        onSelect: () {},
      ),
    );
    expect(find.textContaining('Hulu'), findsNothing);
  });

  for (final (label, pt, width) in const [('iPhone SE balloon', 0.53, 300.0), ('TV panel', 1.0, 760.0)]) {
    testWidgets('$label: a card with facts is as tall as one with a plot', (tester) async {
      Future<double> height(TitleFacts? facts) async {
        await pump(
          tester,
          BigPMatchCard(
            match: _match(facts: facts, snippet: 'Een plot die over twee regels loopt. ' * 4),
            index: 0,
            onSelect: () {},
          ),
          pt: pt,
          width: width,
        );
        return tester.getSize(find.byType(BigPMatchCard)).height;
      }

      final plain = await height(null);
      expect(await height(nlFacts), plain);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('iPhone SE: a long title cuts off cleanly next to the facts', (tester) async {
    final match = _match(
      title: 'The Extraordinarily Long Adventures of the Little Elephant Who Dreamed',
      facts: nlFacts,
    );
    await pump(tester, BigPMatchCard(match: match, index: 0, onSelect: () {}, compact: true), width: 300);
    expect(tester.takeException(), isNull, reason: 'no overflow at 375 pt');
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('an option card shows the facts and keeps its status', (tester) async {
    const option = AssistantRequestOption(
      seerrId: 'movie:1',
      title: 'Spring',
      year: 2019,
      kind: 'movie',
      posterUrl: '',
      overview: 'Een herder en zijn hond.',
      status: 'not_requested',
      facts: TitleFacts(certifications: {'NL': 'AL'}, runtimeMin: 8, sources: {'tmdb'}),
    );
    await pump(tester, BigPOptionCard(option: option, index: 0, onSelect: () {}, compact: true));
    expect(find.text(t.assistant.match.allAges), findsOneWidget);
    expect(find.text(_min(8)), findsOneWidget);
    expect(find.text(t.assistant.option.notRequested), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

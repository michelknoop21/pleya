import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watch_session.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_labels.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_match_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_results.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_watch_card.dart';

import 'tv_assistant_test_support.dart';

/// watch_stats as a ranked card, and the two follow-up questions Pleya
/// builds from it.
void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.nl));
  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  Future<void> pump(WidgetTester tester, AssistantWatchStats stats) =>
      pumpTvFrame(tester, FakeAssistantController(), TvAssistantWatchCard(stats: stats));

  testWidgets('a period: headline with the total, viewers as portraits', (tester) async {
    await pump(
      tester,
      const AssistantWatchStats(
        serverName: 'Pleya',
        days: 7,
        users: [(name: 'Gideuh', plays: 36, seconds: 0), (name: 'Jan', plays: 6, seconds: 0)],
        titles: [
          (title: 'The Block', plays: 19, viewers: ['Gideuh', 'Jan'], show: true, target: null),
        ],
        unavailable: ['Zolder'],
      ),
    );

    expect(find.text('Kijkcijfers'), findsOneWidget);
    expect(find.text('Pleya · Afgelopen 7 dagen'), findsOneWidget);
    expect(find.text('42'), findsOneWidget, reason: 'the period total');
    expect(find.text('36×'), findsOneWidget);
    expect(find.text('6×'), findsOneWidget);
    expect(find.text('In deze periode is niets bekeken.'), findsNothing);
    expect(find.text('Geen kijkgegevens beschikbaar voor Zolder.'), findsOneWidget);
  });

  testWidgets('watched titles are title cards: plays and viewers, a library copy opens', (tester) async {
    final item = MediaItem(id: 's1', backend: MediaBackend.jellyfin, kind: MediaKind.show, title: 'The Block');
    final opened = <AssistantTitleTarget>[];
    await pumpTvFrame(
      tester,
      FakeAssistantController(),
      TvAssistantDisplayView(
        display: AssistantWatchStats(
          serverName: 'Pleya',
          days: 7,
          users: const [(name: 'Jan', plays: 26, seconds: 0)],
          titles: [
            (
              title: 'The Block',
              plays: 19,
              viewers: const ['Gideuh', 'Jan'],
              show: true,
              target: (serverId: ServerId('w'), serverName: 'W', item: item),
            ),
            (title: 'House', plays: 7, viewers: const ['Jan'], show: true, target: null),
          ],
        ),
        onOpenTitle: opened.add,
      ),
    );
    final cards = find.byType(TvAssistantMatchCard);
    expect(cards, findsNWidgets(2));
    expect(find.text('19× bekeken · Gideuh · Jan'), findsOneWidget);
    expect(
      tester.widget<TvAssistantMatchCard>(cards.last).onSelect,
      isNull,
      reason: 'no library copy: shown, not a dead stop',
    );
    tester.widget<TvAssistantMatchCard>(cards.first).onSelect!();
    expect(opened.single.item.id, 's1');
  });

  testWidgets('missing titles of a comparison are cards that open them', (tester) async {
    final item = MediaItem(id: 'm1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Dune', year: 2021);
    final opened = <AssistantTitleTarget>[];
    await pumpTvFrame(
      tester,
      FakeAssistantController(),
      TvAssistantDisplayView(
        display: AssistantServerComparison(
          serverId: ServerId('z'),
          serverName: 'Zolder',
          otherServerId: ServerId('k'),
          otherServerName: 'Kelder',
          kind: MediaKind.movie,
          missing: [item],
          missingTotal: 1,
          capped: false,
        ),
        onOpenTitle: opened.add,
      ),
    );
    expect(find.byType(TvAssistantMatchCard), findsOneWidget);
    tester.widget<TvAssistantMatchCard>(find.byType(TvAssistantMatchCard)).onSelect!();
    expect(opened.single.serverName, 'Zolder');
  });

  testWidgets('now: one line per stream, or that nobody watches', (tester) async {
    await pump(
      tester,
      const AssistantWatchStats(
        serverName: 'Pleya',
        sessions: [WatchSession(id: '1', userName: 'Omar', title: 'House')],
      ),
    );
    expect(find.text('Pleya · Op dit moment'), findsOneWidget);
    expect(find.text('Omar'), findsOneWidget);
    expect(find.text('House'), findsOneWidget);

    await pump(tester, const AssistantWatchStats(serverName: 'Pleya'));
    expect(find.text('Er kijkt nu niemand.'), findsOneWidget);
  });

  test('always three follow-ups that fit the result, never the question just asked', () {
    final f = t.assistant.followUp;
    expect(assistantFollowUps(const [AssistantWatchStats(serverName: 'P', days: 7)]), [
      f.watchNow,
      f.watchMonth,
      f.watchToday,
    ]);
    expect(assistantFollowUps(const [AssistantWatchStats(serverName: 'P')]), [f.watchToday, f.watchWeek, f.watchMonth]);
    expect(assistantFollowUps(const [], acted: true), [f.jobs, f.failedJobs, f.watchWeek]);
    expect(assistantFollowUps(const []), [f.watchWeek, f.tonight, f.recent]);
    expect(assistantFollowUps(const [], prompt: f.watchWeek), [
      f.tonight,
      f.recent,
      f.unwatched,
    ], reason: 'the question just asked is not offered again');
    expect(
      assistantFollowUps(const [
        AssistantWatchStats(serverName: 'P', days: 7, unavailable: ['P']),
      ]),
      hasLength(3),
    );
  });

  testWidgets('a server that ran out of time is not "nothing watched"', (tester) async {
    await pump(tester, const AssistantWatchStats(serverName: 'Pleya', days: 7, partial: true));
    expect(find.text('In deze periode is niets bekeken.'), findsNothing);
    expect(find.text('Niet elke server kon op tijd gelezen worden; dit kan onvolledig zijn.'), findsOneWidget);
  });

  testWidgets('no server answered is not "nothing watched"', (tester) async {
    await pump(tester, const AssistantWatchStats(serverName: 'Pleya', days: 7, unavailable: ['Pleya']));
    expect(find.text('In deze periode is niets bekeken.'), findsNothing);
    expect(find.text('Geen kijkgegevens beschikbaar voor Pleya.'), findsOneWidget);
  });

  test('Markdown in an answer becomes plain text', () {
    expect(
      assistantPlainAnswer('## Top\n\n\n**Gideuh** keek het meest:\n\n- The Block\n* House\nGebruik `scan`.'),
      'Top\n\nGideuh keek het meest:\n\n• The Block\n• House\nGebruik scan.',
    );
    expect(assistantPlainAnswer('5 * 3 = 15, my_user en -1'), '5 * 3 = 15, my_user en -1');
  });
}

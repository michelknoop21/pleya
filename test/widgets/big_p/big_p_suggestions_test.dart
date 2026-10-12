import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_capabilities.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_example_history.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_examples.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_suggestions.dart';

import 'fake_assistant_controller.dart';

void main() {
  final f = t.assistant.followUp;
  List<String> watch() => [f.watchNow, f.watchToday, f.watchYesterday, f.watchWeek, f.watchMonth];
  // Every fixed follow-up Pleya has; anything else would be server text.
  Set<String> fixed() => {
    ...watch(),
    ...f.tonight,
    ...f.recent,
    ...f.unwatched,
    ...f.popular,
    f.missingMovies,
    f.missingShows,
    f.jobs,
    f.failedJobs,
  };

  FakeAssistantController answered(List<AssistantDisplay> displays, {String? prompt}) => FakeAssistantController()
    ..state = AssistantSurfaceState.result
    ..prompt = prompt
    ..displays = displays;

  test('different seeds give different examples and follow-ups', () {
    final examples = {
      for (var seed = 0; seed < 20; seed++)
        (BigPSuggestions(random: Random(seed)).examples(FakeAssistantController())..sort()).join('|'),
    };
    expect(examples.length, greaterThan(5));
    final followUps = {
      for (var seed = 0; seed < 20; seed++)
        (assistantFollowUps(const [AssistantMediaGrid([])], random: Random(seed))..sort()).join('|'),
    };
    expect(followUps.length, greaterThan(5));
  });

  test('one answer keeps its follow-ups, one summon its examples, across rebuilds', () {
    final c = answered(const [AssistantMediaGrid([])]);
    final s = BigPSuggestions(random: Random(1));
    final first = s.followUps(c);
    final examples = s.examples(c);
    for (var i = 0; i < 10; i++) {
      expect(s.followUps(c), same(first));
      expect(s.examples(c), same(examples));
    }
    c.runs++;
    expect(s.followUps(c), isNot(same(first)), reason: 'a new answer picks again');
    s.summoned();
    expect(s.examples(c), isNot(same(examples)), reason: 'a new summon picks again');
  });

  test('never the same set twice in a row', () {
    for (var seed = 0; seed < 10; seed++) {
      final s = BigPSuggestions(random: Random(seed));
      final c = answered([const AssistantWatchStats(serverName: 'Zolder', days: 7)]);
      var lastExamples = <String>{};
      var lastFollowUps = <String>{};
      for (var i = 0; i < 30; i++) {
        s.summoned();
        final examples = s.examples(c).toSet();
        expect(examples, isNot(lastExamples));
        lastExamples = examples;
        // A week of stats leaves two sets: now, month, and today or yesterday.
        c.runs++;
        final followUps = s.followUps(c).toSet();
        expect(followUps, isNot(lastFollowUps));
        lastFollowUps = followUps;
      }
    }
  });

  test('follow-ups are fixed strings without names, and never the question just asked', () {
    final displays = <List<AssistantDisplay>>[
      const [],
      const [AssistantMediaGrid([])],
      const [AssistantWatchStats(serverName: 'Zolder')],
      const [AssistantWatchStats(serverName: 'Zolder', days: 30)],
    ];
    for (var seed = 0; seed < 20; seed++) {
      for (final d in displays) {
        for (final asked in [...f.tonight, ...f.recent, ...f.unwatched, f.watchWeek]) {
          final questions = assistantFollowUps(d, jobs: seed.isEven, prompt: asked, random: Random(seed));
          expect(questions, hasLength(3));
          expect(fixed(), containsAll(questions));
          expect(questions.join(' '), isNot(contains('Zolder')));
          expect(questions, isNot(contains(asked)));
        }
      }
    }
  });

  /// Which capability a shown question belongs to.
  AssistantCapability capabilityOf(String question) =>
      AssistantCapability.values.firstWhere((c) => assistantExamples(c).contains(question));

  group('examples', () {
    test('three capabilities from three groups, one phrasing of each', () {
      for (var seed = 0; seed < 200; seed++) {
        final shown = BigPSuggestions(random: Random(seed)).examples(FakeAssistantController());
        expect(shown, hasLength(3));
        expect(shown.map((q) => capabilityOf(q).group).toSet(), hasLength(3), reason: 'seed $seed: $shown');
      }
    });

    test('only what the profile can use is offered', () {
      // No Seerr, no administration: a member with one server.
      final member = {
        AssistantCapability.tonight,
        AssistantCapability.unwatched,
        AssistantCapability.history,
        AssistantCapability.servers,
      };
      final c = FakeAssistantController()..capabilities = member;
      final s = BigPSuggestions(random: Random(4));
      for (var i = 0; i < 60; i++) {
        s.summoned();
        final shown = s.examples(c).map(capabilityOf).toSet();
        expect(member, containsAll(shown));
        expect(shown, hasLength(3));
        expect(shown, isNot(contains(AssistantCapability.request)));
        expect(shown, isNot(contains(AssistantCapability.scan)));
      }
    });

    test('fewer than three groups: still three different capabilities', () {
      // A children's profile has watch questions only.
      final watch = {
        for (final c in AssistantCapability.values)
          if (c.group == AssistantCapabilityGroup.watch) c,
      };
      final c = FakeAssistantController()..capabilities = watch;
      for (var seed = 0; seed < 50; seed++) {
        final shown = BigPSuggestions(random: Random(seed)).examples(c).map(capabilityOf).toList();
        expect(shown.toSet(), hasLength(3));
        expect(watch, containsAll(shown));
      }
    });

    test('nothing reachable: the three plain watch questions', () {
      final c = FakeAssistantController()..capabilities = {};
      final shown = BigPSuggestions(random: Random(1)).examples(c).map(capabilityOf).toList();
      expect(shown, AssistantCapability.fallback);
    });

    test('with a history, every capability comes by before one repeats often', () {
      final c = FakeAssistantController();
      final counts = <AssistantCapability, int>{};
      final s = BigPSuggestions(random: Random(7), history: BigPExampleHistory());
      // Eight summons fill the history: 24 questions over 22 capabilities.
      for (var i = 0; i < 8; i++) {
        s.summoned();
        for (final q in s.examples(c)) {
          counts.update(capabilityOf(q), (n) => n + 1, ifAbsent: () => 1);
        }
      }
      expect(counts.values.reduce(max), lessThanOrEqualTo(3));
      expect(counts.keys.length, greaterThanOrEqualTo(15), reason: '$counts');
    });

    test('negative control: without a history the same capability returns sooner', () {
      int distinctOverEightSummons({required bool remembers}) {
        var total = 0;
        for (var seed = 0; seed < 40; seed++) {
          final c = FakeAssistantController();
          final seen = <AssistantCapability>{};
          for (var i = 0; i < 8; i++) {
            // A picker that forgets: a new one per summon, same random stream.
            final s = BigPSuggestions(
              random: Random(seed * 100 + i),
              history: remembers ? (c.history ??= BigPExampleHistory()) : BigPExampleHistory(),
            );
            seen.addAll(s.examples(c).map(capabilityOf));
          }
          total += seen.length;
        }
        return total;
      }

      expect(
        distinctOverEightSummons(remembers: true),
        greaterThan(distinctOverEightSummons(remembers: false) + 40),
        reason: 'the history spreads the questions over more capabilities',
      );
    });

    test('a phrasing the history holds is not the next one of that capability', () {
      final c = FakeAssistantController()..capabilities = {AssistantCapability.tonight};
      final history = BigPExampleHistory();
      final s = BigPSuggestions(random: Random(2), history: history);
      final phrasings = <String>{};
      for (var i = 0; i < 3; i++) {
        s.summoned();
        phrasings.add(s.examples(c).firstWhere((q) => capabilityOf(q) == AssistantCapability.tonight));
      }
      expect(phrasings, t.assistant.examples.tonight.toSet(), reason: 'three summons, three phrasings');
    });

    test('the history keeps the last 24 and knows how long ago', () {
      final history = BigPExampleHistory();
      for (var i = 0; i < 10; i++) {
        history.note([
          (capability: AssistantCapability.values[i], phrasing: 0),
          (capability: AssistantCapability.values[i + 10], phrasing: 0),
          (capability: AssistantCapability.servers, phrasing: 0),
        ]);
      }
      expect(history.shown, hasLength(BigPExampleHistory.limit));
      expect(history.summonsSince(AssistantCapability.servers), 0);
      expect(history.summonsSince(AssistantCapability.values[8]), 1);
      expect(history.summonsSince(AssistantCapability.values[0]), isNull, reason: 'fell out of the 24');
    });

    test('picked before the profile was read: picked once more when it is known', () {
      final watch = {AssistantCapability.tonight, AssistantCapability.startSeries, AssistantCapability.describe};
      final c = FakeAssistantController()
        ..capabilities = watch
        ..idleProfileKnown = false;
      final history = BigPExampleHistory();
      final s = BigPSuggestions(random: Random(5), history: history);
      final provisional = s.examples(c);
      expect(s.examples(c), same(provisional));
      expect(history.shown, isEmpty, reason: 'a provisional pick is not remembered');
      c
        ..capabilities = AssistantCapability.values.toSet()
        ..idleProfileKnown = true;
      final settled = s.examples(c);
      expect(settled, isNot(same(provisional)));
      expect(s.examples(c), same(settled), reason: 'and then kept');
      expect(history.shown, hasLength(3));
    });
  });

  test('a new language with the same answer and summon speaks it', () async {
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
    final c = answered(const [AssistantMediaGrid([])]);
    final s = BigPSuggestions(random: Random(3));
    final en = s.followUps(c);
    final enExamples = s.examples(c);
    await LocaleSettings.setLocale(AppLocale.nl);
    final nl = t.assistant.followUp;
    final nlPool = {...nl.tonight, ...nl.unwatched, ...nl.recent};
    expect(s.followUps(c), everyElement(isIn(nlPool)));
    expect(s.followUps(c), isNot(equals(en)));
    expect(s.examples(c), everyElement(isIn(AssistantCapability.values.expand(assistantExamples))));
    expect(s.examples(c), isNot(equals(enExamples)));
  });

  test('watch stats still lead to watch questions, title cards to viewing questions', () {
    for (var seed = 0; seed < 20; seed++) {
      final stats = assistantFollowUps(const [AssistantWatchStats(serverName: 'P', days: 7)], random: Random(seed));
      expect(watch(), containsAll(stats));
      final cards = assistantFollowUps(const [AssistantMediaGrid([])], random: Random(seed));
      expect(cards, [
        predicate<String>(f.tonight.contains),
        predicate<String>(f.unwatched.contains),
        predicate<String>(f.recent.contains),
      ]);
    }
  });
}

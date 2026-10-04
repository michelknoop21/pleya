import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
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
        (BigPSuggestions(random: Random(seed)).examples(t.assistant.mobile.examples)..sort()).join('|'),
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
    final examples = s.examples(t.assistant.idle.examples);
    for (var i = 0; i < 10; i++) {
      expect(s.followUps(c), same(first));
      expect(s.examples(t.assistant.idle.examples), same(examples));
    }
    c.runs++;
    expect(s.followUps(c), isNot(same(first)), reason: 'a new answer picks again');
    s.summoned();
    expect(s.examples(t.assistant.idle.examples), isNot(same(examples)), reason: 'a new summon picks again');
  });

  test('never the same set twice in a row', () {
    for (var seed = 0; seed < 10; seed++) {
      final s = BigPSuggestions(random: Random(seed));
      final c = answered([const AssistantWatchStats(serverName: 'Zolder', days: 7)]);
      var lastExamples = <String>{};
      var lastFollowUps = <String>{};
      for (var i = 0; i < 30; i++) {
        s.summoned();
        final examples = s.examples(t.assistant.mobile.examples).toSet();
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

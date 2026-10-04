import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_kind.dart';

/// Three questions that follow from what the run showed, in the UI's
/// language, after every answer. Pleya builds them from the displays and the
/// actions, never from model prose, and each one stands on its own: a new ask
/// carries no memory of this one. They carry no server, user or title names:
/// a follow-up is sent as the user's own words, and those names come from
/// servers, not from the user. The question just asked is never offered.
///
/// Each kind of question has a few phrasings; [random] picks one per kind,
/// so one call never offers the same kind twice, and shuffles the general
/// questions that fill what the result left open.
List<String> assistantFollowUps(List<AssistantDisplay> displays, {bool jobs = false, String? prompt, Random? random}) {
  final f = t.assistant.followUp;
  final rng = random ?? Random();
  String key(String q) => q.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  final asked = key(prompt ?? '');
  // A phrasing other than the one just asked, when the kind has one.
  String one(List<String> variants) {
    final open = [
      for (final v in variants)
        if (key(v) != asked) v,
    ];
    final from = open.isEmpty ? variants : open;
    return from[rng.nextInt(from.length)];
  }

  final tonight = one(f.tonight);
  final unwatched = one(f.unwatched);
  final recent = one(f.recent);
  final popular = one(f.popular);
  final sinceYesterday = one([f.watchToday, f.watchYesterday]);
  final fitting = <String>[
    // Only after a job Pleya follows (a scan, a refresh): those are admin
    // tools, and a request or download has no task to ask about.
    if (jobs) ...[f.jobs, f.failedJobs],
    for (final d in displays)
      ...switch (d) {
        AssistantWatchStats(days: null) => [sinceYesterday, f.watchWeek, f.watchMonth],
        AssistantWatchStats(:final days?) => [
          f.watchNow,
          if (days < 30) f.watchMonth else f.watchWeek,
          if (days > 1) sinceYesterday else f.watchWeek,
        ],
        AssistantServerComparison(:final kind) => [
          kind == MediaKind.show ? f.missingMovies : f.missingShows,
          unwatched,
        ],
        AssistantRequestOptions() => [popular, recent],
        AssistantTitleMatches() || AssistantMediaGrid() => [tonight, unwatched, recent],
        _ => const <String>[],
      },
    // Always three: the general questions fill what the result left open.
    ...[
      one([f.watchNow, f.watchYesterday, f.watchWeek, f.watchMonth]),
      tonight,
      recent,
      unwatched,
    ]..shuffle(rng),
  ];
  return [
    for (final q in {...fitting})
      if (key(q) != asked) q,
  ].take(3).toList();
}

/// The questions Big P offers, picked once and then kept: the examples once
/// per summon, the follow-ups once per answer, so a rebuild never reshuffles
/// what the balloon shows. A new pick is never the set shown just before,
/// when the pool has another. One per controller, on TV and on iPhone.
class BigPSuggestions {
  BigPSuggestions({Random? random}) : _random = random ?? Random();

  final Random _random;
  static final _byController = Expando<BigPSuggestions>();

  static BigPSuggestions of(AssistantController controller) => _byController[controller] ??= BigPSuggestions();

  /// Tests and shots: a seeded picker for [controller].
  @visibleForTesting
  static void install(AssistantController controller, BigPSuggestions suggestions) =>
      _byController[controller] = suggestions;

  List<String>? _examples;
  List<String> _lastExamples = const [];
  Object? _answer;
  List<String> _followUps = const [];
  List<String> _lastFollowUps = const [];

  /// Big P came out: the next greeting picks new examples.
  void summoned() => _examples = null;

  /// Three of [pool], the same until [summoned].
  List<String> examples(List<String> pool) =>
      _examples ??= _lastExamples = _fresh(() => (List.of(pool)..shuffle(_random)).take(3).toList(), _lastExamples);

  /// The follow-ups for [c]'s answer, the same while that answer shows.
  List<String> followUps(AssistantController c) {
    final jobs = c.actions.any((a) => a.job != null);
    // A started job changes which questions fit; nothing else in an answer
    // does once it shows.
    final answer = (c.runs, jobs);
    if (answer == _answer) return _followUps;
    _answer = answer;
    return _followUps = _lastFollowUps = _fresh(
      () => assistantFollowUps(c.displays, jobs: jobs, prompt: c.prompt, random: _random),
      _lastFollowUps,
    );
  }

  // ponytail: up to 32 draws; the smallest pool (two sets) repeats once in
  // four billion, and a pool with one set returns it. Listing every set and
  // dropping the last is the upgrade.
  List<String> _fresh(List<String> Function() draw, List<String> last) {
    var pick = draw();
    for (var i = 1; i < 32 && setEquals(pick.toSet(), last.toSet()); i++) {
      pick = draw();
    }
    return pick;
  }
}

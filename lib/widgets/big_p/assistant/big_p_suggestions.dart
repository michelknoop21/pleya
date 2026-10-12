import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../assistant/assistant_capabilities.dart';
import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_kind.dart';
import 'big_p_example_history.dart';
import 'big_p_examples.dart';

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
  // Pleya's own question back: its options are the follow-ups, nothing else.
  for (final d in displays) {
    if (d is AssistantClarification) return d.options;
  }
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
  BigPSuggestions({Random? random, BigPExampleHistory? history})
    : _random = random ?? Random(),
      _history = history ?? BigPExampleHistory();

  final Random _random;
  BigPExampleHistory _history;
  static final _byController = Expando<BigPSuggestions>();

  static BigPSuggestions of(AssistantController controller) => _byController[controller] ??= BigPSuggestions();

  /// Tests and shots: a seeded picker for [controller].
  @visibleForTesting
  static void install(AssistantController controller, BigPSuggestions suggestions) =>
      _byController[controller] = suggestions;

  /// The profile's own history of shown examples, read in the background.
  void remember(BigPExampleHistory history) {
    _history = history;
    unawaited(history.load());
  }

  List<String>? _examples;
  AppLocale? _examplesLocale;
  bool _examplesProvisional = false;
  List<String> _lastExamples = const [];
  Object? _answer;
  List<String> _followUps = const [];
  List<String> _lastFollowUps = const [];

  /// Big P came out: the next greeting picks new examples.
  void summoned() => _examples = null;

  /// Three questions that show what Big P can do for [c]'s profile on its
  /// servers, the same until [summoned] or a new language. Three capabilities,
  /// from three groups where the profile has that many, one phrasing of each.
  /// A capability weighs more the longer ago the greeting showed it.
  List<String> examples(AssistantController c) {
    final locale = LocaleSettings.currentLocale;
    // Picked before the profile's switches were read, as for a children's
    // profile: picked once more when they are known.
    final settled = !_examplesProvisional || !c.idleProfileKnown;
    if (_examples case final shown? when _examplesLocale == locale && settled) return shown;
    _examplesLocale = locale;
    _examplesProvisional = !c.idleProfileKnown;
    final available = c.idleCapabilities();
    var picked = const <BigPShownExample>[];
    final texts = _fresh(() {
      picked = _pickExamples(available);
      return [for (final e in picked) assistantExamples(e.capability)[e.phrasing]];
    }, _lastExamples);
    // A provisional pick is not what the user asked to see: not remembered.
    if (!_examplesProvisional) _history.note(picked);
    return _examples = _lastExamples = texts;
  }

  List<BigPShownExample> _pickExamples(Set<AssistantCapability> available) {
    final open = available.toList();
    final picked = <AssistantCapability>[];
    while (picked.length < 3 && open.isNotEmpty) {
      final groups = {for (final c in picked) c.group};
      final other = [
        for (final c in open)
          if (!groups.contains(c.group)) c,
      ];
      final next = _weighted(other.isEmpty ? open : other);
      picked.add(next);
      open.remove(next);
    }
    // Nothing reachable (every server offline): the plain watch questions.
    for (final c in AssistantCapability.fallback) {
      if (picked.length < 3 && !picked.contains(c)) picked.add(c);
    }
    return [for (final c in picked) (capability: c, phrasing: _phrasing(c))];
  }

  AssistantCapability _weighted(List<AssistantCapability> from) {
    // Shown at the last summon weighs 1, a summon earlier 2, and so on; never
    // shown (or longer ago than the history holds) weighs the most.
    int weight(AssistantCapability c) => switch (_history.summonsSince(c)) {
      null => BigPExampleHistory.limit ~/ 3 + 4,
      final ago => ago + 1,
    };
    var roll = _random.nextInt(from.fold(0, (sum, c) => sum + weight(c)));
    for (final c in from) {
      roll -= weight(c);
      if (roll < 0) return c;
    }
    return from.last;
  }

  /// A phrasing the history does not hold, when [c] has one.
  int _phrasing(AssistantCapability c) {
    final count = assistantExamples(c).length;
    final unseen = [
      for (var i = 0; i < count; i++)
        if (!_history.showed(c, i)) i,
    ];
    return unseen.isEmpty ? _random.nextInt(count) : unseen[_random.nextInt(unseen.length)];
  }

  /// The follow-ups for [c]'s answer, the same while that answer shows.
  List<String> followUps(AssistantController c) {
    final jobs = c.actions.any((a) => a.job != null);
    // A started job changes which questions fit, a new language their
    // words; nothing else in an answer does once it shows.
    final answer = (c.runs, jobs, LocaleSettings.currentLocale);
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

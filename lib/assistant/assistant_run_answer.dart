part of 'assistant_run.dart';

// The closing answer: cards for the titles it names, and in kids mode the
// age gate on them. A title the gate turned down never gets a card, and the
// model gets one correction round that Pleya itself words.

extension _AssistantAnswer on AssistantRun {
  /// The ages card, once per ask.
  void _askKidsAges() {
    if (!_displays.any((d) => d is AssistantKidsAgesPrompt)) _displays.add(AssistantKidsAgesPrompt(_prompt));
  }

  /// Settles [answer]: returns the correction for the model when it names a
  /// title the age filter turned down and [mayCorrect]; otherwise adds the
  /// cards for its titles and returns null.
  Future<String?> _settleAnswer(String answer, {required bool mayCorrect}) async {
    final step = await _lookupNamedTitles(answer);
    final rejected = _rejectedNamed(answer);
    final keep = rejected.isEmpty || !mayCorrect;
    if (keep && step?.display != null) _displays.add(step!.display!);
    if (step != null) {
      onStep?.call(
        AssistantStep(
          index: step.index,
          tool: 'find_title',
          phase: AssistantStepPhase.done,
          display: keep ? step.display : null,
        ),
      );
    }
    if (rejected.isEmpty) return null;
    if (keep) {
      // The model kept it: no card, no silent edit, a notice from Pleya.
      _ageNotice = true;
      return null;
    }
    return 'Not suitable for the youngest child (${_ctx.kidsAge} years): '
        '${[for (final r in rejected) '«${r.title}» (${r.reason})'].join(', ')}. '
        'Name only titles from tool results that passed the age filter, or say that none fits.';
  }

  /// Named titles the age gate turned down this ask and no card shows.
  List<({String title, int? year, String reason})> _rejectedNamed(String answer) {
    if (!_ctx.kidsMode || _ctx.ageRejected.isEmpty) return const [];
    final shown = assistantShownTitles(_displays);
    return [
      for (final t in assistantNamedTitles(answer))
        if (!shown.any((c) => assistantSameTitle(c, assistantTitleKey(t.title), t.year)))
          ?_ctx.ageRejected
              .where(
                (r) => assistantSameTitle(
                  (key: assistantTitleKey(r.title), year: r.year),
                  assistantTitleKey(t.title),
                  t.year,
                ),
              )
              .firstOrNull,
    ];
  }

  /// Titles the answer names without a card get one: Pleya looks them up
  /// itself with find_title and keeps the exact titles that can be opened
  /// from a library or requested. Never left to the model alone. After an
  /// action the action is the answer, and a named title is its subject. In
  /// kids mode find_title applies the age gate, so a turned-down title has
  /// no card. Returns the started step with its cards, not yet added.
  Future<({int index, AssistantDisplay? display})?> _lookupNamedTitles(String answer) async {
    if (_actions.isNotEmpty || _cancelled) return null;
    final shown = assistantShownTitles(_displays);
    final named = [
      for (final t in assistantNamedTitles(answer))
        if (!shown.any((c) => assistantSameTitle(c, assistantTitleKey(t.title), t.year))) t,
    ];
    if (named.isEmpty) return null;
    final tool = _available().keys.where((t) => t.name == 'find_title').firstOrNull;
    if (tool == null) return null;
    final index = _stepIndex++;
    onStep?.call(AssistantStep(index: index, tool: tool.name, phase: AssistantStepPhase.started));
    try {
      final titles = {for (final t in named) t.title}.toList();
      final outcome = await tool.run(_ctx, null, {
        'candidates': [
          for (final t in named) {'title': t.title, 'year': ?t.year},
        ],
        'variants': [...titles, if (titles.length == 1) titles.single.toLowerCase()],
      });
      if (outcome case AssistantToolResult(display: AssistantTitleMatches(:final context, :final matches))) {
        final exact = [
          for (final m in matches)
            if ((m.targets.isNotEmpty || m.request != null) &&
                named.any(
                  (t) => assistantSameTitle(
                    (key: assistantTitleKey(m.title), year: m.year),
                    assistantTitleKey(t.title),
                    t.year,
                  ),
                ))
              m,
        ];
        if (exact.isNotEmpty) return (index: index, display: AssistantTitleMatches(context, exact));
      }
    } on AssistantToolError catch (e) {
      if (e.code == 'kids_ages_unknown') _askKidsAges();
    } catch (e) {
      appLogger.d('Assistant: named titles lookup failed', error: e.runtimeType);
    }
    return (index: index, display: null);
  }
}

part of 'assistant_run.dart';

// The standing "nothing I watched or started" in one ask (BP-11d): whether
// the title tools drop those titles, the memory card that saves the wish, and
// the answer that may not name a dropped title. The user's words, the
// conversation and the saved preference decide; the model never does.

const _seenOnNote =
    'Pleya leaves every title this user watched or started out of the title tool results itself '
    '(filtered_seen counts them). Suggest only from what the tools return and never name a title the user '
    'watched or started. When the user is looking for one specific title and filtered_seen is above 0, say it '
    'was left out because they watched or started it; never say it was not found.';

const _seenIncludeNote =
    'For this question the user also wants titles they watched or started. Do not promise to leave them out.';

extension _AssistantRunSeen on AssistantRun {
  /// Sets the filter of this ask and returns the note for the model, or null
  /// when the question and the profile say nothing about watched titles. A
  /// children's profile keeps its own rules: no filter, no card.
  Future<Map<String, Object?>?> _beginSeenFilter(String prompt) async {
    _ctx.seenFilter = AssistantSeenFilter();
    // The memory screen's own run reads and changes facts, never titles.
    if (_ctx.kidsMode || memoryOnly) return null;
    final wish = assistantSeenWish(prompt);
    final memory = _ctx.memory;
    final history = assistantSeenHistoryQuestion(prompt);
    final saved = !history && memory != null && memory.profileCurrent && await memory.service.excludeSeen;
    final earlier =
        !history && conversation.any((turn) => assistantSeenWish(turn.question) == AssistantSeenWish.standing);
    final on = wish != AssistantSeenWish.include && (wish == AssistantSeenWish.standing || earlier || saved);
    _ctx.seenFilter = AssistantSeenFilter(on: on, prompt: prompt);
    if (wish == AssistantSeenWish.standing && !saved) await _offerSeenPreference(prompt);
    if (on) return const {'role': 'system', 'content': _seenOnNote};
    return wish == AssistantSeenWish.include ? const {'role': 'system', 'content': _seenIncludeNote} : null;
  }

  /// The standing wish waits on the memory card with Pleya's own sentence; a
  /// yes stores it and turns the preference on. After a typed "onthoud dat"
  /// it is stored at once. Without the memory (off, or none) the wish holds
  /// for this conversation only.
  Future<void> _offerSeenPreference(String prompt) async {
    final memory = _ctx.memory;
    final turn = _ctx.memoryTurn;
    if (memory == null || !turn.enabled || !userTyped) return;
    final sentence = ExcludeSeenStore.sentenceFor(dutch: languageName == 'Dutch');
    turn.standingHandled = true;
    if (assistantMemoryCommandTail(prompt) == null) {
      turn.proposals.add(
        AssistantMemoryProposal(
          kind: AssistantMemoryProposalKind.remember,
          memory: memory,
          value: sentence,
          category: MemoryCategory.preference,
          excludeSeen: true,
        ),
      );
      return;
    }
    // The one direct save of this ask, with Pleya's sentence and not the
    // model's: the model's remember_fact is not read for it.
    turn.directUsed = true;
    final result = await memory.service.add(
      value: sentence,
      category: MemoryCategory.preference,
      source: MemorySource.userExplicit,
    );
    if (!result.ok && result.code != MemoryCode.exists) {
      turn.refused = result.code;
      return;
    }
    await memory.service.setExcludeSeen(true);
    if (result.ok && result.fact != null) {
      turn.stored.add(result.fact!);
    } else {
      turn.typedKnown = true;
    }
  }

  /// The titles the filter dropped this ask that [answer] names.
  List<({String title, int? year})> _seenNamed(String answer) {
    final dropped = _ctx.seenFilter.dropped;
    if (dropped.isEmpty) return const [];
    final keys = <String>{};
    return [
      for (final t in dropped)
        if (_namesTitle(answer, t) && keys.add(assistantTitleKey(t.title))) t,
    ];
  }

  /// [text] without the sentences that name a dropped title, or Pleya's own
  /// line when nothing is left.
  String _withoutSeen(String text) {
    final named = _seenNamed(text);
    if (named.isEmpty) return text;
    final lines = [
      for (final line in text.split('\n'))
        if ([
              for (final s in _sentencesOf(line))
                if (!named.any((t) => _namesTitle(s, t))) s,
            ].join(' ')
            case final kept when kept.isNotEmpty)
          kept,
    ];
    if (lines.isNotEmpty) return lines.join('\n');
    return languageName == 'Dutch'
        ? 'Ik heb titels weggelaten die je al gezien of begonnen hebt.'
        : 'I left out titles you already watched or started.';
  }
}

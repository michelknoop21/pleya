part of 'assistant_run.dart';

// How an ask ends: the result the controller gets, and the split plans.

/// Words that say a server could not be reached, in the languages Big P
/// answers in.
const _offlineWords = [
  'offline',
  'niet bereikbaar',
  'onbereikbaar',
  'niet bereiken',
  'niet beschikbaar',
  'reageert niet',
  'unreachable',
  'not reachable',
  "isn't reachable",
  "couldn't reach",
  'could not reach',
  'unavailable',
  'not available',
  ' down',
];

/// Whether [text] says that [server] was offline: its name as a whole word in
/// a sentence that, together with the next one, also says it could not be
/// reached. A plain mention does not count: a server called "Films" is named
/// in "Films voor vanavond" without a word about its being offline. A dot
/// inside a name (`nas.local`) does not end a sentence.
bool assistantNamesOffline(String text, String server) {
  final name = server.trim().toLowerCase();
  if (name.isEmpty) return false;
  final word = RegExp('(^|[^\\p{L}\\p{N}])${RegExp.escape(name)}(\$|[^\\p{L}\\p{N}])', unicode: true);
  final sentences = text.toLowerCase().split(RegExp(r'[.!?](?=\s|$)|\n'));
  for (final (i, sentence) in sentences.indexed) {
    if (!word.hasMatch(sentence)) continue;
    final around = i + 1 < sentences.length ? '$sentence ${sentences[i + 1]}' : sentence;
    if (_offlineWords.any(around.contains)) return true;
  }
  return false;
}

extension _AssistantResult on AssistantRun {
  AssistantRunResult _end(AssistantRunEnd end, {String text = '', AssistantModelError? error, String? failure}) {
    text = assistantPlainDashes(text);
    // A pick grid the answer never narrowed (cancelled, an action, a step
    // limit) names nothing: its picks were never shown.
    _displays.removeWhere(_pickGrids.contains);
    // A run that never answered chose nothing: what its searches turned up
    // on the way is not an answer. "Too many steps" stood above ten films
    // nobody asked for (BP-12).
    if (end == AssistantRunEnd.stepLimit) {
      _displays.removeWhere((d) => d is AssistantMediaGrid || d is AssistantTitleMatches);
    }
    _dedupeGrids();
    _markRequested();
    final evidenceContext = _ctx;
    final namedTitlesCurrent = _namedTitlesCurrent;
    bool displaysCurrent() => evidenceContext.recommendationError == null && (namedTitlesCurrent?.call() ?? true);
    // Stored is stored, however the run ends: every result reports it.
    final stored = List<MemoryFact>.unmodifiable(_ctx.memoryTurn.stored);
    final turn = _ctx.memoryTurn;
    var refused = turn.refused;
    var notStored = false;
    var known = false;
    // A typed "onthoud dat ..." that ended without a save, a refusal or a
    // card. The sentence was in the memory already: Pleya says so, whether
    // the model asked for the save or not. Otherwise, when the model never
    // asked: its words may say it was remembered. Pleya's own line replaces
    // them, the reason when the memory would not take the typed words.
    final typed = turn.typedFact;
    final open =
        end == AssistantRunEnd.answered && typed != null && stored.isEmpty && refused == null && turn.proposals.isEmpty;
    if (open && turn.typedKnown) {
      known = true;
    } else if (open && !turn.asked) {
      final checked = checkMemoryValue(typed);
      if (checked.value == null) {
        refused = checked.code;
      } else {
        notStored = true;
      }
    }
    if (_ctx.libraryDoctorError case final doctorError?) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: doctorError,
        libraryDoctorError: () => evidenceContext.libraryDoctorError,
        memoryStored: stored,
        memoryRefused: refused,
      );
    }
    if (!_ctx.playbackEvidenceCurrent) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: 'playback_session_changed',
        playbackEvidenceCurrent: () => false,
        displayEvidenceCurrent: displaysCurrent,
        spoilerPrompt: _spoilerQuestion,
        memoryStored: stored,
        memoryRefused: refused,
      );
    }
    if (evidenceContext.recommendationError case final recommendationError?) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: recommendationError,
        displayEvidenceCurrent: displaysCurrent,
        memoryStored: stored,
        memoryRefused: refused,
      );
    }
    if (_displays.any((d) => d is AssistantHouseholdKidsPrompt)) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        displays: [_displays.whereType<AssistantHouseholdKidsPrompt>().first],
        householdKidsNeeded: true,
        providerError: error,
        error: failure,
        memoryStored: stored,
        memoryRefused: refused,
      );
    }
    final agesFirst = _displays.whereType<AssistantKidsAgesPrompt>().firstOrNull;
    if (agesFirst != null) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        displays: [agesFirst],
        kidsAgesNeeded: true,
        spoilerPrompt: _spoilerQuestion,
        playbackEvidenceCurrent: () => evidenceContext.playbackEvidenceCurrent,
        libraryDoctorError: () => evidenceContext.libraryDoctorError,
        providerError: error,
        error: failure,
        memoryStored: stored,
        memoryRefused: refused,
      );
    }
    // A children's profile keeps no memory: a typed "onthoud dat ..." gets
    // Pleya's own refusal, whatever the model said (BP-11h).
    final kidsRefusal = end == AssistantRunEnd.answered && turn.kidsTyped ? t.assistant.memory.kids : null;
    // A search left out a server that was offline: a partial result is never
    // shown as complete (DEC-142). The model is told to say so; where its
    // answer names no such server, Pleya adds its own line.
    if (end == AssistantRunEnd.answered && kidsRefusal == null && !_ctx.libraryDoctorMode && text.isNotEmpty) {
      final unnamed = [
        for (final name in _ctx.offlineSeen)
          if (!assistantNamesOffline(text, name)) name,
      ];
      if (unnamed.isNotEmpty) {
        final line = unnamed.length == 1
            ? t.assistant.ends.serverOffline(name: unnamed.single)
            : t.assistant.ends.serversOffline(names: unnamed.join(', '));
        text = '$text\n$line';
      }
    }
    return AssistantRunResult(
      end: end,
      text:
          kidsRefusal ??
          (_ctx.libraryDoctorMode
              ? _ctx.libraryDoctorAnswer?.call(languageName) ??
                    (languageName == 'Dutch'
                        ? 'Geen gecontroleerde bibliotheekgegevens; de diagnose blijft onbekend.'
                        : 'No checked library evidence; the diagnosis remains unknown.')
              : text),
      libraryDoctorError: () => evidenceContext.libraryDoctorError,
      spoilerPrompt: _spoilerQuestion,
      playbackEvidenceCurrent: () => evidenceContext.playbackEvidenceCurrent,
      actions: List.unmodifiable(_actions),
      displays: displaysCurrent() ? List.unmodifiable(_displays) : const [],
      displayEvidenceCurrent: displaysCurrent,
      providerError: error,
      ageFilterNotice: _ageNotice,
      memoryProposals: List.unmodifiable(_ctx.memoryTurn.proposals),
      memoryStored: stored,
      memoryRefused: refused,
      memoryNotStored: notStored,
      memoryKnown: known,
      error:
          failure ??
          _errors.values.where((code) => code != 'cancelled_by_user').firstOrNull ??
          _errors.values.firstOrNull,
    );
  }

  String _operationKey(AssistantToolCall call) {
    Object? sorted(Object? value) => switch (value) {
      final Map<String, Object?> map => {for (final key in map.keys.toList()..sort()) key: sorted(map[key])},
      final List list => list.map(sorted).toList(),
      _ => value,
    };
    try {
      return '${call.name}:${jsonEncode(sorted(jsonDecode(call.arguments.isEmpty ? '{}' : call.arguments)))}';
    } on FormatException {
      return '${call.name}:${call.arguments}';
    }
  }

  List<AssistantTaskPlan>? _splitPlans(AssistantReply reply) {
    if (reply.toolCalls.length != 1 || reply.toolCalls.single.name != 'split_tasks') return null;
    try {
      final decoded = jsonDecode(reply.toolCalls.single.arguments);
      if (decoded is! Map || decoded.length != 1 || decoded['tasks'] is! List) return null;
      final tasks = decoded['tasks'] as List;
      if (tasks.length < 2 || tasks.length > AssistantQuestionBudget.splitTaskCap) return null;
      final result = <AssistantTaskPlan>[];
      for (final task in tasks) {
        if (task is! Map || task.length != 3) return null;
        for (final key in ['title', 'intent', 'prompt']) {
          if (task[key] is! String || (task[key] as String).trim().isEmpty || (task[key] as String).length > 4000) {
            return null;
          }
        }
        result.add(
          AssistantTaskPlan(
            title: clipText(assistantPlainDashes(task['title'] as String), 120),
            intent: clipText(assistantPlainDashes(task['intent'] as String), 80),
            prompt: (task['prompt'] as String).trim(),
          ),
        );
      }
      return result;
    } on FormatException {
      return null;
    }
  }
}

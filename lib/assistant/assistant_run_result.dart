part of 'assistant_run.dart';

// How an ask ends: the result the controller gets, and the split plans.

extension _AssistantResult on AssistantRun {
  AssistantRunResult _end(AssistantRunEnd end, {String text = '', AssistantModelError? error, String? failure}) {
    final evidenceContext = _ctx;
    final namedTitlesCurrent = _namedTitlesCurrent;
    bool displaysCurrent() => evidenceContext.recommendationError == null && (namedTitlesCurrent?.call() ?? true);
    if (_ctx.libraryDoctorError case final doctorError?) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: doctorError,
        libraryDoctorError: () => evidenceContext.libraryDoctorError,
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
      );
    }
    if (evidenceContext.recommendationError case final recommendationError?) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: recommendationError,
        displayEvidenceCurrent: displaysCurrent,
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
      );
    }
    return AssistantRunResult(
      end: end,
      text: _ctx.libraryDoctorMode
          ? _ctx.libraryDoctorAnswer?.call(languageName) ??
                (languageName == 'Dutch'
                    ? 'Geen gecontroleerde bibliotheekgegevens; de diagnose blijft onbekend.'
                    : 'No checked library evidence; the diagnosis remains unknown.')
          : text,
      libraryDoctorError: () => evidenceContext.libraryDoctorError,
      spoilerPrompt: _spoilerQuestion,
      playbackEvidenceCurrent: () => evidenceContext.playbackEvidenceCurrent,
      actions: List.unmodifiable(_actions),
      displays: displaysCurrent() ? List.unmodifiable(_displays) : const [],
      displayEvidenceCurrent: displaysCurrent,
      providerError: error,
      ageFilterNotice: _ageNotice,
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
      if (tasks.length < 2 || tasks.length > 10) return null;
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
            title: clipText(task['title'] as String, 120),
            intent: clipText(task['intent'] as String, 80),
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

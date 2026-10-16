part of 'assistant_run.dart';

// The model loop of one ask: model call, split routing, spoiler fence, answer
// settling and the serial tool calls, at most [maxSteps] times.

extension _AssistantLoop on AssistantRun {
  /// The clarifying answer for a past-watch question with no audience, or null
  /// to run normally. Only for a root question on an adult profile, and only
  /// when at least two audiences can actually be answered right now.
  AssistantRunResult? _audienceQuestion() {
    if (!allowSplit || inheritedIntent != null || _ctx.kidsMode || !AssistantIntent.audienceChoiceNeeded(_prompt)) {
      return null;
    }
    // Already answered "whose" earlier in this conversation: that stands.
    if (conversation.any((turn) => AssistantIntent.fromPrompt(turn.question).audience.explicit)) return null;
    final names = _available().keys.map((t) => t.name).toSet();
    final canMe = names.contains('my_watching');
    final canHousehold = names.contains('watch_stats');
    final c = t.assistant.clarify;
    final scope = switch (_intent.days.explicit ? _intent.days.value : null) {
      1 => c.today,
      7 => c.week,
      30 => c.month,
      final int n => c.days(n: n),
      _ => '',
    };
    final kind = _intent.kind.explicit ? (_intent.kind.value == MediaKind.movie ? c.movies : c.shows) : null;
    final options = [
      if (canMe) kind == null ? c.me(scope: scope) : c.meKind(kind: kind, scope: scope),
      if (canHousehold) ...[
        kind == null ? c.others(scope: scope) : c.othersKind(kind: kind, scope: scope),
        kind == null ? c.everyone(scope: scope) : c.everyoneKind(kind: kind, scope: scope),
      ],
    ];
    if (options.length < 2) return null;
    // The question names only the audiences that have a button.
    final question = canMe ? c.question : c.questionHousehold;
    return AssistantRunResult(
      end: AssistantRunEnd.answered,
      text: question,
      displays: [AssistantClarification(question: question, options: options)],
      intent: _intent,
    );
  }

  Future<AssistantRunResult> _ask(String prompt) async {
    _errors.clear();
    _actions.clear();
    _displays.clear();
    _lookups.clear();
    _namedTitlesCurrent = null;
    _stepIndex = 0;
    _prompt = prompt;
    _ageNotice = false;
    // The profile decides, never the prompt or the model.
    _ctx.kidsMode = await _ctx.kidsProfile?.call() ?? false;
    await _beginMemory(prompt);
    _ctx.recommend = AssistantRecommendConstraints.fromPrompt(prompt);
    _intent = AssistantIntent.fromPrompt(prompt);
    if (inheritedIntent case final parent?) _intent = _intent.inheriting(parent);
    _pickGrids.clear();
    _history.clear();
    _personal = false;
    _wanted = assistantAskedCount(prompt);
    _oneTitleAsked = assistantAsksOneTitle(prompt);
    var corrected = false;
    var callsThisRun = 0;
    if (await entitlement.check() != AssistantEntitlementState.entitled) {
      return const AssistantRunResult(end: AssistantRunEnd.notEntitled);
    }
    // "Onthoud dat ..." with a story word in it: Pleya's own line, no model call.
    if (_memoryStoryClash(prompt) case final clash?) return clash;
    // A watch question that names nobody is not guessed: Pleya asks whose, with
    // the period and kind the question named kept in the options.
    if (_audienceQuestion() case final question?) return question;
    // Fresh roles before the first decision: the health probe re-reads the
    // Jellyfin admin flag and the Pleya Server role.
    try {
      await (refreshHealth?.call() ?? _ctx.servers.checkServerHealth()).timeout(healthRefresh);
    } on TimeoutException {
      // Offline servers simply drop out of the tool list.
    }

    // Servers exist but none answers. A profile without servers is not offline:
    // it takes the no-tools path below.
    if (_ctx.libraryDoctorMode &&
        _spoilerQuestion == null &&
        !_ctx.kidsMode &&
        _ctx.userServers.isNotEmpty &&
        !_ctx.userServers.any((id) => _ctx.userClient(id) != null)) {
      return _end(AssistantRunEnd.noTools, failure: 'server_unavailable');
    }

    final memoryNote = await _memoryNote(prompt);
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': _system},
      if (_screenNote() case final note?) {'role': 'system', 'content': note},
      if (_ctx.recommend.describe() case final note?) {'role': 'system', 'content': note},
      if (_intent.describe() case final note?) {'role': 'system', 'content': note},
      if (memoryNote != null) {'role': 'system', 'content': memoryNote},
      if (memoryOnly) const {'role': 'system', 'content': _memoryScreenNote},
      ..._memoryMessages(),
      {'role': 'user', 'content': prompt},
    ];

    for (var step = 0; step < maxSteps; step++) {
      final available = _available();
      // Nothing to act on (no server and no serverless service such as
      // Seerr): do not spend a model call.
      if (_ctx.userServers.isEmpty && available.keys.every((t) => t.name == 'list_servers')) {
        return _end(callsThisRun > 0 && _errors.isEmpty ? AssistantRunEnd.answered : AssistantRunEnd.noTools);
      }
      final AssistantReply reply;
      try {
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        if (budget != null && !budget!.reserveModel()) {
          // Out of budget after Pleya acted and nothing failed: the closing
          // sentence is what is lost, not the action. The run ends as done.
          if (_actions.isNotEmpty && _errors.isEmpty) return _end(AssistantRunEnd.answered);
          return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
        }
        reply = await _operation(() async {
          if (_cancelled) throw const AssistantToolError('cancelled');
          return model.chat(messages, [
            for (final e in available.entries) e.key.spec(e.value),
            if (allowSplit && step == 0) _splitSpec,
          ], abort: cancel);
        });
      } on AssistantModelException catch (e) {
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        return _end(
          e.error == AssistantModelError.toolsUnsupported
              ? AssistantRunEnd.toolsUnsupported
              : AssistantRunEnd.providerError,
          error: e.error,
        );
      } catch (e, st) {
        // Anything else from the provider path is still a provider failure,
        // not a crash of the run.
        appLogger.w('Assistant model call failed', error: e.runtimeType, stackTrace: st);
        return _end(AssistantRunEnd.providerError, error: AssistantModelError.badResponse);
      }
      // Any request for the safe route tightens this run before executing
      // siblings in the same reply. Model candidates/prose never become facts.
      if (!memoryOnly && reply.toolCalls.any((call) => call.name == 'diagnose_library')) {
        _ctx.libraryDoctorMode = true;
      }
      if (!memoryOnly && reply.toolCalls.any((call) => call.name == 'spoiler_context')) {
        _spoilerQuestion ??= prompt;
        _ctx.spoilerQuestion = _spoilerQuestion;
      }
      messages.add(reply.message);
      if (reply.toolCalls.any((call) => call.name == 'split_tasks')) {
        if (!allowSplit || step != 0) return _end(AssistantRunEnd.stepLimit, failure: 'invalid_split');
        var plans = _splitPlans(reply);
        if (plans == null) {
          // One repair turn, with only the read-only routing spec. Neither the
          // malformed reply nor its repair may execute ordinary tools.
          for (final call in reply.toolCalls) {
            messages.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': jsonEncode({'error': 'invalid_split'}),
            });
          }
          messages.add({
            'role': 'user',
            'content':
                'Return one exclusive valid split_tasks call containing every independent command. No other tools.',
          });
          if (budget != null && !budget!.reserveModel()) {
            return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
          }
          try {
            final repair = await _operation(() async {
              if (_cancelled) throw const AssistantToolError('cancelled');
              // Repair a fenced route without echoing invented plot facts,
              // child labels, prompts or arbitrary tool-call names to the model.
              final repairMessages = _spoilerQuestion == null
                  ? messages
                  : <Map<String, Object?>>[
                      {'role': 'system', 'content': _system},
                      {'role': 'user', 'content': prompt},
                      {
                        'role': 'user',
                        'content':
                            'Return one exclusive valid split_tasks call containing every independent command. No other tools.',
                      },
                    ];
              return model.chat(repairMessages, [_splitSpec], abort: cancel);
            });
            plans = _splitPlans(repair);
          } catch (_) {
            return _end(AssistantRunEnd.stepLimit, failure: 'invalid_split');
          }
        }
        if (plans == null || _cancelled) return _end(AssistantRunEnd.stepLimit, failure: 'invalid_split');
        if (budget != null && !budget!.reserveTool()) {
          return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
        }
        if (plans.any((plan) => assistantNeedsSpoilerScope('${plan.intent} ${plan.prompt}'))) {
          _spoilerQuestion ??= prompt;
        }
        return AssistantRunResult(
          end: AssistantRunEnd.answered,
          // A child task's title is model text the age gate never sees: on a
          // children's profile it stays empty and the controller numbers it.
          splitTasks: List.unmodifiable([
            for (final plan in plans)
              _ctx.kidsMode ? AssistantTaskPlan(title: '', intent: plan.intent, prompt: plan.prompt) : plan,
          ]),
          spoilerPrompt: _spoilerQuestion,
          intent: _intent,
        );
      }
      if (_spoilerQuestion != null) {
        // Enforce execution as well as advertised specs. Even an invented
        // unrestricted call or a tool-free hallucination ends with source data.
        for (final call in reply.toolCalls.take(AssistantRun.maxCallsPerReply)) {
          if (budget != null && !budget!.reserveTool()) {
            return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
          }
          if (call.name == 'spoiler_context') {
            await _execute(call);
          } else {
            // Rejection must not publish model-invented tool names as UI labels.
            await _executeCall(call);
          }
        }
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        if (_ctx.spoilerEvidence == null) {
          if (budget != null && !budget!.reserveTool()) {
            return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
          }
          await _execute(AssistantToolCall(id: 'safe-context', name: 'spoiler_context', arguments: '{}'));
        }
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        // Kids mode refuses spoiler_context: no evidence, no answer.
        final evidence = _ctx.spoilerEvidence;
        if (evidence == null) return _end(AssistantRunEnd.answered, failure: 'kids_mode_unsupported');
        return _end(AssistantRunEnd.answered, text: evidence.answer(languageName));
      }
      if (reply.toolCalls.isEmpty) {
        // An answer for children that names titles without any known age:
        // the model named them unchecked, so the ages card replaces it. An
        // answer without titles (a server status) goes through.
        if (_namesTitles(reply.content) && await _kidsAgesMissing()) {
          _askKidsAges();
          return _end(AssistantRunEnd.answered);
        }
        // One correction round when the answer names a title the age
        // filter turned down; Pleya writes that message, not the model.
        final correction = await _settleAnswer(reply.content, mayCorrect: !corrected && step + 1 < maxSteps);
        if (correction != null) {
          corrected = true;
          messages.add({'role': 'system', 'content': correction});
          continue;
        }
        // Still naming a title the age filter did not pass: Pleya's own line
        // (the controller words it), never the model's text.
        return _end(AssistantRunEnd.answered, text: _ageNotice ? '' : _presentedAnswer(reply.content));
      }
      // Serial on purpose: a write must see the state the previous one left.
      for (final (index, call) in reply.toolCalls.indexed) {
        // Every call gets an answer, so the history stays valid.
        // Counted for the memory: only the first call of an ask can store at once.
        _ctx.memoryTurn.calls++;
        final output = index >= AssistantRun.maxCallsPerReply || callsThisRun >= AssistantRun.maxCallsPerRun
            ? const <String, Object?>{'error': 'too_many_calls'}
            : budget != null && !budget!.reserveTool()
            ? const <String, Object?>{'error': 'budget_exhausted'}
            : await _execute(call);
        final operationKey = _operationKey(call);
        // Missing children's ages is a question for the user (the ages card),
        // and a tool refused for children a hint to the model: neither is a
        // failed task.
        if (output['error'] case final String code when !_kidsCodes.contains(code) && !_memoryRefusals.contains(code)) {
          _errors[operationKey] = code;
        } else if (output['library_access'] == 'failed') {
          _errors[operationKey] = 'library_access_failed';
        } else if (output['status'] == 'not_confirmed' || output['status'] == 'cancelled_by_user') {
          _errors[operationKey] = output['status'] as String;
        } else {
          _errors.remove(operationKey);
        }
        callsThisRun++;
        if (output['error'] == 'kids_ages_unknown') _askKidsAges();
        messages.add({'role': 'tool', 'tool_call_id': call.id, 'content': jsonEncode(output)});
      }
    }
    return _end(AssistantRunEnd.stepLimit);
  }
}

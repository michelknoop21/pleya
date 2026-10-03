part of 'assistant_tools.dart';

final _playbackOptions = Expando<Map<String, ({AssistantPlaybackSnapshot snapshot, AssistantPlaybackAction action})>>();

final List<AssistantTool> _playbackTools = [
  AssistantTool(
    name: 'diagnose_playback',
    description:
        'Read current player facts, explicit server stream decisions and unknowns. No invented causes. '
        'Historical detailed diagnostics are unavailable; watch_stats can supply limited retained history.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'period': {
        'type': 'string',
        'enum': ['current', 'yesterday', 'historical'],
      },
    },
    serves: (ctx, _) => ctx.playback != null,
    run: (ctx, _, args) async {
      if (args['period'] != null && args['period'] != 'current') {
        return const AssistantToolResult({
          'status': 'historical_diagnostics_unavailable',
          'unknowns': ['historical_stream_decisions', 'historical_performance', 'historical_cause'],
        });
      }
      final service = ctx.playback;
      if (ctx.cancelled || service == null || !service.available()) {
        return const AssistantToolResult({'error': 'no_active_playback'});
      }
      final snapshot = await service.sample();
      if (ctx.cancelled || snapshot == null || !service.isCurrent(snapshot)) {
        return const AssistantToolResult({'error': 'playback_session_changed'});
      }
      ctx.bindPlaybackEvidence(snapshot);
      final options = _playbackOptions[ctx] ??= {};
      options.clear();
      final shown = <Map<String, Object?>>[];
      for (final action in snapshot.actions) {
        final token = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        options[token] = (snapshot: snapshot, action: action);
        shown.add({
          'option_id': token,
          'kind': action.kind.name,
          'label': playbackSafeLabel(action.label) ?? action.kind.name,
        });
      }
      return AssistantToolResult({...snapshot.diagnose(), 'actions': shown});
    },
  ),
  AssistantTool(
    name: 'change_playback',
    description:
        'Use one option_id from this task\'s current diagnose_playback result. '
        'Only when the user explicitly asked to change playback; a diagnosis-only question only offers options. '
        'Only a registered existing player action; no repairs and no automatic retry.',
    risk: AssistantToolRisk.mutation,
    needsServer: false,
    properties: const {
      'option_id': {'type': 'string'},
    },
    required: const ['option_id'],
    serves: (ctx, _) => ctx.playback?.available() ?? false,
    run: (ctx, _, args) async {
      final option = _playbackOptions[ctx]?.remove(args['option_id']);
      if (option == null) return const AssistantToolResult({'error': 'unknown_playback_option'});
      final service = ctx.playback;
      if (ctx.cancelled || service == null || !service.isCurrent(option.snapshot)) {
        return const AssistantToolResult({'error': 'playback_session_changed'});
      }
      final done = await option.action.execute(() => !ctx.cancelled);
      if (done && !ctx.cancelled) {
        final updated = await service.sample();
        if (updated != null && service.isCurrent(updated)) ctx.bindPlaybackEvidence(updated);
      }
      return AssistantToolResult(
        {'done': done, 'kind': option.action.kind.name},
        record: done
            ? AssistantActionRecord(
                kind: AssistantActionKind.changePlayback,
                serverName: '',
                subject: playbackSafeLabel(option.action.label) ?? option.action.kind.name,
              )
            : null,
      );
    },
  ),
];

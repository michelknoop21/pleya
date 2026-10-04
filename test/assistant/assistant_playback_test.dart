import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_playback.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/mpv/player/player_stream_controllers.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/playback_stream_evidence.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;
import 'package:pleya/widgets/video_controls/widgets/performance_overlay/performance_stats.dart';

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://fixture.invalid',
  model: 'm',
);

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Model extends AssistantModelClient {
  _Model(this.respond) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final Future<AssistantReply> Function(int, List<Map<String, Object?>>) respond;
  int calls = 0;
  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) => respond(calls++, messages);
}

AssistantReply _call(String name, [Map<String, Object?> args = const {}]) {
  final call = AssistantToolCall(id: 'call', name: name, arguments: jsonEncode(args));
  return AssistantReply(
    content: '',
    toolCalls: [call],
    message: {
      'role': 'assistant',
      'tool_calls': [
        {
          'id': call.id,
          'type': 'function',
          'function': {'name': name, 'arguments': call.arguments},
        },
      ],
    },
  );
}

AssistantReply _say(String text) =>
    AssistantReply(content: text, toolCalls: const [], message: {'role': 'assistant', 'content': text});

class _TrackPlayer with PlayerStreamControllersMixin implements Player {
  @override
  PlayerState state = const PlayerState();
  @override
  late final PlayerStreams streams = createStreams();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MultiServerManager manager;
  late AssistantToolContext ctx;
  var revision = 1;
  var available = true;
  var selected = 0;
  var samples = 0;
  late AssistantPlaybackSnapshot snapshot;

  AssistantPlaybackSnapshot state({
    String? method = 'Transcode',
    PlaybackStreamEvidence evidence = const PlaybackStreamEvidence(),
    String? sourceVideo = 'hevc',
    String? subtitleCodec,
    List<AssistantPlaybackAction> actions = const [],
  }) => AssistantPlaybackSnapshot(
    sessionId: 'local-session',
    revision: revision.toString(),
    playMethod: method,
    isTranscoding: method == 'Transcode',
    streamEvidence: evidence,
    sourceVideoCodec: sourceVideo,
    sourceSubtitleCodec: subtitleCodec,
    stats: const PerformanceStats(videoCodec: 'H.264', audioCodec: 'AAC'),
    actions: actions,
  );

  Future<Map<String, Object?>> run(String name, [Map<String, Object?> args = const {}]) async =>
      (await assistantTools.firstWhere((tool) => tool.name == name).run(ctx, null, args) as AssistantToolResult).data;

  setUp(() {
    manager = MultiServerManager();
    addTearDown(manager.dispose);
    revision = 1;
    available = true;
    selected = 0;
    samples = 0;
    snapshot = state();
    ctx = AssistantToolContext(
      servers: manager,
      playback: AssistantPlaybackServices(
        available: () => available,
        sample: () async {
          samples++;
          return snapshot;
        },
        isCurrent: (s) => available && s.sessionId == 'local-session' && s.revision == revision.toString(),
      ),
    );
  });

  for (final method in ['DirectPlay', 'DirectStream']) {
    test('$method is explicit without inventing a transcode cause', () async {
      snapshot = state(method: method);
      final data = await run('diagnose_playback');
      expect(data['play_method'], method);
      expect(data['video_transcode'], method == 'DirectPlay' ? false : isNull);
      expect(data['audio_transcode'], method == 'DirectPlay' ? false : isNull);
      expect(data['subtitle_burn_in'], method == 'DirectPlay' ? false : isNull);
    });
  }

  test('video transcode evidence remains independent of audio', () async {
    snapshot = state(evidence: const PlaybackStreamEvidence(video: PlaybackStreamDecision.transcode));
    final data = await run('diagnose_playback');
    expect(data['video_transcode'], true);
    expect(data['audio_transcode'], isNull);
  });

  test('audio transcode with video copy', () async {
    snapshot = state(
      evidence: const PlaybackStreamEvidence(
        video: PlaybackStreamDecision.copy,
        audio: PlaybackStreamDecision.transcode,
      ),
    );
    final data = await run('diagnose_playback');
    expect(data['video_transcode'], false);
    expect(data['audio_transcode'], true);
  });

  test('burn-in requires explicit decision', () async {
    snapshot = state(evidence: const PlaybackStreamEvidence(subtitle: PlaybackSubtitleDecision.burn));
    expect((await run('diagnose_playback'))['subtitle_burn_in'], true);
  });

  test('combined video audio and burn evidence is retained', () async {
    snapshot = state(
      evidence: const PlaybackStreamEvidence(
        video: PlaybackStreamDecision.transcode,
        audio: PlaybackStreamDecision.transcode,
        subtitle: PlaybackSubtitleDecision.burn,
      ),
    );
    final data = await run('diagnose_playback');
    expect([data['video_transcode'], data['audio_transcode'], data['subtitle_burn_in']], [true, true, true]);
  });

  test('unknowns and source codec are distinct from observed output', () async {
    snapshot = state(method: null);
    final data = await run('diagnose_playback');
    expect(data['video_transcode'], isNull);
    expect(data['source_video_codec'], 'HEVC');
    expect(data['observed_video_codec'], 'H.264');
    expect(data['unknowns'], contains('video_transcode'));
    expect(data.containsKey('network_reason'), false);
  });

  test('PGS alone does not prove burn-in', () async {
    snapshot = state(subtitleCodec: 'pgs');
    expect((await run('diagnose_playback'))['subtitle_burn_in'], isNull);
  });

  test('no fabricated action and no cross-task option authority', () async {
    snapshot = state(
      actions: [
        AssistantPlaybackAction(
          kind: AssistantPlaybackActionKind.audio,
          label: 'Audio 2',
          execute: (_) async {
            selected++;
            return true;
          },
        ),
      ],
    );
    final data = await run('diagnose_playback');
    final options = data['actions'] as List;
    final token = (options.single as Map)['option_id'];
    expect(await run('change_playback', {'option_id': 'forged'}), {'error': 'unknown_playback_option'});
    final other = ctx.fresh();
    final tool = assistantTools.firstWhere((t) => t.name == 'change_playback');
    expect((await tool.run(other, null, {'option_id': token}) as AssistantToolResult).data, {
      'error': 'unknown_playback_option',
    });
    expect(selected, 0);
  });

  test('safe existing action executes once and uncertain failure is not retried', () async {
    snapshot = state(
      actions: [
        AssistantPlaybackAction(
          kind: AssistantPlaybackActionKind.audio,
          label: 'Audio 2',
          execute: (_) async {
            selected++;
            return false;
          },
        ),
      ],
    );
    final data = await run('diagnose_playback');
    final token = ((data['actions'] as List).single as Map)['option_id'];
    expect((await run('change_playback', {'option_id': token}))['done'], false);
    expect((await run('change_playback', {'option_id': token}))['error'], 'unknown_playback_option');
    expect(selected, 1);
  });

  test('successful existing action binds the newly sampled playback revision', () async {
    snapshot = state(
      actions: [
        AssistantPlaybackAction(
          kind: AssistantPlaybackActionKind.audio,
          label: 'Audio 2',
          execute: (_) async {
            selected++;
            revision++;
            snapshot = state();
            return true;
          },
        ),
      ],
    );
    final data = await run('diagnose_playback');
    final token = ((data['actions'] as List).single as Map)['option_id'];
    final result = await run('change_playback', {'option_id': token});
    expect(result['done'], true);
    expect(selected, 1);
    expect(ctx.playbackEvidenceCurrent, true);
  });

  test('cancellation reaches the complete action callback across its native await', () async {
    final cancel = AbortController();
    ctx = AssistantToolContext(servers: manager, playback: ctx.playback, cancel: cancel);
    final native = Completer<void>();
    final started = Completer<void>();
    snapshot = state(
      actions: [
        AssistantPlaybackAction(
          kind: AssistantPlaybackActionKind.audio,
          label: 'Audio 2',
          execute: (live) => assistantSelectPlaybackTrack(
            player: _TrackPlayer(),
            revisions: AssistantPlaybackRevision(),
            select: () async {
              started.complete();
              await native.future;
            },
            persist: (_) async {
              selected++;
            },
            isCurrent: live,
            selectionMatches: () => true,
          ),
        ),
      ],
    );
    final data = await run('diagnose_playback');
    final token = ((data['actions'] as List).single as Map)['option_id'];
    final pending = run('change_playback', {'option_id': token});
    await started.future;
    cancel.abort();
    native.complete();
    expect((await pending)['done'], false);
    expect(selected, 0);
  });

  test('no registered callbacks means no offered actions', () async {
    expect((await run('diagnose_playback'))['actions'], isEmpty);
  });

  test('stale session refuses option before callback', () async {
    snapshot = state(
      actions: [
        AssistantPlaybackAction(
          kind: AssistantPlaybackActionKind.quality,
          label: 'Quality 720p',
          execute: (_) async {
            selected++;
            return true;
          },
        ),
      ],
    );
    final data = await run('diagnose_playback');
    revision++;
    final token = ((data['actions'] as List).single as Map)['option_id'];
    expect((await run('change_playback', {'option_id': token}))['error'], 'playback_session_changed');
    expect(selected, 0);
  });

  test('ended profile or hidden source refuses sampling and action', () async {
    available = false;
    expect((await run('diagnose_playback'))['error'], 'no_active_playback');
    expect(samples, 0);
  });

  test('session changes during sampling discard late snapshot', () async {
    final sampled = Completer<AssistantPlaybackSnapshot?>();
    ctx = AssistantToolContext(
      servers: manager,
      playback: AssistantPlaybackServices(
        available: () => available,
        sample: () => sampled.future,
        isCurrent: (s) => available && s.revision == revision.toString(),
      ),
    );
    final pending = run('diagnose_playback');
    revision++;
    sampled.complete(snapshot);
    expect((await pending)['error'], 'playback_session_changed');
  });

  test('historical diagnosis is explicit unavailable and never samples current player', () async {
    expect((await run('diagnose_playback', {'period': 'yesterday'}))['status'], 'historical_diagnostics_unavailable');
    expect(samples, 0);
  });

  test('codec labels and action labels cannot leak URLs or credentials', () async {
    snapshot = state(
      sourceVideo: 'https://secret.invalid/?api_key=token',
      actions: [
        AssistantPlaybackAction(
          kind: AssistantPlaybackActionKind.subtitle,
          label: 'https://secret.invalid/?api_key=token',
          execute: (_) async => true,
        ),
      ],
    );
    final json = jsonEncode(await run('diagnose_playback'));
    expect(json, isNot(contains('secret.invalid')));
    expect(json, isNot(contains('api_key')));
    expect(json, isNot(contains('token')));
  });

  test('old player lease cannot remove replacement playback services', () {
    final provider = PlaybackStateProvider();
    addTearDown(provider.dispose);
    final old = provider.registerAssistantPlayback(ctx.playback!);
    final replacement = AssistantPlaybackServices(
      available: () => false,
      sample: () async => null,
      isCurrent: (_) => false,
    );
    final release = provider.registerAssistantPlayback(replacement);
    old();
    expect(provider.assistantPlayback, same(replacement));
    release();
    expect(provider.assistantPlayback, isNull);
  });

  test('track revision rejects ABA changes even with the same final selection', () {
    final changes = AssistantPlaybackRevision();
    changes.observe('A');
    final original = changes.value;
    changes.observe('B');
    changes.observe('A');
    expect(changes.value, greaterThan(original));
    final current = changes.value;
    changes.observe('A');
    expect(changes.value, current);
  });

  test('production native event binding invalidates ABA and ignores disposed predecessor events', () async {
    final player = _TrackPlayer();
    final changes = AssistantPlaybackRevision();
    final release = changes.bind(player, isCurrent: () => true);
    addTearDown(player.closeStreamControllers);
    final original = changes.value;
    const a = TrackSelection(audio: AudioTrack(id: '1'));
    const b = TrackSelection(audio: AudioTrack(id: '2'));
    player.trackController.add(a);
    await Future<void>.delayed(Duration.zero);
    final selectedA = changes.value;
    player.trackController.add(b);
    player.trackController.add(a);
    await Future<void>.delayed(Duration.zero);
    expect(changes.value, greaterThan(selectedA));
    expect(changes.value, greaterThan(original));
    final beforeBackend = changes.value;
    player.backendSwitchedController.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(changes.value, greaterThan(beforeBackend));
    release();
    final released = changes.value;
    player.trackController.add(b);
    player.backendSwitchedController.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(changes.value, released);
  });

  test('native selection completes before preferences and profile change stops persistence', () async {
    final native = Completer<void>();
    final started = Completer<void>();
    final events = <String>[];
    var current = true;
    final pending = assistantSelectPlaybackTrack(
      player: _TrackPlayer(),
      revisions: AssistantPlaybackRevision(),
      select: () async {
        events.add('select');
        started.complete();
        await native.future;
      },
      persist: (_) async {
        events.add('persist');
      },
      isCurrent: () => current,
      selectionMatches: () => true,
    );
    await started.future;
    current = false;
    native.complete();
    expect(await pending, false);
    expect(events, ['select']);
  });

  test('complete safe native selection and persistence sequence', () async {
    final events = <String>[];
    expect(
      await assistantSelectPlaybackTrack(
        player: _TrackPlayer(),
        revisions: AssistantPlaybackRevision(),
        select: () async {
          events.add('select');
        },
        persist: (guard) async {
          expect(guard(), true);
          events.add('persist');
        },
        isCurrent: () => true,
        selectionMatches: () => true,
      ),
      true,
    );
    expect(events, ['select', 'persist']);
  });

  test('late final model diagnosis is discarded after playback ends', () async {
    final finalStarted = Completer<void>();
    final finalAnswer = Completer<AssistantReply>();
    final model = _Model((round, _) async {
      if (round == 0) return _call('diagnose_playback');
      finalStarted.complete();
      return finalAnswer.future;
    });
    addTearDown(model.close);
    final run = AssistantRun(
      model: model,
      context: ctx,
      confirm: (_) async => null,
      entitlement: const _Entitled(),
      refreshHealth: () async {},
    );
    final pending = run.ask('What is happening during playback?');
    await finalStarted.future;
    available = false;
    finalAnswer.complete(_say('Old session diagnosis'));
    final result = await pending;
    expect(result.text, isEmpty);
    expect(result.error, 'playback_session_changed');
  });

  test('multi-command stale diagnosis does not overwrite independent task', () async {
    const a = TrackSelection(audio: AudioTrack(id: '1'));
    const b = TrackSelection(audio: AudioTrack(id: '2'));
    final player = _TrackPlayer()..state = const PlayerState(track: a);
    final changes = AssistantPlaybackRevision();
    final release = changes.bind(player, isCurrent: () => true);
    addTearDown(release);
    addTearDown(player.closeStreamControllers);
    revision = changes.value;
    snapshot = state();
    ctx = AssistantToolContext(
      servers: manager,
      playback: AssistantPlaybackServices(
        available: () => true,
        sample: () async => snapshot,
        isCurrent: (s) => s.revision == changes.value.toString(),
      ),
    );
    final delayed = Completer<AssistantReply>();
    final diagnosed = Completer<void>();
    var models = 0;
    final controller = AssistantController(
      buildContext: (_) => ctx,
      entitlement: const _Entitled(),
      loadConfig: () async => _config,
      modelFor: (_) {
        switch (models++) {
          case 0:
            return _Model(
              (_, _) async => _call('split_tasks', {
                'tasks': [
                  {'title': 'Doctor', 'intent': 'playback', 'prompt': 'Diagnose playback'},
                  {'title': 'Servers', 'intent': 'catalog', 'prompt': 'List servers'},
                ],
              }),
            );
          case 1:
            return _Model((round, _) async {
              if (round == 0) return _call('diagnose_playback');
              diagnosed.complete();
              return delayed.future;
            });
          default:
            return _Model((_, _) async => _say('Other task finished'));
        }
      },
    );
    addTearDown(controller.dispose);
    final pending = controller.submit('Diagnose playback and list servers');
    await diagnosed.future;
    player.trackController.add(b);
    player.trackController.add(a);
    await Future<void>.delayed(Duration.zero);
    delayed.complete(_say('Stale diagnosis'));
    await pending;
    expect(controller.tasks[0].status, AssistantTaskStatus.failed);
    expect(controller.tasks[0].answer, isEmpty);
    expect(controller.tasks[0].error, 'playback_session_changed');
    expect(controller.tasks[1].status, AssistantTaskStatus.completed);
    expect(controller.tasks[1].answer, 'Other task finished');
  });

  test('Plex retains only explicit unambiguous decisions', () {
    Map<String, Object?> fixture(List<Object?> streams) => {
      'MediaContainer': {
        'Metadata': [
          {
            'Media': [
              {
                'Part': [
                  {'Stream': streams},
                ],
              },
            ],
          },
        ],
      },
    };
    final evidence = PlaybackStreamEvidence.plex(
      fixture([
        {'streamType': 1, 'decision': 'copy'},
        {'streamType': 2, 'decision': 'transcode'},
        {'streamType': 3, 'decision': 'burn'},
      ]),
    );
    expect(evidence.video, PlaybackStreamDecision.copy);
    expect(evidence.audio, PlaybackStreamDecision.transcode);
    expect(evidence.subtitle, PlaybackSubtitleDecision.burn);
    expect(
      PlaybackStreamEvidence.plex(
        fixture([
          {'streamType': 3, 'codec': 'pgs'},
        ]),
      ).subtitle,
      isNull,
    );
    expect(
      PlaybackStreamEvidence.plex(
        fixture([
          {'streamType': 2, 'decision': 'transcode'},
          {'streamType': 2, 'decision': 'copy'},
        ]),
      ).audio,
      isNull,
    );
  });

  test('Jellyfin requested URL codecs alone are not runtime evidence', () {
    final evidence = PlaybackStreamEvidence.jellyfin({
      'TranscodingUrl': '/stream?VideoCodec=h264&SubtitleMethod=Encode',
    });
    expect(evidence.video, isNull);
    expect(evidence.subtitle, isNull);
    final explicit = PlaybackStreamEvidence.jellyfin({
      'TranscodingInfo': {'IsVideoDirect': true, 'IsAudioDirect': false, 'SubtitleDeliveryMethod': 'burn'},
    });
    expect(explicit.video, PlaybackStreamDecision.copy);
    expect(explicit.audio, PlaybackStreamDecision.transcode);
  });
}

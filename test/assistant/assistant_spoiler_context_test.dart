import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_execution.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_spoiler_context.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/jellyfin_mappers.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import 'assistant_find_fakes.dart' as find;

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://model.test',
  model: 'm',
);

class _Entitlement extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

AssistantReply _reply({String content = 'MODEL_HALLUCINATION', String? tool, Map<String, Object?> args = const {}}) =>
    AssistantReply(
      content: content,
      toolCalls: tool == null ? const [] : [AssistantToolCall(id: 'call', name: tool, arguments: jsonEncode(args))],
      message: {'role': 'assistant', 'content': content},
    );

class _Model extends AssistantModelClient {
  _Model(this.reply) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final AssistantReply reply;
  List<AssistantReply> following = [];
  final messagesSeen = <String>[];
  final specsSeen = <List<String>>[];
  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    messagesSeen.add(jsonEncode(messages));
    specsSeen.add([for (final tool in tools) (tool['function'] as Map)['name'] as String]);
    return messagesSeen.length == 1 || following.isEmpty ? reply : following.removeAt(0);
  }
}

MediaItem _episode(
  String id,
  int number,
  String summary, {
  int? watched = 1,
  int? offset = 0,
  int season = 1,
  String? library = 'library',
  MediaBackend backend = MediaBackend.jellyfin,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.episode,
  serverId: 's',
  libraryId: library,
  parentId: season == 0 ? 'specials' : 'season',
  grandparentId: 'show',
  parentIndex: season,
  index: number,
  title: 'Title $summary',
  originallyAvailableAt: '2026-01-${number.toString().padLeft(2, '0')}',
  summary: summary,
  viewCount: watched,
  viewOffsetMs: offset,
  roles: const [],
  raw: {'future': 'RAW_SECRET'},
  genres: ['CAST_SECRET'],
);

// Exercise the real DTO mapper: IndexNumberEnd survives only in raw metadata.
MediaItem _jellyfinEpisode(String id, int number, {Object? end, int season = 1}) => JellyfinMappers.mediaItem(
  {
    'Id': id,
    'Type': 'Episode',
    'Name': id,
    'Overview': 'COMPOUND_FUTURE_SENTINEL Anna gardener',
    'SeriesId': 'show',
    'SeasonId': 'season',
    'ParentLibraryId': 'library',
    'ParentIndexNumber': season,
    'IndexNumber': number,
    'IndexNumberEnd': end,
    'UserData': {'Played': true, 'PlaybackPositionTicks': 0},
  },
  serverId: ServerId('s'),
  absolutizer: null,
)!;

class _Server extends find.FakeServer {
  _Server(this.episodes) : super('s');
  final List<MediaItem> episodes;
  final asked = <String>[];

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => [
    _episode('current', 3, 'PARTIAL_SECRET', offset: 10000),
  ];
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
  Completer<void>? stall;
  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    asked.add(parentId);
    await stall?.future;
    if (parentId == 'show') {
      return [
        MediaItem(
          id: 'specials',
          backend: MediaBackend.jellyfin,
          kind: MediaKind.season,
          index: 0,
          parentId: 'show',
          libraryId: 'library',
        ),
        MediaItem(
          id: 'season',
          backend: MediaBackend.jellyfin,
          kind: MediaKind.season,
          index: 1,
          parentId: 'show',
          libraryId: 'library',
          summary: 'SERIES_SECRET',
        ),
        MediaItem(
          id: 'future-season',
          backend: MediaBackend.jellyfin,
          kind: MediaKind.season,
          index: 2,
          parentId: 'show',
          libraryId: 'library',
        ),
      ];
    }
    return parentId == 'season' ? episodes : [_episode('special', 1, 'SPECIAL_SECRET', season: 0)];
  }
}

class _Fixture {
  final cache = AssistantSpoilerIndexCache();
  String profile = 'p';
  bool visible = true, live = true, stopped = false;
  int season = 1, number = 3, position = 10000;
  String session = 'session';
  bool boundaryKnown = true;
  late final server = _Server([
    _episode('earlier', 1, 'SAFE_SOURCE gardener knew Anna'),
    _episode('unwatched', 2, 'UNWATCHED_SECRET', watched: 0),
    _episode('current', 3, 'PARTIAL_SECRET', watched: 20),
    _episode('future', 4, 'FUTURE_SECRET', watched: 20).copyWith(originallyAvailableAt: '2026-01-03'),
    _episode('unknown', 5, 'UNKNOWN_SECRET', watched: null),
    _episode('resumable', 6, 'RESUMABLE_SECRET', offset: 5000),
    _episode('libraryless', 2, 'LIBRARYLESS_SECRET', library: null),
  ]);
  AssistantWatchBoundary boundary() => AssistantWatchBoundary(
    profileId: profile,
    serverId: 's',
    libraryId: 'library',
    showId: 'show',
    episodeId: 'current',
    season: season,
    episode: number,
    positionMs: position,
    durationMs: 60000,
    sessionId: session,
    revision: '1',
  );
  AssistantSpoilerServices services() {
    final captured = profile;
    return AssistantSpoilerServices(
      profileId: captured,
      profileCurrent: () => profile == captured,
      boundary: () => boundaryKnown ? boundary() : null,
      boundaryCurrent: (b) => live && b.sessionId == session && b.positionMs <= position,
      libraryVisible: (_, _) => visible,
    );
  }

  Future<AssistantSpoilerContext> build({String question = 'Anna gardener'}) => buildAssistantSpoilerContext(
    services: services(),
    clientFor: (_) => server,
    cancelled: () => stopped,
    question: question,
    cache: cache,
  );
  AssistantToolContext context() {
    final base = find.findCtx([server]);
    return AssistantToolContext(servers: base.servers, spoilers: services());
  }
}

void main() {
  test('supported original NL/EN context and episode phrases establish the fence', () {
    for (final phrase in [
      'Waar was ik ook alweer gebleven?',
      'Wie was die persoon ook alweer?',
      'Welke aflevering was dat waarin iemand verdween?',
      'Wie is Anna?',
      'Who was Anna?',
      'No spoilers please',
      'spoilervrij',
      'zonder spoilers',
      'Explain the scene',
      'Recap this series',
    ]) {
      expect(assistantNeedsSpoilerScope(phrase), isTrue, reason: phrase);
    }
    expect(assistantNeedsSpoilerScope('scan library'), isFalse);
    expect(assistantNeedsSpoilerScope('download three episodes'), isFalse);
    expect(assistantNeedsSpoilerScope('Explain why playback buffers'), isFalse);
    expect(assistantNeedsSpoilerScope('Explain playback without spoilers'), isTrue);
  });

  test('actual index excludes current/future on rewatch and all unproved sources', () async {
    final f = _Fixture();
    final result = await f.build();
    expect(result.position?.episode, 3);
    expect(result.index!.length, 1);
    expect(result.matches.single.item.id, 'earlier');
    for (final secret in [
      'PARTIAL_SECRET',
      'FUTURE_SECRET',
      'UNWATCHED_SECRET',
      'UNKNOWN_SECRET',
      'RESUMABLE_SECRET',
      'LIBRARYLESS_SECRET',
      'SPECIAL_SECRET',
      'SERIES_SECRET',
      'CAST_SECRET',
      'RAW_SECRET',
    ]) {
      expect(result.index!.search([secret]), isEmpty, reason: secret);
      expect(jsonEncode(result.matches.single.item.toJson()), isNot(contains(secret)));
    }
    expect(f.server.asked, ['show', 'season']);
  });

  test('Jellyfin compound 1..3 cannot enter the actual index at rewatch E2', () async {
    final f = _Fixture()..number = 2;
    final compound = _jellyfinEpisode('compound', 1, end: 3);
    expect(compound.raw!['IndexNumberEnd'], 3);
    expect(compound.viewCount, greaterThan(0));
    f.server.episodes
      ..clear()
      ..addAll([compound, _episode('current', 2, 'PARTIAL_SECRET', watched: 20)]);
    final result = await f.build();
    expect(result.position?.episode, 2);
    expect(result.index!.search(['COMPOUND_FUTURE_SENTINEL']), isEmpty);
    expect(result.matches, isEmpty);
    expect(result.answer('English'), isNot(contains('COMPOUND_FUTURE_SENTINEL')));
  });

  test('Jellyfin compound facts cannot reach actual run output or model messages', () async {
    final f = _Fixture()..number = 2;
    f.server.episodes
      ..clear()
      ..addAll([_jellyfinEpisode('compound', 1, end: 3), _episode('current', 2, 'PARTIAL_SECRET', watched: 20)]);
    final model = _Model(_reply(tool: 'spoiler_context'));
    final result = await AssistantRun(
      model: model,
      context: f.context(),
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
    ).ask('Who is Anna without spoilers?');
    expect(model.messagesSeen, isNotEmpty);
    expect(model.messagesSeen.join(), isNot(contains('COMPOUND_FUTURE_SENTINEL')));
    expect(result.text, isNot(contains('COMPOUND_FUTURE_SENTINEL')));
    expect(result.text, contains('Onvoldoende veilige brongegevens'));
    expect(result.displays, isEmpty);
  });

  test('Jellyfin ambiguous source numbering never supplies facts', () async {
    for (final end in <Object>[2, 3, 0, -1, 1.5, '3', true, <int>[], <String, int>{}]) {
      final f = _Fixture();
      f.server.episodes[0] = _jellyfinEpisode('earlier', 1, end: end);
      final result = await f.build();
      expect(result.position?.episode, 3, reason: '$end');
      expect(result.index!.search(['COMPOUND_FUTURE_SENTINEL']), isEmpty, reason: '$end');
      expect(result.matches, isEmpty, reason: '$end');
    }
    final special = _Fixture();
    special.server.episodes[0] = _jellyfinEpisode('earlier', 1, season: 0, end: 3);
    expect((await special.build()).matches, isEmpty);
  });

  test('Jellyfin compound or malformed current numbering closes the position', () async {
    for (final end in <Object>[4, 2, 0, -1, 3.5, '3', true, <int>[], <String, int>{}]) {
      final f = _Fixture();
      f.server.episodes[2] = _jellyfinEpisode('current', 3, end: end);
      final result = await f.build();
      expect(result.position, isNull, reason: '$end');
      expect(result.index, isNull, reason: '$end');
      expect(result.answer('English'), contains('not reliably known'), reason: '$end');
      expect(result.answer('English'), isNot(contains('SAFE_SOURCE')), reason: '$end');
    }
    final special = _Fixture();
    special.server.episodes[2] = _jellyfinEpisode('current', 3, season: 0);
    expect((await special.build()).position, isNull);
  });

  test('Jellyfin ordinary E1 remains allowed before E2 with null or equal end', () async {
    for (final end in <int?>[null, 1]) {
      final f = _Fixture()..number = 2;
      f.server.episodes
        ..clear()
        ..addAll([_jellyfinEpisode('earlier', 1, end: end), _jellyfinEpisode('current', 2, end: 2)]);
      final result = await f.build();
      expect(result.position?.episode, 2);
      expect(result.matches.single.item.id, 'earlier');
      expect(result.index!.length, 1);
    }
  });

  test('unknown position and specials close before fetching or indexing', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.boundaryKnown = false,
      (f) => f.season = 0,
      (f) => f.number = 0,
      (f) => f.position = -1,
      (f) => f.position = 60000,
      (f) => f.visible = false,
    ]) {
      final f = _Fixture();
      change(f);
      final result = await f.build();
      expect(result.index, isNull);
      expect(result.answer('Dutch'), contains('niet betrouwbaar bekend'));
      expect(f.server.asked, isEmpty);
    }
  });

  test('missing summary yields position and explicit insufficiency without fallback', () async {
    final f = _Fixture();
    f.server.episodes.removeWhere((e) => e.id == 'earlier');
    final result = await f.build();
    expect(result.position, isNotNull);
    expect(result.matches, isEmpty);
    expect(result.answer('English'), contains('Insufficient safe source data'));
  });

  test('cache isolates profiles, exact content and watch boundaries', () async {
    final f = _Fixture();
    final first = await f.build();
    expect(identical((await f.build()).index, first.index), isTrue);
    f.profile = 'other';
    final other = await f.build();
    expect(identical(other.index, first.index), isFalse);
    f.position = 12000;
    expect(identical((await f.build()).index, other.index), isFalse);
    f.server.episodes[0] = _episode('earlier', 1, 'CHANGED_SOURCE');
    expect((await f.build(question: 'changed')).matches.single.item.summary, 'CHANGED_SOURCE');
    f.number = 1; // Rewound beyond every earlier episode.
    expect((await f.build()).index, isNull); // Current ID/order mismatch refuses the boundary.
  });

  test('cancel, profile, session, backwards seek and hidden changes across await drop build', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.stopped = true,
      (f) => f.profile = 'changed',
      (f) => f.session = 'replacement',
      (f) => f.visible = false,
      (f) => f.position = 1,
      (f) => f.live = false,
    ]) {
      final f = _Fixture();
      f.server.stall = Completer<void>();
      final future = f.build();
      await pumpEventQueue();
      change(f);
      f.server.stall!.complete();
      final result = await future;
      expect(result.index, isNull);
      expect(f.server.asked, ['show']);
    }
  });

  test('final publication predicate invalidates already built evidence', () async {
    final f = _Fixture();
    final result = await f.build();
    f.visible = false;
    expect(result.current(), isFalse);
    expect(result.answer('English'), isNot(contains('SAFE_SOURCE')));
  });

  for (final reply in [
    _reply(),
    _reply(tool: 'find_title'),
    _reply(tool: 'search_catalog'),
    _reply(tool: 'spoiler_context'),
  ]) {
    test(
      'actual model specs and execution fence reject ${reply.toolCalls.firstOrNull?.name ?? 'tool-free prose'}',
      () async {
        final f = _Fixture();
        final ctx = f.context();
        final model = _Model(reply);
        var unsafeCalls = 0;
        final unsafe = AssistantTool(
          name: 'find_title',
          description: 'unsafe',
          risk: AssistantToolRisk.read,
          needsServer: false,
          properties: const {},
          required: const [],
          serves: (_, _) => true,
          run: (_, _, _) async {
            unsafeCalls++;
            return const AssistantToolResult({'summary': 'FUTURE_SECRET'});
          },
        );
        final result = await AssistantRun(
          model: model,
          context: ctx,
          confirm: (_) async => null,
          entitlement: _Entitlement(),
          refreshHealth: () async {},
          tools: [unsafe],
        ).ask('Who is Anna? No spoilers.');
        expect(unsafeCalls, 0);
        expect(model.specsSeen.single, ['spoiler_context']);
        expect(model.messagesSeen.single, isNot(contains('FUTURE_SECRET')));
        expect(model.messagesSeen.single, isNot(contains('PARTIAL_SECRET')));
        expect(result.text, contains('SAFE_SOURCE'));
        expect(result.text, isNot(contains('MODEL_HALLUCINATION')));
        expect(result.text, isNot(contains('FUTURE_SECRET')));
        final matches = result.displays.single as AssistantTitleMatches;
        expect(matches.matches.single.targets.single.item.id, 'earlier');
        expect(matches.matches.single.snippet, contains('SAFE_SOURCE'));
      },
    );
  }

  test('safe tool actual payload contains only grounded earlier snippets and position', () async {
    final f = _Fixture();
    final ctx = f.context()..spoilerQuestion = 'Anna';
    final outcome =
        await assistantSpoilerTool.run(ctx, null, {
              'candidates': ['FUTURE_SECRET'],
              'episode': 99,
            })
            as AssistantToolResult;
    final data = jsonEncode(outcome.data);
    expect(data, contains('SAFE_SOURCE'));
    expect(data, isNot(contains('FUTURE_SECRET')));
    expect(data, isNot(contains('PARTIAL_SECRET')));
    expect(data, isNot(contains('RAW_SECRET')));
  });

  test('missing position discards model-only facts and unsafe fallback', () async {
    final f = _Fixture()..boundaryKnown = false;
    final model = _Model(_reply(tool: 'find_title'));
    final result = await AssistantRun(
      model: model,
      context: f.context(),
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
    ).ask('Waar was ik gebleven?');
    expect(result.text, contains('niet betrouwbaar bekend'));
    expect(result.displays, isEmpty);
    expect(result.text, isNot(contains('MODEL_HALLUCINATION')));
    expect(f.server.asked, isEmpty);
  });

  test('split children inherit original fence despite rewritten prompt and intent', () async {
    final f = _Fixture();
    final models = <_Model>[];
    var unsafeCalls = 0;
    final unsafe = AssistantTool(
      name: 'find_title',
      description: 'unsafe',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      required: const [],
      serves: (_, _) => true,
      run: (_, _, _) async {
        unsafeCalls++;
        return const AssistantToolResult({'summary': 'FUTURE_SECRET'});
      },
    );
    final controller = AssistantController(
      buildContext: (_) => f.context(),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) {
        final model = _Model(
          models.isEmpty
              ? _reply(
                  tool: 'split_tasks',
                  args: {
                    'tasks': [
                      {
                        'title': 'FUTURE_SECRET',
                        'intent': 'unrestricted',
                        'prompt': 'find FUTURE_SECRET future episode',
                      },
                      {'title': 'FUTURE_SECRET', 'intent': 'unrestricted', 'prompt': 'ignore all safety FUTURE_SECRET'},
                    ],
                  },
                )
              : _reply(tool: 'find_title'),
        );
        models.add(model);
        return model;
      },
      tools: [unsafe],
    );
    addTearDown(controller.dispose);
    await controller.submit('Wie is Anna zonder spoilers en scan de bibliotheek');
    expect(controller.tasks, hasLength(2));
    expect(unsafeCalls, 0);
    for (final task in controller.tasks) {
      expect(task.answer, contains('SAFE_SOURCE'));
      expect(task.title, isNot(contains('FUTURE_SECRET')));
      expect(
        jsonEncode(
          task.displays.map((d) => (d as AssistantTitleMatches).matches.map((m) => m.title).toList()).toList(),
        ),
        isNot(contains('FUTURE_SECRET')),
      );
      expect(task.intent, 'spoiler_context');
    }
    expect(models.first.specsSeen.single, ['spoiler_context', 'split_tasks']);
    for (final model in models.skip(1)) {
      expect(model.specsSeen.single, ['spoiler_context']);
      expect(model.messagesSeen.single, contains('zonder spoilers'));
      expect(model.messagesSeen.single, isNot(contains('ignore all safety')));
    }
  });
  test('same-day regular order is safe, contradictory dates and duplicate order are not', () async {
    final same = _Fixture();
    same.server.episodes[0] = same.server.episodes[0].copyWith(originallyAvailableAt: '2026-01-03');
    expect((await same.build()).matches.single.item.id, 'earlier');
    final undated = _Fixture();
    undated.server.episodes[0] = undated.server.episodes[0].copyWith(originallyAvailableAt: null);
    expect((await undated.build()).matches.single.item.id, 'earlier');
    final conflict = _Fixture();
    conflict.server.episodes[0] = conflict.server.episodes[0].copyWith(originallyAvailableAt: '2026-02-01');
    expect((await conflict.build()).index!.search(['SAFE_SOURCE']), isEmpty);
    final duplicate = _Fixture();
    duplicate.server.episodes.add(_episode('alternate', 1, 'ALTERNATE_SECRET'));
    expect((await duplicate.build()).index, isNull);
  });

  test('fenced split repair never echoes invented narrative into actual model input', () async {
    final f = _Fixture();
    final model =
        _Model(
            _reply(
              content: 'FUTURE_SECRET',
              tool: 'split_tasks',
              args: {
                'tasks': [
                  {'title': 'FUTURE_SECRET', 'prompt': 'FUTURE_SECRET', 'intent': 'FUTURE_SECRET'},
                ],
              },
            ),
          )
          ..following = [
            _reply(
              tool: 'split_tasks',
              args: {
                'tasks': [
                  {'title': 'one', 'intent': 'safe', 'prompt': 'one'},
                  {'title': 'two', 'intent': 'safe', 'prompt': 'two'},
                ],
              },
            ),
          ];
    final result = await AssistantRun(
      model: model,
      context: f.context(),
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
      allowSplit: true,
    ).ask('Who is Anna without spoilers?');
    expect(model.messagesSeen, hasLength(2));
    expect(model.messagesSeen.join(), isNot(contains('FUTURE_SECRET')));
    expect(result.spoilerPrompt, 'Who is Anna without spoilers?');
    expect(result.splitTasks, hasLength(2));
  });

  test('invented unsafe tool names are rejected without UI-visible steps or facts', () async {
    final f = _Fixture();
    final steps = <AssistantStep>[];
    final result = await AssistantRun(
      model: _Model(_reply(tool: 'FUTURE_SECRET')),
      context: f.context(),
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
      onStep: steps.add,
    ).ask('No spoilers: who is Anna?');
    expect(steps.every((step) => step.tool == 'spoiler_context'), isTrue);
    expect(result.text, isNot(contains('FUTURE_SECRET')));
  });

  test('new submit cancels old fenced fetch and ignores its late display and answer', () async {
    final f = _Fixture();
    final ctx = f.context();
    f.server.stall = Completer<void>();
    final controller = AssistantController(
      buildContext: (_) => ctx,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => _Model(_reply(content: 'NEW_ANSWER')),
    );
    addTearDown(controller.dispose);
    final old = controller.submit('Who is Anna without spoilers?');
    await pumpEventQueue();
    expect(f.server.asked, ['show']);
    await controller.submit('hello');
    f.server.stall!.complete();
    await old;
    expect(controller.answer, 'NEW_ANSWER');
    expect(controller.displays, isEmpty);
    expect(controller.tasks.single.title, 'hello');
  });
  test('stale final lease clears already streamed fenced displays and step payloads', () async {
    final f = _Fixture();
    final ctx = f.context();
    final controller = AssistantController(
      buildContext: (_) => ctx,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => _Model(_reply(tool: 'spoiler_context')),
    );
    addTearDown(controller.dispose);
    var streamed = false;
    controller.addListener(() {
      if (controller.displays.isNotEmpty) {
        streamed = true;
        f.visible = false;
      }
    });
    await controller.submit('Who is Anna? No spoilers.');
    expect(streamed, isTrue);
    expect(controller.displays, isEmpty);
    expect(controller.tasks.single.displays, isEmpty);
    expect(controller.steps.where((step) => step.display != null), isEmpty);
    expect(controller.answer, isNot(contains('SAFE_SOURCE')));
    expect(controller.tasks.single.error, 'playback_session_changed');
  });

  test('unchanged final lease keeps grounded streamed fenced results', () async {
    final f = _Fixture();
    final ctx = f.context();
    final controller = AssistantController(
      buildContext: (_) => ctx,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => _Model(_reply(tool: 'spoiler_context')),
    );
    addTearDown(controller.dispose);
    await controller.submit('Who is Anna? No spoilers.');
    expect(controller.displays, hasLength(1));
    expect(controller.tasks.single.displays, hasLength(1));
    expect(controller.answer, contains('SAFE_SOURCE'));
    expect(controller.tasks.single.error, isNull);
  });

  test('client replacement after await closes builder without indexing old source', () async {
    final f = _Fixture();
    f.server.stall = Completer<void>();
    var client = f.server;
    final future = buildAssistantSpoilerContext(
      services: f.services(),
      clientFor: (_) => client,
      cancelled: () => false,
      question: 'Anna',
      cache: f.cache,
    );
    await pumpEventQueue();
    client = _Server([]);
    f.server.stall!.complete();
    expect((await future).index, isNull);
    expect(f.server.asked, ['show']);
  });
  test('clearing one stale fenced child retains the other parallel grounded result', () async {
    final stale = _Fixture(), stable = _Fixture();
    final staleCtx = stale.context(), stableCtx = stable.context();
    var nextContext = stableCtx, models = 0;
    final controller = AssistantController(
      buildContext: (_) => nextContext,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) {
        models++;
        nextContext = models == 2 ? staleCtx : stableCtx;
        return _Model(
          models == 1
              ? _reply(
                  tool: 'split_tasks',
                  args: {
                    'tasks': [
                      {'title': 'one', 'intent': 'safe', 'prompt': 'one'},
                      {'title': 'two', 'intent': 'safe', 'prompt': 'two'},
                    ],
                  },
                )
              : _reply(tool: 'spoiler_context'),
        );
      },
    );
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.tasks.first.displays.isNotEmpty) stale.visible = false;
    });
    await controller.submit('Who is Anna without spoilers?');
    expect(controller.tasks, hasLength(2));
    expect(controller.tasks.first.displays, isEmpty);
    expect(controller.tasks.first.error, 'playback_session_changed');
    expect(controller.tasks.last.displays, hasLength(1));
    expect(controller.tasks.last.answer, contains('SAFE_SOURCE'));
    expect(controller.tasks.last.error, isNull);
  });
  for (final prompt in [
    'Explain this episode and fix the audio',
    'Summarize the episodes I have watched',
    'Explain this show',
    'Explain why this show is slow',
    'Uitleg over de film en audio',
    'Explain this movie and fix the audio',
    'Explain this series',
    'Uitleg over deze film',
    'Uitleg film en audio',
    'Verklaar deze serie en herstel de audio',
    'Verklaar serie en audio',
    'Explain X and fix the audio',
    'Explain A and fix audio',
    'Explain Ω and fix audio',
    'Explain',
    'Explain why',
  ]) {
    test('mixed or English recap original prompt is fenced before first model call: $prompt', () async {
      final f = _Fixture();
      final model = _Model(_reply(tool: 'find_title'));
      var unsafe = 0;
      final tool = AssistantTool(
        name: 'find_title',
        description: 'unsafe',
        risk: AssistantToolRisk.read,
        needsServer: false,
        properties: const {},
        required: const [],
        serves: (_, _) => true,
        run: (_, _, _) async {
          unsafe++;
          return const AssistantToolResult({'plot': 'FUTURE_SECRET'});
        },
      );
      final result = await AssistantRun(
        model: model,
        context: f.context(),
        confirm: (_) async => null,
        entitlement: _Entitlement(),
        refreshHealth: () async {},
        tools: [tool],
      ).ask(prompt);
      expect(model.specsSeen.first, ['spoiler_context']);
      expect(unsafe, 0);
      expect(result.text, isNot(contains('MODEL_HALLUCINATION')));
      expect(result.text, isNot(contains('FUTURE_SECRET')));
      final proseModel = _Model(_reply());
      final controller = AssistantController(
        buildContext: (_) => f.context(),
        entitlement: _Entitlement(),
        loadConfig: () async => _config,
        modelFor: (_) => proseModel,
        tools: [tool],
      );
      addTearDown(controller.dispose);
      await controller.submit(prompt);
      expect(proseModel.specsSeen.first, ['spoiler_context', 'split_tasks']);
      expect(controller.answer, isNot(contains('MODEL_HALLUCINATION')));
    });
  }

  for (final prompt in [
    'Explain why playback buffers',
    'Explain why playback is slow',
    'Uitleg over de audio',
    'Explain the audio codec',
    'Uitleg waarom audio niet werkt',
    'Explain audio and subtitles',
  ]) {
    test('confident technical-only explanations retain actual run and controller Doctor routing: $prompt', () async {
      final f = _Fixture();
      final tool = AssistantTool(
        name: 'find_title',
        description: 'normal tool',
        risk: AssistantToolRisk.read,
        needsServer: false,
        properties: const {},
        required: const [],
        serves: (_, _) => true,
        run: (_, _, _) async => const AssistantToolResult({}),
      );
      final model = _Model(_reply(content: 'TECHNICAL_DIAGNOSIS'));
      final result = await AssistantRun(
        model: model,
        context: f.context(),
        confirm: (_) async => null,
        entitlement: _Entitlement(),
        refreshHealth: () async {},
        tools: [tool],
      ).ask(prompt);
      expect(model.specsSeen.first, ['find_title'], reason: prompt);
      expect(result.text, 'TECHNICAL_DIAGNOSIS', reason: prompt);
      final controllerModel = _Model(_reply(content: 'TECHNICAL_DIAGNOSIS'));
      final controller = AssistantController(
        buildContext: (_) => f.context(),
        entitlement: _Entitlement(),
        loadConfig: () async => _config,
        modelFor: (_) => controllerModel,
        tools: [tool],
      );
      addTearDown(controller.dispose);
      await controller.submit(prompt);
      expect(controllerModel.specsSeen.first, ['find_title', 'split_tasks'], reason: prompt);
      expect(controller.answer, 'TECHNICAL_DIAGNOSIS', reason: prompt);
    });
  }

  test('prepared tool lease closes in async gap before any streamed payload reaches listeners', () async {
    for (final invalidate in [true, false]) {
      final f = _Fixture();
      final steps = <AssistantStep>[];
      var staleSeen = false;
      final pool = _PreparedToolPool(() {
        if (invalidate) f.visible = false;
      });
      final result = await AssistantRun(
        model: _Model(_reply(tool: 'spoiler_context')),
        context: f.context(),
        confirm: (_) async => null,
        entitlement: _Entitlement(),
        refreshHealth: () async {},
        operations: pool,
        onStep: (step) {
          // This callback is the synchronous streamed publication boundary.
          if (!f.visible && step.display != null) staleSeen = true;
          steps.add(step);
        },
      ).ask('Who is Anna the gardener without spoilers?');
      expect(pool.prepared, isTrue);
      expect(staleSeen, isFalse);
      expect(f.visible, !invalidate);
      if (invalidate) {
        expect(steps.where((s) => s.display != null), isEmpty);
        expect(result.displays, isEmpty);
        expect(result.text, isNot(contains('SAFE_SOURCE')));
      } else {
        expect(steps.where((s) => s.display != null), hasLength(1));
        expect(result.displays, hasLength(1));
      }
    }
  });
}

/// Existing operation injection lets the real tool finish preparation first.
/// Close its source lease before the caller resumes from its await.
class _PreparedToolPool extends AssistantOperationPool {
  _PreparedToolPool(this.afterPrepare) : super(2);
  final void Function() afterPrepare;
  bool prepared = false;
  @override
  Future<T> run<T>(Future<T> Function() operation) async {
    final result = await super.run(operation);
    if (result is AssistantToolResult && result.display != null) {
      prepared = true;
      afterPrepare();
    }
    return result;
  }
}

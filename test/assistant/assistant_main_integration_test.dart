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
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import 'assistant_find_fakes.dart' as find;

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://model.test',
  model: 'm',
);
final _id = ServerId('s');

class _Entitled extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Manager extends MultiServerManager {
  bool admin = true;
  @override
  bool canAdministerServer(ServerId id) => admin;
  @override
  Future<void> checkServerHealth() async {}
}

class _Jobs extends find.FakeServer implements ServerJobsClient {
  _Jobs() : super('s');
  Future<List<ServerJob>> Function() read = () async => [];
  @override
  bool get supportsServerAdministration => true;
  @override
  Future<List<ServerJob>> listJobs() => read();
}

class _Seerr extends SeerrClient {
  _Seerr()
    : super(
        const SeerrSession(baseUrl: 'http://requests.test', authMode: SeerrAuthMode.apiKey, userId: 7),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );
  int currentUser = 7;
  @override
  SeerrSession get session => super.session.copyWith(userId: currentUser);
}

class _Model extends AssistantModelClient {
  _Model(this.replies) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> replies;
  int calls = 0;
  void Function()? afterReply;
  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    final reply = replies[calls++];
    afterReply?.call();
    return reply;
  }
}

AssistantReply _say(String text) =>
    AssistantReply(content: text, toolCalls: const [], message: {'role': 'assistant', 'content': text});
AssistantReply _call(String name, [Map<String, Object?> args = const {}]) => AssistantReply(
  content: '',
  toolCalls: [AssistantToolCall(id: 'call', name: name, arguments: jsonEncode(args))],
  message: const {'role': 'assistant'},
);
AssistantReply _split() => _call('split_tasks', {
  'tasks': [
    {'title': 'First', 'intent': 'test', 'prompt': 'first'},
    {'title': 'Second', 'intent': 'test', 'prompt': 'second'},
  ],
});

AssistantTool _tool(
  String name,
  Future<AssistantToolOutcome> Function(AssistantToolContext, Map<String, Object?>) run,
) => AssistantTool(
  name: name,
  description: name,
  risk: AssistantToolRisk.read,
  needsServer: false,
  properties: const {},
  serves: (_, _) => true,
  run: (ctx, _, args) => run(ctx, args),
);

AssistantTitleMatches _cards(AssistantToolContext ctx) => AssistantTitleMatches(ctx, [
  AssistantTitleMatch(
    matchId: 'd',
    title: 'Dune',
    kind: 'movie',
    confidence: 'high',
    targets: [(serverId: _id, serverName: 'S', item: find.fakeItem('d', 'Dune'))],
  ),
]);

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue, reason: 'expected asynchronous checkpoint');
}

void main() {
  late _Manager manager;
  setUp(() {
    manager = _Manager();
    addTearDown(manager.dispose);
  });

  AssistantController controller(List<_Model> models, List<AssistantTool> tools) {
    var next = 0;
    final controller = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: manager),
      entitlement: _Entitled(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: tools,
      jobPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('final display replacement is per task and removes only successful lookups', () async {
    final grid = AssistantMediaGrid([(item: find.fakeItem('d', 'Dune').copyWith(serverId: 's1'), group: null)]);
    final tools = [
      _tool('find_media', (_, _) async => AssistantToolResult(const {}, display: grid)),
      _tool(
        'act',
        (_, _) async => const AssistantToolResult({
          'done': true,
        }, record: AssistantActionRecord(kind: AssistantActionKind.refreshMetadata, serverName: 'S', subject: 'Dune')),
      ),
    ];
    final c = controller([
      _Model([_split()]),
      _Model([
        _call('find_media'),
        _call('act', {'item_id': 'd', 'server_id': 's1'}),
        _say('done'),
      ]),
      _Model([_call('find_media'), _say('found')]),
    ], tools);
    await c.submit('first and second');
    expect(c.tasks.first.displays, isEmpty);
    expect(c.tasks.last.displays.single, same(grid));
    expect(c.displays, [grid]);
    expect(c.tasks.first.actions, hasLength(1));
  });

  test('the same item id on another server does not consume the lookup', () async {
    final grid = AssistantMediaGrid([(item: find.fakeItem('d', 'Dune').copyWith(serverId: 's1'), group: null)]);
    final c = controller(
      [
        _Model([
          _call('find_media'),
          _call('act', {'item_id': 'd', 'server_id': 's2'}),
          _say('done'),
        ]),
      ],
      [
        _tool('find_media', (_, _) async => AssistantToolResult(const {}, display: grid)),
        _tool(
          'act',
          (_, _) async => const AssistantToolResult(
            {'done': true},
            record: AssistantActionRecord(kind: AssistantActionKind.refreshMetadata, serverName: 'S', subject: 'Dune'),
          ),
        ),
      ],
    );
    await c.submit('act');
    expect(c.displays, [grid]);
  });

  for (final outcome in ['declined', 'failed', 'unchanged']) {
    test('$outcome confirmation preserves its lookup', () async {
      final grid = AssistantMediaGrid([(item: find.fakeItem('d', 'Dune'), group: null)]);
      final c = controller(
        [
          _Model([
            _call('find_media'),
            _call('act', {'item_id': 'd'}),
            _say('done'),
          ]),
        ],
        [
          _tool('find_media', (_, _) async => AssistantToolResult(const {}, display: grid)),
          _tool(
            'act',
            (_, _) async => AssistantPendingAction(
              kind: AssistantActionKind.refreshMetadata,
              serverId: _id,
              serverName: 'S',
              subject: 'Dune',
              execute: ({password}) async => outcome == 'failed' ? {'error': 'failed'} : {'done': false},
            ),
          ),
        ],
      );
      final done = c.submit('act');
      await _until(() => c.pendingConfirmation != null);
      final pending = c.pendingConfirmation!;
      if (outcome == 'declined') {
        c.cancelTaskConfirmation(pending.taskId, pending.id);
      } else {
        c.confirmTask(pending.taskId, pending.id);
      }
      await done;
      expect(c.displays, [grid]);
      expect(c.actions, isEmpty);
    });
  }

  test('two job watches update task actions and survive aggregate rebuilding', () async {
    final server = _Jobs();
    manager.debugRegisterClientForTesting(server);
    server.read = () async => [
      const ServerJob(id: 'a', title: 'A', state: ServerJobState.running, progress: .2),
      const ServerJob(id: 'b', title: 'B', state: ServerJobState.running, progress: .7),
    ];
    final scan = _tool(
      'scan',
      (_, args) async => AssistantToolResult(
        const {},
        record: AssistantActionRecord(
          kind: AssistantActionKind.retryJob,
          serverName: 'S',
          subject: args['job']! as String,
          job: AssistantJobWatch(serverId: _id, startedAt: DateTime.now(), jobId: args['job']! as String),
        ),
      ),
    );
    final c = controller(
      [
        _Model([_split()]),
        _Model([
          _call('scan', {'job': 'a'}),
          _say('a'),
        ]),
        _Model([
          _call('scan', {'job': 'b'}),
          _say('b'),
        ]),
      ],
      [scan],
    );
    await c.submit('first and second');
    await _until(() => c.tasks.every((task) => task.actions.single.progress != null));
    expect(c.tasks.map((task) => task.actions.single.progress!.percent), [20, 70]);
    c.cancelTask(c.tasks.first.id); // Rebuilds aggregate actions.
    expect(c.actions.map((action) => action.progress!.percent), [20, 70]);
  });

  for (final change in ['authority', 'client', 'cancel', 'supersede']) {
    test('late job poll after $change cannot publish progress', () async {
      final server = _Jobs();
      manager.debugRegisterClientForTesting(server);
      final held = Completer<List<ServerJob>>();
      var started = false;
      server.read = () {
        started = true;
        return held.future;
      };
      final scan = _tool(
        'scan',
        (_, _) async => AssistantToolResult(
          const {},
          record: AssistantActionRecord(
            kind: AssistantActionKind.scanLibrary,
            serverName: 'S',
            subject: 'Films',
            job: AssistantJobWatch(serverId: _id, startedAt: DateTime.now(), libraryId: 'films'),
          ),
        ),
      );
      final c = controller(
        [
          _Model([_call('scan'), _say('started')]),
          _Model([_say('new')]),
        ],
        [scan],
      );
      await c.submit('scan');
      await _until(() => started);
      switch (change) {
        case 'authority':
          manager.admin = false;
        case 'client':
          manager.debugRegisterClientForTesting(_Jobs());
        case 'cancel':
          c.cancelTask(c.tasks.single.id);
        case 'supersede':
          await c.submit('new');
      }
      held.complete([const ServerJob(id: 'j', title: 'Films', libraryId: 'films', state: ServerJobState.succeeded)]);
      await pumpEventQueue();
      expect(c.actions.every((action) => action.progress == null), isTrue);
    });
  }

  test('named title cancellation finishes before a nonabortable lookup and publishes nothing late', () async {
    final cancel = AbortController();
    final held = Completer<void>();
    var started = false;
    final steps = <AssistantStep>[];
    final model = _Model([_say('Try «Dune».')]);
    addTearDown(model.close);
    final done = AssistantRun(
      model: model,
      context: AssistantToolContext(servers: manager),
      confirm: (_) async => null,
      entitlement: _Entitled(),
      cancel: cancel,
      onStep: steps.add,
      tools: [
        _tool('find_title', (ctx, _) async {
          started = true;
          await held.future;
          return AssistantToolResult(const {}, display: _cards(ctx));
        }),
      ],
    ).ask('a film');
    await _until(() => started);
    cancel.abort();
    final result = await done.timeout(const Duration(milliseconds: 200));
    expect(result.displays, isEmpty);
    held.complete();
    await pumpEventQueue();
    expect(steps.where((step) => step.display != null), isEmpty);
  });

  test('named title lookup reserves the shared tool budget', () async {
    final budget = AssistantQuestionBudget();
    for (var i = 0; i < 30; i++) {
      expect(budget.reserveTool(), isTrue);
    }
    var lookups = 0;
    final model = _Model([_say('Try «Dune».')]);
    addTearDown(model.close);
    final result = await AssistantRun(
      model: model,
      context: AssistantToolContext(servers: manager),
      confirm: (_) async => null,
      entitlement: _Entitled(),
      budget: budget,
      tools: [
        _tool('find_title', (ctx, _) async {
          lookups++;
          return AssistantToolResult(const {}, display: _cards(ctx));
        }),
      ],
    ).ask('a film');
    expect(lookups, 0);
    expect(result.displays, isEmpty);
  });

  test('named title evidence invalidated at final publication cannot reappear', () async {
    manager.debugRegisterClientForTesting(_Jobs());
    final c = controller(
      [
        _Model([_say('Try «Dune».')]),
      ],
      [_tool('find_title', (ctx, _) async => AssistantToolResult(const {}, display: _cards(ctx)))],
    );
    var changed = false;
    c.addListener(() {
      if (!changed && c.displays.isNotEmpty) {
        changed = true;
        manager.debugRegisterClientForTesting(_Jobs());
      }
    });
    await c.submit('a film');
    expect(changed, isTrue);
    expect(c.tasks.single.displays, isEmpty);
    expect(c.displays, isEmpty);
    expect(c.tasks.single.error, 'catalog_changed');
  });

  // Only a connectivity flip keeps a valid card; a replaced client, another
  // profile or a hidden server still revokes it. The flip happens at the
  // lookup's own await, so there is no timing involved.
  for (final change in ['server goes offline', 'replaced client', 'profile switch', 'server hidden']) {
    test('named title evidence: $change', () async {
      final server = _Jobs();
      manager.debugRegisterClientForTesting(server);
      var profile = 'p';
      final catalog = AssistantCatalogServices(
        rowLoader: CatalogHomeCustomRowLoader(
          libraries: () => const [],
          isServerVisible: manager.isServerVisible,
          hiddenLibraryKeys: () => const {},
          clientFor: manager.getClient,
        ),
        profileId: 'p',
        activeProfileId: () => profile,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final models = [
        _Model([_split()]),
        _Model([_say('Try «Dune».')]),
        _Model([_say('Sibling remains')]),
      ];
      var next = 0;
      final c = AssistantController(
        buildContext: (_) => AssistantToolContext(servers: manager, catalog: catalog),
        entitlement: _Entitled(),
        loadConfig: () async => _config,
        modelFor: (_) => models[next++],
        tools: [
          _tool('find_title', (ctx, _) async {
            entered.complete();
            await release.future;
            return AssistantToolResult(const {}, display: _cards(ctx));
          }),
        ],
      );
      addTearDown(c.dispose);
      final done = c.submit('first and second');
      await entered.future;
      switch (change) {
        case 'server goes offline':
          manager.debugRegisterClientForTesting(server, online: false);
        case 'replaced client':
          manager.debugRegisterClientForTesting(_Jobs());
        case 'profile switch':
          profile = 'other';
        case 'server hidden':
          manager.setVisibleServerIds({});
      }
      release.complete();
      await done;
      if (change == 'server goes offline') {
        expect(c.tasks.first.error, isNull);
        expect(c.tasks.first.displays, hasLength(1));
      } else {
        expect(c.tasks.first.error, 'catalog_changed');
        expect(c.tasks.first.displays, isEmpty);
        expect(c.displays, isEmpty);
      }
    });
  }

  test('named title enrichment waits for the shared operation pool', () async {
    final pool = AssistantOperationPool(1);
    final release = Completer<void>();
    var blocked = false, lookedUp = false;
    final model = _Model([_say('Try «Dune».')]);
    addTearDown(model.close);
    model.afterReply = () {
      unawaited(
        pool.run(() async {
          blocked = true;
          await release.future;
        }),
      );
    };
    final done = AssistantRun(
      model: model,
      context: AssistantToolContext(servers: manager),
      confirm: (_) async => null,
      entitlement: _Entitled(),
      operations: pool,
      tools: [
        _tool('find_title', (ctx, _) async {
          lookedUp = true;
          return AssistantToolResult(const {}, display: _cards(ctx));
        }),
      ],
    ).ask('a film');
    await _until(() => blocked);
    await pumpEventQueue();
    expect(lookedUp, isFalse);
    release.complete();
    final result = await done;
    expect(lookedUp, isTrue);
    expect(result.displays, hasLength(1));
  });

  test('fresh contexts retain personal service but isolate Doctor run authority', () {
    final personal = AssistantPersonalServices(
      userName: 'Sam',
      recent: () async => [],
      taste: () async => throw StateError('not called'),
      picks: (_) async => [],
    );
    final original = AssistantToolContext(servers: manager, personal: personal)
      ..libraryDoctorMode = true
      ..libraryDoctorActions.add('scan_library')
      ..libraryDoctorCheck = () => throw const AssistantToolError('old_scope');
    final fresh = original.fresh();
    expect(fresh.personal, same(personal));
    expect(fresh.libraryDoctorMode, isFalse);
    expect(fresh.libraryDoctorActions, isEmpty);
    expect(fresh.libraryDoctorError, isNull);
  });

  for (final change in [
    'replace Seerr',
    'logout Seerr',
    'change Seerr user',
    'remove library',
    'hide library',
    'unchanged',
  ]) {
    for (final gap in ['dispatch', 'await', 'stream notification', 'final result callback']) {
      test('enrichment source lease: $change during $gap', () async {
        manager.debugRegisterClientForTesting(_Jobs());
        final originalRequest = _Seerr();
        final replacementRequest = _Seerr();
        addTearDown(originalRequest.dispose);
        addTearDown(replacementRequest.dispose);
        _Seerr? request = originalRequest;
        var libraries = [find.fakeLib('s', 'films')];
        final hidden = <String>{};
        final catalog = AssistantCatalogServices(
          rowLoader: CatalogHomeCustomRowLoader(
            libraries: () => libraries,
            isServerVisible: manager.isServerVisible,
            hiddenLibraryKeys: () => hidden,
            clientFor: manager.getClient,
          ),
          profileId: 'p',
          activeProfileId: () => 'p',
        );
        void changeSource() {
          switch (change) {
            case 'replace Seerr':
              request = replacementRequest;
            case 'logout Seerr':
              request = null;
            case 'change Seerr user':
              originalRequest.currentUser = 8;
            case 'remove library':
              libraries = [];
            case 'hide library':
              hidden.add('s:films');
            case 'unchanged':
              break;
          }
        }

        final entered = Completer<void>();
        final release = Completer<void>();
        var lookups = 0;
        AssistantToolContext toolContext() => AssistantToolContext(
          servers: manager,
          catalog: catalog,
          requests: AssistantRequestServices(client: () => request),
        );
        final tools = [
          _tool('find_title', (ctx, _) async {
            lookups++;
            entered.complete();
            if (gap == 'await') await release.future;
            return AssistantToolResult(
              const {},
              display: AssistantTitleMatches(ctx, [
                AssistantTitleMatch(
                  matchId: 'd',
                  title: 'Dune',
                  kind: 'movie',
                  confidence: 'high',
                  targets: [(serverId: _id, serverName: 'S', item: find.fakeItem('d', 'Dune', lib: 'films'))],
                  request: const AssistantRequestOption(
                    seerrId: 'movie:1',
                    title: 'Dune',
                    kind: 'movie',
                    posterUrl: '',
                    overview: '',
                    status: 'requested',
                  ),
                ),
              ]),
            );
          }),
        ];
        if (gap == 'final result callback') {
          final model = _Model([_say('Try «Dune».')]);
          addTearDown(model.close);
          final result = await AssistantRun(
            model: model,
            context: toolContext(),
            tools: tools,
            confirm: (_) async => null,
            entitlement: _Entitled(),
          ).ask('a film');
          expect(result.displays, hasLength(1));
          expect(result.displayEvidenceCurrent!(), isTrue);
          changeSource();
          // The controller invokes this live callback after awaiting the run.
          expect(result.displayEvidenceCurrent!(), change == 'unchanged');
          return;
        }
        final models = [
          _Model([_split()]),
          _Model([_say('Try «Dune».')]),
          _Model([_say('Sibling remains')]),
        ];
        var next = 0;
        final c = AssistantController(
          buildContext: (_) => toolContext(),
          entitlement: _Entitled(),
          loadConfig: () async => _config,
          modelFor: (_) => models[next++],
          tools: tools,
        );
        addTearDown(c.dispose);
        var changed = false, everShown = false;
        c.addListener(() {
          if (c.tasks.isEmpty) return;
          final task = c.tasks.first;
          everShown |= task.displays.isNotEmpty;
          final atGap = gap == 'dispatch'
              ? task.steps.any((step) => step.tool == 'find_title' && step.phase == AssistantStepPhase.started)
              : task.displays.isNotEmpty;
          if (!changed && gap != 'await' && atGap) {
            changed = true;
            changeSource();
          }
        });
        final done = c.submit('first and second');
        if (gap == 'await') {
          await entered.future;
          changed = true;
          changeSource();
          release.complete();
        }
        await done;
        expect(changed, isTrue);
        expect(c.tasks.last.answer, 'Sibling remains');
        expect(c.tasks.last.status, AssistantTaskStatus.completed);
        if (change == 'unchanged') {
          expect(c.tasks.first.displays, hasLength(1));
          expect(c.tasks.first.error, isNull);
          expect(lookups, 1);
        } else {
          expect(c.tasks.first.displays, isEmpty, reason: 'revoked source evidence cannot be a final card');
          expect(c.displays, isEmpty);
          expect(c.tasks.first.error, 'catalog_changed');
          if (gap == 'dispatch') expect(lookups, 0);
          if (gap == 'await' || gap == 'dispatch') expect(everShown, isFalse);
        }
      });
    }
  }

  test('Doctor scope rejects personal history and model-named title enrichment', () async {
    var personalReads = 0, lookups = 0;
    final model = _Model([_call('my_watching'), _say('Try «Dune».')]);
    addTearDown(model.close);
    final result = await AssistantRun(
      model: model,
      context: AssistantToolContext(servers: manager),
      confirm: (_) async => null,
      entitlement: _Entitled(),
      originalLibraryDoctorScope: true,
      tools: [
        _tool('my_watching', (_, _) async {
          personalReads++;
          return const AssistantToolResult({});
        }),
        _tool('find_title', (ctx, _) async {
          lookups++;
          return AssistantToolResult(const {}, display: _cards(ctx));
        }),
      ],
    ).ask('diagnose');
    expect(personalReads, 0);
    expect(lookups, 0);
    expect(result.text, isNot(contains('Dune')));
    expect(result.displays, isEmpty);
  });
}

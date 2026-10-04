import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;
import 'package:provider/provider.dart';

import '../../widgets/big_p/fake_assistant_controller.dart';

const _config = AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm');

class _Entitled extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

/// A model that answers once its gate opens.
class _GatedModel extends AssistantModelClient {
  _GatedModel() : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final gate = Completer<void>();

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    await gate.future;
    return const AssistantReply(content: 'Klaar.', toolCalls: [], message: {'role': 'assistant', 'content': 'Klaar.'});
  }
}

MediaItem _film(String id) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Film $id',
  serverId: 'nas',
  serverName: 'NAS',
);

AssistantTitleMatch _match(String id, {bool inLibrary = true}) => AssistantTitleMatch(
  matchId: id,
  title: 'Film $id',
  kind: 'movie',
  confidence: 'high',
  targets: [if (inLibrary) (serverId: ServerId('nas'), serverName: 'NAS', item: _film(id))],
  request: inLibrary
      ? null
      : AssistantRequestOption(
          seerrId: 'movie:$id',
          title: 'Film $id',
          kind: 'movie',
          posterUrl: '',
          overview: '',
          status: 'not_requested',
        ),
);

void main() {
  late DateTime now;
  late FakeAssistantController c;
  late BigPMobileSession session;

  setUp(() {
    now = DateTime(2026, 10, 4, 20);
    c = FakeAssistantController();
    session = BigPMobileSession(c, now: () => now);
    addTearDown(() {
      session.dispose();
      c.dispose();
    });
  });

  /// An ask that finishes, through working, as the controller's would.
  void answer() {
    c
      ..prompt = 'Iets met ruimte?'
      ..state = AssistantSurfaceState.working
      ..emit()
      ..answer = 'Twee films.'
      ..state = AssistantSurfaceState.result
      ..emit();
  }

  test('only the user brings Big P out, with the context and a one-time question', () {
    expect(session.stage, BigPStage.parked);
    const screen = AssistantScreenContext(serverId: 'nas');
    session.summon(context: screen, question: 'Iets met ruimte?');
    expect(session.stage, BigPStage.out);
    expect(session.pendingContext, same(screen));
    expect(session.takeQuestion(), 'Iets met ruimte?');
    expect(session.takeQuestion(), isNull);
  });

  test('a hidden controller is asked again at summon', () {
    c.availability = AssistantAvailability.hidden;
    session.summon();
    expect(c.refreshes, 1);
    c.availability = AssistantAvailability.ready;
    session.summon();
    expect(c.refreshes, 1);
  });

  test('the answer stays after park and summon', () {
    session.summon();
    answer();
    session.park();
    expect(session.stage, BigPStage.parked);
    now = now.add(const Duration(minutes: 29, seconds: 59));
    session.summon();
    expect(c.resets, 0);
    expect(c.answer, 'Twee films.');
    expect(session.stage, BigPStage.out);
  });

  test('an answer of 30 minutes is cleared at the next summon', () {
    session.summon();
    answer();
    session.park();
    now = now.add(const Duration(minutes: 30));
    session.summon();
    expect(c.resets, 1);
  });

  test('a picked option restarts the 30 minutes', () {
    session.summon();
    answer();
    now = now.add(const Duration(minutes: 20));
    c
      ..state = AssistantSurfaceState.working
      ..emit()
      ..state = AssistantSurfaceState.result
      ..emit();
    now = now.add(const Duration(minutes: 20));
    session.summon();
    expect(c.resets, 0);
  });

  test('a cancelled mic keeps the age of the answer', () {
    session.summon();
    answer();
    now = now.add(const Duration(minutes: 20));
    c.beginListening();
    c
      ..state = AssistantSurfaceState.result
      ..emit();
    now = now.add(const Duration(minutes: 10));
    session.summon();
    expect(c.resets, 1);
  });

  test('an answer already there when the session starts is aged from then', () {
    answer();
    final late = BigPMobileSession(c, now: () => now);
    addTearDown(late.dispose);
    now = now.add(const Duration(minutes: 30));
    late.summon();
    expect(c.resets, 1);
  });

  test('park during an option pick keeps the answer and lets the pick finish', () {
    final servers = MultiServerManager();
    addTearDown(servers.dispose);
    c.displays = [
      AssistantTitleMatches(AssistantToolContext(servers: servers), [_match('seerr', inLibrary: false)]),
    ];
    session.summon();
    answer();
    c
      ..state = AssistantSurfaceState.working
      ..emit();
    session.park();
    expect(session.stage, BigPStage.parked);
    expect(c.aborts, 0);
    expect(c.resets, 0);
  });

  test('park while an ask streams its displays lets it go', () {
    final servers = MultiServerManager();
    addTearDown(servers.dispose);
    session.summon();
    c
      ..displays = [
        AssistantTitleMatches(AssistantToolContext(servers: servers), [_match('a')]),
      ]
      ..stillChecking = true
      ..state = AssistantSurfaceState.working
      ..emit();
    session.park();
    expect(c.aborts, 1);
    expect(c.resets, 1);
  });

  test('park with a waiting confirmation card is ignored', () {
    session.summon();
    c
      ..state = AssistantSurfaceState.working
      ..pending = AssistantPendingAction(
        kind: AssistantActionKind.createUser,
        serverId: ServerId('nas'),
        serverName: 'NAS',
        subject: 'Sam',
        execute: ({password}) async => const {},
      )
      ..emit();
    session.park();
    expect(session.stage, BigPStage.out);
    expect(c.aborts, 0);
    expect(c.resets, 0);
  });

  test('remainingTitles counts library titles not opened yet', () {
    final servers = MultiServerManager();
    addTearDown(servers.dispose);
    final ctx = AssistantToolContext(servers: servers);
    c.displays = [
      AssistantTitleMatches(ctx, [_match('a'), _match('b'), _match('seerr', inLibrary: false)]),
      // The same title twice is one title to open.
      AssistantMediaGrid([(item: _film('a'), group: null), (item: _film('c'), group: null)]),
    ];
    answer();
    expect(session.remainingTitles, 3);

    session.openedTitle(_film('a').globalKey);
    expect(session.stage, BigPStage.peek);
    expect(session.remainingTitles, 2);
    session.openedTitle(_film('b').globalKey);
    expect(session.remainingTitles, 1);

    // A new ask starts with no displays: what was opened is forgotten.
    c
      ..displays = []
      ..state = AssistantSurfaceState.working
      ..emit()
      ..displays = [
        AssistantTitleMatches(ctx, [_match('a'), _match('b')]),
      ]
      ..state = AssistantSurfaceState.result
      ..emit();
    expect(session.remainingTitles, 2);
  });

  group('with the real controller', () {
    late MultiServerManager servers;
    late _GatedModel model;
    late AssistantController real;

    setUp(() {
      servers = MultiServerManager();
      addTearDown(servers.dispose);
      model = _GatedModel();
      real = AssistantController(
        buildContext: (screen) => AssistantToolContext(servers: servers, screen: screen),
        rolloutEnabled: true,
        entitlement: _Entitled(),
        loadConfig: () async => _config,
        modelFor: (_) => model,
        languageName: () => 'Dutch',
        tools: [
          AssistantTool(
            name: 'ping',
            description: 'ping',
            risk: AssistantToolRisk.read,
            properties: const {},
            needsServer: false,
            serves: (_, _) => true,
            run: (_, _, _) async => const AssistantToolResult({'ok': true}),
          ),
        ],
      );
      addTearDown(real.dispose);
    });

    test('park while working lets the run go and a new ask runs', () async {
      final s = BigPMobileSession(real, now: () => now);
      addTearDown(s.dispose);
      s.summon();
      final first = real.submit('Iets met ruimte?');
      await pumpEventQueue();
      expect(real.state, AssistantSurfaceState.working);

      s.park();
      expect(s.stage, BigPStage.parked);
      expect(real.state, AssistantSurfaceState.idle);
      model.gate.complete();
      await first;
      // The late reply does not land on the parked conversation.
      expect(real.answer, isEmpty);

      await real.submit('Nog een keer?');
      expect(real.state, AssistantSurfaceState.result);
      expect(real.answer, 'Klaar.');
    });
  });

  testWidgets('a profile switch disposes the session and leaves no listener', (tester) async {
    final first = FakeAssistantController();
    final second = FakeAssistantController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    BigPMobileSession? read;

    Widget profile(FakeAssistantController controller) => ChangeNotifierProvider<AssistantController>.value(
      // A new profile is a new subtree, as ProfileSessionScreen keys it.
      key: ObjectKey(controller),
      value: controller,
      child: ChangeNotifierProvider(
        create: (c) => BigPMobileSession(c.read<AssistantController>()),
        child: Builder(
          builder: (context) {
            read = context.read<BigPMobileSession>();
            return const SizedBox();
          },
        ),
      ),
    );

    await tester.pumpWidget(profile(first));
    final old = read!;
    old.summon();
    expect(first.listened, isTrue);

    await tester.pumpWidget(profile(second));
    expect(first.listened, isFalse);
    expect(read, isNot(same(old)));
    expect(read!.stage, BigPStage.parked);
    // The old profile's controller can still change without reaching it.
    first
      ..state = AssistantSurfaceState.result
      ..emit();
  });
}

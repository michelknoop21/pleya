/// What the user sees after a start question that acts (BP-10): the real
/// controller, the real `list_libraries`, `scan_library`, `list_jobs` and
/// `retry_job` tools against a fake administrator server, and the real
/// balloon on an iPhone and an iPad. A scripted model stands in for the
/// provider, so which tool a model picks is not tested here (see
/// docs/qa/big-p-startvragen.md); what Pleya does with the call is.
///
/// The Home row is the one stand-in: its tool needs the whole catalogue
/// service, so a tool of the same name returns the same pending action.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;
import 'package:pleya/widgets/big_p/assistant/big_p_confirm_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../assistant/assistant_find_fakes.dart' as fakes;
import '../tv/assistant/tv_assistant_test_support.dart' show settle;

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://model.test',
  model: 'm',
);
final _zolder = ServerId('zolder');

class _Entitled extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Manager extends MultiServerManager {
  @override
  bool canAdministerServer(ServerId id) => true;
  @override
  Future<void> checkServerHealth() async {}
}

/// An administrator server: one library and one failed job. After the retry
/// the job shows what the test sets in [after]: running at 40%, then an end.
class _Admin extends fakes.FakeServer implements LibraryScanClient, RetryableJobsClient {
  _Admin() : super('zolder');

  final scanned = <String>[];
  final retried = <String>[];
  ServerJobState after = ServerJobState.running;

  /// How many times the server still answers with the old failure after the retry.
  int staleReads = 0;

  @override
  bool get supportsServerAdministration => true;
  @override
  String get serverName => 'Zolder';
  @override
  Future<List<MediaLibrary>> fetchLibraries() async => const [
    MediaLibrary(id: 'lib-films', backend: MediaBackend.jellyfin, title: 'Films', kind: MediaKind.movie),
  ];
  @override
  Future<void> scanLibrary(String libraryId) async => scanned.add(libraryId);

  // Failed an hour ago: until the server shows it again after the restart, that
  // outcome is the old one and not the answer.
  @override
  Future<List<ServerJob>> listJobs() async => [
    if (retried.isEmpty || staleReads-- > 0)
      ServerJob(
        id: 'job-1',
        title: 'Scan Films',
        state: ServerJobState.failed,
        error: 'Disk error',
        retryable: true,
        updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      )
    else
      ServerJob(
        id: 'job-1',
        title: 'Scan Films',
        state: after,
        progress: after == ServerJobState.running ? .4 : null,
        updatedAt: DateTime.now().add(const Duration(seconds: 5)),
      ),
  ];
  @override
  Future<void> cancelJob(String jobId) async {}
  @override
  Future<void> retryJob(String jobId) async => retried.add(jobId);
}

AssistantReply _say(String text) =>
    AssistantReply(content: text, toolCalls: const [], message: {'role': 'assistant', 'content': text});
AssistantReply _call(String name, [Map<String, Object?> args = const {}]) => AssistantReply(
  content: '',
  toolCalls: [AssistantToolCall(id: 'call', name: name, arguments: jsonEncode(args))],
  message: {
    'role': 'assistant',
    'content': '',
    'tool_calls': [
      {
        'id': 'call',
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(args)},
      },
    ],
  },
);

class _Model extends AssistantModelClient {
  _Model(this.replies) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> replies;
  var calls = 0;
  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async => replies[calls++];
}

/// Titles of the rows the Home-row tool actually created.
final executed = <String>[];

/// The Home row's tool: the pending action the real one builds, with the
/// same kind and the same confirmation, minus the catalogue behind it.
final _homeRowTool = AssistantTool(
  name: 'create_home_row',
  description: 'Add a search result as a row on Home.',
  risk: AssistantToolRisk.mutation,
  properties: const {
    'title': {'type': 'string'},
  },
  needsServer: false,
  serves: (_, _) => true,
  run: (ctx, _, args) async => AssistantPendingAction(
    kind: AssistantActionKind.createHomeRow,
    serverId: _zolder,
    serverName: '',
    subject: args['title']! as String,
    items: const ['Heat', 'Die Hard', 'Se7en'],
    execute: ({password}) async {
      executed.add(args['title']! as String);
      return const {'status': 'row_created'};
    },
  ),
);

void main() {
  late _Manager manager;
  late _Admin server;
  late AssistantController controller;
  late BigPMobileSession session;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = _Manager();
    server = _Admin();
    executed.clear();
    manager.debugRegisterClientForTesting(server);
    addTearDown(manager.dispose);
  });

  /// A controller whose model follows [script], with the real tools.
  void start(List<AssistantReply> script) {
    final model = _Model(script);
    controller = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: manager, kidsProfile: () async => false),
      entitlement: _Entitled(),
      loadConfig: () async => _config,
      modelFor: (_) => model,
      tools: [...assistantTools, _homeRowTool],
      jobPollInterval: const Duration(milliseconds: 5),
    );
    session = BigPMobileSession(controller, now: () => DateTime(2026, 10, 16, 21, 14));
    addTearDown(() {
      session.dispose();
      controller.dispose();
    });
  }

  Future<void> pumpHost(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.summon();
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<BigPMobileSession>.value(
          value: session,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: const Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Runs the real clock in short steps until [finder] matches (or stops
  /// matching, with [gone]); the expect after it names what was missing.
  Future<void> pumpUntil(WidgetTester tester, Finder finder, {bool gone = false}) async {
    for (var i = 0; i < 150; i++) {
      if (finder.evaluate().isEmpty == gone) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester);
  }

  /// Asks like a tapped chip does: the run finishes, the job watch goes on.
  Future<void> ask(WidgetTester tester, String prompt) async {
    await tester.runAsync(() => controller.submit(prompt));
    await settle(tester);
  }

  /// Asks a question whose answer waits for the user, until its card is up.
  Future<void> askUntilCard(WidgetTester tester, String prompt) async {
    unawaited(controller.submit(prompt));
    await pumpUntil(tester, find.byType(BigPConfirmCard));
  }

  for (final (name, size) in [('iPhone', const Size(402, 874)), ('iPad', const Size(1024, 1366))]) {
    group(name, () {
      testWidgets('a scan: started at once, and it stays "gestart" without an operation id', (tester) async {
        start([
          _call('list_libraries', {'server_id': 'zolder'}),
          _call('scan_library', {'server_id': 'zolder', 'library_id': 'lib-films'}),
          _say('Ik heb de scan gestart.'),
        ]);
        await pumpHost(tester, size);
        await ask(tester, t.assistant.examples.scan.first);

        expect(server.scanned, ['lib-films'], reason: 'the server was asked once');
        await pumpUntil(tester, find.textContaining('Scan gestart · Films · Zolder'));
        expect(find.textContaining('Scan gestart · Films · Zolder'), findsWidgets);
        // Give the watch time to settle on something else; it must not.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await settle(tester);
        expect(find.textContaining('Scan klaar'), findsNothing);
        expect(find.textContaining('Scan mislukt'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      for (final (end, line) in [(ServerJobState.succeeded, 'Taak klaar'), (ServerJobState.failed, 'Taak mislukt')]) {
        testWidgets('restarting a failed task: confirmed at once, followed to "$line"', (tester) async {
          start([
            _call('list_jobs', {'server_id': 'zolder'}),
            _call('retry_job', {'server_id': 'zolder', 'job_id': 'job-1'}),
            _say('Ik heb de taak opnieuw gestart.'),
          ]);
          await pumpHost(tester, size);
          await ask(tester, t.assistant.examples.retryJobs.last);
          expect(server.retried, ['job-1'], reason: 'the server was asked once');
          // The job runs at 40%: the watch shows it.
          await pumpUntil(tester, find.textContaining('Taak loopt · 40%'));
          expect(find.textContaining('Taak loopt · 40%'), findsWidgets);
          expect(find.textContaining(line), findsNothing, reason: 'not before the server says so');

          server.after = end;
          await pumpUntil(tester, find.textContaining('$line · Scan Films · Zolder'));
          expect(find.textContaining('$line · Scan Films · Zolder'), findsWidgets);
          expect(find.textContaining('Taak loopt'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('negative control: the old failure the server still shows is not the restart\'s result', (
        tester,
      ) async {
        start([
          _call('list_jobs', {'server_id': 'zolder'}),
          _call('retry_job', {'server_id': 'zolder', 'job_id': 'job-1'}),
          _say('Ik heb de taak opnieuw gestart.'),
        ]);
        server.staleReads = 2;
        await pumpHost(tester, size);
        await ask(tester, t.assistant.examples.retryJobs.last);

        await pumpUntil(tester, find.textContaining('Taak loopt'));
        expect(find.textContaining('Taak loopt · 40%'), findsWidgets);
        expect(find.textContaining('Taak mislukt'), findsNothing, reason: 'the hour-old failure is not this restart');
        expect(server.staleReads, lessThan(0), reason: 'the server did answer with the old failure first');
      });

      testWidgets('a Home row: the card first, nothing created until Bevestigen, then "Rij aangemaakt"', (
        tester,
      ) async {
        start([
          _call('create_home_row', {'title': 'Actiefilms jaren 90'}),
          _say('De rij staat op je Home.'),
        ]);
        await pumpHost(tester, size);
        await askUntilCard(tester, 'Maak een Home-rij met actiefilms uit de jaren negentig.');

        expect(find.byType(BigPConfirmCard), findsOneWidget);
        expect(find.text(t.assistant.confirm.titles.createHomeRow), findsOneWidget);
        expect(find.text('Actiefilms jaren 90'), findsWidgets);
        expect(find.textContaining('Rij aangemaakt'), findsNothing, reason: 'nothing is created before the tap');
        expect(executed, isEmpty, reason: 'the row is not made before the tap');

        await tester.ensureVisible(find.text(t.assistant.confirm.approve));
        await tester.pump();
        await tester.tap(find.text(t.assistant.confirm.approve));
        await pumpUntil(tester, find.textContaining('Rij aangemaakt'));

        expect(executed, ['Actiefilms jaren 90'], reason: 'made once, after the tap');
        expect(find.byType(BigPConfirmCard), findsNothing);
        expect(find.textContaining('Rij aangemaakt'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('negative control: declining the Home row creates nothing', (tester) async {
        start([
          _call('create_home_row', {'title': 'Actiefilms jaren 90'}),
          _say('Goed, ik heb niets gemaakt.'),
        ]);
        await pumpHost(tester, size);
        await askUntilCard(tester, 'Maak een Home-rij met actiefilms uit de jaren negentig.');
        expect(find.byType(BigPConfirmCard), findsOneWidget);

        await tester.tap(find.text(t.assistant.result.cancel));
        await pumpUntil(tester, find.byType(BigPConfirmCard), gone: true);
        expect(find.byType(BigPConfirmCard), findsNothing, reason: 'the card is gone');
        expect(executed, isEmpty, reason: 'declining makes no row');
        expect(find.textContaining('Rij aangemaakt'), findsNothing);
      });
    });
  }
}

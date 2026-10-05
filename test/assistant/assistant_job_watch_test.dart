import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/models/plex/plex_activity.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

const _config = AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm');

class _Entitled extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

/// Calls the scan tool once, then answers.
class _Model extends AssistantModelClient {
  _Model() : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  var calls = 0;

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    if (calls++ > 0) return const AssistantReply(content: 'klaar', toolCalls: [], message: {'role': 'assistant'});
    const call = AssistantToolCall(id: 'c1', name: 'scan', arguments: '{}');
    return AssistantReply(
      content: '',
      toolCalls: const [call],
      message: {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'c1',
            'type': 'function',
            'function': {'name': 'scan', 'arguments': jsonEncode(const {})},
          },
        ],
      },
    );
  }
}

final _server = ServerId('srv');
final _start = DateTime.utc(2026, 10, 3, 12);

ServerJob _job(ServerJobState state, {String id = 'j1', double? progress, DateTime? at}) =>
    ServerJob(id: id, title: 'scan_library', state: state, progress: progress, libraryId: 'films', updatedAt: at);

void main() {
  group('assistantJobLook', () {
    final byLibrary = AssistantJobWatch(serverId: _server, startedAt: _start, libraryId: 'films');
    final byId = AssistantJobWatch(serverId: _server, startedAt: _start, jobId: 'j1');

    test('a running job, with its percent', () {
      final p = assistantJobLook(byId, [_job(ServerJobState.running, progress: 0.4)], seen: false)!;
      expect((p.phase, p.percent), (AssistantJobPhase.running, 40));
    });

    test('without an operation id the outcome is not followable, even if another job runs on the library', () {
      for (final jobs in [
        const <ServerJob>[],
        [_job(ServerJobState.running, id: 'other')],
      ]) {
        expect(assistantJobLook(byLibrary, jobs, seen: false)!.phase, AssistantJobPhase.started);
      }
      // A later scan on the same library, finished after our start, is not ours.
      final later = _job(ServerJobState.succeeded, id: 'other', at: _start.add(const Duration(seconds: 5)));
      expect(assistantJobLook(byLibrary, [later], seen: false)!.phase, AssistantJobPhase.started);
    });

    test('a retried job still showing its old outcome is not ours yet', () {
      final old = _job(ServerJobState.succeeded, at: _start.subtract(const Duration(hours: 1)));
      expect(assistantJobLook(byId, [old], seen: false), isNull);
      final fresh = _job(ServerJobState.failed, at: _start.add(const Duration(seconds: 5)));
      expect(assistantJobLook(byId, [fresh], seen: false)!.phase, AssistantJobPhase.failed);
    });

    test('a job that was seen running and vanished is unknown, never done; never seen decides nothing', () {
      expect(assistantJobLook(byId, const [], seen: true)!.phase, AssistantJobPhase.unknown);
      expect(assistantJobLook(byId, const [], seen: false), isNull);
    });
  });

  test('a Plex scan activity names its library section', () {
    final a = PlexActivity.fromJson(const {
      'uuid': 'u',
      'type': 'library.update.section',
      'title': 'Scanning Films',
      'progress': 40,
      'Context': {'librarySectionID': 3},
    });
    expect(a.librarySectionId, '3');
    expect(PlexActivity.fromJson(const {'uuid': 'u'}).librarySectionId, isNull);
  });

  group('controller watch', () {
    late MultiServerManager servers;
    late List<List<ServerJob>> answers;
    late DateTime now;
    var polls = 0;

    setUp(() {
      servers = MultiServerManager();
      addTearDown(servers.dispose);
      answers = [];
      now = _start;
      polls = 0;
    });

    AssistantController controller() {
      final scan = AssistantTool(
        name: 'scan',
        description: 'scan',
        risk: AssistantToolRisk.mutation,
        properties: const {},
        needsServer: false,
        serves: (_, _) => true,
        run: (_, _, _) async => AssistantToolResult(
          const {'status': 'scan_started'},
          record: AssistantActionRecord(
            kind: AssistantActionKind.scanLibrary,
            serverName: 'Zolder',
            subject: 'Films',
            job: AssistantJobWatch(serverId: _server, startedAt: _start, jobId: 'j1'),
          ),
        ),
      );
      final c = AssistantController(
        buildContext: (screen) => AssistantToolContext(servers: servers, screen: screen),
        entitlement: _Entitled(),
        loadConfig: () async => _config,
        modelFor: (_) => _Model(),
        languageName: () => 'Dutch',
        tools: [scan],
        now: () => now,
        jobPollInterval: const Duration(milliseconds: 1),
        jobsFor: (_) async {
          polls++;
          // Each poll moves the clock 10 s; the last answer repeats.
          now = now.add(const Duration(seconds: 10));
          return answers[(polls - 1).clamp(0, answers.length - 1)];
        },
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 500 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    AssistantJobProgress? progress(AssistantController c) => c.actions.single.progress;

    test('running with percent, then done', () async {
      answers = [
        [_job(ServerJobState.running, progress: 0.4)],
        [_job(ServerJobState.succeeded, at: _start.add(const Duration(seconds: 20)))],
      ];
      final c = controller();
      final seen = <AssistantJobPhase?>[];
      c.addListener(() => seen.add(c.actions.firstOrNull?.progress?.phase));
      await c.submit('scan films');
      await until(() => progress(c)?.settled ?? false);
      expect(seen, contains(AssistantJobPhase.running));
      expect(progress(c)!.phase, AssistantJobPhase.done);
      final after = polls;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(polls, after, reason: 'a settled job is no longer polled');
    });

    test('a failed job says so and fails the question', () async {
      answers = [
        [_job(ServerJobState.failed, at: _start.add(const Duration(seconds: 5)))],
      ];
      final c = controller();
      await c.submit('scan films');
      await until(() => progress(c)?.settled ?? false);
      expect(progress(c)!.phase, AssistantJobPhase.failed);
      expect(c.tasks.single.status, AssistantTaskStatus.failed);
    });

    test('a cancelled job shows failed but does not fail the question', () async {
      answers = [
        [_job(ServerJobState.cancelled, at: _start.add(const Duration(seconds: 5)))],
      ];
      final c = controller();
      await c.submit('scan films');
      await until(() => progress(c)?.settled ?? false);
      expect(progress(c)!.phase, AssistantJobPhase.failed);
      expect(c.tasks.single.status, isNot(AssistantTaskStatus.failed));
    });

    test('seen running, then gone: unknown, not done and not failed', () async {
      answers = [
        [_job(ServerJobState.running, progress: 0.4)],
        const [],
      ];
      final c = controller();
      await c.submit('scan films');
      await until(() => progress(c)?.settled ?? false);
      expect(progress(c)!.phase, AssistantJobPhase.unknown);
      expect(c.tasks.single.status, isNot(AssistantTaskStatus.failed));
    });

    test('failed, then gone: stays failed', () async {
      answers = [
        [_job(ServerJobState.failed, at: _start.add(const Duration(seconds: 5)))],
        const [],
      ];
      final c = controller();
      await c.submit('scan films');
      await until(() => progress(c)?.settled ?? false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(progress(c)!.phase, AssistantJobPhase.failed);
      expect(c.tasks.single.status, AssistantTaskStatus.failed);
    });

    test('still running after the limit: background, and the watch stops', () async {
      answers = [
        [_job(ServerJobState.running, progress: 0.1)],
      ];
      final c = controller();
      await c.submit('scan films');
      await until(() => progress(c)?.settled ?? false);
      expect(progress(c)!.phase, AssistantJobPhase.background);
      expect(polls, lessThanOrEqualTo(13), reason: '2 minutes at 10 s per poll');
    });

    test('a job Pleya cannot find stays "gestart"', () async {
      answers = [const []];
      final c = controller();
      await c.submit('scan films');
      await until(() => progress(c)?.settled ?? false);
      expect(progress(c)!.phase, AssistantJobPhase.started);
      expect(polls, 3);
    });

    test('reset stops the watch', () async {
      answers = [
        [_job(ServerJobState.running)],
      ];
      final c = controller();
      await c.submit('scan films');
      await until(() => polls > 0);
      c.reset();
      final after = polls;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(polls, lessThanOrEqualTo(after + 1));
      expect(c.actions, isEmpty);
    });
  });
}

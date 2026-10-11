import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import '../services/memory/memory_test_support.dart';

const memoryConfig = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://o.lan',
  model: 'm',
);

/// One scripted reply: text, or tool calls as (name, arguments).
typedef ScriptedCall = (String name, Map<String, Object?> args);

AssistantReply say(String text) =>
    AssistantReply(content: text, toolCalls: const [], message: {'role': 'assistant', 'content': text});

AssistantReply callTools(List<ScriptedCall> calls) {
  final toolCalls = [
    for (final (i, call) in calls.indexed)
      AssistantToolCall(id: 'c${i + 1}', name: call.$1, arguments: jsonEncode(call.$2)),
  ];
  return AssistantReply(
    content: '',
    toolCalls: toolCalls,
    message: {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        for (final call in toolCalls)
          {
            'id': call.id,
            'type': 'function',
            'function': {'name': call.name, 'arguments': call.arguments},
          },
      ],
    },
  );
}

AssistantReply callTool(String name, [Map<String, Object?> args = const {}]) => callTools([(name, args)]);

/// Answers from a script and keeps every message list and tool list it got.
/// A reply can be an error to throw instead.
class ScriptedModel extends AssistantModelClient {
  ScriptedModel(this.script) : super(memoryConfig, httpClient: MockClient((_) async => http.Response('', 500)));

  final List<Object> script;
  final List<List<Map<String, Object?>>> seen = [];
  final List<List<String>> offered = [];
  var _next = 0;

  int get calls => seen.length;

  /// The tools of call [index], without the run's own routing spec.
  List<String> offeredTo(int index) => [
    for (final name in offered[index])
      if (name != 'split_tasks') name,
  ];

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    seen.add([for (final m in messages) Map.of(m)]);
    offered.add([for (final tool in tools) ((tool['function'] as Map)['name']) as String]);
    final reply = script[_next++];
    if (reply is AssistantReply) return reply;
    throw reply;
  }

  /// Everything the model was sent in call [index], as one string.
  String sent(int index) => jsonEncode(seen[index]);

  /// The tool outputs the model was handed back, decoded, over all calls.
  List<Map<String, Object?>> get toolOutputs => [
    for (final m in seen.last)
      if (m['role'] == 'tool') jsonDecode(m['content'] as String) as Map<String, Object?>,
  ];
}

class Entitled extends AssistantEntitlement {
  const Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

/// A harmless tool, so a run without memory tools still reaches the model.
final pingTool = AssistantTool(
  name: 'ping',
  description: 'ping',
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (_, _, _) async => const AssistantToolResult({'ok': true}),
);

/// A profile with its memory and the switch that says which profile is active.
///
/// Its clock moves one second per write, so two facts stored right after each
/// other never share a change time and "newest first" does not hang on an id.
class MemoryProfile {
  MemoryProfile(AppDatabase db, this.id, {String Function()? newId, DateTime Function()? now})
    : service = MemoryService(database: db, profileId: id, newId: newId, now: now ?? TickingClock().call),
      active = id;

  final String id;
  final MemoryService service;

  /// What `activeProfileId` answers; another id is a profile switch.
  String? active;
  bool kids = false;
  List<int> kidsAges = const [];

  late final AssistantMemoryServices services = AssistantMemoryServices(
    service: service,
    activeProfileId: () => active,
    kidsProfile: () async => kids,
  );

  AssistantToolContext context(MultiServerManager servers) => AssistantToolContext(
    servers: servers,
    kidsProfile: () async => kids,
    kidsAges: () async => kidsAges,
    memory: services,
  );

  Future<MemoryFact> store(String value, {MemoryCategory category = MemoryCategory.preference}) async {
    final result = await service.add(value: value, category: category, source: MemorySource.settingsManual);
    return result.fact!;
  }

  Future<List<String>> values() async => [for (final fact in await service.list()) fact.value];
}

import 'dart:async';
import 'dart:convert';

import 'package:pleya_verify_mcp/src/mcp_server.dart';
import 'package:pleya_verify_mcp/src/tools/tool.dart';
import 'package:test/test.dart';

/// Feeds [lines] to a fresh [McpServer] over [tools] as if they had arrived
/// over stdin (one JSON-RPC message per line, per the MCP stdio transport),
/// and returns every JSON-RPC message the server wrote back, decoded. This
/// is the representative subprocess/transport boundary this package's tests
/// exercise without spawning a real process: real newline-delimited JSON in,
/// real newline-delimited JSON out, through the same `run()` loop
/// `bin/pleya_verify_mcp.dart` drives against real stdin/stdout.
Future<List<Map<String, Object?>>> _drive(List<Tool> tools, List<Map<String, Object?>> lines) async {
  final output = StringBuffer();
  final controller = StreamController<List<int>>();
  final done = McpServer(tools: tools, input: controller.stream, output: output, logError: (_) {}).run();

  for (final line in lines) {
    controller.add(utf8.encode('${jsonEncode(line)}\n'));
  }
  await controller.close();
  await done;

  return output
      .toString()
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, Object?>)
      .toList();
}

void main() {
  test('initialize responds with server info and a tools capability', () async {
    final responses = await _drive(const [], [
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18'},
      },
    ]);

    expect(responses, hasLength(1));
    expect(responses.single['id'], 1);
    final result = responses.single['result'] as Map<String, Object?>;
    expect(result['serverInfo'], isA<Map<String, Object?>>());
    expect(result['capabilities'], containsPair('tools', isA<Map>()));
  });

  test('notifications/initialized (no id) gets no response', () async {
    final responses = await _drive(const [], [
      {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    ]);

    expect(responses, isEmpty);
  });

  test('tools/list reports every registered tool by name', () async {
    final tool = Tool(
      name: 'run_scenario',
      description: 'runs a scenario',
      inputSchema: const {'type': 'object'},
      handler: (args) async => {'ok': true},
    );

    final responses = await _drive(
      [tool],
      [
        {'jsonrpc': '2.0', 'id': 'a', 'method': 'tools/list'},
      ],
    );

    final tools = (responses.single['result'] as Map<String, Object?>)['tools'] as List<Object?>;
    expect((tools.single as Map<String, Object?>)['name'], 'run_scenario');
  });

  test('tools/call dispatches to the named tool and returns structuredContent', () async {
    final tool = Tool(
      name: 'run_scenario',
      description: 'runs a scenario',
      inputSchema: const {'type': 'object'},
      handler: (args) async => {'ok': true, 'result': 'PASS', 'scenario': args['scenario']},
    );

    final responses = await _drive(
      [tool],
      [
        {
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'tools/call',
          'params': {
            'name': 'run_scenario',
            'arguments': {'scenario': 'macos.smoke.boot'},
          },
        },
      ],
    );

    final result = responses.single['result'] as Map<String, Object?>;
    expect(result['isError'], false);
    expect(result['structuredContent'], {'ok': true, 'result': 'PASS', 'scenario': 'macos.smoke.boot'});
  });

  test('tools/call on an unknown tool reports isError without throwing', () async {
    final responses = await _drive(const [], [
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'no_such_tool', 'arguments': <String, Object?>{}},
      },
    ]);

    final result = responses.single['result'] as Map<String, Object?>;
    expect(result['isError'], true);
  });

  test('a handler exception becomes isError:true, never a crashed server', () async {
    final tool = Tool(
      name: 'run_scenario',
      description: 'runs a scenario',
      inputSchema: const {'type': 'object'},
      handler: (args) async => throw StateError('unknown scenario "bogus"'),
    );

    final responses = await _drive(
      [tool],
      [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'run_scenario',
            'arguments': {'scenario': 'bogus'},
          },
        },
      ],
    );

    final result = responses.single['result'] as Map<String, Object?>;
    expect(result['isError'], true);
    final content = (result['content'] as List<Object?>).single as Map<String, Object?>;
    expect(content['text'], contains('bogus'));
  });

  test('an unknown method reports a JSON-RPC method-not-found error', () async {
    final responses = await _drive(const [], [
      {'jsonrpc': '2.0', 'id': 1, 'method': 'not/a/real/method'},
    ]);

    final error = responses.single['error'] as Map<String, Object?>;
    expect(error['code'], -32601);
  });
}

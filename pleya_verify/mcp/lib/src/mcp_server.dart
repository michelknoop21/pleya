import 'dart:async';
import 'dart:convert';

import 'tools/tool.dart';

/// A minimal MCP server over the stdio transport: newline-delimited JSON-RPC
/// 2.0 messages on [input], responses on [output]. This class only speaks
/// the protocol (`initialize`, `tools/list`, `tools/call`) and never
/// reasons about scenarios, PASS/FAIL, or evidence itself; each [Tool]'s
/// handler already returns a finished, JSON-safe result (see
/// `run_scenario_tool.dart`/`list_scenarios_tool.dart`), and every exception
/// a handler throws becomes an MCP tool error (`isError: true`), never a
/// crash of the server process itself.
///
/// stdout carries protocol messages only. Anything a tool or this class
/// needs to say for debugging goes to [logError] (stderr), never stdout,
/// because a stray line on stdout would corrupt the next JSON-RPC message a
/// client tries to parse.
class McpServer {
  final List<Tool> tools;
  final Stream<List<int>> input;
  final StringSink output;
  final void Function(String message) logError;

  McpServer({required this.tools, required this.input, required this.output, required this.logError});

  static const String _protocolVersion = '2025-06-18';

  Future<void> run() async {
    final lines = input.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      await _handleLine(line);
    }
  }

  Future<void> _handleLine(String line) async {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (e) {
      logError('ignoring unparseable stdio line: $e');
      return;
    }
    if (decoded is! Map<String, Object?>) {
      logError('ignoring non-object JSON-RPC message: $line');
      return;
    }
    final message = decoded;
    final id = message['id'];
    final method = message['method'];
    if (method is! String) {
      logError('ignoring message with no method: $line');
      return;
    }
    final rawParams = message['params'];
    final params = rawParams is Map<String, Object?> ? rawParams : const <String, Object?>{};

    switch (method) {
      case 'initialize':
        _respond(id, {
          'protocolVersion': (params['protocolVersion'] as String?) ?? _protocolVersion,
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': 'pleya-verify-mcp', 'version': '0.1.0'},
        });
      case 'notifications/initialized':
        // A notification (no `id`): the client is done with its half of the
        // handshake. Nothing to reply with.
        break;
      case 'ping':
        _respond(id, const <String, Object?>{});
      case 'tools/list':
        _respond(id, {
          'tools': [for (final t in tools) t.toJson()],
        });
      case 'tools/call':
        await _handleToolsCall(id, params);
      default:
        _respondError(id, -32601, 'Method not found: $method');
    }
  }

  Future<void> _handleToolsCall(Object? id, Map<String, Object?> params) async {
    final name = params['name'];
    if (name is! String) {
      _respondError(id, -32602, 'tools/call requires a string "name"');
      return;
    }
    final rawArguments = params['arguments'];
    final arguments = rawArguments is Map<String, Object?> ? rawArguments : const <String, Object?>{};

    Tool? tool;
    for (final candidate in tools) {
      if (candidate.name == name) {
        tool = candidate;
        break;
      }
    }
    if (tool == null) {
      _respond(id, {
        'content': [
          {'type': 'text', 'text': 'Unknown tool "$name", known tools: ${tools.map((t) => t.name).join(', ')}'},
        ],
        'isError': true,
      });
      return;
    }

    try {
      final result = await tool.handler(arguments);
      _respond(id, {
        'content': [
          {'type': 'text', 'text': jsonEncode(result)},
        ],
        'structuredContent': result,
        'isError': false,
      });
    } catch (e) {
      _respond(id, {
        'content': [
          {'type': 'text', 'text': '$e'},
        ],
        'isError': true,
      });
    }
  }

  void _respond(Object? id, Map<String, Object?> result) {
    // A request carries an `id`; a notification does not and gets no reply,
    // per the JSON-RPC 2.0 spec MCP's stdio transport is built on.
    if (id == null) return;
    output.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
  }

  void _respondError(Object? id, int code, String message) {
    if (id == null) return;
    output.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      }),
    );
  }
}

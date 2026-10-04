import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Local model fixture for the two real catalog searches in TV scenarios.
/// Replies depend only on the transcript, so child requests may run concurrently.
class OllamaFakeServer {
  Completer<void>? _auroraGate;

  /// Existing fixture latency control can hold only the first Aurora child
  /// reply, making insertion above a focused Basalt result reproducible.
  /// Reset/stop release every waiter; this never changes product task state.
  void holdAurora(bool hold) {
    if (hold) {
      _auroraGate ??= Completer<void>();
    } else {
      final gate = _auroraGate;
      _auroraGate = null;
      gate?.complete();
    }
  }

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/tags' && request.method == 'GET') {
      return _json({
        'models': [
          {
            'name': 'pleya-verify',
            'size': 1024,
            'details': {'family': 'verify', 'parameter_size': 'tiny'},
          },
        ],
      });
    }
    if (!{'/api/show', '/api/generate', '/v1/chat/completions'}.contains(path)) {
      return _json({'error': 'unknown model fixture route'}, status: 404);
    }
    if (request.method != 'POST') return _json({'error': 'POST required'}, status: 405);
    try {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['model'] != 'pleya-verify') return _json({'error': 'unknown fixture model'}, status: 400);
      if (path == '/api/show') {
        return _json({
          'capabilities': ['completion', 'tools'],
        });
      }
      if (path == '/api/generate') return _json({'model': 'pleya-verify', 'done': true});

      final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
      final prompt = messages.lastWhere((message) => message['role'] == 'user')['content'];
      final names = (body['tools'] as List? ?? const []).map((tool) => tool['function']['name']).toSet();
      final replies = messages.where((message) => message['role'] == 'tool');
      Map<String, Object?> message;
      if (prompt == 'Zoek Aurora en zoek Basalt.' && replies.isEmpty && names.contains('split_tasks')) {
        message = _call('split-searches', 'split_tasks', {
          'tasks': [
            {'title': 'Aurora zoeken', 'intent': 'search', 'prompt': 'Zoek Aurora.'},
            {'title': 'Basalt zoeken', 'intent': 'search', 'prompt': 'Zoek Basalt.'},
          ],
        });
      } else if (prompt == 'Zoek Aurora.' || prompt == 'Zoek Basalt.') {
        final title = prompt == 'Zoek Aurora.' ? 'Aurora' : 'Basalt';
        if (replies.isNotEmpty) {
          final failed = replies.any((reply) => (jsonDecode(reply['content'] as String) as Map).containsKey('error'));
          message = {'role': 'assistant', 'content': failed ? 'Dat lukte niet.' : '$title gevonden.'};
        } else if (names.contains('find_title')) {
          if (title == 'Aurora') await _auroraGate?.future;
          message = _call('find-${title.toLowerCase()}', 'find_title', {
            'kind': 'movie',
            'candidates': [
              {'title': title, 'year': title == 'Aurora' ? 2021 : 2022, 'kind': 'movie'},
            ],
            'variants': [title, '$title film'],
          });
        } else {
          return _json({'error': 'search tool not offered'}, status: 400);
        }
      } else {
        return _json({'error': 'unsupported fixture transcript'}, status: 400);
      }
      return _json({
        'choices': [
          {'message': message, 'finish_reason': message.containsKey('tool_calls') ? 'tool_calls' : 'stop'},
        ],
      });
    } catch (_) {
      return _json({'error': 'invalid model fixture request'}, status: 400);
    }
  }

  Map<String, Object?> _call(String id, String name, Map<String, Object?> arguments) => {
    'role': 'assistant',
    'content': '',
    'tool_calls': [
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(arguments)},
      },
    ],
  };

  http.Response _json(Map<String, Object?> body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

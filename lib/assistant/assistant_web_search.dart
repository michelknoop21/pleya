import 'dart:convert';

import 'package:http/http.dart' as http;

/// One web search result: page title, address and a text snippet.
typedef WebSearchHit = ({String title, String url, String snippet});

/// A real web search, separate from the chat model: find_title calls it at
/// most once per question, and only when the cheap sources fell short.
abstract class WebSearchClient {
  Future<List<WebSearchHit>> search(String query, {int maxResults = 5});
}

/// `POST https://ollama.com/api/web_search` with a Bearer key: `query` and
/// `max_results` (at most 10), answering `results[{title, url, content}]`.
class OllamaWebSearch implements WebSearchClient {
  OllamaWebSearch(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();
  final String apiKey;
  final http.Client _client;

  static final endpoint = Uri.parse('https://ollama.com/api/web_search');

  @override
  Future<List<WebSearchHit>> search(String query, {int maxResults = 5}) async {
    final response = await _client.post(
      endpoint,
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'max_results': maxResults.clamp(1, 10)}),
    );
    if (response.statusCode != 200) throw http.ClientException('web_search ${response.statusCode}', endpoint);
    final results = (jsonDecode(response.body) as Map?)?['results'];
    return [
      if (results is List)
        for (final r in results)
          if (r is Map && r['title'] is String)
            (title: r['title'] as String, url: '${r['url'] ?? ''}', snippet: '${r['content'] ?? ''}'),
    ];
  }
}

/// OpenRouter's web plugin: a minimal chat completion with
/// `plugins: [{"id": "web"}]`. The pages it read come back as `url_citation`
/// annotations on the message; the short answer itself is one more hit.
class OpenRouterWebSearch implements WebSearchClient {
  OpenRouterWebSearch(this.apiKey, {this.model = 'openrouter/auto', http.Client? client})
    : _client = client ?? http.Client();
  final String apiKey;
  final String model;
  final http.Client _client;

  static final endpoint = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

  @override
  Future<List<WebSearchHit>> search(String query, {int maxResults = 5}) async {
    final response = await _client.post(
      endpoint,
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'max_tokens': 200,
        'plugins': [
          {'id': 'web', 'max_results': maxResults.clamp(1, 10)},
        ],
        'messages': [
          {'role': 'user', 'content': 'Which film or TV series (title and year) matches this description? $query'},
        ],
      }),
    );
    if (response.statusCode != 200) throw http.ClientException('web plugin ${response.statusCode}', endpoint);
    final choices = (jsonDecode(response.body) as Map?)?['choices'];
    final message = choices is List && choices.isNotEmpty && choices.first is Map ? choices.first['message'] : null;
    if (message is! Map) return const [];
    final annotations = message['annotations'];
    return [
      if (message['content'] case final String answer when answer.trim().isNotEmpty)
        (title: answer.trim(), url: '', snippet: ''),
      if (annotations is List)
        for (final a in annotations)
          if (a is Map ? a['url_citation'] : null case final Map c when c['title'] is String)
            (title: c['title'] as String, url: '${c['url'] ?? ''}', snippet: '${c['content'] ?? ''}'),
    ];
  }
}

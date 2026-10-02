import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/assistant/assistant_web_search.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/external_ids.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

void main() {
  test('Wikipedia: one generator=search request, hits in rank order with kind, year and item', () async {
    final seen = <http.Request>[];
    final web = AssistantWebServices(
      client: MockClient((request) async {
        seen.add(request);
        return _json({
          'query': {
            'pages': [
              {'title': 'Heat (1995 film)', 'index': 2, 'description': 'American crime film'},
              {
                'title': 'Doctor Who',
                'index': 1,
                'description': 'Britse televisieserie',
                'pageprops': {'wikibase_item': 'Q34316'},
              },
            ],
          },
        });
      }),
    );
    final hits = await web.wikipedia('tijdreiziger politiebox', lang: 'nl');

    final uri = seen.single.url;
    expect(uri.host, 'nl.wikipedia.org');
    expect(uri.queryParameters, containsPair('generator', 'search'));
    expect(uri.queryParameters, containsPair('gsrsearch', 'tijdreiziger politiebox'));
    expect(uri.queryParameters, containsPair('ppprop', 'wikibase_item'));
    expect(seen.single.headers['User-Agent'], startsWith('Pleya/'));
    expect(hits.map((h) => h.title), ['Doctor Who', 'Heat']);
    expect(hits.first.kind, MediaKind.show);
    expect(hits.first.qid, 'Q34316');
    expect((hits.last.year, hits.last.kind), (1995, MediaKind.movie));
  });

  test('Wikidata: TMDB, IMDb and TVDB ids in one wbgetentities call', () async {
    final seen = <Uri>[];
    Map<String, Object> claim(String value) => {
      'mainsnak': {
        'datavalue': {'value': value},
      },
    };
    final web = AssistantWebServices(
      client: MockClient((request) async {
        seen.add(request.url);
        return _json({
          'entities': {
            'Q34316': {
              'claims': {
                'P4983': [claim('57243')],
                'P345': [claim('tt0436992')],
                'P4835': [claim('78804')],
              },
            },
          },
        });
      }),
    );
    final ids = await web.wikidataIds(['Q34316', 'not-a-qid', 'Q34316']);

    expect(seen.single.queryParameters['ids'], 'Q34316');
    expect(ids['Q34316'], const ExternalIds(tmdb: 57243, imdb: 'tt0436992', tvdb: 78804));
    expect(await web.wikidataIds(['bogus']), isEmpty);
    expect(seen, hasLength(1));
  });

  test('Ollama web search: POST with Bearer key, max_results capped at 10', () async {
    late http.Request sent;
    final search = OllamaWebSearch(
      'ok-web',
      client: MockClient((request) async {
        sent = request;
        return _json({
          'results': [
            {'title': 'Primer (2004)', 'url': 'https://x', 'content': 'Time travel'},
          ],
        });
      }),
    );
    final hits = await search.search('garage time machine', maxResults: 40);

    expect(sent.url.toString(), 'https://ollama.com/api/web_search');
    expect(sent.headers['Authorization'], 'Bearer ok-web');
    expect(jsonDecode(sent.body), {'query': 'garage time machine', 'max_results': 10});
    expect(hits.single, (title: 'Primer (2004)', url: 'https://x', snippet: 'Time travel'));
  });

  test('OpenRouter web search: the web plugin, citations read as hits', () async {
    late http.Request sent;
    final search = OpenRouterWebSearch(
      'or-key',
      client: MockClient((request) async {
        sent = request;
        return _json({
          'choices': [
            {
              'message': {
                'content': 'Primer (2004)',
                'annotations': [
                  {
                    'type': 'url_citation',
                    'url_citation': {'url': 'https://imdb.example', 'title': 'Primer - IMDb', 'content': 'Engineers'},
                  },
                ],
              },
            },
          ],
        });
      }),
    );
    final hits = await search.search('garage time machine');

    final body = jsonDecode(sent.body) as Map;
    expect(sent.url.path, '/api/v1/chat/completions');
    expect(body['plugins'], [
      {'id': 'web', 'max_results': 5},
    ]);
    expect(hits.map((h) => h.title), ['Primer (2004)', 'Primer - IMDb']);
  });

  test('keys pick the web search: ollama.com first, none leaves it out', () {
    expect(AssistantWebServices.forKeys(ollamaWebKey: 'a', openRouterKey: 'b').search, isA<OllamaWebSearch>());
    expect(AssistantWebServices.forKeys(openRouterKey: 'b').search, isA<OpenRouterWebSearch>());
    expect(AssistantWebServices.forKeys().search, isNull);
  });
}

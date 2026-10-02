@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:test/test.dart';

/// Houdt de fake server tegen `docs/pleya-protocol/v1/openapi.yaml`.
///
/// De app-tests draaien tegen deze fake server, niet tegen de Go-server. Loopt
/// hij weg van het contract, dan slagen ze tegen een verzinsel: een veld dat de
/// echte server nooit stuurt wordt dan in de client ingebakken, en dat komt pas
/// bij een echte server aan het licht. Dit is de tegenhanger van de vangst die
/// `internal/api` maakt, met dezelfde manifestvorm en dezelfde validator, zodat
/// beide kanten met dezelfde meetlat gemeten worden.
///
/// De test legt de antwoorden neer; `scripts/check_server_responses.py --subset`
/// toetst ze. Dat `--subset` is geen ontsnapping maar een feit over wat hier
/// getoetst wordt: de fake server is een fixture voor de app en dekt bewust niet
/// het hele contract, dus de dekkingseis van de echte server hoort er niet op.
/// Wat hij wél teruggeeft moet kloppen.
const envResponseDir = 'PLEYA_RESPONSE_DIR';

class _Captured {
  _Captured(this.file, this.schema, this.method, this.path, this.status, this.body);

  final String file;
  final String schema;
  final String method;
  final String path;
  final int status;
  final String body;

  Map<String, Object?> toManifest() => {
    'file': file,
    'schema': schema,
    'method': method,
    'path': path,
    'status': status,
  };
}

PleyaFakeServer _seeded() {
  // setupRequired, want inloggen kan pas als /auth/setup een eigenaar heeft
  // aangemaakt; dat is de enige plek waar de fake server credentials leert.
  final server = PleyaFakeServer(setupRequired: true);
  server.addLibrary(id: 'lib-1', title: 'Films', kind: 'movies', itemCount: 2);
  server.addItem(id: 'item-1', kind: 'movie', title: 'Sintel', libraryId: 'lib-1', year: 2010, durationMs: 888000);
  server.addItem(id: 'item-2', kind: 'movie', title: 'Tears of Steel', libraryId: 'lib-1', year: 2012, durationMs: 734000);
  server.addLibrary(id: 'lib-2', title: 'Series', kind: 'shows', itemCount: 1);
  server.addItem(id: 'show-1', kind: 'show', title: 'Serie', libraryId: 'lib-2');
  server.addItem(id: 'season-1', kind: 'season', title: 'Season 1', libraryId: 'lib-2', parentId: 'show-1');
  server.addItem(id: 'ep-1', kind: 'episode', title: 'Aflevering 1', libraryId: 'lib-2', parentId: 'season-1', durationMs: 1500000);
  return server;
}

void main() {
  test('elk JSON-antwoord van de fake server wordt vastgelegd voor de contractcontrole', () async {
    final server = _seeded();
    final captured = <_Captured>[];

    // Elke TokenPair roteert het access token, dus een vast 'at-0' is na de
    // eerste refresh ongeldig en levert overal 401 op. De vangst draagt daarom
    // het token mee dat de server net heeft uitgegeven.
    var token = 'at-0';

    Future<void> record(String schema, String method, String path, {Object? body, int expect_ = 200}) async {
      final request = http.Request(method, Uri.parse('http://fixture/pleya/v1$path'));
      request.headers['Authorization'] = 'Bearer $token';
      if (body != null) request.body = jsonEncode(body);
      final response = await server.handle(request);

      if (schema == 'TokenPair' && response.statusCode == 200) {
        final pair = jsonDecode(response.body) as Map<String, dynamic>;
        token = pair['access_token'] as String;
      }

      expect(
        response.statusCode,
        expect_,
        reason: '$method $path gaf ${response.statusCode}; de vangst zou dan het verkeerde schema toetsen',
      );

      final name = 'fake-${captured.length.toString().padLeft(2, '0')}.json';
      captured.add(_Captured(name, schema, method, path, response.statusCode, response.body));
    }

    // De routes die de fake server werkelijk bedient, elk tegen het schema dat
    // het contract voor dat endpoint belooft.
    await record('Info', 'GET', '/info');
    await record('TokenPair', 'POST', '/auth/setup', body: {
      'setup_code': 'VERIFY-SETUP-CODE',
      'username': 'eigenaar',
      'password': 'hunter2',
    });
    await record('TokenPair', 'POST', '/auth/login', body: {'username': 'eigenaar', 'password': 'hunter2'});
    await record('TokenPair', 'POST', '/auth/refresh');
    await record('ServerDetail', 'GET', '/server');
    await record('LibraryList', 'GET', '/libraries');
    await record('ItemPage', 'GET', '/libraries/lib-1/items');
    await record('Item', 'GET', '/items/item-1');
    await record('ItemPage', 'GET', '/items/show-1/children');
    await record('ItemPage', 'GET', '/search?q=sintel');
    await record('StreamToken', 'POST', '/auth/stream-token', body: {'version_id': 'ver-1'});
    await record('UserState', 'POST', '/watch-state', body: {
      'item_id': 'item-1',
      'position_ms': 12000,
      'duration_ms': 888000,
      'completed': false,
    });
    await record('WatchStatePage', 'GET', '/watch-state');

    // De foutkant hoort er net zo goed bij: een foutlichaam dat niet aan
    // ErrorEnvelope voldoet breekt de foutafhandeling van de client.
    await record('ErrorEnvelope', 'POST', '/auth/login',
        body: {'username': 'michel', 'password': 'fout'}, expect_: 401);
    await record('ErrorEnvelope', 'GET', '/items/bestaat-niet', expect_: 404);

    expect(captured, isNotEmpty);
    // Zonder deze ondergrens zou een fake server die alles op 404 zet nog steeds
    // een geldige, lege vangst opleveren.
    expect(
      captured.map((c) => c.schema).toSet().length,
      greaterThanOrEqualTo(9),
      reason: 'de vangst dekt te weinig schema\'s om iets te bewijzen',
    );

    final target = Platform.environment[envResponseDir];
    if (target == null || target.isEmpty) {
      markTestSkipped('$envResponseDir is niet gezet; alleen de statuscodes zijn gecontroleerd');
      return;
    }

    final dir = Directory(target);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    for (final entry in captured) {
      File('${dir.path}/${entry.file}').writeAsStringSync(entry.body);
    }
    File('${dir.path}/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'responses': [for (final entry in captured) entry.toManifest()],
      }),
    );
  });
}

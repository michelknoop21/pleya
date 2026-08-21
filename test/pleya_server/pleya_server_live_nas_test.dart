@Tags(['live'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/image_cache_service.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';
import 'package:pleya/services/pleya_server_client.dart';

import '../test_helpers/prefs.dart';

/// PS-3 acceptatiecriterium 1 en het stopcriterium, gemeten tegen de draaiende
/// server op de DS920+ in plaats van tegen een nabootsing.
///
/// Waarom dit bestaat. De fase stond op "opgeleverd, ter goedkeuring" omdat het
/// bewijs uit tests kwam en niet van een toestel. Dezelfde route die de app
/// loopt wordt hier tegen de echte server gelegd: `GET /info`, inloggen,
/// bibliotheken, bladeren, zoeken, artwork, en daarna de rij in een echte
/// database opnieuw inlezen en er een verse client uit bouwen. Dat laatste is
/// wat "overleeft een herstart" in de praktijk betekent.
///
/// De test slaat zichzelf over zonder adres, want een suite die een NAS nodig
/// heeft om groen te zijn is geen suite. Draaien:
///
/// ```sh
/// cd pleya_web && bun run scripts/nas-tunnel.ts &     # http://127.0.0.1:18832
/// export PLEYA_WEB_USER PLEYA_WEB_PASS
/// PLEYA_NAS_BASE_URL=http://127.0.0.1:18832 \
///   flutter test test/pleya_server/pleya_server_live_nas_test.dart --tags live
/// ```
void main() {
  final baseUrl = Platform.environment['PLEYA_NAS_BASE_URL'] ?? '';
  final user = Platform.environment['PLEYA_WEB_USER'] ?? '';
  final pass = Platform.environment['PLEYA_WEB_PASS'] ?? '';

  if (baseUrl.isEmpty || user.isEmpty || pass.isEmpty) {
    test('live NAS measurement', () {
      expect(baseUrl, isEmpty, reason: 'unreachable: this body only runs when the suite is skipped');
    }, skip: 'set PLEYA_NAS_BASE_URL, PLEYA_WEB_USER and PLEYA_WEB_PASS');
    return;
  }

  // flutter_test hangt een HttpOverrides op die elke aanvraag met een 400
  // beantwoordt zonder het netwerk te raken. Deze test bestaat juist om het
  // netwerk te raken, dus de override gaat er vóór elke test af; de binding
  // zet hem bij het opstarten opnieuw.
  setUp(() => HttpOverrides.global = null);

  late AppDatabase db;
  late ConnectionRegistry registry;
  final closeables = <PleyaServerClient>[];

  setUpAll(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registry = ConnectionRegistry(db);
  });

  tearDownAll(() async {
    for (final client in closeables) {
      client.close();
    }
    await db.close();
  });

  test('the DS920+ answers /info as a Pleya Protocol v1 server', () async {
    final info = await PleyaServerAuthService().probe(baseUrl);
    expect(info.major, 1);
    expect(info.auth.setupRequired, isFalse, reason: 'the owner exists; a reset server would fail every stored token');
    expect(info.capabilities.browse, isTrue);
    expect(info.capabilities.search, isTrue);
    // De meting is het product van deze test, dus hij hoort in de uitvoer en
    // niet in een logger die de testrunner wegfiltert.
    // ignore: avoid_print
    print(
      'LIVE /info: server=${info.serverId} browse=${info.capabilities.browse} '
      'search=${info.capabilities.search} artwork=${info.capabilities.artwork} '
      'watch_state=${info.capabilities.watchState}',
    );
  });

  test('logging in yields a connection that browses, searches and draws artwork', () async {
    final auth = PleyaServerAuthService();
    final result = await auth.login(baseUrl: baseUrl, username: user, password: pass);
    final detail = await auth.fetchServerDetail(baseUrl: baseUrl, accessToken: result.tokens.accessToken);

    final connection = PleyaServerConnection(
      id: 'pleyaServer.${result.info.serverId}',
      baseUrl: baseUrl,
      serverId: result.info.serverId,
      serverName: detail?.name.isNotEmpty == true ? detail!.name : 'Pleya Server',
      userName: result.userName,
      refreshToken: result.tokens.refreshToken,
      status: ConnectionStatus.online,
      createdAt: DateTime.now(),
      lastAuthenticatedAt: DateTime.now(),
    );
    await registry.upsert(connection);

    final client = PleyaServerClient.create(connection, onConnectionUpdated: (updated) => registry.upsert(updated));
    closeables.add(client);

    expect(await client.checkHealth(), HealthStatus.online);
    expect(client.backend, MediaBackend.pleyaServer);

    final libraries = await client.fetchLibraries();
    expect(libraries, isNotEmpty, reason: 'acceptatiecriterium 1: de verbinding toont bibliotheken');

    var itemsSeen = 0;
    var artworkBytes = 0;
    for (final library in libraries) {
      final page = await client.fetchLibraryContent(library.id, const LibraryQuery(limit: 20));
      itemsSeen += page.items.length;
      // De meting is het product van deze test, dus hij hoort in de uitvoer en
      // niet in een logger die de testrunner wegfiltert.
      // De meting is het product van deze test, dus hij hoort in de uitvoer en
      // niet in een logger die de testrunner wegfiltert.
      // ignore: avoid_print
      print(
        'LIVE bibliotheek "${library.title}" (${library.kind}): ${page.items.length} items op de eerste pagina, '
        'totaal ${page.totalCount}',
      );
      if (page.items.isEmpty) continue;
      final item = page.items.first;
      expect(item.title, isNotEmpty);
      final url = client.thumbnailUrl(item.thumbPath ?? item.artPath, width: 300);
      if (url.isEmpty) continue;
      final uri = Uri.parse(url);
      final headers = await ArtworkAuthorizationRegistry.headersFor(uri);
      expect(headers.containsKey('Authorization'), isTrue, reason: 'artwork reist met een header, DEC-048');
      final response = await http.get(uri, headers: headers);
      expect(response.statusCode, 200);
      expect(response.bodyBytes.lengthInBytes, greaterThan(0));
      artworkBytes += response.bodyBytes.lengthInBytes;
      // De meting is het product van deze test, dus hij hoort in de uitvoer en
      // niet in een logger die de testrunner wegfiltert.
      // De meting is het product van deze test, dus hij hoort in de uitvoer en
      // niet in een logger die de testrunner wegfiltert.
      // ignore: avoid_print
      print('LIVE artwork "${item.title}": ${response.bodyBytes.lengthInBytes} bytes');
    }
    expect(itemsSeen, greaterThan(0), reason: 'stopcriterium: er valt echt iets te bladeren');
    expect(artworkBytes, greaterThan(0), reason: 'posters komen echt binnen');

    final hits = await client.searchItems('a', limit: 10);
    // De meting is het product van deze test, dus hij hoort in de uitvoer en
    // niet in een logger die de testrunner wegfiltert.
    // ignore: avoid_print
    print('LIVE zoeken "a": ${hits.length} resultaten');
  });

  test('the stored row survives a restart and browses again from cold', () async {
    final restored = await registry.list();
    final pleya = restored.whereType<PleyaServerConnection>().single;
    expect(pleya.baseUrl, baseUrl);
    expect(pleya.refreshToken, isNotEmpty, reason: 'zonder token is een herstart een nieuwe login');

    // Een verse client uit de opgeslagen rij, zonder de tokens uit de vorige
    // test: dit is wat de app na een herstart doet.
    final cold = PleyaServerClient.create(pleya, onConnectionUpdated: (updated) => registry.upsert(updated));
    closeables.add(cold);

    expect(await cold.checkHealth(), HealthStatus.online, reason: 'het bewaarde refreshtoken opent de sessie opnieuw');
    final libraries = await cold.fetchLibraries();
    expect(libraries, isNotEmpty, reason: 'acceptatiecriterium 1: blijft na herstart staan en toont bibliotheken');
    // De meting is het product van deze test, dus hij hoort in de uitvoer en
    // niet in een logger die de testrunner wegfiltert.
    // ignore: avoid_print
    print('LIVE na herstart: ${libraries.length} bibliotheken via het bewaarde refreshtoken');
  });
}

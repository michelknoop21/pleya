@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';
import 'package:pleya/services/pleya_server_client.dart';

import '../test_helpers/prefs.dart';

/// Golden journey 11 (L.5), de appkant: wat Michel deelt komt bij Sanne aan en
/// niet bij Kids, en een afspeellijst staat op volgorde. Alles loopt over
/// [PleyaServerClient] achter een echte [MultiServerManager], tegen de server
/// van `pleya_web/scripts/e2e-stack.sh`. De test begint pas na de webhelft, want
/// die maakt de eigenaar aan; `pleya_server/scripts/journeys/journey-11.sh` zet
/// ze achter elkaar.
///
/// Bewijst de client en de rechten, geen scherm: dat is de Verify-bundel op een
/// toestel, en die staat open in de masterlijst.
void main() {
  final baseUrl = Platform.environment['PLEYA_E2E_BASE_URL'] ?? '';
  final serverId = Platform.environment['PLEYA_E2E_SERVER_ID'] ?? '';
  final ownerName = Platform.environment['PLEYA_E2E_USER'] ?? 'e2e';
  final ownerPass = Platform.environment['PLEYA_E2E_PASS'] ?? 'een-lang-genoeg-wachtwoord';

  if (baseUrl.isEmpty || serverId.isEmpty) {
    test('journey 11', () {}, skip: 'set PLEYA_E2E_BASE_URL and PLEYA_E2E_SERVER_ID, see journey-11.sh');
    return;
  }

  // flutter_test blokkeert het netwerk; deze test bestaat om het te raken.
  setUp(() => HttpOverrides.global = null);
  setUpAll(resetSharedPreferencesForTest);

  final api = '$baseUrl/pleya/v1';
  final auth = PleyaServerAuthService();
  final managers = <MultiServerManager>[];
  final temporary = <String>[];
  late Map<String, String> ownerHeaders;

  Future<PleyaServerClient> signIn(String username, String password) async {
    final result = await auth.login(baseUrl: baseUrl, username: username, password: password);
    final manager = MultiServerManager();
    managers.add(manager);
    final connection = PleyaServerConnection(
      id: pleyaServerConnectionId(serverId: result.info.serverId, userId: result.userId),
      baseUrl: baseUrl,
      serverId: result.info.serverId,
      serverName: 'Journey',
      userName: result.userName,
      refreshToken: result.tokens.refreshToken,
      role: result.role,
      createdAt: DateTime.now(),
    );
    expect(await manager.addPleyaServerConnection(connection), isTrue);
    return manager.getClient(ServerId(result.info.serverId))! as PleyaServerClient;
  }

  Future<(String id, PleyaServerClient client)> temporaryUser(String role) async {
    final name = 'journey-$role-${DateTime.now().microsecondsSinceEpoch}';
    const password = 'journey-wegwerpwachtwoord';
    final created = await http.post(
      Uri.parse('$api/users'),
      headers: ownerHeaders,
      body: jsonEncode({'username': name, 'password': password, 'role': role}),
    );
    expect(created.statusCode, lessThan(300), reason: created.body);
    final id = (jsonDecode(created.body) as Map<String, dynamic>)['id'] as String;
    temporary.add(id);
    final libraries = await http.get(Uri.parse('$api/libraries'), headers: ownerHeaders);
    final granted = await http.put(
      Uri.parse('$api/users/$id/permissions'),
      headers: ownerHeaders,
      body: jsonEncode({
        'permissions': [
          for (final library in (jsonDecode(libraries.body) as Map<String, dynamic>)['items'] as List)
            {'library_id': (library as Map<String, dynamic>)['id'], 'permission': 'view'},
        ],
      }),
    );
    expect(granted.statusCode, lessThan(300), reason: granted.body);
    return (id, await signIn(name, password));
  }

  Future<List<MediaItem>> films(PleyaServerClient client) async {
    final library = (await client.fetchLibraries()).firstWhere((library) => library.kind == MediaKind.movie);
    return (await client.fetchLibraryContent(library.id, const LibraryQuery())).items;
  }

  tearDownAll(() async {
    for (final id in temporary) {
      await http.delete(Uri.parse('$api/users/$id'), headers: ownerHeaders);
    }
    for (final manager in managers) {
      manager.dispose();
    }
  });

  test(
    'a shared collection reaches Sanne and not Kids, and a playlist keeps its order',
    () async {
      final info = await auth.probe(baseUrl);
      expect(info.serverId, serverId, reason: 'PLEYA_E2E_SERVER_ID must name this disposable stack');
      expect(info.capabilities.collections, isTrue);
      expect(info.capabilities.playlists, isTrue);

      final owner = await auth.login(baseUrl: baseUrl, username: ownerName, password: ownerPass);
      ownerHeaders = {'Authorization': 'Bearer ${owner.tokens.accessToken}', 'Content-Type': 'application/json'};
      final michel = await signIn(ownerName, ownerPass);
      final (sanneId, sanne) = await temporaryUser('member');
      final (_, kids) = await temporaryUser('member');
      final (_, admin) = await temporaryUser('admin');

      // Michel maakt hem in de app. Zonder delen is hij voor iedereen op de server.
      final catalogue = await films(michel);
      expect(catalogue.length, greaterThanOrEqualTo(2), reason: 'the stack needs two films');
      final forAll = await michel.createCollection(libraryId: '', title: 'Voor iedereen', items: [catalogue.first]);
      expect((await kids.fetchCollections('')).map((c) => c.id), contains(forAll));
      expect((await sanne.fetchCollectionPage(forAll!)).items.map((i) => i.id), [catalogue.first.id]);

      // Michel deelt met Sanne alleen.
      final shared = await http.patch(
        Uri.parse('$api/collections/$forAll'),
        headers: ownerHeaders,
        body: jsonEncode({
          'visibility': 'users',
          'shared_with': [sanneId],
        }),
      );
      expect(shared.statusCode, 200, reason: shared.body);

      expect((await sanne.fetchCollections('')).map((c) => c.id), contains(forAll));
      expect((await sanne.fetchCollectionPage(forAll)).items, hasLength(1));
      expect((await kids.fetchCollections('')).map((c) => c.id), isNot(contains(forAll)));
      expect((await kids.fetchCollectionPage(forAll)).items, isEmpty);

      // Canoniek beheer blijft bij de eigenaar: Sanne en een admin worden lokaal
      // geweigerd, en de server ziet geen schrijfactie.
      final item = catalogue.last;
      for (final client in [sanne, admin]) {
        await expectLater(
          client.addToCollection(collectionId: forAll, items: [item]),
          throwsA(isA<MediaServerAuthException>()),
        );
      }
      expect((await michel.fetchCollectionPage(forAll)).items, hasLength(1));

      // Sanne maakt haar eigen afspeellijst en draait de volgorde om.
      final MediaServerClient app = sanne;
      final [first, second, ...] = catalogue;
      final playlist = (await app.createPlaylist(title: 'Op volgorde', items: [first, second]))!;
      expect((await app.fetchPlaylistPage(playlist.id)).items.map((i) => i.id), [first.id, second.id]);
      await app.movePlaylistItem(playlistId: playlist.id, item: second, newIndex: 0, afterItem: null);
      expect((await app.fetchPlaylistPage(playlist.id)).items.map((i) => i.id), [second.id, first.id]);
      expect(await kids.fetchPlaylistMetadata(playlist.id), isNull);
      expect((await michel.fetchPlaylists()).map((p) => p.id), isNot(contains(playlist.id)));

      expect(
        await michel.deleteCollection(
          MediaItem(id: forAll, backend: MediaBackend.pleyaServer, kind: MediaKind.collection),
        ),
        isTrue,
      );
      expect(await app.deletePlaylist(playlist), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

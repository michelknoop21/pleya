import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// What happens when the server misbehaves.
///
/// Three failure modes that look alike from a distance and must not be
/// conflated: a token this client believed in but the server no longer accepts,
/// a chain that is genuinely gone, and a server that is simply not there. The
/// first repairs itself, the second needs a sign-in, and the third needs
/// nothing but patience.
void main() {
  late PleyaFakeServer server;
  late PleyaServerClient client;

  Future<PleyaServerClient> connected() async {
    final c = server.client();
    await c.refreshCapabilities();
    return c;
  }

  setUp(() {
    server = PleyaFakeServer();
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    for (var i = 1; i <= 3; i++) {
      server.addItem(id: 'movie-$i', kind: 'movie', title: 'Film $i', libraryId: 'lib-films', durationMs: 1000);
    }
  });

  tearDown(() => client.close());

  test('a restarted server that drops its signing key repairs itself on the next call', () async {
    client = await connected();
    expect(await client.fetchLibraries(), hasLength(1));

    // The server lost its key: every outstanding access token is now rejected.
    server.rejectCurrentAccessTokens = true;
    final duringOutage = await client.fetchLibraries();
    expect(duringOutage, isEmpty, reason: 'the retry also fails while the server rejects everything');

    server.rejectCurrentAccessTokens = false;
    final after = await client.fetchLibraries();
    expect(after, hasLength(1), reason: 'the invalidated token was replaced rather than reused');
  });

  test('a single 401 costs one retry and not a loop', () async {
    client = await connected();
    await client.fetchLibraries();
    final before = server.requests.where((r) => r.endsWith('/libraries')).length;
    server.rejectCurrentAccessTokens = true;
    await client.fetchLibraries();
    final attempts = server.requests.where((r) => r.endsWith('/libraries')).length - before;
    expect(attempts, 2, reason: 'one attempt plus exactly one retry');
  });

  test('an unreachable server is offline and never signed out', () async {
    client = await connected();
    server.unreachable = true;
    expect(await client.checkHealth(), HealthStatus.offline);
    expect(await client.fetchLibraries(), isEmpty);
    server.unreachable = false;
    expect(await client.checkHealth(), HealthStatus.online);
    expect(await client.fetchLibraries(), hasLength(1));
  });

  test('a browse call against an unreachable server returns an empty page, not an exception', () async {
    client = await connected();
    server.unreachable = true;
    final page = await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery());
    expect(page.items, isEmpty);
    expect(page.totalCount, 0);
  });

  test('a body that is not the contract is dropped rather than half-read', () async {
    client = await connected();
    server.items['movie-1'] = const {'id': 'movie-1', 'kind': 'movie'};
    expect(await client.fetchItem('movie-1'), isNull, reason: 'title and added_at are required');
  });

  test('a field a later phase adds is ignored, per compatibility rule 1', () async {
    client = await connected();
    server.items['movie-1'] = {...server.items['movie-1']!, 'summary': 'PS-7 will add this', 'rating': 8.4};
    final item = await client.fetchItem('movie-1');
    expect(item, isNotNull);
    expect(item!.title, 'Film 1');
  });

  test('a health probe refreshes capabilities, so a server that gains a feature is noticed', () async {
    client = await connected();
    expect(client.wireCapabilities.watchState, isFalse);

    final upgraded = PleyaFakeServer(watchState: true);
    upgraded.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    client.close();
    client = upgraded.client();
    await client.checkHealth();
    expect(client.wireCapabilities.watchState, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/services/watchlist/verify_watchlist_source.dart';
import 'package:pleya/services/watchlist/watchlist_source_factory.dart';

import '../pleya_server/pleya_fake_server.dart';

/// A fake Pleya Server with three films, of which [watchlist] are on the
/// Pleya Verify kijklijst (what `watchlist.studio.v1` seeds in a real run).
PleyaFakeServer _server({List<String> watchlist = const []}) {
  final server = PleyaFakeServer();
  server.addLibrary(id: 'lib-1', title: 'Films', kind: 'movies', itemCount: 3);
  for (final (id, title) in [('m-1', 'Sintel'), ('m-2', 'Spring'), ('m-3', 'Charge')]) {
    server.addItem(id: id, kind: 'movie', title: title, libraryId: 'lib-1', year: 2020, posterId: id);
  }
  server.verifyWatchlistIds.addAll(watchlist);
  return server;
}

Future<List<WatchlistSource>> _build(PleyaFakeServer server, {required bool verifyWatchlist}) {
  final client = server.client();
  return WatchlistSourceFactory(
    profileId: 'p1',
    resolvePlexAuth: () async => null,
    clientIdentifier: 'client-1',
    clientsById: () => {'pleyaServer.srv-1': client},
    verifyWatchlist: verifyWatchlist,
  ).build();
}

void main() {
  test('a Verify build turns the fixture kijklijst into a source, in its own order', () async {
    final sources = await _build(_server(watchlist: ['m-2', 'm-3']), verifyWatchlist: true);

    expect(sources, hasLength(1));
    final source = sources.single;
    expect(source, isA<VerifyWatchlistSource>());
    expect(source.scope.backend, MediaBackend.pleyaServer);
    expect(source.scope.profileId, 'p1');

    final entries = await source.fetch();
    expect([for (final e in entries) e.item.title], ['Spring', 'Charge']);
    expect(
      [for (final e in entries) e.key],
      [VerifyWatchlistSource.keyFor('m-2'), VerifyWatchlistSource.keyFor('m-3')],
    );
    expect([for (final e in entries) e.memberships.single.sourcePosition], [0, 1]);
    expect(entries.first.posterRef, isNotNull, reason: 'the rail draws the poster from this ref');
  });

  test('without the seed there is no source, so the empty kijklijst path stays testable', () async {
    expect(await _build(_server(), verifyWatchlist: true), isEmpty);
  });

  test('outside a Verify build the fixture list is never asked for', () async {
    final server = _server(watchlist: ['m-1']);

    expect(await _build(server, verifyWatchlist: false), isEmpty);
    expect(server.requests.where((path) => path.contains('/verify/')), isEmpty);
  });

  test('a fetch asks the client the profile has now, not the one it was built with', () async {
    final before = _server(watchlist: ['m-1']);
    final after = _server(watchlist: ['m-3']);
    var clients = {'pleyaServer.srv-1': before.client()};
    final sources = await WatchlistSourceFactory(
      profileId: 'p1',
      resolvePlexAuth: () async => null,
      clientIdentifier: 'client-1',
      clientsById: () => clients,
      verifyWatchlist: true,
    ).build();

    clients = {'pleyaServer.srv-1': after.client()};
    final entries = await sources.single.fetch();
    expect([for (final e in entries) e.item.title], ['Charge']);
    expect(before.requests.where((path) => path.contains('/items/')), isEmpty);
  });

  test('the list is read-only', () async {
    final source = (await _build(_server(watchlist: ['m-1']), verifyWatchlist: true)).single;
    final item = MediaItem(id: 'm-1', backend: MediaBackend.pleyaServer, kind: MediaKind.movie);

    expect(source.accepts(item), isFalse);
    await expectLater(source.add(item), throwsA(isA<WatchlistScopeUnavailable>()));
  });
}

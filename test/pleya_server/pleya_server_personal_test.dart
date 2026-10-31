import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// S20 on the client side: favorites, ratings and remembered tracks are sent
/// only to a server that advertises them.
void main() {
  late PleyaServerClient client;
  tearDown(() => client.close());

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    return c;
  }

  test('a server with the flags takes favorites, ratings and tracks', () async {
    final server = PleyaFakeServer(watchState: true)..personalCapability = true;
    client = await connected(server);

    expect(await client.setItemFavorite('movie-1', true), isTrue);
    expect(server.favoriteIds, {'movie-1'});
    expect(await client.setItemFavorite('movie-1', false), isTrue);
    expect(server.favoriteIds, isEmpty);

    expect(await client.setItemRating('movie-1', 8), isTrue);
    expect(server.ratingsByItem['movie-1'], 8);
    expect(await client.setItemRating('movie-1', null), isTrue);
    expect(server.ratingsByItem, isEmpty);

    expect((await client.getTrackPreference('movie-1'))?.audioLanguage, isNull);
    await client.saveTrackPreference('movie-1', audioLanguage: 'nld', subtitleMode: 'off');
    final pref = await client.getTrackPreference('movie-1');
    expect(pref?.audioLanguage, 'nld');
    expect(pref?.subtitleMode, 'off');
    expect(pref?.subtitleLanguage, isNull);
    await client.clearItemTrackPreference('movie-1');
    expect((await client.getTrackPreference('movie-1'))?.audioLanguage, isNull);
  });

  test('a server without the flags is not asked', () async {
    final server = PleyaFakeServer(watchState: true);
    client = await connected(server);

    expect(await client.setItemFavorite('movie-1', true), isFalse);
    expect(await client.setItemRating('movie-1', 5), isFalse);
    expect(await client.getTrackPreference('movie-1'), isNull);
    expect(await client.saveTrackPreference('movie-1', audioLanguage: 'nld'), isFalse);
    expect(server.favoriteIds, isEmpty);
  });
  MediaItem movie(String id) => MediaItem(id: id, backend: MediaBackend.pleyaServer, kind: MediaKind.movie);

  test('public favorite and rating writes survive a fresh item fetch', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    server.addItem(id: 'movie-1', kind: 'movie', title: 'One');
    client = await connected(server);
    final MediaServerClient public = client;
    await public.setFavorite(movie('movie-1'), true);
    await public.rate(movie('movie-1'), 7.6);
    final fetched = await public.fetchItem('movie-1');
    expect(fetched?.userRating, 8.0);
    expect(fetched?.raw?['favorite'], isTrue);
    await public.setFavorite(movie('movie-1'), false);
    await public.rate(movie('movie-1'), -1);
    final cleared = await public.fetchItem('movie-1');
    expect(cleared?.userRating, isNull);
    expect(cleared?.raw?['favorite'], isFalse);
  });

  test('public favorites page after filtering kinds and respect cursors', () async {
    final server = PleyaFakeServer(pageSizeCap: 1)..personalCapability = true;
    for (final (id, kind) in [('ep', 'episode'), ('m1', 'movie'), ('show', 'show'), ('m2', 'movie')]) {
      server.addItem(id: id, kind: kind, title: id);
      server.favoriteIds.add(id);
    }
    client = await connected(server);
    final MediaServerClient public = client;
    expect((await public.fetchFavorites(offset: 0, limit: 1)).items.map((i) => i.id), ['m1']);
    expect((await public.fetchFavorites(offset: 1, limit: 1)).items.map((i) => i.id), ['show']);
    expect((await public.fetchFavorites(kind: MediaKind.movie, offset: 1, limit: 1)).items.map((i) => i.id), ['m2']);
    expect((await public.fetchFavorites(kind: MediaKind.movie, offset: 2, limit: 1)).items, isEmpty);
    await public.setFavorite(movie('m1'), false);
    expect((await public.fetchFavorites(limit: 10)).items.map((i) => i.id), ['show', 'm2']);
  });

  test('favorites tolerate unknown item kinds and absent count estimates', () async {
    final server = PleyaFakeServer(pageSizeCap: 1)..personalCapability = true;
    for (final (id, kind) in [('book', 'future-book'), ('m1', 'movie'), ('m2', 'movie')]) {
      server.addItem(id: id, kind: kind, title: id);
      server.favoriteIds.add(id);
    }
    client = PleyaServerClient.create(
      server.connection(),
      httpClientFactory: () => MockClient((request) async {
        final response = await server.handle(request);
        if (!request.url.path.endsWith('/favorites')) return response;
        final page = jsonDecode(response.body) as Map<String, dynamic>;
        page.remove('total_estimate');
        return http.Response(jsonEncode(page), 200, headers: {'content-type': 'application/json'});
      }),
    );
    await client.refreshCapabilities();
    final first = await client.fetchFavorites(limit: 1);
    expect(first.items.map((item) => item.id), ['m1']);
    expect(first.totalCount, greaterThan(1));
    final second = await client.fetchFavorites(offset: 1, limit: 1);
    expect(second.items.map((item) => item.id), ['m2']);
    expect(second.totalCount, 2);
  });

  test('a repeated favorites cursor fails without looping on filtered items', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    server.addItem(id: 'episode', kind: 'episode', title: 'Episode');
    var pages = 0;
    client = PleyaServerClient.create(
      server.connection(),
      httpClientFactory: () => MockClient((request) async {
        if (!request.url.path.endsWith('/favorites')) return server.handle(request);
        pages++;
        if (pages > 3) throw StateError('test transport stopped an endless walk');
        return http.Response(
          jsonEncode({
            'items': [server.items['episode']],
            'next_cursor': 'repeated',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.refreshCapabilities();
    await expectLater(client.fetchFavorites(), throwsStateError);
    expect(pages, 2);
  });

  test('invalid ratings fail before a write and bounds remain usable', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    client = await connected(server);
    final MediaServerClient public = client;
    for (final bad in [0.0, 0.4, 10.1, double.nan, double.infinity, double.negativeInfinity]) {
      await expectLater(public.rate(movie('m'), bad), throwsArgumentError);
    }
    expect(server.ratingsByItem, isEmpty);
    await public.rate(movie('m'), 1);
    expect(server.ratingsByItem['m'], 1);
    await public.rate(movie('m'), 10);
    expect(server.ratingsByItem['m'], 10);
  });

  test('domain track choices preserve modes and the untouched remote language', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    server.trackPreferences['show'] = {'audio_language': 'eng', 'subtitle_language': 'nld', 'subtitle_mode': 'forced'};
    client = await connected(server);
    final forced = await client.getTrackLanguageChoice('show');
    expect(forced?.subtitleForced, isTrue);
    expect(forced?.audioLanguage, 'eng');
    await client.saveTrackLanguageChoice('show', const TrackLanguageChoice(audioLanguage: 'de-DE', updatedAt: 1));
    expect(server.trackPreferences['show']?['audio_language'], 'de');
    expect(server.trackPreferences['show']?['subtitle_language'], 'nl');
    expect(server.trackPreferences['show']?['subtitle_mode'], 'forced');
    await client.saveTrackLanguageChoice('show', const TrackLanguageChoice(subtitlesOff: true, updatedAt: 1));
    expect(server.trackPreferences['show']?['subtitle_mode'], 'off');
    expect(server.trackPreferences['show']?['audio_language'], 'de');
    expect((await client.getTrackLanguageChoice('show'))?.subtitlesOff, isTrue);
    await client.clearItemTrackPreference('show');
    expect(await client.getTrackLanguageChoice('show'), isNull);
  });

  test('a failed preference read cannot erase an untouched server choice', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    server.trackPreferences['show'] = {'subtitle_language': 'nld', 'subtitle_mode': 'forced'};
    client = await connected(server);
    server.queueFailure(pathPrefix: '/track-preferences/show', status: 503);
    await expectLater(
      client.saveTrackLanguageChoice('show', const TrackLanguageChoice(audioLanguage: 'eng', updatedAt: 1)),
      throwsA(anything),
    );
    expect(server.trackPreferences['show']?['subtitle_mode'], 'forced');
    expect(server.trackPreferences['show']?['audio_language'], isNull);
  });

  test('a retained preference cannot be cleared through another server account', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    client = await connected(server);
    await expectLater(client.clearItemTrackPreference('show', expectedAccountId: 'another-user'), throwsStateError);
    expect(server.requests.where((path) => path.contains('/track-preferences/')), isEmpty);
  });

  test('public methods never contact old server personal endpoints', () async {
    final server = PleyaFakeServer();
    client = await connected(server);
    final MediaServerClient public = client;
    await expectLater(public.setFavorite(movie('m'), true), throwsUnsupportedError);
    await expectLater(public.rate(movie('m'), 8), throwsUnsupportedError);
    expect((await public.fetchFavorites()).items, isEmpty);
    expect(server.requests.where((r) => r.contains('/favorites') || r.contains('/ratings')), isEmpty);
  });
}

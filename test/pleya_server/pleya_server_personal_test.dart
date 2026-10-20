import 'package:flutter_test/flutter_test.dart';
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
}

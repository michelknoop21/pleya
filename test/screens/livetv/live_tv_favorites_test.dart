import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/live_tv_support.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/screens/livetv/live_tv_favorites.dart';

/// A store that only has to answer for its key and its mode; nothing here
/// reaches the network.
class _Store implements LiveTvFavoritesStore {
  _Store(this.favoriteStoreKey, this.favoritePersistenceMode);

  @override
  final String favoriteStoreKey;

  @override
  final FavoriteChannelPersistenceMode favoritePersistenceMode;

  @override
  Future<List<FavoriteChannel>> fetchFavoriteChannels() async => const [];

  @override
  Future<void> setFavoriteChannels(List<FavoriteChannel> channels) async {}
}

FavoriteChannel favorite(String id, String source) => FavoriteChannel(source: source, id: id, title: id);

LiveTvChannel channel(String key, {String? storeKey, String? source}) =>
    LiveTvChannel(key: key, title: key).copyWith(favoriteStoreKey: storeKey, favoriteSource: source);

void main() {
  const plexSource = 'server://machine-1/tv.plex.provider.epg';
  const jellyfinSource = 'server://jf-1/jellyfin';

  group('mayWriteFavorites', () {
    test('a serverSlice store needs no read: its write cannot erase another list', () {
      final store = _Store('jellyfin:1', FavoriteChannelPersistenceMode.serverSlice);

      expect(mayWriteFavorites(store: store, generation: 3, proof: null), isTrue);
    });

    test('a sharedFullList store without a read is refused', () {
      final store = _Store('plex-account:a:u', FavoriteChannelPersistenceMode.sharedFullList);

      expect(mayWriteFavorites(store: store, generation: 1, proof: null), isFalse);
    });

    test('a read from the current generation allows the write', () {
      final store = _Store('plex-account:a:u', FavoriteChannelPersistenceMode.sharedFullList);
      final proof = FavoriteStoreReadProof(generation: 4, store: store);

      expect(mayWriteFavorites(store: store, generation: 4, proof: proof), isTrue);
    });

    test('a read from a previous generation does not carry over', () {
      final store = _Store('plex-account:a:u', FavoriteChannelPersistenceMode.sharedFullList);
      final stale = FavoriteStoreReadProof(generation: 4, store: store);

      expect(
        mayWriteFavorites(store: store, generation: 5, proof: stale),
        isFalse,
        reason: 'a rebind reshuffles identities, so proof from before it proves nothing now',
      );
    });

    test('the proof belongs to the instance, not to the key', () {
      final read = _Store('plex-account:a:u', FavoriteChannelPersistenceMode.sharedFullList);
      final other = _Store('plex-account:a:u', FavoriteChannelPersistenceMode.sharedFullList);
      final proof = FavoriteStoreReadProof(generation: 2, store: read);

      expect(
        mayWriteFavorites(store: other, generation: 2, proof: proof),
        isFalse,
        reason: 'same key, different store: the list that was read is not the list being written',
      );
      expect(mayWriteFavorites(store: read, generation: 2, proof: proof), isTrue);
    });
  });

  group('favoritePayload', () {
    final all = [favorite('a', plexSource), favorite('b', jellyfinSource)];

    test('sharedFullList writes everything the store owns', () {
      final payload = favoritePayload(
        mode: FavoriteChannelPersistenceMode.sharedFullList,
        forStore: all,
        source: plexSource,
      );

      expect(payload.map((f) => f.id), ['a', 'b']);
    });

    test('serverSlice writes only what this server stamped', () {
      final payload = favoritePayload(
        mode: FavoriteChannelPersistenceMode.serverSlice,
        forStore: all,
        source: jellyfinSource,
      );

      expect(payload.map((f) => f.id), ['b']);
    });

    test('none writes nothing', () {
      expect(favoritePayload(mode: FavoriteChannelPersistenceMode.none, forStore: all, source: plexSource), isEmpty);
    });
  });

  group('groupFavoritesByStore', () {
    test('groups per store and drops what has nowhere to go', () {
      final grouped = groupFavoritesByStore(
        favorites: [favorite('a', plexSource), favorite('b', jellyfinSource), favorite('orphan', 'server://gone/x')],
        storeBySource: {plexSource: 'plex-account:a:u', jellyfinSource: 'jellyfin:1'},
      );

      expect(grouped.keys.toSet(), {'plex-account:a:u', 'jellyfin:1'});
      expect(grouped['plex-account:a:u']!.map((f) => f.id), ['a']);
      // Writing the orphan somewhere would mean writing it into a list that is
      // not its own.
      expect(grouped.values.expand((v) => v).map((f) => f.id), isNot(contains('orphan')));
    });
  });

  group('capability versus permission', () {
    final plexStore = _Store('plex-account:a:u', FavoriteChannelPersistenceMode.sharedFullList);
    final jellyfinStore = _Store('jellyfin:1', FavoriteChannelPersistenceMode.serverSlice);
    final storeById = {'plex-account:a:u': plexStore, 'jellyfin:1': jellyfinStore};

    test('a channel without a store key is not favoritable at all', () {
      final orphan = channel('c1');

      expect(isFavoriteCapable(orphan, storeByChannel: const {}), isFalse);
      expect(
        canToggleFavorite(
          orphan,
          storeByChannel: const {},
          storeById: storeById,
          proofByStore: const {},
          generation: 1,
        ),
        isFalse,
      );
    });

    test('after a failed reread the star stays capable but becomes untouchable', () {
      final plexChannel = channel('c1', storeKey: 'plex-account:a:u', source: plexSource);

      expect(
        isFavoriteCapable(plexChannel, storeByChannel: const {}),
        isTrue,
        reason: 'the last proven list is still worth showing',
      );
      expect(
        canToggleFavorite(
          plexChannel,
          storeByChannel: const {},
          storeById: storeById,
          proofByStore: const {},
          generation: 7,
        ),
        isFalse,
        reason: 'without a read this generation, a toggle would write an unproven list',
      );
    });

    test('a Jellyfin channel stays toggleable without any read', () {
      final jellyfinChannel = channel('c2', storeKey: 'jellyfin:1', source: jellyfinSource);

      expect(
        canToggleFavorite(
          jellyfinChannel,
          storeByChannel: const {},
          storeById: storeById,
          proofByStore: const {},
          generation: 7,
        ),
        isTrue,
      );
    });

    test('the channel map fills in for channels that were never stamped', () {
      final unstamped = channel('c3');
      final byChannel = {liveTvChannelScopeKey(unstamped): 'jellyfin:1'};

      expect(favoriteStoreKeyForChannel(unstamped, storeByChannel: byChannel), 'jellyfin:1');
      expect(isFavoriteCapable(unstamped, storeByChannel: byChannel), isTrue);
    });
  });
}

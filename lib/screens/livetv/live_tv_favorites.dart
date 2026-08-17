/// The favorite-channel rules of the Live TV screen, as plain functions.
///
/// They live outside the widget for one reason: they decide when a write may
/// replace an entire account's favorite list, and a rule like that should be
/// testable without a widget tree, a MultiServerProvider and a focus system.
library;

import '../../media/live_tv_support.dart';
import '../../models/livetv_channel.dart';

/// Proof that a store was read successfully, and when.
///
/// A `sharedFullList` write replaces the whole list at the other end, so it may
/// only go out when the app has actually seen that list. Carrying the store
/// instance and the generation inside the proof, instead of keeping a set of
/// keys next to a counter, means the rule cannot quietly weaken later: a proof
/// from a previous resolution round, or from a different store that happens to
/// share a key, does not match.
class FavoriteStoreReadProof {
  const FavoriteStoreReadProof({required this.generation, required this.store});

  final int generation;
  final LiveTvFavoritesStore store;
}

/// Whether [store] may be handed the given [channels] as a write right now.
///
/// [serverSlice] stores need no proof: such a write only ever touches the
/// favorites of that one server, so it can never erase somebody else's list.
/// [sharedFullList] does need it, and that is the whole point.
bool mayWriteFavorites({
  required LiveTvFavoritesStore store,
  required int generation,
  required FavoriteStoreReadProof? proof,
}) {
  if (store.favoritePersistenceMode != FavoriteChannelPersistenceMode.sharedFullList) return true;
  if (proof == null) return false;
  return proof.generation == generation && identical(proof.store, store);
}

/// The payload for one store, given the merged list the screen holds.
///
/// [sharedFullList] writes everything that belongs to this store, because the
/// endpoint replaces the list wholesale. [serverSlice] writes only the entries
/// stamped with this server's own source.
List<FavoriteChannel> favoritePayload({
  required FavoriteChannelPersistenceMode mode,
  required List<FavoriteChannel> forStore,
  required String source,
}) {
  return switch (mode) {
    FavoriteChannelPersistenceMode.sharedFullList => forStore,
    FavoriteChannelPersistenceMode.serverSlice => forStore.where((f) => f.source == source).toList(),
    FavoriteChannelPersistenceMode.none => const [],
  };
}

/// Group the merged favorites by the store that owns them.
///
/// A favorite whose source maps to no store is left out on purpose: there is
/// nowhere to write it, and guessing would mean writing it into somebody
/// else's list.
Map<String, List<FavoriteChannel>> groupFavoritesByStore({
  required List<FavoriteChannel> favorites,
  required Map<String, String> storeBySource,
}) {
  final byStore = <String, List<FavoriteChannel>>{};
  for (final favorite in favorites) {
    final storeKey = storeBySource[favorite.source];
    if (storeKey == null) continue;
    byStore.putIfAbsent(storeKey, () => []).add(favorite);
  }
  return byStore;
}

/// Whether this channel belongs to a store that can hold favorites at all.
///
/// Structural, and therefore stable while the screen is open: it answers "could
/// this ever be a favorite", not "may I toggle it right now". Those are
/// different questions after a failed reread, when the last proven star is
/// still worth showing but must not be touched.
bool isFavoriteCapable(LiveTvChannel channel, {required Map<String, String> storeByChannel}) {
  return favoriteStoreKeyForChannel(channel, storeByChannel: storeByChannel) != null;
}

/// Whether this channel may be toggled right now.
///
/// Adds the write permission to [isFavoriteCapable]: the store has to exist,
/// and for a `sharedFullList` store the current generation has to have read it.
bool canToggleFavorite(
  LiveTvChannel channel, {
  required Map<String, String> storeByChannel,
  required Map<String, LiveTvFavoritesStore> storeById,
  required Map<String, FavoriteStoreReadProof> proofByStore,
  required int generation,
}) {
  final storeKey = favoriteStoreKeyForChannel(channel, storeByChannel: storeByChannel);
  if (storeKey == null) return false;
  final store = storeById[storeKey];
  if (store == null) return false;
  return mayWriteFavorites(store: store, generation: generation, proof: proofByStore[storeKey]);
}

/// The store key stamped onto the channel, falling back to the per-channel map
/// for channels that were built before the stamp existed.
///
/// One place decides this, so the guide, the reorder sheet and the keyboard
/// cannot each invent their own reading of "which store does this belong to".
String? favoriteStoreKeyForChannel(LiveTvChannel channel, {required Map<String, String> storeByChannel}) {
  return channel.favoriteStoreKey ?? storeByChannel[liveTvChannelScopeKey(channel)];
}

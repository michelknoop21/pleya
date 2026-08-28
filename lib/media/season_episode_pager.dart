import 'media_item.dart';
import 'paged_media_list_state.dart';

/// Per-season paging state for a show's episode lists, keyed by season id.
///
/// Owned by the detail screen's `State`: not persisted, not shared across
/// screens. [completeFirstPage]/[completeMoreLoad] swap the underlying
/// [PagedMediaListState] atomically, so a caller applying a fresh page never
/// exposes an intermediate empty state.
class SeasonEpisodePager {
  final Map<String, PagedMediaListState<MediaItem>> _states = {};
  final Set<String> _firstPageLoadsInFlight = {};
  final Set<String> _moreLoadsInFlight = {};

  PagedMediaListState<MediaItem> stateFor(String seasonId) {
    return _states[seasonId] ?? const PagedMediaListState<MediaItem>();
  }

  bool hasState(String seasonId) => _states.containsKey(seasonId);

  bool beginFirstPageLoad(String seasonId) => _firstPageLoadsInFlight.add(seasonId);
  void endFirstPageLoad(String seasonId) => _firstPageLoadsInFlight.remove(seasonId);

  bool beginMoreLoad(String seasonId) => _moreLoadsInFlight.add(seasonId);
  void endMoreLoad(String seasonId) => _moreLoadsInFlight.remove(seasonId);

  void markFirstPageLoading(String seasonId) {
    _states[seasonId] = stateFor(seasonId).startInitialLoad();
  }

  void completeFirstPage(String seasonId, List<MediaItem> episodes, int total) {
    _states[seasonId] = stateFor(seasonId).completeInitialLoad(episodes, total);
  }

  void failFirstPage(String seasonId) {
    _states[seasonId] = stateFor(seasonId).failInitialLoad();
  }

  void markMoreLoading(String seasonId) {
    _states[seasonId] = stateFor(seasonId).startLoadMore();
  }

  void completeMoreLoad(
    String seasonId, {
    required int expectedOffset,
    required List<MediaItem> episodes,
    required int total,
  }) {
    _states[seasonId] = stateFor(
      seasonId,
    ).completeLoadMore(expectedOffset: expectedOffset, pageItems: episodes, total: total);
  }

  void failMoreLoad(String seasonId) {
    _states[seasonId] = stateFor(seasonId).failLoadMore();
  }

  void resetSeason(String seasonId) {
    _states.remove(seasonId);
    _firstPageLoadsInFlight.remove(seasonId);
    _moreLoadsInFlight.remove(seasonId);
  }

  void removeEpisode(String episodeId) {
    for (final entry in _states.entries.toList()) {
      _states[entry.key] = entry.value.removeWhere((episode) => episode.id == episodeId);
    }
  }

  void updateEpisode(String seasonId, int index, MediaItem updated) {
    final state = _states[seasonId];
    if (state == null || index < 0 || index >= state.items.length) return;
    final next = List<MediaItem>.of(state.items);
    next[index] = updated;
    _states[seasonId] = state.replaceItems(next);
  }

  void patchEpisode(String episodeId, MediaItem Function(MediaItem existing) patch) {
    for (final entry in _states.entries.toList()) {
      var changed = false;
      final next = <MediaItem>[];
      for (final episode in entry.value.items) {
        if (episode.id == episodeId) {
          changed = true;
          next.add(patch(episode));
        } else {
          next.add(episode);
        }
      }
      if (changed) _states[entry.key] = entry.value.replaceItems(next);
    }
  }
}

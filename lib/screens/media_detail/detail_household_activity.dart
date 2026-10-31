part of '../media_detail_screen.dart';

/// The activity line on a backend that is not Plex: a Pleya Server's answer
/// under its capability, and the viewer's own line from the item's watch state
/// on any backend that allows one (referenties 03, 01 and 06).
extension _MediaDetailHouseholdActivity on _MediaDetailScreenState {
  bool get _readsHouseholdActivity {
    final client = _getMediaClientForMetadata(context);
    return client is HouseholdActivityClient && client.capabilities.itemActivity;
  }

  /// One request per item and page. Reads nothing when the server has no such
  /// route, so a call from a build is harmless.
  Future<void> _loadHouseholdActivity(MediaItem item) async {
    if (!_readsHouseholdActivity || !_householdActivityAsked.add(item.id)) return;
    final client = _getMediaClientForMetadata(context) as HouseholdActivityClient;
    final watchers = await client.fetchHouseholdActivity(item.id);
    setStateIfMounted(() {
      _householdActivity[item.id] = watchers;
      if (item.id == _metadata.id) _watchers = (watchers: watchers, scope: ItemWatchersScope.activity);
    });
  }

  /// A season tab shows that season's activity, every other page its own item.
  MediaItem get _tvDetailActivitySubject => _tvDetailShowsSeasonTab ? _tvDetailOpenSeason ?? _metadata : _metadata;

  ItemWatchers? _tvDetailActivity() {
    final client = _getMediaClientForMetadata(context);
    if (client == null || !client.capabilities.ownActivityLine) return _watchers;
    final subject = _tvDetailActivitySubject;
    if (subject.id != _metadata.id) unawaited(_loadHouseholdActivity(subject));
    return const ItemWatchersService().activityLine(
      subject,
      household: _householdActivity[subject.id] ?? const [],
      selfName: context.read<ActiveProfileProvider?>()?.active?.displayName ?? t.discover.watchedByYou,
    );
  }
}

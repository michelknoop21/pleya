import 'dart:async';

import 'package:flutter/widgets.dart';

import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/unified/unified_media_group.dart';
import '../media/watchlist_entry.dart';
import '../media/unified/unified_media_hub.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/livetv_channel.dart';
import '../models/livetv_hub_result.dart';
import '../services/unified_catalog/home_projection_service.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids.dart';
import '../utils/external_ids_fetcher.dart';
import '../utils/live_tv_matching.dart';
import '../utils/live_tv_player_navigation.dart';
import '../services/data_aggregation_service.dart';
import 'discover_provider.dart';
import 'hidden_libraries_provider.dart';
import 'home_layout_provider.dart';
import 'multi_server_provider.dart';
import 'watchlist_provider.dart';

/// How many cards a row Pleya adds itself shows. The full list has its own
/// screen (Kijklijst, Live TV); Home shows a short selection of it.
const int kHomeExtraRowCardLimit = 20;

typedef HomeLiveTvContent = ({List<LiveTvHubEntry> entries, List<LiveTvChannel> channels});

/// Starts live playback of a channel; `navigateToLiveTv` unless a test hands
/// in its own.
typedef HomeLiveTvTuner = Future<void> Function(BuildContext context, LiveTvChannel channel, List<LiveTvChannel> all);

/// The Home rows Pleya adds itself (DEC-145): Kijklijst and Nu op tv.
///
/// Both take part in the layout like any other row, under their own ids
/// ([homeWatchlistRowId], [homeLiveTvRowId]). A hidden row fetches nothing:
/// Kijklijst is asked for only while it is visible, and Nu op tv, which is
/// hidden until the viewer turns it on, costs a profile that never does
/// exactly zero requests.
class HomeExtraRowsProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  HomeExtraRowsProvider({
    required HomeLayoutProvider layout,
    required MultiServerProvider multiServer,
    required String watchlistTitle,
    required String liveTvTitle,
    WatchlistProvider? watchlist,
    HiddenLibrariesProvider? hiddenLibraries,
    DiscoverProvider? discover,
    HomeProjectionService? watchlistProjection,
    Future<HomeLiveTvContent> Function()? loadLiveTv,
    HomeLiveTvTuner? tuneChannel,
  }) : _layout = layout,
       _multiServer = multiServer,
       _watchlist = watchlist,
       _hiddenLibraries = hiddenLibraries,
       _discover = discover,
       _watchlistTitle = watchlistTitle,
       _liveTvTitle = liveTvTitle,
       _watchlistProjection =
           watchlistProjection ?? HomeProjectionService(fetchExternalIds: externalIdsFetcherFor(multiServer)),
       _loadLiveTvOverride = loadLiveTv,
       _tuneChannel = tuneChannel {
    _layout.addListener(_refresh);
    _watchlist?.addListener(_refresh);
    _hiddenLibraries?.addListener(_refresh);
    _onlineServers = _onlineServerKey();
    _multiServer.addListener(_onServersChanged);
    _seenLoadGeneration = _discover?.loadGeneration ?? 0;
    _discover?.addListener(_onDiscoverChanged);
    _refresh();
  }

  final HomeLayoutProvider _layout;
  final MultiServerProvider _multiServer;
  final WatchlistProvider? _watchlist;
  final HiddenLibrariesProvider? _hiddenLibraries;
  final DiscoverProvider? _discover;
  int _seenLoadGeneration = 0;
  final String _watchlistTitle;
  final String _liveTvTitle;
  final HomeProjectionService _watchlistProjection;
  final Future<HomeLiveTvContent> Function()? _loadLiveTvOverride;
  final HomeLiveTvTuner? _tuneChannel;

  /// An EPG entry has no library identity to resolve, so its projection never
  /// asks a server for external ids.
  final HomeProjectionService _liveTvProjection = HomeProjectionService(
    fetchExternalIds: (_, _) async => const ExternalIds(),
  );

  List<UnifiedMediaGroup> _watchlistGroups = const [];
  List<String> _watchlistKeys = const [];

  /// Entries whose availability lookup failed. A failed lookup puts the entry
  /// back to unknown and notifies, which would otherwise make an offline
  /// profile ask again on every pass. Emptied when the server set changes, so a
  /// server coming back gets asked. Only failures are remembered: a reloaded
  /// kijklijst hands out fresh, unresolved entries under the same keys, and
  /// those have to be asked again or the row would lose its cards.
  final Set<String> _resolveFailed = {};

  List<UnifiedMediaGroup> _liveTvGroups = const [];
  Map<String, LiveTvHubEntry> _liveEntries = const {};
  List<LiveTvChannel> _liveChannels = const [];

  /// The Live TV servers the row was last loaded for; a change reloads it.
  String? _liveTvLoadedFor;

  /// A flag of its own, not a cleared [_liveTvLoadedFor]: a load in flight
  /// writes that field when it lands and would swallow the request.
  bool _liveTvReloadRequested = false;

  /// The last Live TV load lost at least one server, so it is not the whole
  /// answer and a change in the online set asks again.
  bool _liveTvIncomplete = false;

  String _onlineServers = '';
  bool _retryIncompleteMisses = false;

  bool _running = false;
  bool _pending = false;

  bool get _hasWatchlist => _watchlist?.hasWatchlist ?? false;

  /// Plex only, like [_loadLiveTv]: a Jellyfin Live TV server is in the list
  /// too, and offering the row there would be a switch that never fills.
  bool get _hasLiveTv =>
      _loadLiveTvOverride != null ||
      _multiServer.liveTvServers.any((s) => _multiServer.getPlexClientForServer(ServerId(s.serverId)) != null);

  /// Every row this profile can have, empty and hidden ones included, for the
  /// surfaces that let the viewer turn one back on.
  List<UnifiedMediaHub> allRows() => [
    if (_hasWatchlist)
      UnifiedMediaHub.synthesized(
        slug: 'watchlist',
        title: _watchlistTitle,
        kind: UnifiedHubKind.mixed,
        groups: _watchlistGroups,
        contributingRowIds: const [homeWatchlistRowId],
      ),
    if (_hasLiveTv)
      UnifiedMediaHub.synthesized(
        slug: 'livetv',
        title: _liveTvTitle,
        kind: UnifiedHubKind.other,
        groups: _liveTvGroups,
        contributingRowIds: const [homeLiveTvRowId],
      ),
  ];

  /// What Home draws: [allRows] minus the empty ones.
  List<UnifiedMediaHub> visibleRows() => [
    for (final row in allRows())
      if (row.groups.isNotEmpty) row,
  ];

  /// Whether [group] is a card of the Nu op tv row.
  bool isLiveTv(UnifiedMediaGroup group) => _liveEntryFor(group) != null;

  LiveTvHubEntry? _liveEntryFor(UnifiedMediaGroup group) {
    for (final source in group.sources) {
      final entry = _liveEntries[source.item.globalKey];
      if (entry != null) return entry;
    }
    return null;
  }

  /// Tunes the channel behind a Nu op tv card. Returns false for any other
  /// card, so a caller can try this first and fall through to its own path.
  Future<bool> activateLiveTv(BuildContext context, UnifiedMediaGroup group) async {
    final entry = _liveEntryFor(group);
    if (entry == null) return false;
    final channel = _liveChannels.where((c) => liveTvProgramMatchesChannel(entry.program, c)).firstOrNull;
    if (channel == null) return false;
    final tune = _tuneChannel;
    if (tune != null) {
      await tune(context, channel, _liveChannels);
    } else {
      await navigateToLiveTv(context, multiServer: _multiServer, channel: channel, channels: _liveChannels);
    }
    return true;
  }

  /// A full Home load reloads Nu op tv with it: what is on now is stale by the
  /// next programme, and Home's own refresh is when the viewer asks for fresh.
  void _onDiscoverChanged() {
    final generation = _discover?.loadGeneration ?? 0;
    if (generation == _seenLoadGeneration) return;
    _seenLoadGeneration = generation;
    _liveTvReloadRequested = true;
    _refresh();
  }

  /// A server coming or going is the one moment an earlier miss can have
  /// become a hit: failed lookups, misses that could not reach every server,
  /// and a Live TV load that lost a server are all asked again. Only on a real
  /// change of the online set; the provider notifies for much more than that.
  void _onServersChanged() {
    final online = _onlineServerKey();
    if (online != _onlineServers) {
      _onlineServers = online;
      _resolveFailed.clear();
      _retryIncompleteMisses = true;
      if (_liveTvIncomplete) _liveTvReloadRequested = true;
    }
    _refresh();
  }

  String _onlineServerKey() => (_multiServer.serverManager.onlineClients.keys.toList()..sort()).join(',');

  /// Never synchronous. This provider is lazy, so its constructor runs inside
  /// the build of the first widget that watches it, and loading the kijklijst
  /// from there would notify the kijklijst's listeners in the middle of that
  /// build. A microtask runs once the build has returned.
  void _refresh() {
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    scheduleMicrotask(() => unawaited(_run()));
  }

  Future<void> _run() async {
    try {
      if (isDisposed) return;
      do {
        _pending = false;
        // Each row publishes as soon as it has an answer; Nu op tv does not
        // wait for the kijklijst's lookups to be drawn.
        if (await _syncWatchlist() && !isDisposed) safeNotifyListeners();
        if (isDisposed) return;
        if (await _syncLiveTv() && !isDisposed) safeNotifyListeners();
        if (isDisposed) return;
      } while (_pending);
    } finally {
      _running = false;
    }
  }

  Future<bool> _syncWatchlist() async {
    final watchlist = _watchlist;
    if (watchlist == null || !_hasWatchlist || _layout.isRowHidden(homeWatchlistRowId)) {
      return _setWatchlist(const [], const []);
    }
    try {
      await watchlist.ensureLoaded();
      // Availability is resolved lazily by the list itself; the row needs it
      // for its first cards only, so this is bounded by the card limit.
      final retry = _retryIncompleteMisses;
      _retryIncompleteMisses = false;
      for (final entry in watchlist.entriesByRecentlyAdded.take(kHomeExtraRowCardLimit)) {
        if (retry) await watchlist.retryIncompleteAvailability(entry);
        if (entry.availability != WatchlistAvailability.unknown || _resolveFailed.contains(entry.key)) continue;
        await watchlist.resolveAvailability(entry);
        if (watchlist.entryForKey(entry.key)?.availability == WatchlistAvailability.unknown) {
          _resolveFailed.add(entry.key);
        }
      }
      if (isDisposed) return false;
      // A match in a library the viewer hid stays off Home, like everywhere
      // else the hidden libraries apply.
      final items = filterHiddenLibraryItems([
        for (final entry in watchlist.entriesByRecentlyAdded.take(kHomeExtraRowCardLimit)) ?entry.lastKnownMatch,
      ], _hiddenLibraries?.hiddenLibraryKeys);
      final keys = [for (final item in items) item.globalKey];
      if (_sameKeys(keys, _watchlistKeys)) return false;
      final projected = await _watchlistProjection.projectHubs([
        MediaHub(id: 'pleya:home:watchlist', title: _watchlistTitle, type: 'mixed', items: items),
      ]);
      return _setWatchlist(projected.isEmpty ? const [] : projected.first.groups, keys);
    } catch (e, st) {
      appLogger.w('HomeExtraRowsProvider: Kijklijst row failed (keeping previous)', error: e, stackTrace: st);
      return false;
    }
  }

  bool _setWatchlist(List<UnifiedMediaGroup> groups, List<String> keys) {
    if (_sameKeys(keys, _watchlistKeys) && groups.length == _watchlistGroups.length) return false;
    _watchlistGroups = groups;
    _watchlistKeys = keys;
    return true;
  }

  static bool _sameKeys(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<bool> _syncLiveTv() async {
    if (!_hasLiveTv || _layout.isRowHidden(homeLiveTvRowId)) {
      _liveTvLoadedFor = null;
      if (_liveTvGroups.isEmpty) return false;
      _liveTvGroups = const [];
      _liveEntries = const {};
      _liveChannels = const [];
      return true;
    }
    final loadedFor = [for (final s in _multiServer.liveTvServers) s.serverId].join(',');
    if (loadedFor == _liveTvLoadedFor && !_liveTvReloadRequested) return false;
    _liveTvReloadRequested = false;
    try {
      final content = await (_loadLiveTvOverride ?? _loadLiveTv)();
      if (isDisposed) return false;
      final airing = [
        for (final entry in content.entries)
          if (entry.program.isCurrentlyAiring &&
              content.channels.any((c) => liveTvProgramMatchesChannel(entry.program, c)))
            entry,
      ].take(kHomeExtraRowCardLimit).toList();
      final projected = await _liveTvProjection.projectHubs([
        MediaHub(
          id: 'pleya:home:livetv',
          title: _liveTvTitle,
          type: 'mixed',
          items: [for (final entry in airing) entry.metadata],
        ),
      ]);
      _liveEntries = {for (final entry in airing) entry.metadata.globalKey: entry};
      _liveChannels = content.channels;
      _liveTvGroups = projected.isEmpty ? const [] : projected.first.groups;
      _liveTvLoadedFor = loadedFor;
      return true;
    } catch (e, st) {
      appLogger.w('HomeExtraRowsProvider: Nu op tv row failed (keeping previous)', error: e, stackTrace: st);
      return false;
    }
  }

  /// Plex only: the Live TV hubs endpoint this row reads has no counterpart on
  /// the other backends. One failing server leaves the others' entries intact.
  Future<HomeLiveTvContent> _loadLiveTv() async {
    final entries = <LiveTvHubEntry>[];
    final channels = <LiveTvChannel>[];
    final asked = <String>{};
    _liveTvIncomplete = false;
    for (final info in _multiServer.liveTvServers) {
      if (!asked.add(info.serverId)) continue;
      final client = _multiServer.getPlexClientForServer(ServerId(info.serverId));
      if (client == null) continue;
      try {
        final hubs = await client.getLiveTvHubs();
        channels.addAll(await client.liveTv.fetchChannels(lineup: info.lineup));
        entries.addAll([for (final hub in hubs) ...hub.entries]);
      } catch (e) {
        _liveTvIncomplete = true;
        appLogger.d('HomeExtraRowsProvider: Live TV on ${info.serverId} unavailable', error: e);
      }
    }
    return (entries: entries, channels: channels);
  }

  @override
  void dispose() {
    _layout.removeListener(_refresh);
    _watchlist?.removeListener(_refresh);
    _hiddenLibraries?.removeListener(_refresh);
    _multiServer.removeListener(_onServersChanged);
    _discover?.removeListener(_onDiscoverChanged);
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/ids.dart';
import '../media/media_server_client.dart';
import '../services/api_cache.dart';
import '../services/watchlist/plex_account_watchlist_source.dart';
import '../services/watchlist/watchlist_source_factory.dart';
import '../media/watchlist_entry.dart';
import '../media/watchlist_scope.dart';
import '../media/watchlist_source.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/watchlist/watchlist_availability_resolver.dart';
import '../services/watchlist/watchlist_repository.dart';
import '../services/watchlist/watchlist_snapshot_store.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';

/// Whether a title can be requested through Seerr, and how loudly to offer it.
enum WatchlistRequestability {
  /// No Seerr, or the title is already available.
  unsupported,

  /// Not found while some servers could not be reached. Requesting is still
  /// possible but must not be the primary action, or one offline server turns
  /// into a stack of duplicate requests for titles the user already owns.
  resolvable,

  /// Not found and every server answered. Requesting is the normal next step.
  ready,
}

/// Reads the merged kijklijst and answers the questions the UI actually asks:
/// can I play this, and can I request it.
///
/// Both live here rather than on the model because both depend on state the
/// model cannot see. Playability needs to know which servers are online right
/// now and what has been downloaded; requestability needs to know whether
/// Seerr is configured and how complete the last lookup was.
class WatchlistProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  WatchlistProvider({
    required this.snapshots,
    this.repository,
    this.resolver,
    this.isServerOnline = _noServersOnline,
    this.hasDownload = _noDownloads,
    this.seerrConfigured = false,
  });

  /// Rebuilt on every profile switch, so a stale repository cannot serve the
  /// previous user's list.
  WatchlistRepository? repository;
  WatchlistAvailabilityResolver? resolver;
  final WatchlistSnapshotStore snapshots;

  /// Whether a server of the active profile is reachable right now.
  bool Function(ServerId serverId) isServerOnline;

  /// Whether a completed local download exists for a `serverId:itemId` key.
  bool Function(String globalKey) hasDownload;

  bool seerrConfigured;

  static bool _noServersOnline(ServerId _) => false;
  static bool _noDownloads(String _) => false;

  List<WatchlistEntry> _entries = const [];
  bool _isLoading = false;
  bool _complete = true;
  bool _offline = false;
  String? _error;

  List<WatchlistEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _isLoading;

  /// Whether every source answered on the last fetch.
  bool get isComplete => _complete;

  /// Whether the list on screen came from the snapshot rather than the network.
  bool get isFromSnapshot => _offline;

  String? get error => _error;

  /// Whether there is a kijklijst to show at all.
  ///
  /// A profile with no source and no snapshot has nothing to put on screen and
  /// the section is hidden. This does **not** gate Mijn Pleya itself, which
  /// exists regardless.
  bool get hasWatchlist => _entries.isNotEmpty || (repository?.sources.isNotEmpty ?? false) || _hasSnapshot;

  bool _hasSnapshot = false;

  String? _attachedProfileId;
  WatchlistSourceFactory? _factory;

  /// Bind the provider to the active profile's connections.
  ///
  /// Rebuilding the sources is deliberately cheap to call: the wiring runs on
  /// every proxy-provider update, and only an actual profile change tears the
  /// old repository down. Everything downstream (cache keys, snapshot rows,
  /// scope checks) hangs off the profile, so serving one user's list from a
  /// repository built for another would be the exact failure this design is
  /// shaped to prevent.
  void attach({
    required String? profileId,
    required PlexAccountAuthResolver resolvePlexAuth,
    required Future<String> Function() clientIdentifier,
    required Map<String, MediaServerClient> Function() clientsById,
    required List<EligibleServer> Function() serversFor,
    required ApiCache cache,
  }) {
    if (profileId == null) {
      _factory?.dispose();
      _factory = null;
      repository = null;
      resolver = null;
      _attachedProfileId = null;
      return;
    }

    if (_attachedProfileId != profileId) {
      _factory?.dispose();
      _factory = null;
      reset();
    }
    _attachedProfileId = profileId;

    resolver ??= WatchlistAvailabilityResolver(profileId: profileId, serversFor: serversFor, cache: cache);
    if (_factory != null) return;

    unawaited(() async {
      final factory = WatchlistSourceFactory(
        profileId: profileId,
        resolvePlexAuth: resolvePlexAuth,
        clientIdentifier: await clientIdentifier(),
        clientsById: clientsById,
      );
      if (_attachedProfileId != profileId) {
        factory.dispose();
        return;
      }
      _factory = factory;
      repository = WatchlistRepository(sources: await factory.build());
      safeNotifyListeners();
    }());
  }

  WatchlistEntry? entryForKey(String key) {
    for (final entry in _entries) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  /// Load the list: snapshot first so something is on screen, then the network.
  Future<void> load({bool offline = false}) async {
    _isLoading = true;
    _error = null;
    safeNotifyListeners();

    final scopes = repository?.sources.map((s) => s.scope).toList() ?? const <WatchlistScopeId>[];
    final restored = await _readSnapshots(scopes);
    if (restored != null) {
      _entries = restored;
      _hasSnapshot = true;
      _offline = true;
      safeNotifyListeners();
    }

    if (offline || repository == null) {
      _isLoading = false;
      _offline = true;
      safeNotifyListeners();
      return;
    }

    try {
      final result = await repository!.fetch();
      _entries = result.entries;
      _complete = result.complete;
      _offline = false;
      await _writeSnapshots(result);
      _hasSnapshot = true;
    } catch (e, st) {
      appLogger.w('Watchlist load failed', error: e, stackTrace: st);
      _error = e.toString();
    } finally {
      _isLoading = false;
      safeNotifyListeners();
    }
  }

  /// Resolve availability for [entry] and fold the answer back into the list.
  ///
  /// Lazy and viewport-driven by design: a 300-title list must not fan out
  /// 300 lookups on open. The card asks for its own row when it scrolls into
  /// view.
  Future<void> resolveAvailability(WatchlistEntry entry) async {
    final resolver = this.resolver;
    if (resolver == null || entry.availability != WatchlistAvailability.unknown) return;

    _replace(entry.copyWith(availability: WatchlistAvailability.checking));
    try {
      final result = await resolver.resolve(entry);
      _replace(
        entry.copyWith(
          availability: result.match != null ? WatchlistAvailability.available : WatchlistAvailability.notFound,
          coverageComplete: result.coverageComplete,
          lastKnownMatch: result.match,
        ),
      );
    } catch (e) {
      appLogger.d('Watchlist availability resolve failed for ${entry.key}', error: e);
      _replace(entry.copyWith(availability: WatchlistAvailability.unknown));
    }
  }

  /// Resolve everything still unknown, bounded by the resolver's own
  /// concurrency cap.
  ///
  /// Only used when the user turns on the "Available" filter. Lazy resolving
  /// and filtering on availability contradict each other: entries outside the
  /// viewport are still unknown, so the filter would hide titles that are in
  /// fact there. Asking for the filter is asking for the full sweep.
  Future<void> resolveAllUnknown() async {
    final pending = _entries.where((e) => e.availability == WatchlistAvailability.unknown).toList();
    for (final entry in pending) {
      await resolveAvailability(entry);
    }
  }

  /// Whether the user can press play on [entry] right now.
  ///
  /// Two independent routes. Either the last known match is on a server this
  /// profile can reach and that server is up, or there is a finished local
  /// download, in which case the origin server being unreachable is beside the
  /// point. Without the second route the offline screen would offer a list of
  /// titles it cannot open.
  bool isPlayable(WatchlistEntry entry) {
    final match = entry.lastKnownMatch;
    if (match == null) return false;

    final serverId = match.serverId;
    if (serverId != null && hasDownload(buildGlobalKey(ServerId(serverId), match.id))) return true;

    return serverId != null && isServerOnline(ServerId(serverId));
  }

  /// How prominently to offer a Seerr request for [entry].
  WatchlistRequestability requestability(WatchlistEntry entry) {
    if (!seerrConfigured) return WatchlistRequestability.unsupported;
    if (entry.availability != WatchlistAvailability.notFound) return WatchlistRequestability.unsupported;
    return entry.coverageComplete ? WatchlistRequestability.ready : WatchlistRequestability.resolvable;
  }

  /// Drop everything and rebind. Called on a profile switch.
  void reset() {
    _entries = const [];
    _complete = true;
    _offline = false;
    _hasSnapshot = false;
    _error = null;
    safeNotifyListeners();
  }

  void _replace(WatchlistEntry updated) {
    final index = _entries.indexWhere((e) => e.key == updated.key);
    if (index < 0) return;
    final next = List<WatchlistEntry>.of(_entries);
    next[index] = updated;
    _entries = next;
    safeNotifyListeners();
  }

  Future<List<WatchlistEntry>?> _readSnapshots(List<WatchlistScopeId> scopes) async {
    if (scopes.isEmpty) return null;
    final restored = <WatchlistEntry>[];
    var found = false;
    for (final scope in scopes) {
      final rows = await snapshots.read(scope);
      if (rows == null) continue;
      found = true;
      restored.addAll(rows);
    }
    return found ? WatchlistRepository.mergeEntries(restored) : null;
  }

  /// Write one snapshot per source, but only for sources that answered.
  ///
  /// Overwriting a failed source's snapshot with nothing would delete the last
  /// good offline copy on the strength of a timeout.
  Future<void> _writeSnapshots(WatchlistFetchResult result) async {
    final failed = result.failed.map((s) => s.scope).toSet();
    final bySource = <WatchlistScopeId, List<WatchlistEntry>>{};
    for (final source in repository?.sources ?? const <WatchlistSource>[]) {
      if (failed.contains(source.scope)) continue;
      bySource[source.scope] = <WatchlistEntry>[];
    }
    for (final entry in result.entries) {
      for (final membership in entry.memberships) {
        bySource[membership.scope]?.add(entry);
      }
    }
    for (final scope in bySource.keys) {
      await snapshots.write(scope, bySource[scope]!);
    }
  }
}

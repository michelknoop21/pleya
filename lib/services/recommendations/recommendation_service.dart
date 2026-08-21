import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;

import '../../database/app_database.dart';
import '../../media/ids.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../settings_service.dart';
import 'affinity_engine.dart';
import 'candidate_pool.dart';
import 'personalized_rows_builder.dart';
import 'tautulli_history_importer.dart';

/// Builds a [TautulliHistoryImporter] for one resolved target, or null when
/// nothing can import. Injected so tests never need a provider tree.
typedef TautulliImporterFactory = TautulliHistoryImporter? Function(String profileId, ServerId serverId);

/// How long a sync waits for the integration store to finish loading before it
/// proceeds on whatever is known. Generous, because the wait costs nothing (the
/// rows are already on screen) and the alternative is not importing at all;
/// bounded, because a store that never answers must not strand the future.
const Duration kImportSourcesReadyTimeout = Duration(seconds: 20);

/// Extra passes one call may pull in behind it when requests keep arriving
/// mid-flight. A backstop against a caller in a loop, not a normal path: two is
/// already more than the feed ever needs.
const int kMaxChainedSyncPasses = 3;

/// Profile-scoped facade the discover feed uses to obtain personalized rows.
/// Owns the affinity engine + candidate pool and gates on the user's
/// `personalizedRecommendations` setting. Runs entirely off the counted
/// aggregation paths, so it never affects the discover fetch-cost contract.
class RecommendationService {
  final String profileId;
  final AffinityEngine _affinity;
  final CandidatePool _candidates;
  final PersonalizedRowTitles _titles;

  /// Servers whose imported history may count right now. Read fresh on every
  /// use rather than captured, because the admin can flip the policy or
  /// disconnect while the app is running and both must take effect at once.
  final Set<String> Function() _enabledImportServerIds;

  /// Resolves once [_enabledImportServerIds] answers from storage rather than
  /// from its empty default.
  ///
  /// Without this the whole feature loses a cold start. Discover builds its
  /// rows as soon as the first server is online, which is routinely before the
  /// integration store has been read, and an empty set at that moment is
  /// indistinguishable from "nothing is paired". The sync would then do
  /// nothing and there is no second trigger, so a saved integration only
  /// imported after a profile switch or a manual reload.
  final Future<void> Function()? _importSourcesReady;

  final TautulliImporterFactory? _importerFactory;

  /// The enabled set the last [buildRows] actually scored with, so a sync can
  /// tell whether the rows on screen were built before the answer was known.
  Set<String>? _scoredWith;

  /// One sync at a time per service. Two readiness notifications, or a reload
  /// arriving while the first sync is still waiting on hydration, must not
  /// start a second pass over the same pages.
  Future<bool>? _inFlightSync;

  /// A request arrived while a pass was running, so one more pass may be owed.
  bool _rerunRequested = false;

  /// The enabled set the last completed pass actually visited. A mid-flight
  /// request is only worth a second pass when this has moved since.
  Set<String>? _lastSyncedWith;

  RecommendationService({
    required this.profileId,
    required AppDatabase database,
    required this._titles,
    CandidatePool? candidatePool,
    Set<String> Function()? enabledImportServerIds,
    this._importSourcesReady,
    this._importerFactory,
  }) : _affinity = AffinityEngine(database),
       _candidates = candidatePool ?? CandidatePool(),
       _enabledImportServerIds = enabledImportServerIds ?? _noImports;

  static Set<String> _noImports() => const {};

  bool get _enabled => SettingsService.instanceOrNull?.read(SettingsService.personalizedRecommendations) ?? true;

  /// Builds personalized rows for the current taste, or an empty list when the
  /// feature is off, there's no history, or the pool is too thin. Fully
  /// fault-tolerant — any failure yields no rows rather than breaking the feed.
  Future<List<MediaHub>> buildRows(
    List<MediaServerClient> clients, {
    List<MediaItem> hubItems = const [],
    Set<String> excludeKeys = const {},
    int? nowMs,
  }) async {
    if (!_enabled || clients.isEmpty) return const [];
    try {
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final enabled = _enabledImportServerIds();
      // Copied: the closure may hand back a set it keeps mutating, and this is
      // the record of what the visible rows were actually built from.
      _scoredWith = Set.of(enabled);
      final taste = await _affinity.vectorFor(profileId, enabledImportServerIds: enabled, nowMs: now);
      final pool = await _candidates.candidates(clients, extra: hubItems);
      if (pool.isEmpty) return const [];
      return buildPersonalizedRows(taste, pool, titles: _titles, nowMs: now, excludeKeys: excludeKeys);
    } catch (e, s) {
      appLogger.w('RecommendationService: buildRows failed (leaving rows out)', error: e, stackTrace: s);
      return const [];
    }
  }

  /// Pulls in any new external history for this profile.
  ///
  /// Returns whether the personalized rows should be rebuilt, which is two
  /// things and not one. New rows are the obvious case. The other is that the
  /// rows currently on screen were scored before hydration answered, so they
  /// were built as if nothing were paired: a warm start with everything already
  /// imported changes no row in the database and would otherwise keep showing a
  /// taste profile with the imported history left out until the next reload.
  ///
  /// Without a configured, enabled and correctly bound integration this issues
  /// no network calls at all: the factory refuses before a client exists.
  Future<bool> syncImportedHistory() {
    final running = _inFlightSync;
    if (running != null) {
      // Not the same request. The running pass read the enabled set when it
      // started, and the reason a second call arrives is usually that the set
      // has since moved — a server hydrated, a policy flipped. Dropping it
      // would lose that server until an unrelated reload; starting a second
      // concurrent pass would double the work. So it is owed one more pass.
      _rerunRequested = true;
      return running;
    }
    return _inFlightSync = _syncChain().whenComplete(() => _inFlightSync = null);
  }

  Future<bool> _syncChain() async {
    var changed = await _syncImportedHistory();
    var extra = 0;
    while (_rerunRequested) {
      _rerunRequested = false;
      // Only when the answer has actually moved. Two notifications for the
      // same state are one piece of news, and re-running on them would spend a
      // second pass over the same pages every time something notified twice.
      final last = _lastSyncedWith;
      if (last != null && setEquals(last, _enabledImportServerIds())) break;
      if (extra++ >= kMaxChainedSyncPasses) {
        appLogger.w('RecommendationService: stopped chaining history syncs after $kMaxChainedSyncPasses extra passes');
        break;
      }
      changed = await _syncImportedHistory() || changed;
    }
    return changed;
  }

  Future<bool> _syncImportedHistory() async {
    if (!_enabled) return false;
    final factory = _importerFactory;
    if (factory == null) return false;

    await _awaitImportSources();

    final enabled = _enabledImportServerIds();
    _lastSyncedWith = Set.of(enabled);
    // Compared against what the visible rows were scored with, not against the
    // empty default, so this is false on every warm pass.
    final scored = _scoredWith;
    var changed = scored != null && !setEquals(scored, enabled);

    for (final serverId in enabled) {
      try {
        final importer = factory(profileId, ServerId(serverId));
        if (importer == null) continue;
        final outcome = await importer.sync();
        changed = changed || (outcome?.changedAnything ?? false);
      } catch (e, s) {
        // A failing import must never take Discover down, drop existing rows or
        // surface anything to the user.
        appLogger.w('RecommendationService: history sync failed', error: e, stackTrace: s);
      }
    }
    return changed;
  }

  /// Waits for the integration store, bounded, and never fails because of it.
  Future<void> _awaitImportSources() async {
    final ready = _importSourcesReady;
    if (ready == null) return;
    try {
      await ready().timeout(kImportSourcesReadyTimeout);
    } on TimeoutException {
      appLogger.w('RecommendationService: integrations still loading, syncing with what is known');
    } catch (e, s) {
      appLogger.w('RecommendationService: waiting for integrations failed', error: e, stackTrace: s);
    }
  }

  void invalidateCandidates() => _candidates.invalidate();
}

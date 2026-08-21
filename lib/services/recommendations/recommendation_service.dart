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

  final TautulliImporterFactory? _importerFactory;

  RecommendationService({
    required this.profileId,
    required AppDatabase database,
    required this._titles,
    CandidatePool? candidatePool,
    Set<String> Function()? enabledImportServerIds,
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
      final taste = await _affinity.vectorFor(profileId, enabledImportServerIds: _enabledImportServerIds(), nowMs: now);
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
  /// Returns whether anything was actually imported, so the caller can rebuild
  /// the personalized rows once instead of on every load. Without a configured,
  /// enabled and correctly bound integration this issues no network calls at
  /// all: the factory refuses before a client exists.
  Future<bool> syncImportedHistory() async {
    if (!_enabled) return false;
    final factory = _importerFactory;
    if (factory == null) return false;

    var changed = false;
    for (final serverId in _enabledImportServerIds()) {
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

  void invalidateCandidates() => _candidates.invalidate();
}

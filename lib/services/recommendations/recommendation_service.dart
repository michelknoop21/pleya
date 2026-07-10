import '../../database/app_database.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../settings_service.dart';
import 'affinity_engine.dart';
import 'candidate_pool.dart';
import 'personalized_rows_builder.dart';

/// Profile-scoped facade the discover feed uses to obtain personalized rows.
/// Owns the affinity engine + candidate pool and gates on the user's
/// `personalizedRecommendations` setting. Runs entirely off the counted
/// aggregation paths, so it never affects the discover fetch-cost contract.
class RecommendationService {
  final String profileId;
  final AffinityEngine _affinity;
  final CandidatePool _candidates;
  final PersonalizedRowTitles _titles;

  RecommendationService({
    required this.profileId,
    required AppDatabase database,
    required PersonalizedRowTitles titles,
    CandidatePool? candidatePool,
  }) : _affinity = AffinityEngine(database),
       _candidates = candidatePool ?? CandidatePool(),
       _titles = titles;

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
      final taste = await _affinity.vectorFor(profileId, nowMs: now);
      final pool = await _candidates.candidates(clients, extra: hubItems);
      if (pool.isEmpty) return const [];
      return buildPersonalizedRows(taste, pool, titles: _titles, nowMs: now, excludeKeys: excludeKeys);
    } catch (e, s) {
      appLogger.w('RecommendationService: buildRows failed (leaving rows out)', error: e, stackTrace: s);
      return const [];
    }
  }

  void invalidateCandidates() => _candidates.invalidate();
}

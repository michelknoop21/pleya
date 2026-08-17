import '../media/media_item.dart';
import '../media/media_watch_stats.dart';
import '../utils/app_logger.dart';
import 'tautulli/tautulli_client.dart';

/// Resolves play counts and watch time for one title from Tautulli.
///
/// Separate from [ItemWatchersService] because it answers a different question
/// from different endpoints, and because it has no Plex fallback: the Plex
/// Media Server records who finished something, not how long anyone spent on
/// it. Without Tautulli there is simply no section.
///
/// Admin-only by construction, like everything Tautulli-backed. The caller
/// gates on server ownership before getting here.
class MediaWatchStatsService {
  const MediaWatchStatsService();

  /// Stats for [metadata], or [MediaWatchStats.empty] when Tautulli is absent,
  /// unreachable, or has nothing recorded.
  ///
  /// Two calls: one for the play/time windows, one for the distinct users. The
  /// second is the same endpoint the watchers row uses, so on a series it is
  /// already warm in Tautulli's own query cache.
  Future<MediaWatchStats> resolve(MediaItem metadata, {TautulliClient? tautulli}) async {
    if (tautulli == null) return MediaWatchStats.empty;
    try {
      final windows = await tautulli.itemWatchTimeStats(metadata.id);
      if (windows.isEmpty) return MediaWatchStats.empty;

      final allTime = windows.where((w) => w.isAllTime).firstOrNull;
      if (allTime == null || allTime.totalPlays == 0) return MediaWatchStats.empty;

      final last30 = windows.where((w) => w.queryDays == 30).firstOrNull;

      // Only worth a second round-trip once we know the title was played.
      int? userCount;
      try {
        userCount = (await tautulli.itemUserStats(metadata.id)).length;
      } catch (e) {
        appLogger.d('Tautulli user count unavailable for ${metadata.id}', error: e);
      }

      return MediaWatchStats(
        totalPlays: allTime.totalPlays,
        totalTime: Duration(seconds: allTime.totalTime),
        userCount: userCount,
        playsLast30Days: last30?.totalPlays,
      );
    } catch (e) {
      // Secondary detail-page content: a monitoring service being down is not a
      // reason to put an error next to a film.
      appLogger.d('Tautulli watch stats unavailable for ${metadata.id}', error: e);
      return MediaWatchStats.empty;
    }
  }
}

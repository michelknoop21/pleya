import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';

/// Supplies a bounded pool of catalogue items for personalized-row scoring,
/// cached in memory per server so warm home loads issue zero extra fetches.
/// One `fetchRecentlyAdded` per server per [_ttl] window; the profile-scoped
/// owner keeps this instance alive across discover reloads within a session.
class CandidatePool {
  static const Duration _ttl = Duration(hours: 12);
  static const int _perServerLimit = 100;

  final int Function() _nowMs;

  CandidatePool({int Function()? clock}) : _nowMs = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Map<String, _Entry> _byServer = {};

  /// Fetches (or returns cached) candidate items across [clients], plus any
  /// [extra] items already loaded elsewhere (e.g. the discover hubs) for free.
  Future<List<MediaItem>> candidates(
    List<MediaServerClient> clients, {
    List<MediaItem> extra = const [],
  }) async {
    final now = _nowMs();
    final results = await Future.wait([
      for (final client in clients) _forClient(client, now),
    ]);

    // Merge server pools + free extras, de-duplicated by global key.
    final seen = <String>{};
    final merged = <MediaItem>[];
    for (final item in [...results.expand((r) => r), ...extra]) {
      if (seen.add(item.globalKey)) merged.add(item);
    }
    return merged;
  }

  Future<List<MediaItem>> _forClient(MediaServerClient client, int now) async {
    final key = client.serverId.toString();
    final cached = _byServer[key];
    if (cached != null && now - cached.fetchedAtMs < _ttl.inMilliseconds) {
      return cached.items;
    }
    try {
      final items = await client.fetchRecentlyAdded(limit: _perServerLimit);
      _byServer[key] = _Entry(items: items, fetchedAtMs: now);
      return items;
    } catch (e, s) {
      appLogger.w('CandidatePool: fetchRecentlyAdded failed for $key', error: e, stackTrace: s);
      return cached?.items ?? const <MediaItem>[];
    }
  }

  void invalidate([ServerId? serverId]) {
    if (serverId == null) {
      _byServer.clear();
    } else {
      _byServer.remove(serverId.toString());
    }
  }
}

class _Entry {
  final List<MediaItem> items;
  final int fetchedAtMs;
  const _Entry({required this.items, required this.fetchedAtMs});
}

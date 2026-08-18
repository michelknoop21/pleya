import '../media/media_server_client.dart';
import '../media/watch_session.dart';
import '../models/tautulli/tautulli_activity.dart';
import '../utils/app_logger.dart';
import 'tautulli/tautulli_client.dart';

/// Resolves "who is streaming right now" into the backend-neutral
/// [WatchSession] the UI renders.
///
/// Tautulli is the only source, and it is Plex-only monitoring: Jellyfin has no
/// equivalent, so on a Jellyfin profile this feature is simply absent rather
/// than emulated. Callers gate on server ownership before getting here, because
/// a Tautulli key opens the whole admin API.
///
/// The mapping lives in [map], separate from the fetching, so the shapes
/// measured on a live instance can be asserted without a transport.
class NowWatchingService {
  const NowWatchingService();

  /// Poll once. Returns null when the instance could not answer, which is not
  /// the same as an empty answer: nobody watching is news the UI acts on, while
  /// an unreachable Tautulli is something the caller rides out for a tick
  /// before clearing what it last showed.
  ///
  /// Never throws. This drives an ambient indicator, and a monitoring service
  /// being down is not a reason to interrupt anyone.
  Future<NowWatching?> resolve(
    TautulliClient tautulli, {

    /// plex.tv account id of the signed-in admin, whose own playback is not
    /// news and is filtered out.
    int? selfUserId,

    /// Used to turn Tautulli's Plex library paths into loadable URLs. Without
    /// it the rows fall back to a placeholder.
    MediaServerClient? artworkClient,
  }) async {
    try {
      final activity = await tautulli.activity();
      return map(activity, selfUserId: selfUserId, artworkClient: artworkClient);
    } catch (e) {
      appLogger.d('Tautulli activity unavailable', error: e);
      return null;
    }
  }

  /// Pure translation of one `get_activity` response.
  NowWatching map(TautulliActivity activity, {int? selfUserId, MediaServerClient? artworkClient}) {
    final sessions = <WatchSession>[];
    var own = 0;

    for (final s in activity.streams) {
      if (selfUserId != null && s.userId == selfUserId) {
        own++;
        continue;
      }
      sessions.add(_session(s, artworkClient));
    }

    sessions.sort(WatchSession.compare);
    return NowWatching(
      sessions: sessions,
      ownSessionCount: own,
      totalBandwidthKbps: activity.totalBandwidth,
      lanBandwidthKbps: activity.lanBandwidth,
      wanBandwidthKbps: activity.wanBandwidth,
    );
  }

  WatchSession _session(TautulliStream s, MediaServerClient? artwork) {
    final art = s.art ?? s.thumb;
    return WatchSession(
      id: s.sessionKey,
      userName: s.displayName,
      userThumb: s.userThumb,
      title: _title(s),
      subtitle: _subtitle(s),
      ratingKey: s.ratingKey,
      artUrl: art == null || artwork == null ? null : artwork.thumbnailUrl(art, width: 480),
      progressPercent: s.percentComplete.clamp(0, 100),
      remainingSeconds: s.remainingSeconds,
      isPaused: s.isPaused,
      delivery: switch (s.decision) {
        TautulliDecision.transcode => StreamDelivery.transcode,
        TautulliDecision.directStream => StreamDelivery.directStream,
        TautulliDecision.directPlay => StreamDelivery.directPlay,
      },
      transcodeSummary: s.decision == TautulliDecision.transcode ? transcodeSummary(s) : null,
      hardwareTranscode: s.decision == TautulliDecision.transcode && s.hardwareTranscode,
      bandwidthKbps: s.bandwidthKbps,
      isLan: s.location == null ? null : s.location == 'lan',
      playerLabel: playerLabel(s),
    );
  }

  /// A series is named by the show, so a row reads as "Reacher" rather than as
  /// an episode title nobody recognises out of context.
  String _title(TautulliStream s) {
    if (s.isEpisode && (s.grandparentTitle?.isNotEmpty ?? false)) return s.grandparentTitle!;
    return s.title ?? '';
  }

  String? _subtitle(TautulliStream s) {
    if (!s.isEpisode) return s.year?.toString();
    final season = s.seasonNumber;
    final episode = s.episodeNumber;
    final parts = [if (season != null && episode != null) 'S$season · E$episode', ?s.title];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// What the server is actually changing, shortest true version first.
  ///
  /// Measured on a live transcode: the resolution dropped 1080p to 720p while
  /// the video codec stayed h264 and only the audio changed, so a summary built
  /// on the video codec alone would have said nothing was happening. Returns
  /// null when Tautulli calls it a transcode but reports nothing that differs,
  /// in which case the badge stands on its own.
  static String? transcodeSummary(TautulliStream s) {
    final parts = <String>[];
    if (_differs(s.sourceResolution, s.streamResolution)) {
      parts.add('${s.sourceResolution!} → ${s.streamResolution!}');
    }
    if (_differs(s.sourceVideoCodec, s.streamVideoCodec)) {
      parts.add('${_codec(s.sourceVideoCodec)} → ${_codec(s.streamVideoCodec)}');
    } else if (parts.isEmpty && _differs(s.sourceAudioCodec, s.streamAudioCodec)) {
      // Audio-only re-encodes are common (EAC3 to Opus for a browser), but they
      // are the least interesting change, so they only speak when nothing
      // louder happened.
      parts.add('${_codec(s.sourceAudioCodec)} → ${_codec(s.streamAudioCodec)}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Device and app, without saying the same word twice: Tautulli reports
  /// `player: Pleya` and `product: Pleya` for this app, and `player: Apple TV`
  /// with `product: Plex for Apple TV` for Plex's own client.
  static String? playerLabel(TautulliStream s) {
    final player = s.player;
    final product = s.product;
    if (player == null) return product;
    if (product == null || product == player || product.contains(player)) return player;
    return '$player · $product';
  }

  static bool _differs(String? a, String? b) => a != null && b != null && a.toLowerCase() != b.toLowerCase();

  static String _codec(String? raw) => (raw ?? '').toUpperCase();
}

/// Playback-plan wire types for Pleya Protocol v1 (window 5, S17):
/// `PlaybackPlan` and its reasons. Split from `pleya_wire.dart` like the
/// library types, so neither file outgrows one reading.
library;

import 'pleya_wire_parse.dart';

/// `PlaybackDeliveryMode`. Unknown-safe: a mode this build does not know parses
/// to null and the caller keeps today's direct-play behaviour.
enum PleyaDeliveryMode {
  directPlay('direct_play'),
  remux('remux'),
  directStream('direct_stream'),
  transcode('transcode');

  const PleyaDeliveryMode(this.wire);

  final String wire;

  static PleyaDeliveryMode? tryParse(String? raw) {
    for (final mode in values) {
      if (mode.wire == raw) return mode;
    }
    return null;
  }
}

/// `PlaybackReason`: a domain code with parameters, never a translation key.
/// The app maps [code] to its own text and shows a generic message for a code
/// it does not know, logging the code instead of showing nothing.
class PleyaPlaybackReason {
  const PleyaPlaybackReason({required this.code, required this.params});

  final String code;
  final Map<String, dynamic> params;

  factory PleyaPlaybackReason.fromJson(Map<String, dynamic> json) {
    final params = json['params'];
    return PleyaPlaybackReason(code: str(json, 'code'), params: params is Map<String, dynamic> ? params : const {});
  }
}

/// `PlaybackPlan`.
class PleyaPlaybackPlan {
  const PleyaPlaybackPlan({
    required this.itemId,
    required this.versionId,
    required this.deliveryMode,
    required this.streamUrl,
    required this.seekable,
    required this.reason,
    required this.reasons,
    this.sessionId,
  });

  final String itemId;
  final String versionId;

  /// Null when the server named a mode this build does not know.
  final PleyaDeliveryMode? deliveryMode;

  /// A path on the server. The bytes still ask for authorisation as always.
  final String streamUrl;

  /// Whether the player may seek by range request. Branch on this, not on the
  /// backend type.
  final bool seekable;

  /// Null for direct play.
  final String? sessionId;

  final PleyaPlaybackReason reason;
  final List<PleyaPlaybackReason> reasons;

  factory PleyaPlaybackPlan.fromJson(Map<String, dynamic> json) {
    final reasons = [for (final r in objectList(json['reasons'], 'reasons')) PleyaPlaybackReason.fromJson(r)];
    final reason = PleyaPlaybackReason.fromJson(obj(json['reason'], 'reason'));
    return PleyaPlaybackPlan(
      itemId: str(json, 'item_id'),
      versionId: str(json, 'version_id'),
      deliveryMode: PleyaDeliveryMode.tryParse(strOrNull(json, 'delivery_mode')),
      streamUrl: str(json, 'stream_url'),
      seekable: boolean(json, 'seekable'),
      sessionId: strOrNull(json, 'session_id'),
      reason: reason,
      reasons: reasons.isEmpty ? [reason] : reasons,
    );
  }
}

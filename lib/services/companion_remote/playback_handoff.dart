/// Playback Handoff (A-23): a phone passes what it is playing to a Pleya on
/// Apple TV over the existing Companion Remote connection.
///
/// The request names the item the way every other cross-device link does
/// (server id plus item id, as the Top Shelf links do) and carries the position
/// the phone was at. The receiver plays it as an explicit start position, which
/// [PlaybackResumeResolver] ranks above any local or backend progress, so an
/// old offset on the Apple TV can never win.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../media/media_item.dart';

@immutable
class PlaybackHandoffRequest {
  const PlaybackHandoffRequest({
    required this.id,
    required this.serverId,
    required this.itemId,
    required this.positionMs,
    required this.title,
    required this.from,
  });

  /// Correlates the request with the acknowledgement.
  final String id;
  final String serverId;
  final String itemId;
  final int positionMs;
  final String title;

  /// Name of the sending device, shown on the Apple TV.
  final String from;

  Map<String, dynamic> toData() => {
    'id': id,
    'serverId': serverId,
    'itemId': itemId,
    'positionMs': positionMs,
    'title': title,
    'from': from,
  };

  /// Null for a malformed request: it came over the wire, so nothing is trusted.
  static PlaybackHandoffRequest? fromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final id = data['id'];
    final serverId = data['serverId'];
    final itemId = data['itemId'];
    final positionMs = data['positionMs'];
    if (id is! String || id.isEmpty) return null;
    if (serverId is! String || serverId.isEmpty) return null;
    if (itemId is! String || itemId.isEmpty) return null;
    if (positionMs is! int || positionMs < 0) return null;
    final title = data['title'];
    final from = data['from'];
    return PlaybackHandoffRequest(
      id: id,
      serverId: serverId,
      itemId: itemId,
      positionMs: positionMs,
      title: title is String ? title : '',
      from: from is String ? from : '',
    );
  }
}

/// The item as the handoff wants it played. Transcode start paths (Plex and
/// Jellyfin) take their offset from the item's view offset, not from the
/// player's start position, so both must say the same thing: otherwise the
/// stream starts at the old server position and reports the new one.
MediaItem itemAtHandoffPosition(MediaItem item, PlaybackHandoffRequest request) =>
    item.copyWith(viewOffsetMs: request.positionMs);

/// Whether a phone may hand playback to this device. The companion handshake
/// admits every member of the Plex Home, but a handoff plays under the active
/// profile of this device and writes its progress to that account, so only the
/// same user may start one.
bool handoffUserMatches({required String clientUserUuid, required String hostUserUuid}) =>
    clientUserUuid.isNotEmpty && clientUserUuid == hostUserUuid;

/// What the receiving Apple TV reports back through `syncState`.
enum PlaybackHandoffOutcome {
  /// The Apple TV is playing; the sender may stop.
  playing,

  /// The Apple TV could not start it; the sender keeps playing.
  failed,

  /// No answer in time; the sender keeps playing.
  timedOut,
}

const handoffPlayingKey = 'handoffPlaying';
const handoffFailedKey = 'handoffFailed';

/// Sent by the phone when it gave up (timeout, failure): a late start on the
/// Apple TV must not leave both devices playing.
const handoffCancelKey = 'handoffCancel';

/// Matches the host's answers to the requests a phone has outstanding.
class PlaybackHandoffTracker {
  final Map<String, Completer<PlaybackHandoffOutcome>> _pending = {};

  /// Resolves with the host's answer for [id], or [PlaybackHandoffOutcome.timedOut].
  /// Call [complete] with the same id from the command stream.
  Future<PlaybackHandoffOutcome> wait(String id, Duration timeout) async {
    final pending = Completer<PlaybackHandoffOutcome>();
    _pending[id] = pending;
    try {
      return await pending.future.timeout(timeout, onTimeout: () => PlaybackHandoffOutcome.timedOut);
    } finally {
      _pending.remove(id);
    }
  }

  /// A late or repeated answer, or one for an id nobody waits on, is ignored.
  void complete(String id, PlaybackHandoffOutcome outcome) {
    final pending = _pending[id];
    if (pending != null && !pending.isCompleted) pending.complete(outcome);
  }

  /// The connection dropped: nothing will answer any more.
  void failAll() {
    for (final id in _pending.keys.toList()) {
      complete(id, PlaybackHandoffOutcome.failed);
    }
  }

  /// Reads the acknowledgement a `syncState` command may carry.
  void handleSyncState(Map<String, dynamic>? data) {
    final playing = data?[handoffPlayingKey];
    final failed = data?[handoffFailedKey];
    if (playing is String) complete(playing, PlaybackHandoffOutcome.playing);
    if (failed is String) complete(failed, PlaybackHandoffOutcome.failed);
  }
}

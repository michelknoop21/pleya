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
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';

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
/// same user plays at once; another member gets their own profile first (A-23b).
bool handoffUserMatches({required String clientUserUuid, required String hostUserUuid}) =>
    clientUserUuid.isNotEmpty && clientUserUuid == hostUserUuid;

/// What the receiving Apple TV reports back through `syncState`.
enum PlaybackHandoffOutcome {
  /// The Apple TV is playing; the sender may stop.
  playing,

  /// The Apple TV could not start it; the sender keeps playing.
  failed,

  /// The Apple TV refused because another profile is active there and it could
  /// not switch to the sender's (none, or the PIN was cancelled); the sender
  /// keeps playing and can retry after picking the profile on the Apple TV.
  wrongProfile,

  /// No answer in time; the sender keeps playing.
  timedOut,
}

const handoffPlayingKey = 'handoffPlaying';
const handoffFailedKey = 'handoffFailed';

/// Why the Apple TV refused, next to [handoffFailedKey]; absent for any other failure.
const handoffReasonKey = 'handoffReason';
const handoffReasonWrongProfile = 'profile';

/// Sent by the phone when it gave up (timeout, failure): a late start on the
/// Apple TV must not leave both devices playing.
const handoffCancelKey = 'handoffCancel';

/// Sent by the Apple TV before it switches to the sender's profile (A-23b). The
/// switch drops the connection, so the phone waits for it and reconnects.
const handoffSwitchingKey = 'handoffSwitching';
const handoffProfileKey = 'handoffProfile';

/// Whether the Apple TV asks for the profile's PIN, next to [handoffSwitchingKey].
const handoffPinKey = 'handoffPin';

/// Sent by a phone that reconnected after a switch, to learn how its handoff
/// went; [handoffPendingKey] means the Apple TV is still on it.
const handoffQueryKey = 'handoffQuery';
const handoffPendingKey = 'handoffPending';

/// The `syncState` data that tells the phone how handoff [id] ended.
Map<String, dynamic> handoffOutcomeData(String id, PlaybackHandoffOutcome outcome) => switch (outcome) {
  PlaybackHandoffOutcome.playing => {handoffPlayingKey: id},
  PlaybackHandoffOutcome.wrongProfile => {handoffFailedKey: id, handoffReasonKey: handoffReasonWrongProfile},
  PlaybackHandoffOutcome.failed || PlaybackHandoffOutcome.timedOut => {handoffFailedKey: id},
};

/// The profile on this device that belongs to the member of the Home who sends a
/// handoff, or null when there is none or more than one (A-23b). A Plex Home
/// profile of that user on the same account wins; otherwise exactly one local
/// profile that holds the account for that user through a join row.
Profile? profileForHandoffSender(
  Iterable<Profile> profiles, {
  required String connectionId,
  required String userUuid,
  required Iterable<ProfileConnection> joinRows,
}) {
  if (connectionId.isEmpty || userUuid.isEmpty) return null;
  for (final profile in profiles) {
    if (profile.isPlexHome && profile.parentConnectionId == connectionId && profile.plexHomeUserUuid == userUuid) {
      return profile;
    }
  }
  final localIds = {
    for (final row in joinRows)
      if (row.connectionId == connectionId && row.userIdentifier == userUuid) row.profileId,
  };
  final locals = [
    for (final profile in profiles)
      if (profile.isLocal && localIds.contains(profile.id)) profile,
  ];
  return locals.length == 1 ? locals.single : null;
}

class _Waiting {
  _Waiting(this.onSwitching);

  final Completer<PlaybackHandoffOutcome> completer = Completer<PlaybackHandoffOutcome>();
  final void Function(String profile, bool pin)? onSwitching;
  Timer? timer;
  bool switching = false;
}

/// Matches the host's answers to the requests a phone has outstanding.
class PlaybackHandoffTracker {
  PlaybackHandoffTracker({this.switchBudget = const Duration(seconds: 90)});

  /// How long the phone waits once the Apple TV says it switches profile: a PIN
  /// typed there, a new session, and the phone reconnecting. Longer than
  /// [PlaybackHandoffLedger.ttl], so the Apple TV never starts after the phone gave up.
  final Duration switchBudget;

  final Map<String, _Waiting> _pending = {};

  /// Resolves with the host's answer for [id], or [PlaybackHandoffOutcome.timedOut].
  /// Call [complete] with the same id from the command stream. [onSwitching]
  /// hears the profile name when the Apple TV switches to it first.
  Future<PlaybackHandoffOutcome> wait(
    String id,
    Duration timeout, {
    void Function(String profile, bool pin)? onSwitching,
  }) async {
    final waiting = _pending[id] = _Waiting(onSwitching);
    waiting.timer = Timer(timeout, () => complete(id, PlaybackHandoffOutcome.timedOut));
    try {
      return await waiting.completer.future;
    } finally {
      waiting.timer?.cancel();
      if (identical(_pending[id], waiting)) _pending.remove(id);
    }
  }

  /// The handoffs that wait for a profile switch on the Apple TV; a phone that
  /// reconnects asks after these.
  List<String> get switchingIds => [
    for (final entry in _pending.entries)
      if (entry.value.switching) entry.key,
  ];

  /// A late or repeated answer, or one for an id nobody waits on, is ignored.
  void complete(String id, PlaybackHandoffOutcome outcome) {
    final pending = _pending[id]?.completer;
    if (pending != null && !pending.isCompleted) pending.complete(outcome);
  }

  /// The connection dropped: nothing will answer any more. A handoff that waits
  /// for a profile switch expected the drop and survives it, unless [force]
  /// says the phone stopped reconnecting.
  void failAll({bool force = false}) {
    for (final entry in _pending.entries.toList()) {
      if (force || !entry.value.switching) complete(entry.key, PlaybackHandoffOutcome.failed);
    }
  }

  /// Reads the acknowledgement a `syncState` command may carry.
  void handleSyncState(Map<String, dynamic>? data) {
    final switching = data?[handoffSwitchingKey];
    if (switching is String) {
      final profile = data?[handoffProfileKey];
      _switching(switching, profile is String ? profile : '', data?[handoffPinKey] == true);
    }
    final playing = data?[handoffPlayingKey];
    final failed = data?[handoffFailedKey];
    if (playing is String) complete(playing, PlaybackHandoffOutcome.playing);
    if (failed is String) {
      final wrongProfile = data?[handoffReasonKey] == handoffReasonWrongProfile;
      complete(failed, wrongProfile ? PlaybackHandoffOutcome.wrongProfile : PlaybackHandoffOutcome.failed);
    }
  }

  void _switching(String id, String profile, bool pin) {
    final waiting = _pending[id];
    if (waiting == null || waiting.completer.isCompleted || waiting.switching) return;
    waiting.switching = true;
    waiting.timer?.cancel();
    waiting.timer = Timer(switchBudget, () => complete(id, PlaybackHandoffOutcome.timedOut));
    waiting.onSwitching?.call(profile, pin);
  }
}

/// Apple TV side of a handoff that switches profile first (A-23b). The switch
/// rebuilds the profile session, and the Companion Remote connection with it,
/// so this lives outside it: the new session takes the request from here, and
/// a phone that reconnects asks here how its handoff ended.
class PlaybackHandoffLedger {
  PlaybackHandoffLedger({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Shorter than [PlaybackHandoffTracker.switchBudget]: a cancel from the phone
  /// cannot reach this device during the switch, so this budget must run out first.
  static const ttl = Duration(seconds: 60);

  final DateTime Function() _clock;
  ({PlaybackHandoffRequest request, String profileId, DateTime at})? _armed;

  /// Recent handoffs by id; null while one is still under way. Bounded, since
  /// ids arrive from the network.
  final Map<String, PlaybackHandoffOutcome?> _outcomes = {};

  bool _expired(DateTime at) => _clock().difference(at) > ttl;

  /// A switch for a handoff is under way.
  bool get isArmed {
    final armed = _armed;
    return armed != null && !_expired(armed.at);
  }

  /// [request] plays once the profile [profileId] is active.
  void arm(PlaybackHandoffRequest request, String profileId) {
    _armed = (request: request, profileId: profileId, at: _clock());
    _remember(request.id, null);
  }

  /// The switch was cancelled or failed.
  void clear() => _armed = null;

  /// The armed request, taken once by the session of [profileId]. A request
  /// armed for another profile, or older than [ttl], is dropped as failed.
  PlaybackHandoffRequest? takeFor(String? profileId) {
    final armed = _armed;
    if (armed == null) return null;
    _armed = null;
    if (armed.profileId != profileId || _expired(armed.at)) {
      record(armed.request.id, PlaybackHandoffOutcome.failed);
      return null;
    }
    return armed.request;
  }

  void record(String id, PlaybackHandoffOutcome outcome) => _remember(id, outcome);

  void _remember(String id, PlaybackHandoffOutcome? outcome) {
    _outcomes.remove(id);
    _outcomes[id] = outcome;
    while (_outcomes.length > 16) {
      _outcomes.remove(_outcomes.keys.first);
    }
  }

  /// Still under way: armed and in time, or taken and not yet answered.
  bool isPending(String id) {
    if (!_outcomes.containsKey(id) || _outcomes[id] != null) return false;
    final armed = _armed;
    return armed == null || armed.request.id != id || !_expired(armed.at);
  }

  PlaybackHandoffOutcome? outcomeOf(String id) => _outcomes[id];
}

/// The handoff state of this device, kept across profile sessions.
final playbackHandoffLedger = PlaybackHandoffLedger();

/// The answer to a phone asking after handoff [id]. An id this device does not
/// know (dropped, or from before a restart) is a failure: nothing will start.
Map<String, dynamic> handoffQueryReply(PlaybackHandoffLedger ledger, String id) {
  if (ledger.isPending(id)) return {handoffPendingKey: id};
  return handoffOutcomeData(id, ledger.outcomeOf(id) ?? PlaybackHandoffOutcome.failed);
}

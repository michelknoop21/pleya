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
import '../../utils/app_logger.dart';
import '../../utils/log_redaction_manager.dart';

@immutable
class PlaybackHandoffRequest {
  const PlaybackHandoffRequest({
    required this.id,
    required this.serverId,
    required this.itemId,
    required this.positionMs,
    required this.title,
    required this.from,
    this.plexUserToken,
  });

  /// Correlates the request with the acknowledgement.
  final String id;
  final String serverId;
  final String itemId;
  final int positionMs;
  final String title;

  /// Name of the sending device, shown on the Apple TV.
  final String from;

  /// The Plex token of the sender's protected profile (A-23c). The Apple TV
  /// checks it with plex.tv and then skips the PIN of that profile; without it,
  /// or when the check fails, it asks the PIN. Never log it.
  final String? plexUserToken;

  Map<String, dynamic> toData() => {
    'id': id,
    'serverId': serverId,
    'itemId': itemId,
    'positionMs': positionMs,
    'title': title,
    'from': from,
    if (plexUserToken != null) _plexUserTokenKey: plexUserToken,
  };

  static const _plexUserTokenKey = 'plexUserToken';

  PlaybackHandoffRequest withPlexUserToken(String? token) => PlaybackHandoffRequest(
    id: id,
    serverId: serverId,
    itemId: itemId,
    positionMs: positionMs,
    title: title,
    from: from,
    plexUserToken: token,
  );

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
    // A token of the wrong type only costs the PIN skip, not the handoff.
    final token = data[_plexUserTokenKey];
    return PlaybackHandoffRequest(
      id: id,
      serverId: serverId,
      itemId: itemId,
      positionMs: positionMs,
      title: title is String ? title : '',
      from: from is String ? from : '',
      plexUserToken: token is String && token.isNotEmpty ? token : null,
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

  /// The Apple TV refused because another profile is active there and it has no
  /// profile of the sender to switch to; the sender keeps playing and can retry
  /// after picking the profile on the Apple TV.
  wrongProfile,

  /// The Apple TV would switch to the sender's profile, but its PIN was not
  /// entered there (cancelled, wrong, or too late); the sender keeps playing.
  pinCancelled,

  /// No answer in time; the sender keeps playing.
  timedOut,
}

const handoffPlayingKey = 'handoffPlaying';
const handoffFailedKey = 'handoffFailed';

/// Why the Apple TV refused, next to [handoffFailedKey]; absent for any other failure.
const handoffReasonKey = 'handoffReason';
const handoffReasonWrongProfile = 'profile';
const handoffReasonPinCancelled = 'pin';

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
  PlaybackHandoffOutcome.pinCancelled => {handoffFailedKey: id, handoffReasonKey: handoffReasonPinCancelled},
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

/// The Plex token a phone sends along so the Apple TV can skip the PIN of the
/// sender's profile there (A-23c): only when [profile], the active profile on
/// the phone, is protected itself, and only the token of its [row] for
/// [plexConnectionId], the Plex account the handshake used. Null otherwise.
String? plexUserTokenForHandoff({
  required Profile? profile,
  required String? plexConnectionId,
  required ProfileConnection? row,
}) {
  if (profile == null || !profile.isPinProtected) return null;
  if (plexConnectionId == null || plexConnectionId.isEmpty) return null;
  if (profile.isPlexHome && profile.parentConnectionId != plexConnectionId) return null;
  if (!profile.isPlexHome && !profile.isLocal) return null;
  if (row == null || row.profileId != profile.id || row.connectionId != plexConnectionId || !row.hasToken) return null;
  return row.userToken;
}

/// The Plex user a token must belong to before it replaces the PIN of [target]
/// (A-23c), or null when no token may: [target] is not protected, or it is not
/// tied to exactly that user. A Plex Home profile on the account of the
/// handshake [connectionId]; a local profile only with a single join row
/// ([targetRows]), and that row on [connectionId]. A local profile with more
/// rows opens more than that one Plex user, so its PIN stays.
String? handoffTokenProofUuid(
  Profile target, {
  required String connectionId,
  required List<ProfileConnection> targetRows,
}) {
  if (!target.isPinProtected || connectionId.isEmpty) return null;
  if (target.isPlexHome) {
    final uuid = target.plexHomeUserUuid;
    return target.parentConnectionId == connectionId && uuid != null && uuid.isNotEmpty ? uuid : null;
  }
  if (!target.isLocal || targetRows.length != 1) return null;
  final row = targetRows.single;
  if (row.profileId != target.id || row.connectionId != connectionId || row.userIdentifier.isEmpty) return null;
  return row.userIdentifier;
}

/// Returns [token] when plex.tv says it belongs to [expectedUuid] and the
/// handshake named that same user ([peerUuid]); null on anything else,
/// including an error or no answer within [timeout]. The PIN then stays.
Future<String?> verifyPlexHomeTokenProof({
  required Future<Map<String, dynamic>> Function(String token) userInfo,
  required String? token,
  required String expectedUuid,
  required String? peerUuid,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (token == null || token.isEmpty || expectedUuid.isEmpty || peerUuid != expectedUuid) return null;
  LogRedactionManager.registerToken(token);
  try {
    final uuid = (await userInfo(token).timeout(timeout))['uuid'];
    if (uuid is String && uuid.trim() == expectedUuid) return token;
    appLogger.w('Playback handoff: the Plex token belongs to another user');
  } catch (e) {
    // Only the type: an error text could carry the request.
    appLogger.w('Playback handoff: the Plex token could not be checked (${e.runtimeType})');
  }
  return null;
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
  PlaybackHandoffTracker({this.switchBudget = const Duration(seconds: 120)});

  /// How long the phone waits once the Apple TV says it switches profile: a PIN
  /// typed there, a new session, and the phone reconnecting. The Apple TV starts
  /// at the latest [PlaybackHandoffLedger.pinWait] plus
  /// [PlaybackHandoffLedger.startWindow] (90 s) after it sent that, which leaves
  /// 30 s for fetching the item, opening the player and the answer.
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
      complete(failed, switch (data?[handoffReasonKey]) {
        handoffReasonWrongProfile => PlaybackHandoffOutcome.wrongProfile,
        handoffReasonPinCancelled => PlaybackHandoffOutcome.pinCancelled,
        _ => PlaybackHandoffOutcome.failed,
      });
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
///
/// Deadlines, so the Apple TV never starts after the phone gave up (a cancel
/// cannot reach it while the connection is down): the PIN must be accepted
/// within [pinWait] of [arm], and playback must start within [startWindow] of
/// that. Both together stay below [PlaybackHandoffTracker.switchBudget].
class PlaybackHandoffLedger {
  PlaybackHandoffLedger({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const pinWait = Duration(seconds: 60);
  static const startWindow = Duration(seconds: 30);

  final DateTime Function() _clock;
  _ArmedHandoff? _armed;
  ({String id, DateTime startBy})? _taken;

  /// Recent handoffs by id; null while one is still under way. Bounded, since
  /// ids arrive from the network.
  final Map<String, PlaybackHandoffOutcome?> _outcomes = {};

  bool _late(DateTime deadline) => _clock().isAfter(deadline);

  /// A switch for a handoff is under way: its PIN dialog is open, or the new
  /// session has not taken it yet and may still.
  bool get isArmed {
    final startBy = _armed?.startBy;
    return _armed != null && (startBy == null || !_late(startBy));
  }

  /// [request] plays once the profile [profileId] is active. Call before
  /// anything else of the switch, so a second handoff meets [isArmed].
  void arm(PlaybackHandoffRequest request, String profileId) {
    _armed = _ArmedHandoff(request, profileId, _clock());
    _remember(request.id, null);
  }

  /// The PIN for [id] was accepted: may the profile switch now? Not when it came
  /// after [pinWait]. Yes starts the [startWindow].
  bool mayActivate(String id) {
    final armed = _armed;
    if (armed == null || armed.request.id != id || _late(armed.at.add(pinWait))) return false;
    armed.startBy = _clock().add(startWindow);
    return true;
  }

  /// The switch was cancelled or failed.
  void clear() => _armed = null;

  /// The armed request, taken once by the session of [profileId]. A request
  /// for another profile, one that never passed [mayActivate], or one past its
  /// start window is dropped as failed.
  PlaybackHandoffRequest? takeFor(String? profileId) {
    final armed = _armed;
    if (armed == null) return null;
    _armed = null;
    final startBy = armed.startBy;
    if (armed.profileId != profileId || startBy == null || _late(startBy)) {
      record(armed.request.id, PlaybackHandoffOutcome.failed);
      return null;
    }
    _taken = (id: armed.request.id, startBy: startBy);
    return armed.request;
  }

  /// A taken request may still start: asked again right before playing, since
  /// binding the new profile's servers takes time.
  bool mayStart(String id) {
    final taken = _taken;
    return taken != null && taken.id == id && !_late(taken.startBy);
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
    return _armed?.request.id != id || isArmed;
  }

  PlaybackHandoffOutcome? outcomeOf(String id) => _outcomes[id];
}

class _ArmedHandoff {
  _ArmedHandoff(this.request, this.profileId, this.at);

  final PlaybackHandoffRequest request;
  final String profileId;
  final DateTime at;

  /// Set once the PIN was accepted in time; playback must start before it.
  DateTime? startBy;
}

/// The handoff state of this device, kept across profile sessions.
final playbackHandoffLedger = PlaybackHandoffLedger();

/// The answer to a phone asking after handoff [id]. An id this device does not
/// know (dropped, or from before a restart) is a failure: nothing will start.
Map<String, dynamic> handoffQueryReply(PlaybackHandoffLedger ledger, String id) {
  if (ledger.isPending(id)) return {handoffPendingKey: id};
  return handoffOutcomeData(id, ledger.outcomeOf(id) ?? PlaybackHandoffOutcome.failed);
}

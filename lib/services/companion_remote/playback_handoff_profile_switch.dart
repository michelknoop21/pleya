import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../connection/connection_registry.dart';
import '../../models/companion_remote/remote_command.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_activation.dart';
import '../../profiles/profile_connection_registry.dart';
import '../../providers/companion_remote_provider.dart';
import '../../utils/app_logger.dart';
import '../plex_auth_service.dart';
import 'playback_handoff.dart';
import 'playback_handoff_receiver.dart';

/// Apple TV side of a handoff from another member of the Home (A-23b): switch to
/// that member's profile first, so playback and progress land on their account.
///
/// The PIN is asked here, as the profile picker does, and decided before
/// anything switches. The switch rebuilds the profile session and drops the
/// connection to the phone, so the request waits in [playbackHandoffLedger] for
/// the new session ([resumePendingPlaybackHandoff]) and the phone reconnects to
/// ask how it went. Without a matching profile, or when a switch is already
/// under way, the phone hears no and keeps playing.
Future<void> switchProfileForHandoff(BuildContext context, PlaybackHandoffRequest request) async {
  final provider = context.read<CompanionRemoteProvider>();
  final active = context.read<ActiveProfileProvider>();
  void refuse(String reason, PlaybackHandoffOutcome outcome) {
    appLogger.w('Playback handoff ${request.id} refused: $reason');
    reportPlaybackHandoff(provider, request.id, outcome);
  }

  final connectionId = provider.peerConnectionId;
  final userUuid = provider.peerUserUuid;
  Profile? target;
  if (connectionId != null && userUuid != null) {
    final joinRows = await context.read<ProfileConnectionRegistry>().listForConnection(connectionId);
    if (!context.mounted) return;
    target = profileForHandoffSender(
      active.profiles,
      connectionId: connectionId,
      userUuid: userUuid,
      joinRows: joinRows,
    );
  }
  // The active profile itself would not rebuild the session, so nothing would take the request.
  if (target == null || target.id == active.activeId) {
    return refuse('no profile of the sender to switch to', PlaybackHandoffOutcome.wrongProfile);
  }

  final profile = target;
  final connections = context.read<ConnectionRegistry>();
  final profileConnections = context.read<ProfileConnectionRegistry>();
  await runHandoffProfileSwitch(
    request: request,
    target: profile,
    ledger: playbackHandoffLedger,
    send: (data) => provider.sendCommand(RemoteCommandType.syncState, data: data),
    verifyProof: () => _verifyHandoffToken(
      request,
      profile,
      connectionId: connectionId,
      peerUuid: userUuid,
      connections: connections,
      profileConnections: profileConnections,
    ),
    activate: (mayActivate, verifiedToken, onPinCancelled) => context.mounted
        ? activateProfileWithPin(
            context,
            profile,
            mayActivate: mayActivate,
            verifiedPlexUserToken: verifiedToken,
            onPinCancelled: onPinCancelled,
          )
        : Future.value(false),
  );
}

/// The Plex token of the request when plex.tv confirms it belongs to the user
/// of [target] and of the handshake (A-23c); null keeps the PIN.
Future<String?> _verifyHandoffToken(
  PlaybackHandoffRequest request,
  Profile target, {
  required String? connectionId,
  required String? peerUuid,
  required ConnectionRegistry connections,
  required ProfileConnectionRegistry profileConnections,
}) async {
  final token = request.plexUserToken;
  if (token == null || connectionId == null) return null;
  // Only a Plex account says which Plex user the handshake named.
  if (await connections.getPlexAccount(connectionId) == null) return null;
  final expected = handoffTokenProofUuid(
    target,
    connectionId: connectionId,
    targetRows: await profileConnections.listForProfile(target.id),
  );
  if (expected == null) return null;
  final auth = await PlexAuthService.create();
  try {
    return await verifyPlexHomeTokenProof(
      userInfo: auth.getUserInfo,
      token: token,
      expectedUuid: expected,
      peerUuid: peerUuid,
    );
  } finally {
    auth.dispose();
  }
}

/// The switch itself, with the device parts passed in. The request is armed
/// before anything else, so a second handoff meanwhile is refused without a
/// second dialog. The phone hears about the switch before it starts: a
/// successful activation tears this session down at once. The PIN dialog is
/// never closed for the phone, but a PIN that comes after the phone gave up
/// (its cancel arrived, or [PlaybackHandoffLedger.pinWait] passed) does not switch.
///
/// [verifyProof] returns the sender's Plex token once it is proven to belong to
/// the protected [target] (A-23c); that token then replaces the PIN and goes to
/// [activate]. It runs after arming, so a second handoff meanwhile is refused.
/// Null, or any error, keeps the PIN.
///
/// [activate] calls its third argument when the user cancelled the PIN dialog.
/// Only that tells the phone the PIN was not entered; every other failure
/// (activation, storage, binding, an exception, [PlaybackHandoffLedger.mayActivate]
/// refusing after the phone gave up) is a plain failure without a reason.
@visibleForTesting
Future<void> runHandoffProfileSwitch({
  required PlaybackHandoffRequest request,
  required Profile target,
  required PlaybackHandoffLedger ledger,
  required void Function(Map<String, dynamic> data) send,
  required Future<bool> Function(
    bool Function() mayActivate,
    String? verifiedPlexUserToken,
    void Function() onPinCancelled,
  )
  activate,
  Future<String?> Function()? verifyProof,
  Duration sendDelay = const Duration(milliseconds: 300),
}) async {
  if (ledger.isArmed) {
    appLogger.w('Playback handoff ${request.id} refused: a profile switch is under way');
    ledger.record(request.id, PlaybackHandoffOutcome.failed);
    return send(handoffOutcomeData(request.id, PlaybackHandoffOutcome.failed));
  }
  ledger.arm(request, target.id);
  String? proven;
  if (target.isPinProtected && verifyProof != null) {
    try {
      proven = await verifyProof();
    } catch (e) {
      // Only the type: an error text could carry the request.
      appLogger.w('Playback handoff ${request.id}: no proof for the profile (${e.runtimeType})');
    }
  }
  final pin = target.isPinProtected && proven == null;
  send({handoffSwitchingKey: request.id, handoffProfileKey: target.displayName, handoffPinKey: pin});
  // Sending encrypts asynchronously; a switch without a PIN closes the connection right after.
  await Future<void>.delayed(sendDelay);
  var switched = false;
  var pinCancelled = false;
  try {
    switched = await activate(
      () => !isPlaybackHandoffCancelled(request.id) && ledger.mayActivate(request.id),
      proven,
      () => pinCancelled = true,
    );
  } catch (e) {
    appLogger.w('Playback handoff ${request.id}: profile switch failed (${e.runtimeType})');
  }
  if (switched) return;
  // Still the old profile, and the phone is still connected.
  final outcome = pin && pinCancelled ? PlaybackHandoffOutcome.pinCancelled : PlaybackHandoffOutcome.failed;
  ledger.clear();
  ledger.record(request.id, outcome);
  send(handoffOutcomeData(request.id, outcome));
}

/// Called by the session of a newly active profile: plays the handoff that
/// switched to it, once its servers are bound.
Future<void> resumePendingPlaybackHandoff(BuildContext context) {
  final active = context.read<ActiveProfileProvider>();
  final provider = context.read<CompanionRemoteProvider>();
  return runPendingHandoffResume(
    ledger: playbackHandoffLedger,
    profileId: active.activeId,
    awaitBinding: active.awaitBindingSettle,
    report: (id, outcome) =>
        context.mounted ? reportPlaybackHandoff(provider, id, outcome) : playbackHandoffLedger.record(id, outcome),
    receive: (request) async {
      if (context.mounted) {
        return receivePlaybackHandoff(
          context,
          request,
          mayStart: () => playbackHandoffLedger.mayStart(request.id),
          startWithin: playbackHandoffLedger.startTimeLeft(request.id),
        );
      }
      playbackHandoffLedger.record(request.id, PlaybackHandoffOutcome.failed);
    },
  );
}

/// The resume itself, with the device parts passed in. The start window is
/// checked again after binding, which takes time: the phone may have given up.
@visibleForTesting
Future<void> runPendingHandoffResume({
  required PlaybackHandoffLedger ledger,
  required String? profileId,
  required Future<bool> Function() awaitBinding,
  required void Function(String id, PlaybackHandoffOutcome outcome) report,
  required Future<void> Function(PlaybackHandoffRequest request) receive,
}) async {
  final request = ledger.takeFor(profileId);
  if (request == null) return;
  // The receiver needs this profile's server clients.
  final bound = await awaitBinding();
  final late = !ledger.mayStart(request.id);
  if (!bound || late) {
    appLogger.w(
      'Playback handoff ${request.id} failed: ${late ? 'past its start window' : 'the profile did not bind'}',
    );
    return report(request.id, PlaybackHandoffOutcome.failed);
  }
  await receive(request);
}

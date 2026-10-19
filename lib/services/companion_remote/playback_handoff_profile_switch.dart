import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/companion_remote/remote_command.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_activation.dart';
import '../../profiles/profile_connection_registry.dart';
import '../../providers/companion_remote_provider.dart';
import '../../utils/app_logger.dart';
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
  await runHandoffProfileSwitch(
    request: request,
    target: profile,
    ledger: playbackHandoffLedger,
    send: (data) => provider.sendCommand(RemoteCommandType.syncState, data: data),
    activate: () => context.mounted ? activateProfileWithPin(context, profile) : Future.value(false),
  );
}

/// The switch itself, with the device parts passed in. The phone hears about
/// the switch before it starts, and the request is armed before the profile
/// activates: a successful activation tears this session down at once. One
/// switch at a time: a second handoff meanwhile is refused, without a dialog.
@visibleForTesting
Future<void> runHandoffProfileSwitch({
  required PlaybackHandoffRequest request,
  required Profile target,
  required PlaybackHandoffLedger ledger,
  required void Function(Map<String, dynamic> data) send,
  required Future<bool> Function() activate,
  Duration sendDelay = const Duration(milliseconds: 300),
}) async {
  if (ledger.isArmed) {
    appLogger.w('Playback handoff ${request.id} refused: a profile switch is under way');
    ledger.record(request.id, PlaybackHandoffOutcome.failed);
    return send(handoffOutcomeData(request.id, PlaybackHandoffOutcome.failed));
  }
  send({handoffSwitchingKey: request.id, handoffProfileKey: target.displayName, handoffPinKey: target.isPinProtected});
  // Sending encrypts asynchronously; a switch without a PIN closes the connection right after.
  await Future<void>.delayed(sendDelay);
  ledger.arm(request, target.id);
  var switched = false;
  try {
    switched = await activate();
  } catch (e) {
    appLogger.w('Playback handoff ${request.id}: profile switch failed', error: e);
  }
  if (switched) return;
  // Cancelled PIN or a failed check: still the old profile, and the phone is still connected.
  ledger.clear();
  ledger.record(request.id, PlaybackHandoffOutcome.wrongProfile);
  send(handoffOutcomeData(request.id, PlaybackHandoffOutcome.wrongProfile));
}

/// Called by the session of a newly active profile: plays the handoff that
/// switched to it, once its servers are bound.
Future<void> resumePendingPlaybackHandoff(BuildContext context) async {
  final active = context.read<ActiveProfileProvider>();
  final request = playbackHandoffLedger.takeFor(active.activeId);
  if (request == null) return;
  // The receiver needs this profile's server clients.
  final bound = await active.awaitBindingSettle();
  if (!context.mounted) {
    playbackHandoffLedger.record(request.id, PlaybackHandoffOutcome.failed);
    return;
  }
  if (!bound) {
    appLogger.w('Playback handoff ${request.id} failed: the new profile did not bind');
    return reportPlaybackHandoff(context.read<CompanionRemoteProvider>(), request.id, PlaybackHandoffOutcome.failed);
  }
  await receivePlaybackHandoff(context, request);
}

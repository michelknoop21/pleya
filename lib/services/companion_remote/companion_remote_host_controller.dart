import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../connection/connection_registry.dart';
import '../../profiles/active_plex_identity.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/plex_home_service.dart';
import '../../profiles/profile_connection_registry.dart';
import '../../providers/companion_remote_provider.dart';
import '../../utils/app_logger.dart';

/// Builds the auth contexts for the active profile, so this device can host or
/// join a Companion Remote session. False when no usable identity exists.
Future<bool> ensureCompanionRemoteCrypto(BuildContext context) async {
  final companionRemote = context.read<CompanionRemoteProvider>();
  final connections = context.read<ConnectionRegistry>();
  final activeProfile = context.read<ActiveProfileProvider>();
  final profileConnections = context.read<ProfileConnectionRegistry>();
  final plexHome = context.read<PlexHomeService>();
  final identity = await resolveActivePlexIdentity(
    activeProfile: activeProfile,
    connections: connections,
    profileConnections: profileConnections,
  );
  if (!context.mounted) return false;
  final home = identity == null ? null : await plexHome.materializePlexHomeForConnection(identity.account.id);
  if (!context.mounted) return false;
  final ok = await companionRemote.ensureCryptoReady(
    home,
    connections: connections,
    activeProfile: activeProfile,
    profileConnections: profileConnections,
    identity: identity,
    plexHomeForConnection: plexHome.materializePlexHomeForConnection,
  );
  return context.mounted && ok;
}

Future<bool> startCompanionRemoteHost(BuildContext context) async {
  final companionRemote = context.read<CompanionRemoteProvider>();
  if (companionRemote.isHostServerRunning) return true;

  try {
    if (!await ensureCompanionRemoteCrypto(context)) return false;
    await companionRemote.startHostServer();
    return companionRemote.isHostServerRunning;
  } catch (e) {
    appLogger.e('CompanionRemote: Failed to start server', error: e);
    return false;
  }
}

Future<void> applyCompanionRemoteServerSetting(BuildContext context, bool enabled) async {
  final companionRemote = context.read<CompanionRemoteProvider>();
  if (!enabled) {
    await companionRemote.stopHostServer();
    return;
  }

  await startCompanionRemoteHost(context);
}

/// Starts listening for Pleya Fly on an iPhone or iPad (A-23d): a host that
/// takes a fly and nothing else. While the phone is a client somewhere (the
/// remote, or a fly to the Apple TV) it waits, and leaving that session
/// brings it back.
Future<bool> startPleyaFlyReceiveHost(BuildContext context) async {
  final companionRemote = context.read<CompanionRemoteProvider>();
  if (!await companionRemote.requestHandoffOnlyHost()) return companionRemote.isHandoffOnlyHost;
  try {
    if (!await ensureCompanionRemoteCrypto(context)) return false;
    // A client session may have started while the identity was derived.
    if (!await companionRemote.requestHandoffOnlyHost()) return false;
    await companionRemote.startHostServer(handoffOnly: true);
    return companionRemote.isHandoffOnlyHost;
  } catch (e) {
    appLogger.e('CompanionRemote: Failed to start the Pleya Fly host', error: e);
    return false;
  }
}

Future<void> applyPleyaFlyReceiveSetting(BuildContext context, bool enabled) async {
  if (!enabled) return context.read<CompanionRemoteProvider>().stopHandoffOnlyHost();
  await startPleyaFlyReceiveHost(context);
}

/// Pleya Fly in the other direction (A-23d): an iPhone or iPad listens for a
/// fly from the Apple TV while Pleya is in the foreground. It hosts the
/// Companion Remote in a handoff-only mode: a fly is the one command it acts
/// on, so another member of the Home cannot steer the phone with D-pad
/// presses. The Remote Session dialog stays the explicit path for that, and
/// it does not exist on a phone.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../models/companion_remote/remote_command.dart';
import '../../utils/platform_detector.dart';
import 'lan_discovery_service.dart';

/// Beacon platform of an iPhone or iPad, the only Pleya Fly targets of an Apple TV.
const pleyaFlyTargetPlatform = 'iOS';

/// Whether this device receives a fly: an iPhone or iPad. Not an Apple TV, and
/// not the iOS app on a Mac, whose beacon would also say iOS.
bool pleyaFlyReceiveSupported() =>
    Platform.isIOS && !PlatformDetector.isTV() && !TvDetectionService.isIOSAppOnMacSync();

/// A host the Apple TV may fly to. Only iPhones and iPads host as a receiver.
bool isPleyaFlyTarget(DiscoveredHost host) => host.platform == pleyaFlyTargetPlatform;

/// A host a phone may steer as a remote. An iPhone or iPad hosts only to
/// receive a fly and takes no remote commands, so the remote does not list it.
bool isRemoteControlTarget(DiscoveredHost host) => host.platform != pleyaFlyTargetPlatform;

/// Whether a host passes [type] on to the app. A handoff-only host takes the
/// fly and nothing else; answers and queries of the fly itself travel as
/// `syncState`, which the provider handles before this.
bool routesHostCommand(RemoteCommandType type, {required bool handoffOnly}) =>
    !handoffOnly || type == RemoteCommandType.handoff;

enum PleyaFlyHostAction { start, stop, none }

/// What the receiving host does on a lifecycle change. iOS drops sockets and
/// beacons of a suspended app, so the host runs only in the foreground: it
/// starts on [AppLifecycleState.resumed] and stops on paused or detached.
/// Inactive and hidden are passing states (Control Center, the app switcher).
PleyaFlyHostAction pleyaFlyHostActionFor(
  AppLifecycleState state, {
  required bool receiveSupported,
  required bool enabled,
}) {
  if (!receiveSupported) return PleyaFlyHostAction.none;
  return switch (state) {
    AppLifecycleState.resumed => enabled ? PleyaFlyHostAction.start : PleyaFlyHostAction.none,
    AppLifecycleState.paused || AppLifecycleState.detached => PleyaFlyHostAction.stop,
    AppLifecycleState.inactive || AppLifecycleState.hidden => PleyaFlyHostAction.none,
  };
}

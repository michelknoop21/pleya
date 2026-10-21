import 'dart:async';

import 'package:pleya/services/companion_remote/lan_discovery_service.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/playback_handoff_sender.dart';

/// A beacon as the LAN discovery would report it.
DiscoveredHost fakeHost(String name, {String platform = 'iOS', String? clientId}) => DiscoveredHost(
  authContextId: 'ctx',
  clientId: clientId ?? name,
  name: name,
  platform: platform,
  port: 48632,
  ips: const ['192.168.1.20'],
);

/// A transport that records every call in [log] and answers a handoff with
/// [answer] (A-23d).
/// The one outgoing fly a device may run, shared by the fakes of one device.
class FakeFlyLock {
  bool held = false;
}

class FakeHandoffTransport implements PlaybackHandoffTransport {
  FakeHandoffTransport({this.hostRunning = true, this.discoverable = true, FakeFlyLock? flyLock})
    : flyLock = flyLock ?? FakeFlyLock();

  final FakeFlyLock flyLock;

  final log = <String>[];
  final beacons = StreamController<List<DiscoveredHost>>.broadcast();

  @override
  bool hostRunning;

  /// False: no remote identity, so discovery gives no stream.
  bool discoverable;
  int discoverCalls = 0;

  /// Runs inside [discover], as deriving the identity would.
  void Function()? onDiscover;

  /// Awaited inside [discover]: an identity that takes a while to derive.
  Future<void> Function()? onDiscoverAsync;

  /// What the receiver answers; defaults to playing.
  Future<PlaybackHandoffOutcome> Function(PlaybackHandoffRequest request)? answer;
  final requests = <PlaybackHandoffRequest>[];

  @override
  String get deviceName => 'Woonkamer';

  @override
  Future<Stream<List<DiscoveredHost>>?> discover() async {
    discoverCalls++;
    log.add('discover');
    onDiscover?.call();
    await onDiscoverAsync?.call();
    return discoverable ? beacons.stream : null;
  }

  @override
  void stopDiscovery() => log.add('stopDiscovery');

  @override
  Future<void> stopHost() async {
    log.add('stopHost');
    hostRunning = false;
  }

  @override
  Future<void> restartHost() async {
    log.add('restartHost');
    hostRunning = true;
  }

  @override
  Future<void> connect(DiscoveredHost host) async => log.add('connect:${host.name}');

  @override
  Future<PlaybackHandoffOutcome> handOff(
    PlaybackHandoffRequest request, {
    void Function(String profile, bool pin)? onSwitching,
  }) {
    log.add('handOff');
    requests.add(request);
    return answer?.call(request) ?? Future.value(PlaybackHandoffOutcome.playing);
  }

  @override
  Future<void> cancel(String requestId) async => log.add('cancel:$requestId');

  @override
  Future<void> leave() async => log.add('leave');

  @override
  bool beginFly() {
    if (flyLock.held) return false;
    flyLock.held = true;
    return true;
  }

  @override
  void endFly() => flyLock.held = false;
}

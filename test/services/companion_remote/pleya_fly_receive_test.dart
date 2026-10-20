import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/companion_remote/remote_command.dart';
import 'package:pleya/services/companion_remote/pleya_fly_receive.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/fake_handoff_transport.dart';

// A-23d: an iPhone or iPad hosts the Companion Remote only to receive Pleya Fly.
void main() {
  group('routesHostCommand', () {
    test('a handoff-only host takes the fly and drops every other command', () {
      expect(routesHostCommand(RemoteCommandType.handoff, handoffOnly: true), isTrue);
      for (final type in RemoteCommandType.values.where((t) => t != RemoteCommandType.handoff)) {
        expect(routesHostCommand(type, handoffOnly: true), isFalse, reason: type.name);
      }
    });

    test('a full host passes everything on, D-pad included', () {
      for (final type in [RemoteCommandType.dpadUp, RemoteCommandType.select, RemoteCommandType.handoff]) {
        expect(routesHostCommand(type, handoffOnly: false), isTrue, reason: type.name);
      }
    });
  });

  group('pleyaFlyHostActionFor', () {
    PleyaFlyHostAction action(AppLifecycleState state, {bool supported = true, bool enabled = true}) =>
        pleyaFlyHostActionFor(state, receiveSupported: supported, enabled: enabled);

    test('the phone listens in the foreground and stops when iOS suspends it', () {
      expect(action(AppLifecycleState.resumed), PleyaFlyHostAction.start);
      expect(action(AppLifecycleState.paused), PleyaFlyHostAction.stop);
      expect(action(AppLifecycleState.detached), PleyaFlyHostAction.stop);
    });

    test('passing states leave the host alone', () {
      expect(action(AppLifecycleState.inactive), PleyaFlyHostAction.none);
      expect(action(AppLifecycleState.hidden), PleyaFlyHostAction.none);
    });

    test('the setting off starts nothing on resume, but a suspend still stops', () {
      expect(action(AppLifecycleState.resumed, enabled: false), PleyaFlyHostAction.none);
      expect(action(AppLifecycleState.paused, enabled: false), PleyaFlyHostAction.stop);
    });

    test('an Apple TV, a Mac or a desktop never follows the lifecycle', () {
      for (final state in AppLifecycleState.values) {
        expect(action(state, supported: false), PleyaFlyHostAction.none, reason: state.name);
      }
    });
  });

  test('receiving Pleya Fly is on by default on an iPhone or iPad only', () {
    expect(SettingsService.pleyaFlyReceiveDefaultFor(iosHandheld: true), isTrue);
    expect(SettingsService.pleyaFlyReceiveDefaultFor(iosHandheld: false), isFalse);
  });

  test('a phone is a fly target of the Apple TV and never a remote target', () {
    final phone = fakeHost('iPhone');
    final tv = fakeHost('Apple TV', platform: 'tvOS');
    final mac = fakeHost('MacBook', platform: 'macOS');
    expect(isPleyaFlyTarget(phone), isTrue);
    expect(isPleyaFlyTarget(tv), isFalse);
    expect(isRemoteControlTarget(phone), isFalse);
    expect(isRemoteControlTarget(tv), isTrue);
    expect(isRemoteControlTarget(mac), isTrue);
  });
}

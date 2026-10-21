import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/companion_remote/remote_command.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/pleya_fly_receive.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/fake_handoff_transport.dart';

// A-23d: an iPhone or iPad hosts the Companion Remote only to receive Pleya Fly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('installHostCommandRouting', () {
    List<String> route(bool handoffOnly, List<RemoteCommandType> types, {bool mounted = true}) {
      final provider = CompanionRemoteProvider();
      addTearDown(provider.dispose);
      final seen = <String>[];
      installHostCommandRouting(
        provider,
        handoffOnly: handoffOnly,
        isMounted: () => mounted,
        onHandoff: (c) => seen.add('handoff'),
        onCommand: (c) => seen.add(c.type.name),
      );
      for (final type in types) {
        provider.onCommandReceived!(RemoteCommand(type: type));
      }
      return seen;
    }

    const types = [RemoteCommandType.dpadUp, RemoteCommandType.handoff, RemoteCommandType.select];

    test('a phone acts on the fly only', () {
      expect(route(true, types), ['handoff']);
    });

    test('an Apple TV or desktop acts on everything', () {
      expect(route(false, types), ['dpadUp', 'handoff', 'select']);
    });

    test('nothing reaches a screen that is gone', () {
      expect(route(false, types, mounted: false), isEmpty);
    });
  });

  test('followLifecycleWithPleyaFlyHost starts on resume and stops on suspend', () async {
    final calls = <String>[];
    Future<void> follow(AppLifecycleState state) => followLifecycleWithPleyaFlyHost(
      state,
      receiveSupported: true,
      enabled: true,
      start: () async => calls.add('start'),
      stop: () async => calls.add('stop'),
    );
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]) {
      await follow(state);
    }
    expect(calls, ['stop', 'start']);
  });

  // The units above only count while the main screen uses them: a phone that
  // routes everything takes D-pad presses from any member of the Home.
  test('the main screen wires the command routing and the lifecycle', () {
    final source = File('lib/screens/main_screen.dart').readAsStringSync();
    final setup = source.substring(
      source.indexOf('void _setupCompanionRemote()'),
      source.indexOf('final receiver = CompanionRemoteReceiver.instance;'),
    );
    expect(setup, contains('installHostCommandRouting('));
    expect(setup, contains('handoffOnly: handoffOnly'));
    expect(setup, contains('final handoffOnly = !PlatformDetector.shouldActAsRemoteHost(context);'));
    expect(setup, isNot(contains('onCommandReceived =')), reason: 'one place installs the routing');
    final lifecycle = source.substring(source.indexOf('void didChangeAppLifecycleState('));
    expect(lifecycle.substring(0, lifecycle.indexOf('\n  }\n')), contains('_followLifecycleWithPleyaFlyHost(state)'));
    expect(source, contains('await followLifecycleWithPleyaFlyHost('));
  });
}

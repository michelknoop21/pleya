import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_capabilities.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

import 'assistant_memory_support.dart';

// The start questions follow the profile: until its switches are read they
// are those of a children's profile.

void main() {
  late MultiServerManager servers;
  setUp(() {
    servers = MultiServerManager();
    addTearDown(servers.dispose);
    servers.debugRegisterJellyfinClientForTesting(
      JellyfinClient.forTesting(
        connection: JellyfinConnection(
          id: 'jf-1/user-a',
          baseUrl: 'https://jellyfin.example',
          serverName: 'Jelly',
          serverMachineId: 'jf-1',
          userId: 'user-a',
          userName: 'User A',
          accessToken: 'token',
          deviceId: 'device',
          isAdministrator: true,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        httpClient: MockClient((_) async => http.Response(jsonEncode(null), 404)),
      ),
    );
  });

  AssistantController controller(Future<bool> Function() kidsProfile, {bool rollout = true}) {
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(
        servers: servers,
        screen: screen,
        kidsProfile: kidsProfile,
        personal: AssistantPersonalServices(
          userName: 'Michel',
          recent: () async => const [],
          everSeen: () async => const {},
          taste: () async => AffinityVector.empty,
          picks: (_) async => const [],
        ),
      ),
      rolloutEnabled: rollout,
      entitlement: const Entitled(),
      loadConfig: () async =>
          const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
    );
    addTearDown(c.dispose);
    return c;
  }

  bool onlyWatch(Set<AssistantCapability> got) => got.every((c) => c.group == AssistantCapabilityGroup.watch);

  test('before the profile is read: the questions of a children\'s profile', () async {
    final c = controller(() async => false);
    expect(c.idleProfileKnown, isFalse);
    expect(c.idleCapabilities(), isNotEmpty);
    expect(onlyWatch(c.idleCapabilities()), isTrue, reason: 'an administrator, but nobody read that yet');

    var notified = 0;
    c.addListener(() => notified++);
    await c.refreshIdleProfile();
    expect(c.idleProfileKnown, isTrue);
    expect(notified, 1, reason: 'the greeting picks again');
    expect(
      c.idleCapabilities(),
      containsAll([AssistantCapability.scan, AssistantCapability.users, AssistantCapability.history]),
    );

    await c.refreshIdleProfile();
    expect(notified, 1, reason: 'the same answer is no news');
  });

  test('a children\'s profile keeps watch questions only', () async {
    final c = controller(() async => true);
    await c.refreshIdleProfile();
    expect(c.idleProfileKnown, isTrue);
    expect(onlyWatch(c.idleCapabilities()), isTrue);
    expect(c.idleCapabilities(), isNot(contains(AssistantCapability.history)));
  });

  test('an unreadable switch stays closed', () async {
    final c = controller(() async => throw StateError('prefs'));
    await c.refreshIdleProfile();
    expect(c.idleProfileKnown, isFalse);
    expect(onlyWatch(c.idleCapabilities()), isTrue);
  });

  test('a failed read after a good one closes the questions again', () async {
    var fail = false;
    final c = controller(() async => fail ? throw StateError('prefs') : false);
    await c.refreshIdleProfile();
    expect(c.idleCapabilities(), contains(AssistantCapability.scan));
    fail = true;
    var notified = 0;
    c.addListener(() => notified++);
    await c.refreshIdleProfile();
    expect(c.idleProfileKnown, isFalse);
    expect(onlyWatch(c.idleCapabilities()), isTrue, reason: 'no admin chip on the strength of an old answer');
    expect(notified, 1);
  });

  test('the switch flipped in Instellingen counts from the next read', () async {
    var kids = false;
    final c = controller(() async => kids);
    await c.refreshIdleProfile();
    expect(c.idleCapabilities(), contains(AssistantCapability.scan));
    kids = true;
    await c.refreshIdleProfile();
    expect(onlyWatch(c.idleCapabilities()), isTrue);
  });

  test('showing an entry point reads the profile', () async {
    final c = controller(() async => false);
    await c.refreshAvailability();
    await pumpEventQueue();
    expect(c.availability, AssistantAvailability.ready);
    expect(c.idleProfileKnown, isTrue);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/add_pleya_server_screen.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';
import 'package:pleya/services/pleya_server_lan_discovery_service.dart';
import 'package:pleya/utils/platform_detector.dart';

/// A server that answers `/info` as [serverId] and records which addresses
/// were asked.
PleyaServerAuthService _auth(String serverId, List<Uri> asked) => PleyaServerAuthService(
  httpClientFactory: () => MockClient((request) async {
    asked.add(request.url);
    if (request.url.path != '/pleya/v1/info') return http.Response('', 404);
    return http.Response(
      jsonEncode({
        'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
        'server': {'id': serverId},
        'capabilities': {'browse': true, 'search': true, 'artwork': true, 'watch_state': false},
        'auth': {
          'methods': ['password'],
          'setup_required': false,
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

const _home = DiscoveredPleyaServer(address: 'http://192.168.1.20:8832', id: 'srv-1', name: 'Thuis');
const _attic = DiscoveredPleyaServer(address: 'http://192.168.1.30:8832', id: 'srv-2', name: 'Zolder');

Future<List<DiscoveredPleyaServer>> _none() async => const [];

Widget _screen({
  List<DiscoveredPleyaServer> found = const [],
  String answersAs = 'srv-1',
  List<Uri>? asked,
  Future<List<DiscoveredPleyaServer>> Function()? discovery,
}) => InputModeTracker(
  child: MaterialApp(
    home: AddPleyaServerScreen(
      authServiceFactory: () => _auth(answersAs, asked ?? []),
      localDiscoveryFactory: discovery ?? () async => found,
    ),
  ),
);

void main() {
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('shows the servers that were found on the network', (tester) async {
    await tester.pumpWidget(_screen(found: const [_home, _attic]));
    await tester.pumpAndSettle();

    expect(find.text(t.addServer.localServers), findsOneWidget);
    expect(find.text('Thuis'), findsOneWidget);
    expect(find.text('http://192.168.1.20:8832'), findsOneWidget);
    expect(find.text('Zolder'), findsOneWidget);
  });

  testWidgets('shows no list when nothing answered, and the address field still works', (tester) async {
    final asked = <Uri>[];
    await tester.pumpWidget(_screen(discovery: _none, asked: asked));
    await tester.pumpAndSettle();

    expect(find.text(t.addServer.localServers), findsNothing);
    expect(find.text(t.addServer.searchingLocalServers), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'nas.lan:8832');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(asked.single.toString(), 'http://nas.lan:8832/pleya/v1/info');
    expect(find.text(t.addServer.signIn), findsOneWidget);
  });

  testWidgets('a failing search leaves the address field usable', (tester) async {
    await tester.pumpWidget(_screen(discovery: () async => throw const FormatException('socket')));
    await tester.pumpAndSettle();

    expect(find.text(t.addServer.searchingLocalServers), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('choosing a found server fills in its address and goes to sign-in', (tester) async {
    final asked = <Uri>[];
    await tester.pumpWidget(_screen(found: const [_home], asked: asked));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thuis'));
    await tester.pumpAndSettle();

    expect(asked.single.toString(), 'http://192.168.1.20:8832/pleya/v1/info');
    expect(find.text('http://192.168.1.20:8832'), findsOneWidget);
    expect(find.text(t.addServer.signIn), findsOneWidget);
    expect(find.text(t.addServer.pleyaServerDiscoveryMismatch), findsNothing);
  });

  testWidgets('another server on the found address stops before sign-in', (tester) async {
    await tester.pumpWidget(_screen(found: const [_home], answersAs: 'someone-else'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thuis'));
    await tester.pumpAndSettle();

    expect(find.text(t.addServer.pleyaServerDiscoveryMismatch), findsOneWidget);
    expect(find.text(t.addServer.signIn), findsNothing);
    expect(find.text(t.addServer.password), findsNothing);

    // The wrong address is not left in the field for a second try.
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text(t.addServer.signIn), findsNothing);
  });

  testWidgets('a found address typed by hand is held to the same id, another address is not', (tester) async {
    await tester.pumpWidget(_screen(found: const [_home], answersAs: 'someone-else'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'http://192.168.1.20:8832/');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text(t.addServer.pleyaServerDiscoveryMismatch), findsOneWidget);
    expect(find.text(t.addServer.signIn), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'http://192.168.1.99:8832');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text(t.addServer.signIn), findsOneWidget);
  });

  testWidgets('TV: the remote walks address, found servers, continue and back', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    await tester.pumpWidget(_screen(found: const [_home, _attic]));
    await tester.pumpAndSettle();

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(focused(), 'AddPleyaServer:Url');
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'AddPleyaServer:Discovered:http://192.168.1.20:8832');
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'AddPleyaServer:Discovered:http://192.168.1.30:8832');
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'AddPleyaServer:Continue');
    await press(LogicalKeyboardKey.arrowUp);
    expect(focused(), 'AddPleyaServer:Discovered:http://192.168.1.30:8832');
    await press(LogicalKeyboardKey.arrowUp);
    await press(LogicalKeyboardKey.arrowUp);
    expect(focused(), 'AddPleyaServer:Url');
  });

  testWidgets('two addresses that claim the same id are both listed and both reachable', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    const copy = DiscoveredPleyaServer(address: 'http://192.168.1.66:8832', id: 'srv-1', name: 'Thuis');
    await tester.pumpWidget(_screen(found: const [_home, copy]));
    await tester.pumpAndSettle();

    expect(find.text('http://192.168.1.20:8832'), findsOneWidget);
    expect(find.text('http://192.168.1.66:8832'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddPleyaServer:Discovered:http://192.168.1.20:8832');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddPleyaServer:Discovered:http://192.168.1.66:8832');
  });

  testWidgets('TV: select on a found server goes to sign-in', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final asked = <Uri>[];
    await tester.pumpWidget(_screen(found: const [_home], asked: asked));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(asked.single.host, '192.168.1.20');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddPleyaServer:Username');
  });
}

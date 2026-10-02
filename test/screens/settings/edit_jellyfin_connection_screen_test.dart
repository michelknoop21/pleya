import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/edit_jellyfin_connection_screen.dart';

/// DEC-141: the edit screen names the server type the connection really is.
void main() {
  JellyfinConnection connection({required bool isEmby}) => JellyfinConnection(
    id: 'srv-1/user-1',
    baseUrl: 'https://media.example.com',
    baseUrls: const ['https://media.example.com'],
    serverName: 'Home',
    serverMachineId: 'srv-1',
    userId: 'user-1',
    userName: 'edde',
    accessToken: 'tok',
    deviceId: 'dev',
    isEmby: isEmby,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  Future<void> pump(WidgetTester tester, {required bool isEmby}) => tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: EditJellyfinConnectionScreen(connection: connection(isEmby: isEmby)),
      ),
    ),
  );

  testWidgets('a Jellyfin connection is edited as Jellyfin', (tester) async {
    await pump(tester, isEmby: false);
    expect(find.text('Edit Jellyfin connection'), findsOneWidget);
  });

  testWidgets('an Emby connection is edited as Emby', (tester) async {
    await pump(tester, isEmby: true);
    expect(find.text('Edit Emby connection'), findsOneWidget);
    expect(find.text('Edit Jellyfin connection'), findsNothing);
  });
}

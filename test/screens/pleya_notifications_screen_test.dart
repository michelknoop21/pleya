import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/pleya_notifications_screen.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

class _Profiles extends ChangeNotifier implements ActiveProfileProvider {
  @override
  String activeId = 'alice';

  @override
  bool get isBinding => false;

  void changeTo(String id) {
    activeId = id;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  final client = _PleyaLibrary();

  @override
  List<String> get onlineServerIds => [client.serverId];

  @override
  MediaServerClient? getClientForServer(ServerId serverId) => serverId == client.serverId ? client : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PleyaLibrary implements MediaServerClient {
  @override
  final serverId = ServerId('fixture');

  @override
  MediaBackend get backend => MediaBackend.pleyaServer;

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => [
    const MediaLibrary(id: 'shows', backend: MediaBackend.pleyaServer, title: 'Series', kind: MediaKind.show),
  ];

  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    required String libraryName,
    MediaKind? libraryKind,
    int limit = 20,
    bool includePlaybackHubs = true,
  }) async => [
    MediaHub(
      id: 'recently_added',
      title: 'Recent',
      type: 'episode',
      items: [
        MediaItem(
          id: '1',
          backend: backend,
          kind: MediaKind.episode,
          title: 'New episode',
          addedAt: DateTime(2026, 10, 8).millisecondsSinceEpoch ~/ 1000,
        ),
        MediaItem(
          id: '2',
          backend: backend,
          kind: MediaKind.episode,
          title: 'Old episode',
          addedAt: DateTime(2026, 10, 6).millisecondsSinceEpoch ~/ 1000,
        ),
      ],
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('categories require opt-in and the saved choices are scoped to the profile', (tester) async {
    resetSharedPreferencesForTest();
    final profiles = _Profiles();
    addTearDown(profiles.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ActiveProfileProvider>.value(
        value: profiles,
        child: MaterialApp(
          theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS),
          home: const PleyaNotificationsScreen(profileId: 'alice'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final prefs = await BaseSharedPreferencesService.sharedCache();
    const alice = 'pleya.notifications.alice';
    expect(prefs.getString(alice), isNull);
    expect(find.text(t.pleyaNotifications.disabled), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, t.pleyaNotifications.settings));
    await tester.pumpAndSettle();
    final films = find.widgetWithText(SwitchListTile, t.pleyaNotifications.movies);
    expect(tester.widget<SwitchListTile>(films).value, isFalse);
    expect(tester.widget<SwitchListTile>(films).onChanged, isNull);

    await tester.tap(find.text(t.pleyaNotifications.enable));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.pleyaNotifications.movies));
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString(alice)!)['movies'], isA<String>());

    profiles.changeTo('bob');
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(prefs.getString('pleya.notifications.bob'), isNull);
  });

  testWidgets('Pleya Server episodes use the recent hub and respect the consent timestamp', (tester) async {
    resetSharedPreferencesForTest(
      initialAsync: {'pleya.notifications.alice': '{"enabled":true,"episodes":"2026-10-07T00:00:00"}'},
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _Profiles()),
          ChangeNotifierProvider<MultiServerProvider>(create: (_) => _Servers()),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS),
          home: const PleyaNotificationsScreen(profileId: 'alice'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New episode'), findsOneWidget);
    expect(find.text('Old episode'), findsNothing);
    expect(find.text(t.pleyaNotifications.loadPartial), findsNothing);
  });
}

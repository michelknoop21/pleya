import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/widgets/mobile/mobile_unified_context_menu.dart';
import '../../test_helpers/followup_capture.dart';
import '../../test_helpers/golden.dart';
import 'package:provider/provider.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/screens/metadata_edit_screen.dart';
import 'package:pleya/screens/plex_match_screen.dart';
import '../../test_helpers/prefs.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/unified_catalog/unified_management_menu.dart';

class _OwnerManager extends MultiServerManager {
  @override
  bool canManageServerMetadata(ServerId serverId) => true;
}

class _OwnerOf extends _OwnerManager {
  _OwnerOf(this.owned);
  String owned;
  @override
  bool canManageServerMetadata(ServerId serverId) => serverId == ServerId(owned);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFontsForGoldens);
  late AppDatabase db;
  late PlexClient client;
  var requests = 0;
  setUp(() {
    resetSharedPreferencesForTest();
    requests = 0;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://fixture.invalid',
        token: 'fixture',
        clientIdentifier: 'test',
        product: 'Pleya Verify',
        version: 'test',
      ),
      serverId: ServerId('fixture'),
      serverName: 'Fixture',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('Unexpected request', 500);
      }),
    );
  });
  tearDown(() async {
    client.close();
    await db.close();
  });
  Future<BuildContext> mount(WidgetTester tester, Widget child, {_OwnerManager? owner}) async {
    final manager = owner ?? _OwnerManager();
    manager.debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    late BuildContext pageContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return child;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pageContext;
  }

  testWidgets('no server provider means no management actions', (tester) async {
    final item = MediaItem(
      id: 'movie',
      serverId: 'fixture',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Film',
    );
    final source = UnifiedMediaSource.fromItem(item);
    final group = UnifiedMediaGroup(
      groupId: 'fixture',
      identity: CanonicalMediaIdentity.movie(title: 'Film'),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(unifiedManagementChoices(context, group, isOffline: false), isEmpty);
            return const Text('No management source');
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(requests, 0);
  });

  testWidgets('owner catalogue menu exposes artwork and matching', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final context = await mount(tester, const Text('Catalogue'));
    final item = MediaItem(
      id: 'movie',
      serverId: 'fixture',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Film',
    );
    final source = UnifiedMediaSource.fromItem(item);
    final group = UnifiedMediaGroup(
      groupId: 'fixture',
      identity: CanonicalMediaIdentity.movie(title: 'Film'),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
    final opened = showMobileUnifiedQuickMenu(
      context,
      anchor: const Rect.fromLTWH(24, 80, 120, 180),
      group: group,
      availabilityFor: (_) => SourceAvailability.online,
      onPlay: () {},
    );
    unawaited(opened);
    await tester.pumpAndSettle();
    expect(find.text(t.metadataEdit.artwork), findsOneWidget);
    expect(find.text(t.matchScreen.fixMatch), findsOneWidget);
    expect(find.text(t.mediaMenu.deleteFromServer), findsOneWidget);
    await captureFollowup(tester, find.byType(Overlay).last, 'catalogue-owner-management');
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await opened;
    expect(requests, 0);
  });

  testWidgets('stale management choice cannot navigate using a replacement connection', (tester) async {
    final owner = _OwnerManager();
    final stale = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://fixture.invalid',
        token: 'old',
        clientIdentifier: 'old',
        product: 'Pleya Verify',
        version: 'test',
      ),
      serverId: ServerId('fixture'),
      serverName: 'Old',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }),
    );
    addTearDown(stale.close);
    final context = await mount(tester, const Text('Home'), owner: owner);
    final item = MediaItem(
      id: 'movie',
      serverId: 'fixture',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Film',
    );
    await runUnifiedManagementChoice(
      context,
      UnifiedManagementChoice(UnifiedMediaSource.fromItem(item), UnifiedManagementAction.metadata, stale),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MetadataEditScreen), findsNothing);
    expect(requests, 0);
  });

  for (final match in [false, true]) {
    testWidgets('missing source never falls back to another server in ${match ? 'matching' : 'metadata'}', (
      tester,
    ) async {
      final item = MediaItem(
        id: 'movie',
        serverId: 'missing',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Film',
      );
      await mount(tester, match ? PlexMatchScreen(metadata: item) : MetadataEditScreen(metadata: item));
      expect(requests, 0);
      expect(tester.takeException(), isNull);
    });
  }

  test('owner can edit artwork, metadata and matching on films and series', () {
    for (final kind in [MediaKind.movie, MediaKind.show]) {
      expect(
        unifiedManagementActions(client: client, kind: kind, canManage: true, isOffline: false),
        UnifiedManagementAction.values,
      );
    }
  });
  test('read-only and revoked permissions expose no canonical actions', () {
    expect(
      unifiedManagementActions(client: client, kind: MediaKind.movie, canManage: false, isOffline: false),
      isEmpty,
    );
  });
  test('a server with its own delete rule offers only the delete without metadata rights', () {
    expect(
      unifiedManagementActions(
        client: client,
        kind: MediaKind.movie,
        canManage: false,
        canDelete: true,
        isOffline: false,
      ),
      [UnifiedManagementAction.delete],
    );
    expect(
      unifiedManagementActions(
        client: client,
        kind: MediaKind.movie,
        canManage: true,
        canDelete: false,
        isOffline: false,
      ),
      isNot(contains(UnifiedManagementAction.delete)),
    );
  });
  test('offline and disconnected sources expose no canonical actions', () {
    expect(unifiedManagementActions(client: client, kind: MediaKind.movie, canManage: true, isOffline: true), isEmpty);
    expect(unifiedManagementActions(client: null, kind: MediaKind.show, canManage: true, isOffline: false), isEmpty);
  });
  test('episode has artwork editing but cannot be rematched as a film or series', () {
    expect(unifiedManagementActions(client: client, kind: MediaKind.episode, canManage: true, isOffline: false), [
      UnifiedManagementAction.artwork,
      UnifiedManagementAction.metadata,
      UnifiedManagementAction.delete,
    ]);
  });

  group('delete from server', () {
    late List<String> calls;
    late PlexClient second;
    late MediaItem onFixture;
    late MediaItem onSecond;
    setUp(() {
      calls = [];
      PlexClient plex(String id, String name) => PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://$id.invalid',
          token: 'fixture',
          clientIdentifier: 'test',
          product: 'Pleya Verify',
          version: 'test',
        ),
        serverId: ServerId(id),
        serverName: name,
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.host}${request.url.path}');
          return http.Response('', 200);
        }),
      );
      client.close();
      client = plex('fixture', 'Fixture');
      second = plex('second', 'Second');
      MediaItem movie(String server, String name) => MediaItem(
        id: 'movie-$server',
        serverId: server,
        serverName: name,
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Film',
      );
      onFixture = movie('fixture', 'Fixture');
      onSecond = movie('second', 'Second');
    });
    tearDown(() => second.close());

    UnifiedMediaGroup twoServers() {
      final sources = [UnifiedMediaSource.fromItem(onFixture), UnifiedMediaSource.fromItem(onSecond)];
      return UnifiedMediaGroup(
        groupId: 'film',
        identity: CanonicalMediaIdentity.movie(title: 'Film'),
        sources: sources,
        representativeSourceKey: sources.first.sourceKey,
        watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
      );
    }

    Future<BuildContext> mountBoth(WidgetTester tester, _OwnerManager owner) {
      owner.debugRegisterClientForTesting(second);
      return mount(tester, const Text('Alle films'), owner: owner);
    }

    testWidgets('a title on two servers offers one delete per server it may manage', (tester) async {
      final context = await mountBoth(tester, _OwnerManager());
      final deletes = unifiedManagementChoices(
        context,
        twoServers(),
        isOffline: false,
      ).where((c) => c.action == UnifiedManagementAction.delete).toList();
      expect(deletes.map((c) => c.source.serverName), ['Fixture', 'Second']);
      expect(deletes.every((c) => c.destructive), isTrue);
    });

    testWidgets('no rights on a server means no delete for its copy', (tester) async {
      final context = await mountBoth(tester, _OwnerOf('second'));
      final deletes = unifiedManagementChoices(
        context,
        twoServers(),
        isOffline: false,
      ).where((c) => c.action == UnifiedManagementAction.delete);
      expect(deletes.map((c) => c.source.serverName), ['Second']);
    });

    testWidgets('confirming deletes only the named source and reports the change', (tester) async {
      final context = await mountBoth(tester, _OwnerManager());
      final choice = unifiedManagementChoices(
        context,
        twoServers(),
        isOffline: false,
      ).singleWhere((c) => c.action == UnifiedManagementAction.delete && c.source.serverName == 'Second');
      var changed = 0;
      final done = runUnifiedManagementChoice(context, choice, onChanged: () => changed++);
      await tester.pumpAndSettle();
      // The dialog names the server whose copy goes.
      expect(find.text('${t.mediaMenu.deleteFromServer} · Second'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(find.text(t.mediaMenu.deleteFromServer));
      await tester.pumpAndSettle();
      await done;
      expect(calls, ['DELETE second.invalid/library/metadata/movie-second']);
      expect(changed, 1);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final context = await mountBoth(tester, _OwnerManager());
      final choice = unifiedManagementChoices(
        context,
        twoServers(),
        isOffline: false,
      ).firstWhere((c) => c.action == UnifiedManagementAction.delete);
      var changed = 0;
      final done = runUnifiedManagementChoice(context, choice, onChanged: () => changed++);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();
      await done;
      expect(calls, isEmpty);
      expect(changed, 0);
    });

    testWidgets('rights lost while the dialog is open: the server is not asked', (tester) async {
      final owner = _OwnerOf('second');
      final context = await mountBoth(tester, owner);
      final choice = unifiedManagementChoices(
        context,
        twoServers(),
        isOffline: false,
      ).singleWhere((c) => c.action == UnifiedManagementAction.delete);
      var changed = 0;
      final done = runUnifiedManagementChoice(context, choice, onChanged: () => changed++);
      await tester.pumpAndSettle();
      owner.owned = 'none';
      await tester.tap(find.text(t.mediaMenu.deleteFromServer));
      await tester.pumpAndSettle();
      await done;
      expect(calls, isEmpty);
      expect(changed, 0);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}

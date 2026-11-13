/// "Verwijderen van server" in Alle films and Alle series, per backend, with
/// the real owner rule of [MultiServerManager.canManageServerMetadata] and the
/// real clients: who sees the row, which path the DELETE takes, and what the
/// viewer reads when the server refuses.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/unified_catalog/unified_management_menu.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/media_item_deletion.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';

import '../../test_helpers/notice_layer.dart';
import '../../test_helpers/prefs.dart';

/// What every fake server heard, as `METHOD host/path`.
final List<String> _calls = [];

/// The answer to a DELETE; everything else gets an empty 200.
int _deleteStatus = 200;

MockClient _server() => MockClient((request) async {
  _calls.add('${request.method} ${request.url.host}${request.url.path}');
  return http.Response(request.method == 'DELETE' ? '' : '{}', request.method == 'DELETE' ? _deleteStatus : 200);
});

PlexClient _plex() => PlexClient.forTesting(
  config: PlexConfig(
    baseUrl: 'https://plex.example',
    token: 'token',
    clientIdentifier: 'client-id',
    product: 'Pleya',
    version: 'test',
  ),
  serverId: ServerId('plex-1'),
  serverName: 'Plex NAS',
  httpClient: _server(),
);

/// Binds the Plex account the way a profile does, with [owned] as Plex
/// reports it for this server.
Future<void> _bindPlex(MultiServerManager manager, {required bool owned}) => manager.refreshTokensForProfile(
  PlexAccountConnection(
    id: 'account-1',
    accountToken: 'account-token',
    clientIdentifier: 'account-client',
    accountLabel: 'Account',
    servers: [
      PlexServer(
        name: 'Plex NAS',
        clientIdentifier: 'plex-1',
        accessToken: 'token',
        connections: const [],
        owned: owned,
      ),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  ),
);

JellyfinClient _jellyfin({required bool admin, bool emby = false}) => JellyfinClient.forTesting(
  connection: JellyfinConnection(
    id: '${emby ? 'emby' : 'jf'}-1/user-1',
    baseUrl: emby ? 'https://emby.example/emby' : 'https://jf.example',
    serverName: emby ? 'Emby' : 'Jellyfin',
    serverMachineId: emby ? 'emby-1' : 'jf-1',
    userId: 'user-1',
    userName: 'user',
    accessToken: 'token',
    deviceId: 'device',
    isAdministrator: admin,
    isEmby: emby,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  ),
  httpClient: _server(),
);

MediaItem _movie(String serverId, String serverName, MediaBackend backend, String id, {String? libraryTitle}) =>
    MediaItem(
      id: id,
      serverId: serverId,
      serverName: serverName,
      backend: backend,
      kind: MediaKind.movie,
      title: 'Arrival',
      year: 2016,
      libraryTitle: libraryTitle,
    );

UnifiedMediaGroup _group(List<MediaItem> items) {
  final sources = [for (final item in items) UnifiedMediaSource.fromItem(item)];
  return UnifiedMediaGroup(
    groupId: 'arrival',
    identity: CanonicalMediaIdentity.movie(title: 'Arrival', year: 2016),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    resetSharedPreferencesForTest();
    resetNotices();
    _calls.clear();
    _deleteStatus = 200;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });
  tearDown(() async {
    resetNotices();
    await db.close();
  });

  Future<BuildContext> mount(WidgetTester tester, MultiServerManager manager) async {
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    late BuildContext pageContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          builder: noticeLayer,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const Text('Alle films');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pageContext;
  }

  List<UnifiedManagementChoice> deletes(BuildContext context, UnifiedMediaGroup group) => unifiedManagementChoices(
    context,
    group,
    isOffline: false,
  ).where((c) => c.action == UnifiedManagementAction.delete).toList();

  /// Runs [choice] and presses the confirm button of the dialog.
  Future<void> confirm(WidgetTester tester, BuildContext context, UnifiedManagementChoice choice) async {
    final before = _calls.where((c) => c.startsWith('DELETE')).length;
    final done = runUnifiedManagementChoice(context, choice);
    await tester.pumpAndSettle();
    expect(
      _calls.where((c) => c.startsWith('DELETE')),
      hasLength(before),
      reason: 'nothing goes out before the confirm',
    );
    await tester.tap(find.widgetWithText(FilledButton, t.mediaMenu.deleteFromServer));
    await tester.pumpAndSettle();
    await done;
  }

  List<String> deleteCalls() => _calls.where((c) => c.startsWith('DELETE')).toList();

  group('Plex', () {
    Future<MultiServerManager> plexManager({required bool owned}) async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(_plex());
      await _bindPlex(manager, owned: owned);
      return manager;
    }

    final group = _group([_movie('plex-1', 'Plex NAS', MediaBackend.plex, '4711')]);

    testWidgets('owner: the row is there and the DELETE goes to /library/metadata/{ratingKey}', (tester) async {
      final manager = await tester.runAsync(() => plexManager(owned: true));
      final context = await mount(tester, manager!);
      final rows = deletes(context, group);
      expect(rows, hasLength(1));
      await confirm(tester, context, rows.single);
      expect(deleteCalls(), ['DELETE plex.example/library/metadata/4711']);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a server shared with the account (not owned): no row', (tester) async {
      final manager = await tester.runAsync(() => plexManager(owned: false));
      final context = await mount(tester, manager!);
      expect(deletes(context, group), isEmpty);
    });

    testWidgets('a restricted or non-admin Home member on an owned server: no row', (tester) async {
      final manager = await tester.runAsync(() => plexManager(owned: true));
      manager!.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      final context = await mount(tester, manager);
      expect(deletes(context, group), isEmpty);
    });
  });

  for (final emby in [false, true]) {
    final name = emby ? 'Emby' : 'Jellyfin';
    final serverId = emby ? 'emby-1' : 'jf-1';
    final path = emby ? 'DELETE emby.example/emby/Items/item-9' : 'DELETE jf.example/Items/item-9';
    final backend = MediaBackend.jellyfin;

    group(name, () {
      MultiServerManager manager({required bool admin}) {
        final m = MultiServerManager();
        addTearDown(m.dispose);
        m.debugRegisterJellyfinClientForTesting(_jellyfin(admin: admin, emby: emby));
        return m;
      }

      final group = _group([_movie(serverId, name, backend, 'item-9')]);

      testWidgets('administrator: the row is there and the DELETE goes to /Items/{id}', (tester) async {
        final context = await mount(tester, manager(admin: true));
        final rows = deletes(context, group);
        expect(rows, hasLength(1));
        await confirm(tester, context, rows.single);
        expect(deleteCalls(), [path]);
        await tester.pump(const Duration(seconds: 10));
      });

      testWidgets('ordinary user: no row', (tester) async {
        final context = await mount(tester, manager(admin: false));
        expect(deletes(context, group), isEmpty);
      });

      for (final status in [401, 403]) {
        testWidgets('a $status on the delete says the account may not delete there', (tester) async {
          _deleteStatus = status;
          final context = await mount(tester, manager(admin: true));
          await confirm(tester, context, deletes(context, group).single);
          expect(deleteCalls(), [path]);
          expect(noticeController.visible.map((e) => e.notice.title), contains(t.mediaMenu.deletionForbidden));
          await tester.pump(const Duration(seconds: 10));
        });
      }
    });
  }

  testWidgets('Plex 403 on the delete says this account may not delete on that server', (tester) async {
    _deleteStatus = 403;
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    manager.debugRegisterClientForTesting(_plex());
    await tester.runAsync(() => _bindPlex(manager, owned: true));
    final context = await mount(tester, manager);
    await confirm(
      tester,
      context,
      deletes(context, _group([_movie('plex-1', 'Plex NAS', MediaBackend.plex, '4711')])).single,
    );
    expect(noticeController.visible.map((e) => e.notice.title), contains(t.mediaMenu.plexDeletionForbidden));
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('Plex 401 on the delete asks to sign in again, not for a server setting', (tester) async {
    _deleteStatus = 401;
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    manager.debugRegisterClientForTesting(_plex());
    await tester.runAsync(() => _bindPlex(manager, owned: true));
    final context = await mount(tester, manager);
    await confirm(
      tester,
      context,
      deletes(context, _group([_movie('plex-1', 'Plex NAS', MediaBackend.plex, '4711')])).single,
    );
    final shown = noticeController.visible.map((e) => e.notice.title);
    expect(shown, contains(t.connections.reauthRequired));
    expect(shown, isNot(contains(t.mediaMenu.deletionForbidden)));
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('one title on Plex (owner) and Jellyfin (admin): two named rows, each deletes only its own copy', (
    tester,
  ) async {
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    manager.debugRegisterClientForTesting(_plex());
    await tester.runAsync(() => _bindPlex(manager, owned: true));
    manager.debugRegisterJellyfinClientForTesting(_jellyfin(admin: true));
    final context = await mount(tester, manager);
    final group = _group([
      _movie('plex-1', 'Plex NAS', MediaBackend.plex, '4711'),
      _movie('jf-1', 'Jellyfin', MediaBackend.jellyfin, 'item-9'),
    ]);

    final rows = deletes(context, group);
    expect(
      [for (final row in rows) managementLabel(group, row)],
      ['${t.mediaMenu.deleteFromServer} · Plex NAS', '${t.mediaMenu.deleteFromServer} · Jellyfin'],
    );

    await confirm(tester, context, rows.last);
    expect(deleteCalls(), ['DELETE jf.example/Items/item-9']);
    await tester.pump(const Duration(seconds: 10));
    await confirm(tester, context, rows.first);
    expect(deleteCalls(), ['DELETE jf.example/Items/item-9', 'DELETE plex.example/library/metadata/4711']);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('two copies on one Plex server: each row and dialog names its library, and deletes only that copy', (
    tester,
  ) async {
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    manager.debugRegisterClientForTesting(_plex());
    await tester.runAsync(() => _bindPlex(manager, owned: true));
    final context = await mount(tester, manager);
    final group = _group([
      _movie('plex-1', 'Plex NAS', MediaBackend.plex, '4711', libraryTitle: 'Films'),
      _movie('plex-1', 'Plex NAS', MediaBackend.plex, '4712', libraryTitle: '4K Films'),
    ]);

    final rows = deletes(context, group);
    final labels = [for (final row in rows) managementLabel(group, row)];
    expect(labels, [
      '${t.mediaMenu.deleteFromServer} · Plex NAS · Films',
      '${t.mediaMenu.deleteFromServer} · Plex NAS · 4K Films',
    ]);
    expect(rows.map((r) => r.automationInstance).toSet(), hasLength(2));

    final done = runUnifiedManagementChoice(context, rows.last);
    await tester.pumpAndSettle();
    expect(find.text('${t.mediaMenu.deleteFromServer} · Plex NAS · 4K Films'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, t.mediaMenu.deleteFromServer));
    await tester.pumpAndSettle();
    await done;
    expect(deleteCalls(), ['DELETE plex.example/library/metadata/4712']);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a client for another server than the item\'s is refused before anything is sent', (tester) async {
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final other = _jellyfin(admin: true);
    final context = await mount(tester, manager);
    // What `getMediaClientWithFallback` hands back once the item's own server
    // is gone: the first one that is online.
    final done = confirmAndDeleteMediaItem(
      context,
      item: _movie('plex-gone', 'Plex NAS', MediaBackend.plex, '4711'),
      client: () => other,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, t.mediaMenu.deleteFromServer));
    await tester.pumpAndSettle();
    expect(await done, isFalse);
    expect(deleteCalls(), isEmpty);
    expect(noticeController.visible.map((e) => e.notice.title), contains(t.mediaMenu.deleteServerGone));
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a partly failed delete that left the title tells the caller to refresh, and removes nothing', (
    tester,
  ) async {
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final context = await mount(tester, manager);
    var refreshed = 0;
    final done = confirmAndDeleteMediaItem(
      context,
      item: _movie('pleya-1', 'Pleya', MediaBackend.pleyaServer, 'item-1'),
      client: () => _PartlyDeletingClient(),
      onPartlyDeleted: () => refreshed++,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(t.mediaMenu.pleyaServerDeletesFiles), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, t.mediaMenu.deleteFromServer));
    await tester.pumpAndSettle();
    expect(await done, isFalse);
    expect(refreshed, 1);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('the confirmation names the title', (tester) async {
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    manager.debugRegisterJellyfinClientForTesting(_jellyfin(admin: true));
    final context = await mount(tester, manager);
    final done = runUnifiedManagementChoice(
      context,
      deletes(context, _group([_movie('jf-1', 'Jellyfin', MediaBackend.jellyfin, 'item-9')])).single,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Arrival'), findsOneWidget);
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    await done;
  });
}

class _PartlyDeletingClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('pleya-1');

  @override
  Future<bool> deleteMediaItem(MediaItem item) async =>
      throw const MediaDeletionIncompleteException(removedFiles: 1, failedPaths: ['Arrival/extra.mkv']);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

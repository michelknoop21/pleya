/// The owner rule on the collection screen: deleting a collection and
/// removing an item from it are canonical server writes, so a profile without
/// owner rights never sees either action.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/collection_detail_screen.dart';
import 'package:pleya/screens/tv/tv_collection_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

class _AuthorityManager extends MultiServerManager {
  bool canManage = false;

  @override
  bool canManageServerMetadata(ServerId serverId) => canManage;
}

class _CollectionClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    AbortController? abort,
    String? libraryId,
    String? libraryTitle,
  }) async => const LibraryPage(items: [], totalCount: 0);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _AuthorityManager manager;
  late MultiServerProvider multiServer;

  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    TvDetectionService.debugSetAppleTVOverride(true);
    manager = _AuthorityManager()..debugRegisterClientForTesting(_CollectionClient());
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    multiServer.dispose();
    manager.dispose();
  });

  Future<TvCollectionScreen> pumpScreen(WidgetTester tester, {Map<String, dynamic>? raw}) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: multiServer,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: CollectionDetailScreen(
              collection: MediaItem(
                id: 'col-1',
                backend: MediaBackend.plex,
                kind: MediaKind.collection,
                title: 'Blender',
                serverId: 'nas',
                raw: raw,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<TvCollectionScreen>(find.byType(TvCollectionScreen));
  }

  testWidgets('non-owner gets no delete and no remove-from-collection', (tester) async {
    manager.canManage = false;
    final screen = await pumpScreen(tester);
    expect(screen.onDelete, isNull);
    expect(screen.onRemoveItem, isNull);
    expect(find.text(t.common.delete), findsNothing);
  });

  testWidgets('owner gets no action on a collection the server says is someone else\'s', (tester) async {
    manager.canManage = true;
    final screen = await pumpScreen(tester, raw: const {'is_owner': false});
    expect(screen.onDelete, isNull);
    expect(screen.onRemoveItem, isNull);
  });

  testWidgets('owner gets delete and remove-from-collection', (tester) async {
    manager.canManage = true;
    final screen = await pumpScreen(tester);
    expect(screen.onDelete, isNotNull);
    expect(screen.onRemoveItem, isNotNull);
    expect(find.text(t.common.delete), findsOneWidget);
  });

  // The grid needs the download and settings stack, so this reads the source. The
  // id on a card is what offers "remove from collection" in its context menu, and
  // that menu cannot see `is_owner`: it holds the film, not the collection.
  test('a card only carries the collection when this viewer may change it', () {
    final source = File('lib/screens/collection_detail_screen.dart').readAsStringSync();
    expect(source, contains('collectionId: _canManageCollection ? widget.collection.id : null'));
  });
}

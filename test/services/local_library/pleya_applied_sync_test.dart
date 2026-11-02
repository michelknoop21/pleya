import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/identity_lookup_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import 'package:pleya/models/pleya_server/pleya_wire.dart';
import 'package:pleya/models/pleya_server/pleya_wire_library.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/services/local_library/local_library_sync.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';

const _library = MediaLibrary(
  id: 'films',
  backend: MediaBackend.pleyaServer,
  title: 'Films',
  kind: MediaKind.movie,
  serverId: 'srv-1',
);

MediaItem _row({int? applied, bool legacy = false}) => MediaItem(
  id: 'film',
  backend: MediaBackend.pleyaServer,
  kind: MediaKind.movie,
  title: 'Film',
  serverId: 'srv-1',
  libraryId: 'films',
  updatedAt: 42,
  raw: {
    pleyaExternalIdsSourceKey: legacy ? 'legacy' : 'applied',
    if (applied != null) pleyaExternalIdsRawKey: {'tmdb': applied},
  },
);

class _RetainedPleya implements PleyaServerClient {
  MediaItem row = _row(applied: 11);
  bool lookupFails = false;
  bool applied = true;
  final lookupEntered = Completer<void>();
  Future<({ExternalIds ids, bool authoritative, String source})>? delayedAnswer;
  int detailCalls = 0;
  @override
  ServerId get serverId => ServerId('srv-1');
  @override
  bool get isOfflineMode => false;
  @override
  bool get identityCapabilitiesKnown => true;
  @override
  String get externalIdentitySource => applied ? 'applied' : 'legacy';
  @override
  PleyaCapabilities get wireCapabilities => PleyaCapabilities(
    browse: true,
    search: true,
    artwork: false,
    watchState: false,
    appliedExternalIdentity: applied,
  );
  @override
  bool canUseStoredExternalIds(MediaItem item) => hasAppliedExternalIds(item) || !applied;
  @override
  Future<MediaItem?> fetchItem(String id) async {
    detailCalls++;
    return row;
  }

  @override
  Future<({ExternalIds ids, bool authoritative, String source})> fetchExternalIdsDetailed(String id) async {
    if (delayedAnswer != null) {
      if (!lookupEntered.isCompleted) lookupEntered.complete();
      return delayedAnswer!;
    }
    if (lookupFails) throw const IdentityLookupUnavailable('synthetic unavailable');
    return (ids: const ExternalIds(), authoritative: false, source: externalIdentitySource);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
    bool strictSnapshot = false,
    bool Function(PleyaItem)? itemFilter,
  }) async => LibraryPage(items: query.offset == 0 ? [row] : [], totalCount: 1, offset: query.offset);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  test(
    'retained equal-timestamp row replaces old proof and clears it on fresh unknown or lookup failure, through persisted snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp('pleya-applied-retained-');
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalLibraryStore(directory);
      await store.load();
      await store.saveLibrary(_library, [
        _row(applied: 22, legacy: true).copyWith(
          raw: {
            ...?_row(applied: 22, legacy: true).raw,
            'pleyaLocalExternalIds': {'tmdb': 22},
            'pleyaLocalExternalIdsFinal': true,
          },
        ),
      ], complete: true);
      final client = _RetainedPleya();
      await LocalLibrarySync(store: store).syncLibrary(_library, client);
      expect(client.detailCalls, 0, reason: 'same updatedAt/title/poster retains descriptive row');
      expect(externalIdsCarriedBy(store.items.single), const ExternalIds(tmdb: 11));
      expect(store.items.single.raw?['pleyaLocalExternalIds'], {'tmdb': 11});
      for (final fails in [false, true]) {
        client.row = _row();
        client.lookupFails = fails;
        await LocalLibrarySync(store: store).syncLibrary(_library, client);
        final reopened = LocalLibraryStore(directory);
        await reopened.load();
        expect(externalIdsCarriedBy(reopened.items.single), isNull);
        expect(reopened.items.single.raw?['pleyaLocalExternalIdsFinal'], isNot(true));
        expect((reopened.items.single.raw?['pleyaLocalExternalIds'] as Map?)?['tmdb'], isNull);
        expect(reopened.items.single.title, 'Film');
      }
    },
  );
  test('a held legacy answer is never stamped applied after the capability changes during sync', () async {
    final directory = await Directory.systemTemp.createTemp('pleya-held-proof-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalLibraryStore(directory);
    await store.load();
    final answer = Completer<({ExternalIds ids, bool authoritative, String source})>();
    final client = _RetainedPleya()
      ..applied = false
      ..row = _row(legacy: true)
      ..delayedAnswer = answer.future;
    final syncing = LocalLibrarySync(store: store).syncLibrary(_library, client);
    await client.lookupEntered.future;
    client.applied = true;
    answer.complete((ids: const ExternalIds(tmdb: 22), authoritative: true, source: 'legacy'));
    await syncing;
    final reopened = LocalLibraryStore(directory);
    await reopened.load();
    expect(hasAppliedExternalIds(reopened.items.single), isFalse);
    expect(externalIdsCarriedBy(reopened.items.single), isNull);
  });
}

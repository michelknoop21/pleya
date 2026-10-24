import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/services/local_library/local_library_sync.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/external_ids.dart';
import 'local_library_store_test.dart' show library, film;

class Client implements MediaServerClient {
  List<MediaItem> rows = [film('a'), film('b')];
  int? failOffset;
  Completer<void>? gate;
  final entered = Completer<void>();
  bool repeat = false;
  bool childrenFail = false;
  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    if (childrenFail) throw StateError('Unverified child page');
    return LibraryPage(items: [], totalCount: 0, offset: start ?? 0);
  }

  @override
  ServerId get serverId => ServerId('one');
  @override
  bool get isOfflineMode => false;
  @override
  Future<ExternalIds> fetchExternalIds(String id) async => const ExternalIds();
  @override
  Future<MediaItem?> fetchItem(String id) async => rows.where((i) => i.id == id).firstOrNull;
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (query.offset == failOffset) throw const SocketException('fixture offline');
    final start = repeat ? 0 : query.offset;
    return LibraryPage(
      items: rows.skip(start).take(query.limit).toList(),
      totalCount: rows.length,
      offset: query.offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late Directory root;
  late LocalLibraryStore store;
  late Client client;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pleya-library-sync-test-');
    store = LocalLibraryStore(root);
    await store.load();
    client = Client();
  });
  tearDown(() async => root.delete(recursive: true));

  test('unverified children preserve descendants; confirmed empty children remove them', () async {
    final shows = library.copyWith(kind: MediaKind.show);
    final show = film('show').copyWith(kind: MediaKind.show);
    final episode = film('ep').copyWith(kind: MediaKind.episode, parentId: 'season', grandparentId: 'show');
    await store.saveLibrary(shows, [show, episode], complete: true);
    client.rows = [show];
    client.childrenFail = true;
    await expectLater(LocalLibrarySync(store: store).syncLibrary(shows, client), throwsStateError);
    expect(store.items.map((i) => i.id), contains('ep'));
    client.childrenFail = false;
    await LocalLibrarySync(store: store).syncLibrary(shows, client);
    expect(store.items.map((i) => i.id), ['show']);
  });

  test('successful complete scan removes confirmed missing rows', () async {
    await store.saveLibrary(library, [film('removed')], complete: true);
    await LocalLibrarySync(store: store, pageSize: 1).syncLibrary(library, client);
    expect(store.items.map((i) => i.id), ['a', 'b']);
  });

  test('failed next page never deletes the previous snapshot', () async {
    await store.saveLibrary(library, [film('old')], complete: true);
    client.failOffset = 1;
    await expectLater(
      LocalLibrarySync(store: store, pageSize: 1).syncLibrary(library, client),
      throwsA(isA<SocketException>()),
    );
    expect(store.items.map((i) => i.id), contains('old'));
  });

  test('cancelled response cannot recreate a cleared library', () async {
    client.gate = Completer<void>();
    var current = true;
    final pending = LocalLibrarySync(store: store).syncLibrary(library, client, isCurrent: () => current);
    await client.entered.future;
    final checked = expectLater(pending, throwsA(isA<LocalLibraryPaused>()));
    current = false;
    await store.clear();
    client.gate!.complete();
    await checked;
    expect(store.items, isEmpty);
  });

  test('server ignoring pagination is an error rather than a successful partial scan', () async {
    await store.saveLibrary(library, [film('old')], complete: true);
    client.repeat = true;
    await expectLater(
      LocalLibrarySync(store: store, pageSize: 1).syncLibrary(library, client),
      throwsA(isA<StateError>()),
    );
    expect(store.items.map((i) => i.id), contains('old'));
  });

  test('low storage pauses before fetching and preserves cached rows', () async {
    await store.saveLibrary(library, [film('old')], complete: true);
    await expectLater(
      LocalLibrarySync(store: store, mayContinue: () async => false).syncLibrary(library, client),
      throwsA(isA<LocalLibraryPaused>()),
    );
    expect(store.items.single.id, 'old');
  });
}

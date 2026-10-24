import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/services/local_library/local_library_store.dart';

const library = MediaLibrary(
  id: 'films',
  backend: MediaBackend.plex,
  title: 'Films',
  kind: MediaKind.movie,
  serverId: 'one',
);
MediaItem film(String id) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: id,
  serverId: 'one',
  libraryId: 'films',
  thumbPath: '/shared-poster',
);

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('pleya-local-library-test-'));
  tearDown(() async => root.delete(recursive: true));

  test('metadata and settings survive reopening the same profile only', () async {
    final store = LocalLibraryStore(root);
    await store.load();
    await store.setOptions(enabled: true, wifiOnly: false);
    await store.saveLibrary(library, [film('a')], complete: true);
    final reopened = LocalLibraryStore(root);
    await reopened.load();
    expect(reopened.items.single.title, 'a');
    expect(reopened.enabled, isTrue);
    expect(reopened.wifiOnly, isFalse);
    final other = LocalLibraryStore(Directory('${root.path}/other-profile'));
    await other.load();
    expect(other.items, isEmpty);
    expect(other.enabled, isFalse);
  });

  test('incomplete scan preserves old titles; complete scan removes missing ones', () async {
    final store = LocalLibraryStore(root);
    await store.load();
    await store.saveLibrary(library, [film('a'), film('b')], complete: true);
    await store.saveLibrary(library, [film('a')], complete: false);
    expect(store.items.map((i) => i.id), containsAll(['a', 'b']));
    await store.saveLibrary(library, [film('a')], complete: true);
    expect(store.items.map((i) => i.id), ['a']);
  });

  test('shared artwork survives until its last reference disappears', () async {
    final store = LocalLibraryStore(root);
    await store.load();
    await store.saveLibrary(library, [film('a'), film('b')], complete: true);
    await store.savePoster('one', '/shared-poster', Uint8List.fromList([1, 2, 3]));
    final path = store.posterPath('one', '/shared-poster');
    expect(path, isNotNull);
    await store.saveLibrary(library, [film('b')], complete: true);
    expect(File(path!).existsSync(), isTrue);
    await store.saveLibrary(library, [], complete: true);
    expect(File(path).existsSync(), isFalse);
    expect(store.posterPath('one', '/shared-poster'), isNull);
  });

  test('updated poster bytes get a new image identity and old version is retired', () async {
    final store = LocalLibraryStore(root);
    await store.load();
    await store.saveLibrary(library, [film('a')], complete: true);
    await store.savePoster('one', '/shared-poster', Uint8List.fromList([1]));
    final first = store.posterPath('one', '/shared-poster')!;
    await store.savePoster('one', '/shared-poster', Uint8List.fromList([2]));
    final second = store.posterPath('one', '/shared-poster')!;
    expect(second, isNot(first), reason: 'Flutter must not reuse decoded bytes of the old poster');
    await store.saveLibrary(library, [film('a')], complete: true);
    expect(File(second).existsSync(), isTrue);
    expect(File(first).existsSync(), isFalse);
  });

  test('confirmed series removal deletes descendants without completing a partial scan', () async {
    final store = LocalLibraryStore(root);
    await store.load();
    await store.saveLibrary(library.copyWith(kind: MediaKind.show), [
      film('show').copyWith(kind: MediaKind.show),
      film('season').copyWith(kind: MediaKind.season, parentId: 'show'),
      film('episode').copyWith(kind: MediaKind.episode, parentId: 'season'),
      film('unrelated'),
    ], complete: false);
    await store.removeConfirmed('one', 'show');
    expect(store.items.map((i) => i.id), ['unrelated']);
    expect(store.isComplete('one:films'), isFalse);
    final reopened = LocalLibraryStore(root);
    await reopened.load();
    expect(reopened.items.map((i) => i.id), ['unrelated']);
    expect(reopened.isComplete('one:films'), isFalse);
  });

  test('clear stops prefetch and invalidated late writes cannot refill it', () async {
    final store = LocalLibraryStore(root);
    await store.load();
    await store.setOptions(enabled: true);
    var valid = true;
    final lateWrite = store.saveLibrary(library, [film('late')], complete: true, isCurrent: () => valid);
    valid = false;
    await store.clear();
    await lateWrite;
    expect(store.items, isEmpty);
    expect(store.enabled, isFalse);
    final reopened = LocalLibraryStore(root);
    await reopened.load();
    expect(reopened.items, isEmpty);
    expect(reopened.enabled, isFalse);
  });
}

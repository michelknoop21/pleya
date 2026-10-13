import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/widgets/library_cover_artwork.dart';
import 'package:pleya/widgets/optimized_media_image.dart';

class _Client implements MediaServerClient {
  final List<MediaItem> members;
  _Client(this.members);

  int calls = 0;
  int? requestedSize;
  AbortController? lastAbort;
  Completer<LibraryPage<MediaItem>>? pending;

  @override
  ServerId get serverId => ServerId('s');
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  String thumbnailUrl(String? path, {int? width, int? height}) => '';
  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String id, {
    int? start,
    int? size,
    AbortController? abort,
    String? libraryId,
    String? libraryTitle,
  }) async {
    calls++;
    requestedSize = size;
    lastAbort = abort;
    return pending?.future ?? LibraryPage(items: members, totalCount: members.length);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, AbortController? abort}) =>
      fetchCollectionPage(id, start: start, size: size, abort: abort);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _member(String id) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: id,
  thumbPath: '/poster/$id',
  serverId: 's',
);

MediaItem _collection({String? thumb, int updated = 1}) => MediaItem(
  id: 'collection',
  backend: MediaBackend.plex,
  kind: MediaKind.collection,
  title: 'Collection',
  serverId: 's',
  thumbPath: thumb,
  updatedAt: updated,
);

void main() {
  Future<void> pumpCover(WidgetTester tester, Object item, _Client client) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: LibraryCoverArtwork(item: item, client: client, fallbackIcon: Icons.collections),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an existing server cover wins without fetching members', (tester) async {
    final client = _Client([_member('a')]);
    await pumpCover(tester, _collection(thumb: '/own'), client);
    expect(client.calls, 0);
    expect(tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).imagePath, '/own');
  });

  for (final count in [1, 2, 3, 4]) {
    testWidgets('$count members keep exactly $count original positions and the approved geometry', (tester) async {
      final client = _Client(List.generate(count, (i) => _member('$i')));
      await pumpCover(tester, _collection(), client);
      expect(client.calls, 1);
      expect(client.requestedSize, 4);
      final images = tester.widgetList<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).toList();
      expect(images.map((image) => image.imagePath).toList(), List.generate(count, (i) => '/poster/$i'));
      final finders = find.byType(OptimizedMediaImage);
      final rects = [for (var i = 0; i < count; i++) tester.getRect(finders.at(i))];
      final origin = tester.getTopLeft(find.byType(LibraryCoverCollage));
      if (count == 1) expect(rects.single, origin & const Size(200, 300));
      if (count == 2) {
        expect(rects[0], origin & const Size(100, 300));
        expect(rects[1], (origin + const Offset(100, 0)) & const Size(100, 300));
        expect(images.every((image) => image.fit == BoxFit.contain), isTrue);
        expect(images.every((image) => image.requestSize == const Size(200, 300)), isTrue);
      }
      if (count == 3) {
        expect(rects[0].width, closeTo(200 * 2 / 3, 0.01));
        expect(rects[0].height, 300);
        expect(rects[2].top - origin.dy, 150);
      }
      if (count == 4) {
        expect(rects.every((rect) => rect.size == const Size(100, 150)), isTrue);
        expect(rects.last.topLeft - origin, const Offset(100, 150));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('playlist duplicates remain real positions and a fifth member is excluded', (tester) async {
    final client = _Client(['a', 'b', 'a', 'c', 'd'].map(_member).toList());
    const playlist = MediaPlaylist(
      id: 'p',
      backend: MediaBackend.plex,
      title: 'List',
      playlistType: 'video',
      serverId: 's',
    );
    await pumpCover(tester, playlist, client);
    expect(tester.widgetList<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).map((image) => image.imagePath), [
      '/poster/a',
      '/poster/b',
      '/poster/a',
      '/poster/c',
    ]);
  });

  testWidgets('a late member response cannot replace a newly supplied own cover', (tester) async {
    final client = _Client([_member('a')])..pending = Completer<LibraryPage<MediaItem>>();
    await pumpCover(tester, _collection(), client);
    final abort = client.lastAbort!;
    await pumpCover(tester, _collection(thumb: '/new-own', updated: 2), client);
    expect(abort.isAborted, isTrue);
    client.pending!.complete(LibraryPage(items: client.members, totalCount: 1));
    await tester.pump();
    expect(tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).imagePath, '/new-own');
    expect(find.byType(LibraryCoverCollage), findsNothing);
  });
}

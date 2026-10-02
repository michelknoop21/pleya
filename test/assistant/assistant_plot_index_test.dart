import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_plot_index.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';

MediaItem _item(String id, String title, {String? summary, MediaKind kind = MediaKind.movie}) =>
    MediaItem(id: id, backend: MediaBackend.jellyfin, kind: kind, title: title, summary: summary);

class _Server implements MediaServerClient {
  _Server(this.libraries, {this.fail = const {}});
  final Map<String, List<MediaItem>> libraries;
  final Set<String> fail;
  final asked = <String>[];

  @override
  ServerId get serverId => ServerId('s');

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryContent(String libraryId, LibraryQuery query) async {
    asked.add(libraryId);
    if (fail.contains(libraryId)) throw StateError('down');
    expect(query.withTasteFields, isTrue);
    final all = libraries[libraryId] ?? const [];
    return LibraryPage(items: all.skip(query.offset).take(query.limit).toList(), totalCount: all.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('BM25 ranks the synopsis that fits, accents and stopwords folded away', () {
    final index = AssistantPlotIndex([
      AssistantPlotDoc('s', _item('1', 'Amélie', summary: 'Een verlegen serveerster in Parijs helpt anderen.')),
      AssistantPlotDoc('s', _item('2', 'Heat', summary: 'A detective hunts a crew of bank robbers.')),
      AssistantPlotDoc('s', _item('3', 'Up', summary: 'An old man ties balloons to his house.', kind: MediaKind.show)),
    ]);
    expect(index.search(['de verlegen serveerster']).first.doc.item.title, 'Amélie');
    expect(index.search(['amelie']).single.doc.item.id, '1');
    expect(index.search(['the of and']), isEmpty);
    expect(index.search(['balloons house'], kind: MediaKind.movie), isEmpty);
    expect(plotTokens('Het is een film'), isEmpty);
  });

  test('reads only the libraries it is given, and keeps the index for its ttl', () async {
    var now = DateTime(2026, 10, 2);
    final server = _Server({
      'films': [_item('1', 'Heat'), _item('2', 'Up')],
      'hidden': [_item('3', 'Secret')],
    });
    final cache = AssistantPlotIndexCache(pageSize: 1, now: () => now);
    final sources = [(client: server as MediaServerClient, libraryId: 'films', kind: MediaKind.movie)];

    final index = await cache.indexFor(sources);
    expect(index.length, 2);
    expect(server.asked, ['films', 'films']);
    expect(identical(await cache.indexFor(sources), index), isTrue);

    now = now.add(const Duration(minutes: 31));
    await cache.indexFor(sources);
    expect(server.asked.where((l) => l == 'hidden'), isEmpty);
    expect(server.asked, hasLength(4));
  });

  test('a library that fails marks the index partial, the rest stays', () async {
    final server = _Server(
      {
        'films': [_item('1', 'Heat')],
      },
      fail: {'broken'},
    );
    final index = await AssistantPlotIndexCache().indexFor([
      (client: server, libraryId: 'broken', kind: MediaKind.movie),
      (client: server, libraryId: 'films', kind: MediaKind.movie),
    ]);
    expect(index.partial, isTrue);
    expect(index.length, 1);
  });

  test('the cap stops the build and flags it', () async {
    final server = _Server({
      'films': [for (var i = 0; i < 5; i++) _item('$i', 'Film $i')],
    });
    final index = await AssistantPlotIndexCache(
      cap: 3,
      pageSize: 2,
    ).indexFor([(client: server, libraryId: 'films', kind: MediaKind.movie)]);
    expect(index.length, 3);
    expect(index.partial, isTrue);
  });
}

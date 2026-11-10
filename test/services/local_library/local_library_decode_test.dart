import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/local_library/local_library_decode.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('pleya-local-library-decode-test-'));
  tearDown(() async => root.delete(recursive: true));

  // Same layout as LocalLibraryStore writes: head, rows separated by commas, tail.
  String write(Iterable<String> rows, {String tail = '],"completed":null,"scanned":null,"scannedUpdatedAt":null}'}) {
    final head = jsonEncode({
      'library': {
        'id': 's',
        'backend': 'plex',
        'title': 'Series [4K] {"x"}',
        'kind': 'show',
        'serverId': 'one',
        'serverName': 'Thuis',
      },
    });
    final file = File('${root.path}/library-s.json').openSync(mode: FileMode.write);
    file.writeStringSync('${head.substring(0, head.length - 1)},"items":[');
    var first = true;
    for (final row in rows) {
      file.writeStringSync(first ? row : ',$row');
      first = false;
    }
    file
      ..writeStringSync(tail)
      ..closeSync();
    return '${root.path}/library-s.json';
  }

  test('rows with brackets, quotes and multibyte text load back unchanged and in order', () {
    // About 1.4 MB, so rows, escapes and multibyte characters all straddle the
    // 64 KB read blocks; raw carries nested lists and maps that look like rows.
    final items = [
      for (var i = 0; i < 300; i++)
        MediaItem.plex(
          id: '$i',
          kind: MediaKind.episode,
          title: r'a]"},{"\ ★ 日本語 😀',
          summary: r'\"]}[{★😀' * (150 + i),
          serverId: 'one',
          libraryId: 's',
          raw: {
            'backend': 'plex',
            'kind': 'movie',
            'Children': [
              {'backend': 'plex', 'kind': 'movie', 'id': ']'},
              [
                1,
                [
                  2,
                  {'a': '}{'},
                ],
              ],
            ],
          },
        ),
    ];

    final result = decodeLibraryFile(
      write(
        items.map((item) => jsonEncode(item.toJson())),
        tail:
            '],"completed":"2026-11-10T11:14:27.000","scanned":"2026-11-10T11:12:02.000","scannedUpdatedAt":1730000000}',
      ),
    );

    expect(result.rows.keys, [for (final item in items) item.globalKey]);
    expect(
      [for (final row in result.rows.values) jsonEncode(row.toJson())],
      [for (final item in items) jsonEncode(item.toJson())],
    );
    expect(result.library.title, 'Series [4K] {"x"}');
    expect(result.completed, DateTime(2026, 11, 10, 11, 14, 27));
    expect(result.scanned, DateTime(2026, 11, 10, 11, 12, 2));
    expect(result.scannedUpdatedAt, 1730000000);
  });

  test('an empty library loads without rows', () {
    final result = decodeLibraryFile(write(const []));

    expect(result.rows, isEmpty);
    expect(result.library.id, 's');
    expect(result.completed, isNull);
  });

  test('loading a large index peaks under four times its file size', () {
    // 52,000 episode rows of about 1.7 KB, the row size of the index on the
    // bedroom Apple TV. Decoding the file as one JSON tree peaked at about 5
    // times the file size on the host; row by row it stays near 2.5 times.
    final row = MediaItem.plex(
      id: '0',
      kind: MediaKind.episode,
      guid: 'plex://episode/5d9c08000000000000000000',
      title: 'Aflevering 7: de lange weg naar huis',
      titleSort: 'Aflevering 7',
      summary: 'Samenvatting. ${'Een stad, een geheim en iemand die terugkomt na jaren weg te zijn geweest. ' * 6}',
      year: 2021,
      originallyAvailableAt: '2021-03-14',
      contentRating: '12',
      parentId: '50000',
      parentTitle: 'Seizoen 3',
      parentThumbPath: '/library/metadata/50000/thumb/1730000000',
      parentIndex: 3,
      index: 7,
      grandparentId: '9000',
      grandparentGuid: 'plex://show/5d9c08000000000000000000',
      grandparentTitle: 'Een serie met een redelijk lange titel',
      grandparentThumbPath: '/library/metadata/9000/thumb/1730000000',
      grandparentArtPath: '/library/metadata/9000/art/1730000000',
      thumbPath: '/library/metadata/100000/thumb/1730000000',
      artPath: '/library/metadata/9000/art/1730000000',
      durationMs: 2640000,
      viewOffsetMs: 120000,
      viewCount: 1,
      lastViewedAt: 1730000000,
      addedAt: 1720000000,
      updatedAt: 1730000000,
      rating: 7.4,
      audienceRating: 8.1,
      genres: const ['Drama', 'Misdaad'],
      directors: const ['Iemand Regisseur'],
      writers: const ['Een Schrijver', 'Nog Een Schrijver'],
      libraryId: 's',
      libraryTitle: 'Series',
      serverId: 'one',
      serverName: 'Thuis',
      raw: {
        'ratingKey': '100000',
        'type': 'episode',
        'pleyaLocalExternalIdsFinal': true,
        'Guid': [
          {'id': 'tvdb://1'},
          {'id': 'imdb://tt1'},
        ],
      },
    ).toJson();
    const count = 52000;
    final path = write(Iterable.generate(count, (i) => jsonEncode(row..['id'] = '${100000 + i}')));
    final size = File(path).lengthSync(), before = ProcessInfo.currentRss;

    final rows = decodeLibraryFile(path).rows;

    final peak = ProcessInfo.maxRss - before;
    expect(rows, hasLength(count));
    expect(peak, lessThan(4 * size), reason: 'peak ${peak >> 20} MB for an index of ${size >> 20} MB');
  });
}

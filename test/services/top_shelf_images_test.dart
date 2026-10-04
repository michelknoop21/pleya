import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/top_shelf_images.dart';

void main() {
  const secret = 'X-Plex-Token=s3cr3t';
  late Directory tmp;
  late Directory shelf;
  late List<String> fetched;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('top_shelf_test');
    shelf = Directory('${tmp.path}/TopShelfImages');
    fetched = [];
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  TopShelfImages images({Set<String> failing = const {}}) => TopShelfImages(
    fetch: (url) async {
      fetched.add(url);
      if (failing.contains(url)) throw const SocketException('unreachable');
      return File('${tmp.path}/src_${fetched.length}')..writeAsBytesSync([1, 2, 3]);
    },
  );

  Map<String, dynamic> entry(String id, String url) => {'contentId': id, 'title': id, 'imageUri': url};

  test('rewrites each image to a file:// URL in the folder, keeping order and fields', () async {
    final result = await images().localize([
      entry('pleya_ps_1', 'https://nas.local/pleya/v1/artwork/a?width=1920'),
      entry('pleya_plex_2', 'https://plex.local/photo/:/transcode?url=%2Fart&$secret'),
    ], shelf);
    expect(result.map((i) => i['contentId']), ['pleya_ps_1', 'pleya_plex_2']);
    expect(result.first['title'], 'pleya_ps_1');
    for (final item in result) {
      final uri = Uri.parse(item['imageUri'] as String);
      expect(uri.scheme, 'file');
      expect(File(uri.toFilePath()).readAsBytesSync(), [1, 2, 3]);
      expect(File(uri.toFilePath()).parent.path, shelf.path);
    }
  });

  test('no token, host or id in the payload or the file names', () async {
    final result = await images().localize([entry('pleya_plex_2', 'https://plex.local/a?$secret')], shelf);
    final payload = jsonEncode(result);
    expect(payload, isNot(contains('s3cr3t')));
    expect(payload, isNot(contains('plex.local')));
    final names = shelf.listSync().map((e) => e.path.split('/').last);
    expect(names.single, matches(RegExp(r'^ts_[0-9a-f]{32}\.jpg$')));
    expect(TopShelfImages.fileNameFor('https://plex.local/a?$secret'), names.single);
  });

  test('a failed download drops only that item and never leaks its URL', () async {
    const bad = 'https://nas.local/pleya/v1/artwork/bad?$secret';
    final result = await images(
      failing: {bad},
    ).localize([entry('ok', 'https://nas.local/pleya/v1/artwork/ok'), entry('bad', bad)], shelf);
    expect(result.map((i) => i['contentId']), ['ok']);
    expect(jsonEncode(result), isNot(contains('s3cr3t')));
    expect(shelf.listSync(), hasLength(1));
  });

  test('a timeout counts as a failure and does not hold the shelf', () async {
    final slow = TopShelfImages(fetch: (_) => Completer<File>().future, timeout: const Duration(milliseconds: 10));
    expect(await slow.localize([entry('slow', 'https://x/slow')], shelf), isEmpty);
  });

  test('removeUnused deletes files of items no longer on the shelf; localize reuses current ones', () async {
    await images().localize([entry('a', 'https://x/a'), entry('b', 'https://x/b')], shelf);
    File('${shelf.path}/leftover.jpg.part').writeAsBytesSync([0]);
    fetched.clear();
    final result = await images().localize([entry('b', 'https://x/b'), entry('c', 'https://x/c')], shelf);
    expect(fetched, ['https://x/c'], reason: 'b is already on disk');
    expect(shelf.listSync(), hasLength(4), reason: 'nothing is deleted before the new payload is written');
    await images().removeUnused(result, shelf);
    final onDisk = shelf.listSync().map((e) => e.path).toSet();
    expect(onDisk, {for (final i in result) Uri.parse(i['imageUri'] as String).toFilePath()});
  });

  test('an empty shelf empties the folder', () async {
    await images().localize([entry('a', 'https://x/a')], shelf);
    await images().removeUnused(await images().localize(const [], shelf), shelf);
    expect(shelf.listSync(), isEmpty);
  });

  // Review B, I-1: two episodes of one series carry the show's backdrop, so
  // two resume items share one URL and one file name. Downloaded in parallel,
  // they raced on one `.part` file and the second fell out of the carousel.
  test('two items with one shared backdrop URL both stay in the carousel, from one download', () async {
    const shared = 'https://plex.local/library/metadata/7/art';
    final slow = TopShelfImages(
      fetch: (url) async {
        fetched.add(url);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return File('${tmp.path}/src_${fetched.length}')..writeAsBytesSync([1, 2, 3]);
      },
    );
    final result = await slow.localize([entry('ep1', shared), entry('ep2', shared)], shelf);
    expect(result.map((i) => i['contentId']), ['ep1', 'ep2']);
    expect(result.map((i) => i['imageUri']).toSet(), hasLength(1));
    expect(fetched, [shared]);
  });
}

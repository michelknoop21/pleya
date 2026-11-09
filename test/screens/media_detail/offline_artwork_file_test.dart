import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/media_detail/offline_artwork_file.dart';

void main() {
  late Directory root;
  late String download;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pleya-offline-artwork-test-');
    download = '${root.path}/download-season.jpg';
    await File(download).writeAsBytes([1, 2, 3]);
  });
  tearDown(() async => root.delete(recursive: true));

  test('an index poster removed from disk falls back to the downloaded artwork', () {
    expect(offlineArtworkFile('${root.path}/posters/gone.image', () => download), download);
  });

  test('an index poster on disk wins without asking the downloads', () async {
    final indexed = '${root.path}/indexed.image';
    await File(indexed).writeAsBytes([4]);
    expect(offlineArtworkFile(indexed, () => fail('downloads asked')), indexed);
  });

  test('neither file on disk gives no local artwork', () {
    expect(offlineArtworkFile('${root.path}/gone.image', () => '${root.path}/gone.jpg'), isNull);
    expect(offlineArtworkFile(null, () => null), isNull);
  });
}

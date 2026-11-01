import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image_ce/cached_network_image.dart' show FileInfo;
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/services/image_cache_service.dart';
import 'local_library_store_test.dart' show film;
import 'local_library_sync_test.dart' show Client;

class Paths extends PathProviderPlatform {
  Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class ThumbnailClient extends Client {
  @override
  String thumbnailUrl(String? path, {int? width, int? height}) => 'https://fixture.invalid/poster?width=720';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('production default loader awaits HTTP instead of the first cached FileInfo', () async {
    final root = await Directory.systemTemp.createTemp('pleya-default-artwork-test-');
    final prior = PathProviderPlatform.instance;
    PathProviderPlatform.instance = Paths(root.path);
    final cache = PlexImageCacheManager.instance;
    try {
      const url = 'https://fixture.invalid/poster?width=720';
      await cache.putFile(url, Uint8List.fromList([1]), maxAge: const Duration(days: 1));
      final renderedKey = OptimizedMediaImage.artworkCacheKey(url);
      await cache.putFile(url, Uint8List.fromList([1]), key: renderedKey, maxAge: const Duration(days: 1));
      var requests = 0;
      final result = await LocalLibraryProvider.loadPoster(
        ThumbnailClient(),
        film('a'),
        {},
        transport: MockClient((request) async {
          requests++;
          return http.Response.bytes([2], 200, headers: {'etag': 'new'});
        }),
      );
      expect(result.bytes, [2], reason: 'the cached FileInfo contains old bytes [1]');
      expect(requests, 1);
      expect(result.etag, 'new');
      // This is deliberate gap evidence for separate Task4B, not a fixed
      // expectation: fill-off network images still use this exact CE key.
      final transient = await cache.getFileStream(url, key: renderedKey).firstWhere((r) => r is FileInfo);
      expect(await (transient as FileInfo).file.readAsBytes(), [1]);
      expect(OptimizedMediaImage.artworkCacheKey(url), renderedKey);
      print(
        'TASK4B GAP: local HTTP200=[2], rendered CE key still=[1], same decoded URL/key; no permanent-local read with fill off',
      );
    } finally {
      await cache.dispose();
      PathProviderPlatform.instance = prior;
      await root.delete(recursive: true);
    }
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pleya/media/download_resolution.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/image_cache_service.dart';
import 'package:pleya/services/media_controls_manager.dart';

import '../pleya_server/pleya_fake_server.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.directory);
  final Directory directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
  @override
  Future<String?> getApplicationSupportPath() async => directory.path;
}

class _DelayedArtworkClient implements MediaServerClient {
  final headers = Completer<Map<String, String>>();
  @override
  String thumbnailUrl(String? path, {int? width, int? height}) => 'https://fixture.test/art';
  @override
  List<DownloadArtworkSpec> resolveDownloadArtwork(MediaItem item) => [
    DownloadArtworkSpec(
      localKey: item.thumbPath!,
      url: thumbnailUrl(item.thumbPath),
      headersSupplier: () => headers.future,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.edde746.os_media_controls/methods');
  final calls = <MethodCall>[];
  final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  final item = MediaItem(
    id: 'movie',
    backend: MediaBackend.pleyaServer,
    kind: MediaKind.movie,
    serverId: 'physical',
    title: 'Offline movie',
    thumbPath: 'pleya-artwork:poster',
  );
  late Directory directory;
  late MediaControlsManager manager;
  late PathProviderPlatform previousPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pleya-media-controls-artwork-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory);
  });
  tearDownAll(() async {
    await PlexImageCacheManager.instance.dispose();
    PathProviderPlatform.instance = previousPaths;
    DownloadStorageService.resetForTesting();
    await directory.delete(recursive: true);
  });
  setUp(() {
    calls.clear();
    manager = MediaControlsManager();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    manager.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('offline Now Playing uses the existing downloaded poster without a client', () async {
    final path = await DownloadStorageService.instance.getArtworkPathFromThumb(ServerId('physical'), item.thumbPath!);
    await File(path).writeAsBytes(bytes);
    addTearDown(() => File(path).delete());
    await manager.updateMetadata(metadata: item);
    final metadata = calls.single.arguments as Map;
    expect(metadata['artwork'], bytes);
    expect(metadata['artworkUrl'], isNull);
  });

  test('header-authenticated artwork uses the existing image cache before the native handoff', () async {
    final client = PleyaFakeServer().client();
    await client.refreshCapabilities();
    addTearDown(client.close);
    await PlexImageCacheManager.instance.putFile(client.thumbnailUrl(item.thumbPath), bytes);
    await manager.updateMetadata(metadata: item, client: client);
    final metadata = calls.single.arguments as Map;
    expect(metadata['artwork'], bytes);
    expect(metadata['artworkUrl'], isNull);
  });

  test('closed account never hands an unauthenticated artwork URL to the native plugin', () async {
    final client = PleyaFakeServer().client();
    await client.refreshCapabilities();
    client.close();
    await manager.updateMetadata(metadata: item, client: client);
    final metadata = calls.single.arguments as Map;
    expect(metadata['title'], 'Offline movie');
    expect(metadata['artworkUrl'], isNull);
    expect(metadata['artwork'], isNull);
  });

  test('cleared metadata cannot be republished by an older artwork fetch', () async {
    final client = _DelayedArtworkClient();
    await PlexImageCacheManager.instance.putFile(client.thumbnailUrl(item.thumbPath), bytes);
    final pending = manager.updateMetadata(metadata: item, client: client);
    await Future<void>.delayed(Duration.zero);
    await manager.clear();
    client.headers.complete({'Authorization': 'Bearer canned-test-only'});
    await pending;
    expect(calls.where((call) => call.method == 'setMetadata'), isEmpty);
  });
}

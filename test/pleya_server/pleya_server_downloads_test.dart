import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_part.dart';
import 'package:pleya/media/media_stream.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/services/download_manager_service.dart' show verifyDownloadAfterRestart, verifyDownloadDigest;
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// S23 on the client side: the app's download queue asks the server to prepare
/// a file, waits for it, and fetches it with the session header and the
/// digest the server stated.
void main() {
  late PleyaServerClient client;
  tearDown(() => client.close());

  final item = MediaItem(
    id: 'movie-1',
    backend: MediaBackend.pleyaServer,
    kind: MediaKind.movie,
    mediaVersions: const [MediaVersion(id: 'version-1', container: 'mkv')],
  );

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    c.downloadPollInterval = Duration.zero;
    return c;
  }

  test('waits for the digest, then hands the queue a url, a header and the sha256', () async {
    final server = PleyaFakeServer()
      ..downloadsCapability = true
      ..downloadPrepareRounds = 2;
    client = await connected(server);

    final resolution = await client.resolveDownload(item);

    expect(server.downloadRequests.single, {'item_id': 'movie-1', 'version_id': 'version-1'});
    expect(resolution.videoUrl, endsWith('/downloads/dl-1/file?container=mkv'));
    expect(resolution.sha256, 'a' * 64);
    expect(resolution.mediaSourceId, 'version-1');
    expect(resolution.headers.keys, contains('Authorization'));
  });

  test('public artwork resolution keeps only canonical Pleya artwork', () async {
    client = await connected(PleyaFakeServer());
    final posterItem = item.copyWith(thumbPath: 'pleya-artwork:poster-1', artPath: 'https://foreign.test/image');
    final specs = client.resolveDownloadArtwork(posterItem);
    expect(specs, hasLength(1));
    expect(specs.single.localKey, 'pleya-artwork:poster-1');
    expect(specs.single.url, endsWith('/pleya/v1/artwork/poster-1'));
    expect(await specs.single.headersSupplier!(), contains('Authorization'));
    client.close();
    await expectLater(specs.single.headersSupplier!(), throwsStateError);
  });

  test('download companions retain stable sidecar identity and originating authorization', () async {
    client = await connected(PleyaFakeServer()..downloadsCapability = true);
    final withSubtitles = item.copyWith(
      mediaVersions: const [
        MediaVersion(
          id: 'version-1',
          parts: [
            MediaPart(
              id: 'part',
              streams: [
                MediaStream(id: 'embedded', kind: MediaStreamKind.subtitle, index: 2, codec: 'srt'),
                MediaStream(
                  id: 'sidecar-uuid',
                  kind: MediaStreamKind.subtitle,
                  codec: 'srt',
                  languageCode: 'eng',
                  forced: true,
                  sidecarPath: 'pleya-subtitle:sidecar-uuid',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final result = await client.resolveDownload(withSubtitles);
    expect(result.externalSubtitles, hasLength(1));
    final subtitle = result.externalSubtitles.single;
    expect(subtitle.sourceStreamId, 'sidecar-uuid');
    expect(subtitle.url, endsWith('/pleya/v1/subtitles/sidecar-uuid'));
    expect(subtitle.forced, isTrue);
    expect(await subtitle.headersSupplier!(), contains('Authorization'));
    client.close();
    await expectLater(subtitle.headersSupplier!(), throwsStateError);
  });

  test('recovery resolves sidecars for the stable source without creating another download', () async {
    final fake = PleyaFakeServer()..downloadsCapability = true;
    client = await connected(fake);
    final metadata = item.copyWith(
      mediaVersions: const [
        MediaVersion(id: 'other'),
        MediaVersion(
          id: 'chosen',
          parts: [
            MediaPart(
              id: 'chosen',
              streams: [
                MediaStream(
                  id: 'sidecar',
                  kind: MediaStreamKind.subtitle,
                  codec: 'srt',
                  languageCode: 'eng',
                  sidecarPath: 'pleya-subtitle:sidecar',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final subtitles = client.resolveDownloadSubtitles(metadata, mediaSourceId: 'chosen');
    expect(subtitles.single.sourceStreamId, 'sidecar');
    expect(fake.downloadRequests, isEmpty);
    expect(client.resolveDownloadSubtitles(metadata, mediaSourceId: 'removed'), isEmpty);
  });

  test('a download the server could not prepare is an error, not a silent skip', () async {
    final server = PleyaFakeServer()
      ..downloadsCapability = true
      ..downloadFails = true;
    client = await connected(server);

    await expectLater(client.resolveDownload(item), throwsException);
  });

  test('a server without the flag is not asked', () async {
    final server = PleyaFakeServer();
    client = await connected(server);

    final resolution = await client.resolveDownload(item);

    expect(resolution.videoUrl, isNull);
    expect(server.downloadRequests, isEmpty);
  });

  group('digest after an app restart', () {
    test('asks the server again for the digest behind the queued file url', () async {
      final server = PleyaFakeServer()..downloadsCapability = true;
      client = await connected(server);
      final resolution = await client.resolveDownload(item);

      expect(await client.expectedDigestForUrl(resolution.videoUrl!), 'a' * 64);
    });

    test('a url that is not a download file url has no digest', () async {
      final server = PleyaFakeServer()..downloadsCapability = true;
      client = await connected(server);

      expect(await client.expectedDigestForUrl('http://nas.lan:8832/pleya/v1/items/x/stream'), isNull);
    });
  });

  group('digest check on the finished file', () {
    late Directory dir;
    late File file;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pleya_digest');
      file = File('${dir.path}/movie.mkv')..writeAsBytesSync([1, 2, 3, 4]);
    });
    tearDown(() => dir.delete(recursive: true));

    test('keeps a file whose digest matches', () async {
      await verifyDownloadDigest(file.path, sha256.convert([1, 2, 3, 4]).toString());
      expect(file.existsSync(), isTrue);
    });

    test('removes a file whose digest differs and fails the download', () async {
      await expectLater(verifyDownloadDigest(file.path, 'b' * 64), throwsException);
      expect(file.existsSync(), isFalse);
    });

    group('after a restart', () {
      final good = sha256.convert([1, 2, 3, 4]).toString();

      test('a good file passes', () async {
        await verifyDownloadAfterRestart(file.path, () async => good);
        expect(file.existsSync(), isTrue);
      });

      test('a corrupted file fails and is removed (negative control)', () async {
        file.writeAsBytesSync([9, 9, 9, 9]);
        await expectLater(verifyDownloadAfterRestart(file.path, () async => good), throwsException);
        expect(file.existsSync(), isFalse);
      });

      test('an unreachable server leaves the download standing', () async {
        await verifyDownloadAfterRestart(file.path, () async => throw const SocketException('offline'));
        expect(file.existsSync(), isTrue);
      });

      test('no stated digest leaves the download standing', () async {
        await verifyDownloadAfterRestart(file.path, () async => null);
        expect(file.existsSync(), isTrue);
      });

      test('a missing file is skipped without asking the server', () async {
        var asked = false;
        await verifyDownloadAfterRestart('${dir.path}/gone.mkv', () async {
          asked = true;
          return good;
        });
        expect(asked, isFalse);
      });
    });
  });
}

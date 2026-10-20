import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/device_capabilities.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/services/playback_initialization_types.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/pleya_server_client/pleya_device_capabilities_wire.dart';

import 'pleya_fake_server.dart';

/// S17 on the client side: the capabilities that go out, and following the plan
/// that comes back.
void main() {
  late PleyaFakeServer server;
  late PleyaServerClient client;

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    return c;
  }

  MediaItem twoVersions(PleyaFakeServer fake) {
    fake.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    fake.addItem(id: 'movie-1', kind: 'movie', title: 'Grease', libraryId: 'lib-films', durationMs: 6720000);
    return MediaItem(
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      id: 'movie-1',
      title: 'Grease',
      mediaVersions: const [
        MediaVersion(id: 'version-1', container: 'mkv'),
        MediaVersion(id: 'version-2', container: 'mp4'),
      ],
    );
  }

  Future<PlaybackInitializationResult> play(MediaItem item, {int index = 0}) =>
      client.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: index));

  tearDown(() => client.close());

  group('following the plan', () {
    test('the default selection lets the server pick the version', () async {
      server = PleyaFakeServer(watchState: true)
        ..playbackPlanCapability = true
        ..planVersionId = 'version-2';
      final item = twoVersions(server);
      client = await connected(server);

      final result = await play(item);

      expect(result.videoUrl, 'http://nas.lan:8832/pleya/v1/stream/version-2');
      expect(result.selectedMediaIndex, 1);
      expect(server.planRequests.single.containsKey('version_id'), isFalse);
      expect(server.planRequests.single['item_id'], 'movie-1');
      expect(server.planRequests.single['capabilities'], isA<Map>());
    });

    test('an explicit version choice goes out as version_id', () async {
      server = PleyaFakeServer(watchState: true)..playbackPlanCapability = true;
      final item = twoVersions(server);
      client = await connected(server);

      final result = await play(item, index: 1);

      expect(server.planRequests.single['version_id'], 'version-2');
      expect(result.selectedMediaIndex, 1);
    });

    test('without the capability there is no plan call and nothing changes', () async {
      server = PleyaFakeServer(watchState: true);
      final item = twoVersions(server);
      client = await connected(server);

      final result = await play(item);

      expect(server.requests.where((r) => r.contains('/playback/plan')), isEmpty);
      expect(result.videoUrl, endsWith('/stream/version-1'));
    });

    test('a failed plan keeps direct play of the selected version', () async {
      server = PleyaFakeServer(watchState: true)
        ..playbackPlanCapability = true
        ..planFailureStatus = 415;
      final item = twoVersions(server);
      client = await connected(server);

      final result = await play(item);

      expect(result.videoUrl, endsWith('/stream/version-1'));
      expect(result.playMethod, 'DirectPlay');
    });

    test('a delivery the build does not know keeps direct play', () async {
      server = PleyaFakeServer(watchState: true)
        ..playbackPlanCapability = true
        ..planDeliveryMode = 'warp'
        ..planVersionId = 'version-2';
      final item = twoVersions(server);
      client = await connected(server);

      final result = await play(item);

      expect(result.videoUrl, endsWith('/stream/version-1'));
      expect(result.isTranscoding, isFalse);
    });

    test('a transcode plan opens the HLS playlist of its session', () async {
      server = PleyaFakeServer(watchState: true)
        ..playbackPlanCapability = true
        ..planDeliveryMode = 'transcode'
        ..planVersionId = 'version-2';
      final item = twoVersions(server);
      client = await connected(server);

      final result = await play(item);

      expect(result.videoUrl, 'http://nas.lan:8832/pleya/v1/playback/sessions/sess-1/index.m3u8');
      expect(result.isTranscoding, isTrue);
      expect(result.playMethod, 'Transcode');
      expect(result.selectedMediaIndex, 1);
      expect(server.sessionCalls, isEmpty, reason: 'nothing is called before the first heartbeat is due');
    });

    test('reporting the playback stopped stops the session', () async {
      server = PleyaFakeServer(watchState: true)
        ..playbackPlanCapability = true
        ..planDeliveryMode = 'direct_stream';
      final item = twoVersions(server);
      client = await connected(server);

      final result = await play(item);
      expect(result.playMethod, 'DirectStream');
      await client.reportPlaybackStopped(itemId: 'movie-1', position: const Duration(minutes: 3));

      expect(server.sessionCalls, ['DELETE /playback/sessions/sess-1']);
    });

    test('closing the client stops a session it still holds', () async {
      server = PleyaFakeServer(watchState: true)
        ..playbackPlanCapability = true
        ..planDeliveryMode = 'remux';
      final item = twoVersions(server);
      client = await connected(server);

      await play(item);
      await client.closeGracefully();

      expect(server.sessionCalls, ['DELETE /playback/sessions/sess-1']);
    });
  });

  group('capabilities on the wire', () {
    test('an unknown capability goes out as null with confidence unknown', () {
      final wire = pleyaDeviceCapabilitiesToWire(DeviceCapabilities.unknown);
      final codecs = (wire['decoder'] as Map)['video_codecs'] as Map;
      expect(codecs['value'], isNull);
      expect(codecs['confidence'], 'unknown');
    });

    test('a known set keeps the order of the client, an override says so, and confidence follows the observation', () {
      final caps = DeviceCapabilities.unknown.copyWith(
        decoder: DeviceDecoderCapabilities(
          engine: PlayerEngine.mpv,
          videoCodecs: const Capability.inferred({'hevc', 'h264'}),
          audioCodecs: const Capability<Set<String>>.unknown(),
          containers: const Capability<Set<String>>.unknown(),
          maxBitDepth: const Capability<int>.detected(10).overriddenWith(8),
        ),
      );
      final decoder = pleyaDeviceCapabilitiesToWire(caps)['decoder'] as Map;
      expect((decoder['video_codecs'] as Map)['value'], ['hevc', 'h264']);
      expect((decoder['video_codecs'] as Map)['confidence'], 'inferred');
      final depth = decoder['max_bit_depth'] as Map;
      expect(depth['value'], 8);
      expect(depth['overridden'], true);
      expect(depth['confidence'], 'detected');
    });
  });
}

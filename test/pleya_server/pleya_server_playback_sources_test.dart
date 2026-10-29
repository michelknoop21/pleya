import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/pleya_server_api_cache.dart';
import 'package:pleya/services/cached_playback_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_part.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_stream.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/services/playback_initialization_types.dart';
import 'package:pleya/services/playback_stream_evidence.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'pleya_fake_server.dart';

void main() {
  late PleyaServerClient client;
  tearDown(() => client.close());
  final item = MediaItem(
    id: 'movie',
    backend: MediaBackend.pleyaServer,
    kind: MediaKind.movie,
    mediaVersions: const [
      MediaVersion(
        id: 'v',
        container: 'mkv',
        width: 1920,
        height: 1080,
        videoCodec: 'h264',
        parts: [
          MediaPart(
            id: 'v',
            durationMs: 60000,
            streams: [
              MediaStream(
                id: 'a-uuid',
                kind: MediaStreamKind.audio,
                index: 1,
                codec: 'aac',
                languageCode: 'eng',
                channels: 2,
                selected: true,
              ),
              MediaStream(id: 'embedded', kind: MediaStreamKind.subtitle, index: 2, codec: 'srt', languageCode: 'eng'),
              MediaStream(
                id: 'sidecar',
                kind: MediaStreamKind.subtitle,
                codec: 'ass',
                languageCode: 'nld',
                forced: true,
                sidecarPath: 'pleya-subtitle:sidecar',
              ),
            ],
          ),
        ],
      ),
    ],
  );

  test('live metadata pins raw streams in the scoped cache and rehydrates offline without requests', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PleyaServerApiCache.initialize(db);
    addTearDown(db.close);
    final fake = PleyaFakeServer();
    fake.addItem(id: 'cached', kind: 'movie', title: 'Cached', durationMs: 60000);
    final version = (fake.items['cached']!['versions'] as List).single as Map<String, dynamic>;
    version['audio_streams'] = [
      {'id': 'audio', 'index': 1, 'codec': 'aac', 'channels': 2, 'language': 'eng', 'is_default': true},
    ];
    client = fake.client();
    final MediaServerClient public = client;
    expect((await public.fetchItem('cached'))?.mediaVersions, hasLength(1));
    await public.cache.pinForOffline(ServerId(client.scopedServerId), 'cached');
    client.setOfflineMode(true);
    final requestCount = fake.requests.length;
    final info = await public.fetchCachedMediaSourceInfo('cached');
    expect(info?.mediaSourceId, 'cached-v1');
    expect(info?.audioTracks.single.codec, 'aac');
    final offline = await CachedPlaybackMetadataService.fetchMediaSourceInfo(
      backend: MediaBackend.pleyaServer,
      cacheServerId: client.scopedServerId,
      itemId: 'cached',
    );
    expect(offline?.audioTracks.single.codec, 'aac');
    expect(
      await CachedPlaybackMetadataService.fetchMediaSourceInfo(
        backend: MediaBackend.pleyaServer,
        cacheServerId: 'other-account',
        itemId: 'cached',
      ),
      isNull,
    );
    expect(fake.requests, hasLength(requestCount));
  });

  test('sidecar and embedded tracks reach the shared playback result with authenticated URLs', () async {
    final server = PleyaFakeServer();
    client = server.client();
    final MediaServerClient public = client;
    final result = await public.getPlaybackInitialization(
      PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0),
    );
    expect(result.externalSubtitles, hasLength(1));
    final sidecar = result.externalSubtitles.single;
    expect(sidecar.uri, 'http://nas.lan:8832/pleya/v1/subtitles/sidecar');
    expect(sidecar.codec, 'ass');
    expect(sidecar.isForced, isTrue);
    expect(sidecar.language, 'nld');
    expect(result.mediaInfo?.mediaSourceId, 'v');
    expect(result.mediaInfo?.audioTracks.single.languageCode, 'eng');
    expect(result.mediaInfo?.subtitleTracks, hasLength(2));
    expect(public.streamHeaders['Authorization'], startsWith('Bearer '));
    expect(sidecar.uri, isNot(contains('token')));
  });

  test('HLS delivers embedded text through the canonical authenticated subtitle route', () async {
    final server = PleyaFakeServer()
      ..playbackPlanCapability = true
      ..embeddedSubtitlesCapability = true
      ..planVersionId = 'v'
      ..planDeliveryMode = 'remux';
    client = server.client();
    await client.refreshCapabilities();
    final MediaServerClient public = client;
    final result = await public.getPlaybackInitialization(
      PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0),
    );
    expect(result.externalSubtitles.map((s) => s.uri), [
      'http://nas.lan:8832/pleya/v1/subtitles/embedded',
      'http://nas.lan:8832/pleya/v1/subtitles/sidecar',
    ]);
    expect(result.mediaInfo!.subtitleTracks.first.usesExternalDelivery, isTrue);
    expect(result.mediaInfo!.subtitleTracks.first.isExternalFile, isFalse);
    expect(public.streamHeaders['Authorization'], startsWith('Bearer '));
  });

  for (final choice in [0, 3]) {
    test('explicit subtitle $choice uses the public interface and stable wire id', () async {
      final server = PleyaFakeServer()
        ..playbackPlanCapability = true
        ..playbackSubtitlesCapability = true
        ..embeddedSubtitlesCapability = true
        ..planVersionId = 'v';
      client = server.client();
      await client.refreshCapabilities();
      final MediaServerClient public = client;
      final result = await public.getPlaybackInitialization(
        PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0, selectedSubtitleStreamId: choice),
      );
      expect(
        server.planRequests.single['subtitle'],
        choice == 0 ? {'mode': 'off'} : {'mode': 'external', 'stream_id': 'embedded'},
      );
      expect(server.planRequests.single['version_id'], 'v');
      expect(result.mediaInfo!.subtitleTracks.first.sourceStreamId, 'embedded');
      expect(result.mediaInfo!.defaultSubtitleStreamIndex, choice == 0 ? -1 : 2);
    });
  }

  test('old server refuses explicit subtitles before sending a new field', () async {
    final server = PleyaFakeServer()..playbackPlanCapability = true;
    client = server.client();
    await client.refreshCapabilities();
    final MediaServerClient public = client;
    await expectLater(
      public.getPlaybackInitialization(
        PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0, selectedSubtitleStreamId: 0),
      ),
      throwsA(isA<PlaybackException>()),
    );
    expect(server.planRequests, isEmpty);
  });

  test('automatic HLS uses shared preferences only after the server chooses a version', () async {
    final server = PleyaFakeServer()
      ..playbackPlanCapability = true
      ..playbackAudioSelectionCapability = true
      ..planVersionId = 'v'
      ..planDeliveryMode = 'remux';
    client = server.client();
    await client.refreshCapabilities();
    final MediaServerClient public = client;
    final version = item.mediaVersions!.single;
    final preferredItem = item.copyWith(
      mediaVersions: [
        const MediaVersion(id: 'other'),
        MediaVersion(
          id: 'v',
          container: 'mkv',
          parts: [
            MediaPart(
              id: 'v',
              streams: [
                ...version.parts.single.streams,
                const MediaStream(
                  id: 'dutch-audio',
                  kind: MediaStreamKind.audio,
                  index: 7,
                  codec: 'aac',
                  languageCode: 'nld',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final result = await public.getPlaybackInitialization(
      PlaybackInitializationOptions(
        metadata: preferredItem,
        selectedMediaIndex: 0,
        selectSourceTracks: (info) async {
          expect(info.mediaSourceId, 'v');
          return (audioStreamId: 7, subtitleStreamId: null);
        },
      ),
    );
    expect(server.planRequests, hasLength(2));
    expect(server.planRequests.first.containsKey('version_id'), isFalse);
    expect(server.planRequests.last['version_id'], 'v');
    expect(server.planRequests.last['audio_stream_id'], 'dutch-audio');
    expect(server.sessionCalls, ['DELETE /playback/sessions/sess-1']);
    expect(result.activeAudioStreamId, 7);
  });

  test('cancelled preference preflight stops its provisional conversion', () async {
    final server = PleyaFakeServer()
      ..playbackPlanCapability = true
      ..playbackAudioSelectionCapability = true
      ..planVersionId = 'v'
      ..planDeliveryMode = 'remux';
    client = server.client();
    await client.refreshCapabilities();
    final MediaServerClient public = client;
    await expectLater(
      public.getPlaybackInitialization(
        PlaybackInitializationOptions(
          metadata: item,
          selectedMediaIndex: 0,
          selectSourceTracks: (_) async => throw StateError('account changed'),
        ),
      ),
      throwsStateError,
    );
    expect(server.sessionCalls, ['DELETE /playback/sessions/sess-1']);
  });

  test('a closed client cannot prepare another playback from cached credentials', () async {
    final server = PleyaFakeServer();
    client = server.client();
    final MediaServerClient public = client;
    await public.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0));
    client.close();
    await expectLater(
      public.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0)),
      throwsA(isA<PlaybackException>()),
    );
  });

  test('an invalid source subtitle preference fails visibly and stops its provisional session', () async {
    final server = PleyaFakeServer()
      ..playbackPlanCapability = true
      ..playbackSubtitlesCapability = true
      ..planVersionId = 'v'
      ..planDeliveryMode = 'remux';
    client = server.client();
    await client.refreshCapabilities();
    final MediaServerClient public = client;
    await expectLater(
      public.getPlaybackInitialization(
        PlaybackInitializationOptions(
          metadata: item,
          selectedMediaIndex: 0,
          selectSourceTracks: (_) async => (audioStreamId: null, subtitleStreamId: 999),
        ),
      ),
      throwsA(isA<PlaybackException>()),
    );
    expect(server.sessionCalls, ['DELETE /playback/sessions/sess-1']);
  });

  test('a burned bitmap keeps source controls but never adds a second text overlay', () async {
    final server = PleyaFakeServer()
      ..playbackPlanCapability = true
      ..playbackSubtitlesCapability = true
      ..planVersionId = 'v'
      ..planDeliveryMode = 'transcode';
    client = server.client();
    await client.refreshCapabilities();
    final MediaServerClient public = client;
    final bitmapItem = item.copyWith(
      mediaVersions: const [
        MediaVersion(
          id: 'v',
          parts: [
            MediaPart(
              id: 'v',
              streams: [
                MediaStream(id: 'bitmap', kind: MediaStreamKind.subtitle, index: 2, codec: 'pgs', languageCode: 'eng'),
                MediaStream(
                  id: 'text',
                  kind: MediaStreamKind.subtitle,
                  codec: 'srt',
                  languageCode: 'eng',
                  sidecarPath: 'pleya-subtitle:text',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final result = await public.getPlaybackInitialization(
      PlaybackInitializationOptions(metadata: bitmapItem, selectedMediaIndex: 0, selectedSubtitleStreamId: 3),
    );
    expect(server.planRequests.single['subtitle'], {'mode': 'burn', 'stream_id': 'bitmap'});
    expect(result.streamEvidence.subtitle, PlaybackSubtitleDecision.burn);
    expect(result.mediaInfo!.subtitleTracks, hasLength(2));
    expect(result.mediaInfo!.subtitleTracks.first.selected, isTrue);
    expect(result.externalSubtitles, isEmpty);
  });

  test('the public adapter produces the approved closed selection request fixture', () async {
    final request =
        jsonDecode(File('docs/pleya-protocol/v1/examples/playback_plan_selection_request.json').readAsStringSync())
            as Map<String, dynamic>;
    final server = PleyaFakeServer()
      ..playbackPlanCapability = true
      ..playbackQualityCapability = true
      ..playbackAudioSelectionCapability = true
      ..playbackSubtitlesCapability = true
      ..planDeliveryMode = 'transcode';
    client = server.client();
    await client.refreshCapabilities();
    final MediaServerClient public = client;
    final metadata = MediaItem(
      id: request['item_id'] as String,
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      mediaVersions: [
        MediaVersion(
          id: request['version_id'] as String,
          parts: [
            MediaPart(
              id: 'part',
              streams: [
                MediaStream(
                  id: request['audio_stream_id'] as String,
                  kind: MediaStreamKind.audio,
                  index: 7,
                  codec: 'aac',
                ),
                MediaStream(
                  id: (request['subtitle'] as Map)['stream_id'] as String,
                  kind: MediaStreamKind.subtitle,
                  index: 8,
                  codec: 'pgs',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final quality = request['quality'] as Map;
    await public.getPlaybackInitialization(
      PlaybackInitializationOptions(
        metadata: metadata,
        selectedMediaIndex: 0,
        selectedMediaSourceId: request['version_id'] as String,
        selectedAudioStreamId: 7,
        selectedSubtitleStreamId: 9,
        qualityPreset: TranscodeQualityPreset.values.firstWhere(
          (p) => p.videoBitrateKbps == quality['max_video_bitrate_kbps'] && p.resolutionHeight == quality['max_height'],
        ),
      ),
    );
    final actual = Map<String, dynamic>.of(server.planRequests.single)..remove('capabilities');
    expect(actual, request);
  });

  test('file details use mapped metadata instead of returning the unsupported stub', () async {
    client = PleyaFakeServer().client();
    final MediaServerClient public = client;
    final info = await public.getFileInfo(item);
    expect(info?.container, 'mkv');
    expect(info?.width, 1920);
    expect(info?.height, 1080);
    expect(info?.duration, 60000);
    expect(info?.audioTracks.single.codec, 'aac');
    expect(info?.subtitleTracks, hasLength(2));
  });
}

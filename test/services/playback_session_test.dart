import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/services/playback_context.dart';
import 'package:pleya/services/playback_initialization_types.dart';
import 'package:pleya/services/playback_session.dart';

PlaybackContext _context(PlaybackInitializationResult result, {MediaBackend backend = MediaBackend.plex}) {
  return PlaybackContext(
    metadata: MediaItem(id: 'item-1', backend: backend, kind: MediaKind.movie, serverId: 'srv'),
    result: result,
    sourceKind: result.usesLocalMedia ? PlaybackSourceKind.localFile : PlaybackSourceKind.remoteDirect,
    reportingMode: PlaybackReportingMode.online,
    streamHeaders: const {'X-Test': 'token'},
  );
}

void main() {
  group('a failed reload on a server-held conversion', () {
    PlaybackSession session(MediaBackend backend, String? playMethod, {bool isOffline = false}) =>
        PlaybackSession.fromContext(
          _context(
            PlaybackInitializationResult(
              availableVersions: const [],
              videoUrl: 'u',
              playMethod: playMethod,
              isOffline: isOffline,
            ),
            backend: backend,
          ),
          requestedQualityPreset: TranscodeQualityPreset.original,
        );

    test('only a Pleya Server conversion dies with its stop report', () {
      expect(session(MediaBackend.pleyaServer, 'Transcode').holdsServerConversion, isTrue);
      expect(session(MediaBackend.pleyaServer, 'DirectStream').holdsServerConversion, isTrue);
      expect(session(MediaBackend.pleyaServer, 'DirectPlay').holdsServerConversion, isFalse);
      expect(session(MediaBackend.pleyaServer, 'Transcode', isOffline: true).holdsServerConversion, isFalse);
      expect(session(MediaBackend.plex, 'Transcode').holdsServerConversion, isFalse);
      expect(session(MediaBackend.jellyfin, 'Transcode').holdsServerConversion, isFalse);
    });

    test('the rollback reopens it once and otherwise resumes as before', () {
      final source = File('lib/screens/video_player/parts/episode_navigation.dart').readAsStringSync();
      final rollback = source.substring(source.indexOf('if (!didOpenReplacement) {'));

      expect(rollback, contains('holdsServerConversion'));
      expect(rollback, contains('!reopeningFailedReload'));
      expect(rollback, contains('_playWithPlaybackIntent(currentPlayer)'));
      expect(rollback, contains('reopeningFailedReload: true'));
    });
  });

  group('PlaybackSession.fromContext', () {
    test('keeps the requested preset when no fallback occurred', () {
      final session = PlaybackSession.fromContext(
        _context(PlaybackInitializationResult(availableVersions: const [], videoUrl: 'u')),
        requestedQualityPreset: TranscodeQualityPreset.p1080_8mbps,
      );
      expect(session.qualityPreset, TranscodeQualityPreset.p1080_8mbps);
    });

    test('falls back to original when the backend rejected the preset', () {
      final session = PlaybackSession.fromContext(
        _context(
          PlaybackInitializationResult(
            availableVersions: const [],
            videoUrl: 'u',
            fallbackReason: TranscodeFallbackReason.values.first,
          ),
        ),
        requestedQualityPreset: TranscodeQualityPreset.p1080_8mbps,
      );
      expect(session.qualityPreset, TranscodeQualityPreset.original);
    });

    test('an original-quality request ignores the fallback reason', () {
      final session = PlaybackSession.fromContext(
        _context(
          PlaybackInitializationResult(
            availableVersions: const [],
            videoUrl: 'u',
            fallbackReason: TranscodeFallbackReason.values.first,
          ),
        ),
        requestedQualityPreset: TranscodeQualityPreset.original,
      );
      expect(session.qualityPreset, TranscodeQualityPreset.original);
    });

    test('refines the media source id from the clamped version index', () {
      final versions = [MediaVersion(id: 'v0'), MediaVersion(id: 'v1')];
      final session = PlaybackSession.fromContext(
        _context(PlaybackInitializationResult(availableVersions: versions, videoUrl: 'u', selectedMediaIndex: 1)),
        requestedQualityPreset: TranscodeQualityPreset.original,
        requestedMediaSourceId: 'requested',
      );
      expect(session.mediaSourceId, 'v1');
      expect(session.mediaIndex, 1);
    });

    test('keeps the requested source id when the index is out of range', () {
      final session = PlaybackSession.fromContext(
        _context(PlaybackInitializationResult(availableVersions: const [], videoUrl: 'u', selectedMediaIndex: 2)),
        requestedQualityPreset: TranscodeQualityPreset.original,
        requestedMediaSourceId: 'requested',
      );
      expect(session.mediaSourceId, 'requested');
    });
  });

  test('forwarding getters mirror the resolver output', () {
    final result = PlaybackInitializationResult(
      availableVersions: [MediaVersion(id: 'v0')],
      videoUrl: 'u',
      isTranscoding: true,
      playSessionId: 'psid',
      playMethod: 'Transcode',
      activeAudioStreamId: 7,
    );
    final session = PlaybackSession.fromContext(
      _context(result),
      requestedQualityPreset: TranscodeQualityPreset.original,
    );

    expect(session.isTranscoding, isTrue);
    expect(session.isOffline, isFalse);
    expect(session.playSessionId, 'psid');
    expect(session.playMethod, 'Transcode');
    expect(session.audioStreamId, 7);
    expect(session.availableVersions, hasLength(1));
    expect(session.streamHeaders, containsPair('X-Test', 'token'));
    expect(session.metadata.id, 'item-1');
  });
}

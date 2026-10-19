import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/playback_resume_resolver.dart';

const _serverPosition = Duration(minutes: 45);
const _localPosition = Duration(minutes: 50);

// The server last saw the item at 10:00, the local tracker wrote at 11:00.
final _serverSeenAt = DateTime.utc(2026, 10, 18, 10);
final _localWroteAt = DateTime.utc(2026, 10, 18, 11);

MediaItem _movie() => MediaItem(
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  id: 'movie_1',
  serverId: 'server_1',
  title: 'Movie 1',
  viewOffsetMs: _serverPosition.inMilliseconds,
  lastViewedAt: _serverSeenAt.millisecondsSinceEpoch ~/ 1000,
);

class _FakeOfflineWatch implements OfflineWatchSyncService {
  _FakeOfflineWatch(this.local);

  final LocalResumeProgress? local;
  int reads = 0;

  @override
  Future<LocalResumeProgress?> getLocalResumeProgress(String globalKey, {String? clientScopeId}) async {
    reads++;
    return local;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalResumeProgress get _passiveLocal => LocalResumeProgress(
  position: _localPosition,
  updatedAt: _localWroteAt,
  intent: PlaybackResumeIntent.passive,
  origin: PlaybackResumeOrigin.offlinePlayback,
);

void main() {
  group('resolveOpenResumePosition', () {
    test('a view offset read during this launch beats a newer passive local record', () async {
      final position = await resolveOpenResumePosition(
        metadata: _movie(),
        isOffline: true,
        offlineWatchService: _FakeOfflineWatch(_passiveLocal),
        backendProgressIsFresh: true,
      );

      expect(position, _serverPosition);
    });

    // Negative control: the same inputs without the fresh flag. If the flag
    // were dropped on the way (hard-coded false), the test above would see
    // this answer instead.
    test('the same snapshot without the fresh flag yields to the newer local record', () async {
      final position = await resolveOpenResumePosition(
        metadata: _movie(),
        isOffline: true,
        offlineWatchService: _FakeOfflineWatch(_passiveLocal),
      );

      expect(position, _localPosition);
    });

    test('an online open does not read local progress at all', () async {
      final offline = _FakeOfflineWatch(_passiveLocal);

      final position = await resolveOpenResumePosition(
        metadata: _movie(),
        isOffline: false,
        offlineWatchService: offline,
        backendProgressIsFresh: true,
      );

      expect(position, _serverPosition);
      expect(offline.reads, 0);
    });

    test('a fresh read without a view offset does not invent one', () async {
      final position = await resolveOpenResumePosition(
        metadata: _movie().copyWith(viewOffsetMs: null),
        isOffline: false,
        offlineWatchService: _FakeOfflineWatch(null),
        backendProgressIsFresh: true,
      );

      expect(position, isNull);
    });

    test('a handoff start position beats a fresh backend offset and a newer local record', () async {
      // The phone said "from 3:46"; neither the Apple TV's own old progress nor
      // the server value may pull the start elsewhere.
      final position = await resolveOpenResumePosition(
        metadata: _movie(),
        isOffline: true,
        offlineWatchService: _FakeOfflineWatch(_passiveLocal),
        backendProgressIsFresh: true,
        requested: const Duration(minutes: 3, seconds: 46),
      );

      expect(position, const Duration(minutes: 3, seconds: 46));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/video_player_navigation.dart';

void main() {
  test('in-flight video player navigation rejects duplicate requests', () {
    final guard = VideoPlayerNavigationInFlightGuard();
    final item = MediaItem(
      id: 'episode_1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Episode 1',
      serverId: 'server_1',
    );

    expect(
      guard.tryStart(item, mediaIndex: 0, selectedMediaSourceId: null, selectedQualityPreset: null, isOffline: false),
      isTrue,
    );
    expect(
      guard.tryStart(item, mediaIndex: 0, selectedMediaSourceId: null, selectedQualityPreset: null, isOffline: false),
      isFalse,
    );
    expect(
      guard.tryStart(item, mediaIndex: 1, selectedMediaSourceId: null, selectedQualityPreset: null, isOffline: false),
      isTrue,
    );

    guard.finish(item, mediaIndex: 0, selectedMediaSourceId: null, selectedQualityPreset: null, isOffline: false);

    expect(
      guard.tryStart(item, mediaIndex: 0, selectedMediaSourceId: null, selectedQualityPreset: null, isOffline: false),
      isTrue,
    );
  });
}

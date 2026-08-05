import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/services/ambient_lighting_service.dart';
import 'package:pleya/services/video_filter_manager.dart';

void main() {
  test('zoom scale snaps to whole percentages', () {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(player: player);
    addTearDown(manager.dispose);

    expect(manager.setZoomScale(1.234), 1.23);
    expect(manager.zoomScale, 1.23);

    expect(manager.adjustZoom(VideoFilterManager.zoomStep), 1.24);
    expect(manager.zoomScale, 1.24);
  });

  test('zoom scale snaps near 100 percent to exact default', () {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(player: player);
    addTearDown(manager.dispose);

    manager.setZoomScale(1.5);

    expect(manager.setZoomScale(1.00008), 1.0);
    expect(manager.zoomScale, 1.0);
    expect(manager.resetZoom(), 1.0);
  });

  test('video zoom property is exact zero at normalized default', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(player: player);
    addTearDown(manager.dispose);

    expect(VideoFilterManager.videoZoomPropertyForScale(1.00008), 0.0);

    manager.setZoomScale(1.00008);
    await Future<void>.delayed(Duration.zero);
    player.writes.clear();

    await manager.updateVideoFilter();

    final zoomWrites = player.writes.where((write) => write.key == 'video-zoom').toList();
    expect(zoomWrites, isNotEmpty);
    expect(zoomWrites.last.value, '0.0');
  });

  test('stretch mode applies the initial player size before a resize event', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(player: player, initialBoxFitMode: 2, initialPlayerSize: const Size(1920, 1080));
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();

    final aspectWrites = player.writes.where((write) => write.key == 'video-aspect-override').toList();
    expect(aspectWrites, isNotEmpty);
    expect(double.parse(aspectWrites.last.value), closeTo(16 / 9, 0.0001));
  });

  test('cover-mode zoom change writes only video-zoom', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(player: player, initialBoxFitMode: 1);
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();
    player.clearRecords();

    manager.setZoomScale(1.5);
    await Future<void>.delayed(Duration.zero);

    expect(player.boxFitCalls, isEmpty);
    expect(player.zoomCalls, [1.5]);
    expect(player.writes, hasLength(1));
    expect(player.writes.single.key, 'video-zoom');
    expect(player.writes.single.value, VideoFilterManager.videoZoomPropertyForScale(1.5).toString());
  });

  test('repeated run with unchanged state writes nothing', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(player: player);
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();
    player.clearRecords();

    await manager.updateVideoFilter();

    expect(player.writes, isEmpty);
    expect(player.boxFitCalls, isEmpty);
    expect(player.zoomCalls, isEmpty);
  });

  test('concurrent calls coalesce into one trailing re-run', () async {
    final player = _SlowRecordingPlayer();
    final manager = VideoFilterManager(player: player);
    addTearDown(manager.dispose);

    final first = manager.updateVideoFilter();
    manager.setZoomScale(0.8);
    await first;

    final zoomWrites = player.writes.where((write) => write.key == 'video-zoom').toList();
    expect(zoomWrites, hasLength(2));
    expect(zoomWrites.last.value, VideoFilterManager.videoZoomPropertyForScale(0.8).toString());
    expect(player.writes.where((write) => write.key == 'panscan'), hasLength(1));
    expect(player.writes.where((write) => write.key == 'sub-ass-force-margins'), hasLength(1));
    expect(player.zoomCalls, [1.0, 0.8]);
  });

  test('ambient-active run leaves aspect-override unknown', () async {
    final player = _RecordingPlayer();
    final ambient = _FakeAmbientLightingService(player);
    final manager = VideoFilterManager(player: player)..ambientLightingService = ambient;
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();
    player.clearRecords();

    ambient.fakeEnabled = true;
    await manager.updateVideoFilter();
    expect(player.writes.where((write) => write.key == 'video-aspect-override'), isEmpty);

    ambient.fakeEnabled = false;
    await manager.updateVideoFilter();
    final aspectWrites = player.writes.where((write) => write.key == 'video-aspect-override').toList();
    expect(aspectWrites, hasLength(1));
    expect(aspectWrites.single.value, 'no');
  });

  test('fill mode rewrites aspect on player size change', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(player: player, initialBoxFitMode: 2, initialPlayerSize: const Size(1920, 1080));
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();
    player.clearRecords();

    manager.updatePlayerSize(const Size(1000, 1000));
    // Cover the 50ms leading+trailing debounce.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final aspectWrites = player.writes.where((write) => write.key == 'video-aspect-override').toList();
    expect(aspectWrites, hasLength(1));
    expect(double.parse(aspectWrites.single.value), closeTo(1.0, 0.0001));
  });

  test('subtitle position is untouched without layer scaling', () {
    expect(VideoFilterManager.subtitlePositionForScale(100, 1.0), 100);
    expect(VideoFilterManager.subtitlePositionForScale(90, 1.00005), 90);
  });

  test('subtitle position pulls inward proportionally to the layer scale', () {
    // A bottom-aligned subtitle sits half a frame below center, so the scale
    // divides that offset: 0.5 + 0.5 / scale.
    expect(VideoFilterManager.subtitlePositionForScale(100, 1.33), 88);
    expect(VideoFilterManager.subtitlePositionForScale(100, 2.0), 75);
    expect(VideoFilterManager.subtitlePositionForScale(0, 2.0), 25);
  });

  test('subtitle position at center is scale invariant', () {
    for (final scale in [1.0, 1.33, 2.0, 10.0]) {
      expect(VideoFilterManager.subtitlePositionForScale(50, scale), 50);
    }
  });

  test('cover crop scale compensates only for vertical crop', () {
    // 4:3 content in a 16:9 player: mpv scales it up 4/3 to fill the width.
    expect(VideoFilterManager.coverCropScale(playerAspect: 16 / 9, videoAspect: 4 / 3), closeTo(4 / 3, 0.0001));
    // Wider-than-player content crops horizontally; no vertical compensation.
    expect(VideoFilterManager.coverCropScale(playerAspect: 16 / 9, videoAspect: 2.39), 1.0);
    // Degenerate inputs fall back to no compensation.
    expect(VideoFilterManager.coverCropScale(playerAspect: 0, videoAspect: 4 / 3), 1.0);
    expect(VideoFilterManager.coverCropScale(playerAspect: double.nan, videoAspect: 4 / 3), 1.0);
    expect(VideoFilterManager.coverCropScale(playerAspect: 16 / 9, videoAspect: double.infinity), 1.0);
  });

  test('mpv-native cover mode writes crop-compensated sub-pos and resets on contain', () async {
    final player = _RecordingPlayer()
      ..dwidth = '1440'
      ..dheight = '1080';
    final manager = VideoFilterManager(
      player: player,
      initialBoxFitMode: 1,
      initialPlayerSize: const Size(1920, 1080),
      subtitleBasePosition: () => 100,
      useLayerScaleCompensation: false,
    );
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();
    var subPosWrites = player.writes.where((write) => write.key == 'sub-pos').toList();
    // base 100 at scale 4/3 → 0.5 + 0.5 / (4/3) = 0.875 → 88.
    expect(subPosWrites, hasLength(1));
    expect(subPosWrites.single.value, '88');

    player.clearRecords();
    manager.cycleBoxFitMode(); // → fill
    manager.cycleBoxFitMode(); // → contain
    await manager.updateVideoFilter();
    subPosWrites = player.writes.where((write) => write.key == 'sub-pos').toList();
    expect(subPosWrites, isNotEmpty);
    expect(subPosWrites.last.value, '100');
  });

  test('mpv-native zoom-only compensation uses the zoom scale', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(
      player: player,
      subtitleBasePosition: () => 100,
      useLayerScaleCompensation: false,
    );
    addTearDown(manager.dispose);

    manager.setZoomScale(2.0);
    await Future<void>.delayed(Duration.zero);

    final subPosWrites = player.writes.where((write) => write.key == 'sub-pos').toList();
    expect(subPosWrites, isNotEmpty);
    expect(subPosWrites.last.value, '75');
  });

  test('mpv-native cover mode without video dimensions falls back to base position', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(
      player: player,
      initialBoxFitMode: 1,
      initialPlayerSize: const Size(1920, 1080),
      subtitleBasePosition: () => 90,
      useLayerScaleCompensation: false,
    );
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();

    final subPosWrites = player.writes.where((write) => write.key == 'sub-pos').toList();
    expect(subPosWrites, hasLength(1));
    expect(subPosWrites.single.value, '90');
  });

  test('layer-scale compensation path keeps the iOS transform math', () async {
    final player = _RecordingPlayer();
    final manager = VideoFilterManager(
      player: player,
      initialBoxFitMode: 1,
      subtitleBasePosition: () => 100,
      useLayerScaleCompensation: true,
    );
    addTearDown(manager.dispose);

    await manager.updateVideoFilter();

    final subPosWrites = player.writes.where((write) => write.key == 'sub-pos').toList();
    expect(subPosWrites, hasLength(1));
    expect(subPosWrites.single.value, VideoFilterManager.subtitlePositionForScale(100, 1.33).toString());
  });

  test('effective layer scale mirrors the native zoom and panscan transform', () {
    expect(
      VideoFilterManager.effectiveLayerScale(zoomScale: 1.0, coverMode: false, aspectOverrideActive: false),
      closeTo(1.0, 0.0001),
    );
    expect(
      VideoFilterManager.effectiveLayerScale(zoomScale: 1.0, coverMode: true, aspectOverrideActive: false),
      closeTo(1.33, 0.0001),
    );
    // Stretch mode overrides the aspect natively, so panscan is not applied.
    expect(
      VideoFilterManager.effectiveLayerScale(zoomScale: 1.5, coverMode: true, aspectOverrideActive: true),
      closeTo(1.5, 0.0001),
    );
  });
}

class _RecordingPlayer implements Player {
  final writes = <MapEntry<String, String>>[];
  final boxFitCalls = <int>[];
  final zoomCalls = <double>[];

  /// Display dimensions returned for the `dwidth`/`dheight` properties.
  String? dwidth;
  String? dheight;

  @override
  Future<String?> getProperty(String name) async {
    if (name == 'dwidth') return dwidth;
    if (name == 'dheight') return dheight;
    return null;
  }

  void clearRecords() {
    writes.clear();
    boxFitCalls.clear();
    zoomCalls.clear();
  }

  @override
  Future<void> setProperty(String name, String value) async {
    writes.add(MapEntry(name, value));
  }

  @override
  Future<void> setBoxFitMode(int mode) async {
    boxFitCalls.add(mode);
  }

  @override
  Future<void> setVideoZoom(double scale) async {
    zoomCalls.add(scale);
  }

  @override
  PlayerState get state => const PlayerState();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Delays each property write so single-flight coalescing can be observed.
class _SlowRecordingPlayer extends _RecordingPlayer {
  @override
  Future<void> setProperty(String name, String value) async {
    await super.setProperty(name, value);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class _FakeAmbientLightingService extends AmbientLightingService {
  _FakeAmbientLightingService(super.player);

  bool fakeEnabled = false;

  @override
  bool get isEnabled => fakeEnabled;
}

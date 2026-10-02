import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/video_display_preference_store.dart';
import 'package:pleya/services/video_filter_manager.dart';

import '../test_helpers/prefs.dart';

MediaItem _item(String id, {String? show, String server = 'server-a', MediaBackend backend = MediaBackend.plex}) =>
    MediaItem(
      id: id,
      backend: backend,
      kind: show == null ? MediaKind.movie : MediaKind.episode,
      grandparentId: show,
      serverId: server,
    );

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  test('screen-specific framing stays local to the device', () {
    final key = SettingsService.videoDisplayPreferences.key;
    expect(PreferenceSyncPolicyRegistry.isRegistered(key), isTrue);
    expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
    expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse);
  });

  test('user controls automatically save the fit and zoom pair for playback restart', () async {
    final store = await VideoDisplayPreferenceStore.forItem(_item('ep1', show: 'show'));
    final pending = <Future<void>>[];
    final manager = VideoFilterManager(
      player: _Player(),
      onDisplaySettingsChanged: (mode, zoom) => pending.add(store.save(boxFitMode: mode, zoomScale: zoom)),
    );
    addTearDown(manager.dispose);
    manager.cycleBoxFitMode();
    manager.setZoomScale(1.234);
    await Future.wait(pending);
    await manager.updateVideoFilter();

    final next = await VideoDisplayPreferenceStore.forItem(_item('ep2', show: 'show'));
    final saved = next.read()!;
    final restored = VideoFilterManager(
      player: _Player(),
      initialBoxFitMode: saved.boxFitMode,
      initialZoomScale: saved.zoomScale,
    );
    addTearDown(restored.dispose);
    expect(restored.boxFitMode, 1);
    expect(restored.zoomScale, 1.23);
    await restored.updateVideoFilter();
  });

  test('restores both settings after preferences are reloaded', () async {
    final store = await VideoDisplayPreferenceStore.forItem(_item('movie'));
    await store.save(boxFitMode: 2, zoomScale: 1.37);
    BaseSharedPreferencesService.resetForTesting();
    SettingsService.resetForTesting();

    final reopened = await VideoDisplayPreferenceStore.forItem(_item('movie'));
    expect(reopened.read(), (boxFitMode: 2, zoomScale: 1.37));
    expect((await VideoDisplayPreferenceStore.forItem(_item('other'))).read(), isNull);
  });

  for (final backend in MediaBackend.values) {
    test('all episodes share the series settings on ${backend.id}', () async {
      final first = await VideoDisplayPreferenceStore.forItem(_item('ep1', show: 'show', backend: backend));
      await first.save(boxFitMode: 1, zoomScale: 1.25);
      final next = await VideoDisplayPreferenceStore.forItem(_item('ep2', show: 'show', backend: backend));
      expect(next.read(), (boxFitMode: 1, zoomScale: 1.25));
      expect(first.matches(_item('ep2', show: 'show', backend: backend)), isTrue);
      expect((await VideoDisplayPreferenceStore.forItem(_item('ep3', show: 'other', backend: backend))).read(), isNull);
    });
  }

  test('identical IDs on different servers or backends stay separate', () async {
    final store = await VideoDisplayPreferenceStore.forItem(_item('movie'));
    await store.save(boxFitMode: 1, zoomScale: 1.1);
    expect((await VideoDisplayPreferenceStore.forItem(_item('movie', server: 'server-b'))).read(), isNull);
    expect((await VideoDisplayPreferenceStore.forItem(_item('movie', backend: MediaBackend.jellyfin))).read(), isNull);
  });

  test('a captured profile keeps pending writes out of the next profile', () async {
    final storage = await StorageService.getInstance();
    await storage.setActiveProfileId('profile-a');
    final a = await VideoDisplayPreferenceStore.forItem(_item('movie'));
    await storage.setActiveProfileId('profile-b');
    await a.save(boxFitMode: 2, zoomScale: 1.5);
    expect((await VideoDisplayPreferenceStore.forItem(_item('movie'))).read(), isNull);
    await storage.setActiveProfileId('profile-a');
    expect((await VideoDisplayPreferenceStore.forItem(_item('movie'))).read(), (boxFitMode: 2, zoomScale: 1.5));
  });

  test('rapid changes keep the latest settings and other titles', () async {
    final first = await VideoDisplayPreferenceStore.forItem(_item('first'));
    final second = await VideoDisplayPreferenceStore.forItem(_item('second'));
    await Future.wait([
      first.save(boxFitMode: 1, zoomScale: 1.2),
      second.save(boxFitMode: 2, zoomScale: 0.9),
      first.save(boxFitMode: 0, zoomScale: 1.0),
    ]);
    expect(first.read(), (boxFitMode: 0, zoomScale: 1.0));
    expect(second.read(), (boxFitMode: 2, zoomScale: 0.9));
  });

  test('invalid stored values fall back without losing valid entries', () async {
    final store = await VideoDisplayPreferenceStore.forItem(_item('movie'));
    await store.save(boxFitMode: 1, zoomScale: 1.2);
    final settings = await SettingsService.getInstance();
    final entries = settings.read(SettingsService.videoDisplayPreferences);
    final other = await VideoDisplayPreferenceStore.forItem(_item('other'));
    await other.save(boxFitMode: 2, zoomScale: 1.3);
    await settings.write(SettingsService.videoDisplayPreferences, {
      ...settings.read(SettingsService.videoDisplayPreferences),
      entries.keys.single: {'boxFitMode': 99, 'zoomScale': 'broken'},
    });
    expect(store.read(), isNull);
    expect(other.read(), (boxFitMode: 2, zoomScale: 1.3));
  });

  test('reset all settings removes remembered video settings', () async {
    final store = await VideoDisplayPreferenceStore.forItem(_item('movie'));
    await store.save(boxFitMode: 1, zoomScale: 1.2);
    await (await SettingsService.getInstance()).resetAllSettings();
    expect(store.read(), isNull);
  });
}

class _Player implements Player {
  @override
  Future<void> setBoxFitMode(int mode) async {}

  @override
  Future<void> setVideoZoom(double scale) async {}

  @override
  Future<void> setProperty(String name, String value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

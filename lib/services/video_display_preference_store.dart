import 'dart:async';
import 'dart:convert';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../utils/app_logger.dart';
import 'settings_service.dart';
import 'storage_service.dart';
import 'video_filter_manager.dart';

/// Device-local fit and zoom, shared by a show's episodes and scoped to the
/// profile, backend and server. Capture the key before any queued writes so a
/// profile or title switch cannot redirect a choice made on the outgoing item.
class VideoDisplayPreferenceStore {
  VideoDisplayPreferenceStore._(this._settings, String scope, MediaItem metadata)
    : _mediaKey = _keyFor(metadata),
      _key = jsonEncode([scope, ..._keyFor(metadata)]);

  final SettingsService _settings;
  final List<String> _mediaKey;
  final String _key;
  static Future<void> _writeLock = Future<void>.value();

  static Future<VideoDisplayPreferenceStore> forItem(MediaItem metadata) async {
    final storage = await StorageService.getInstance();
    final scope = storage.activeUserScope() ?? '';
    final settings = await SettingsService.getInstance();
    return VideoDisplayPreferenceStore._(settings, scope, metadata);
  }

  static List<String> _keyFor(MediaItem metadata) {
    final isEpisode = metadata.kind == MediaKind.episode;
    final showId = isEpisode ? metadata.grandparentId : null;
    return [
      metadata.backend.id,
      metadata.serverId ?? '',
      showId != null && showId.isNotEmpty ? 'show' : metadata.kind.id,
      showId != null && showId.isNotEmpty ? showId : metadata.id,
    ];
  }

  bool matches(MediaItem metadata) => jsonEncode(_mediaKey) == jsonEncode(_keyFor(metadata));

  ({int boxFitMode, double zoomScale})? read() {
    final raw = _settings.read(SettingsService.videoDisplayPreferences)[_key];
    if (raw is! Map) return null;
    final mode = raw['boxFitMode'];
    final zoom = raw['zoomScale'];
    if (mode is! int || mode < 0 || mode > 2 || zoom is! num || !zoom.isFinite) return null;
    return (boxFitMode: mode, zoomScale: VideoFilterManager.normalizeZoomScale(zoom.toDouble()));
  }

  Future<void> save({required int boxFitMode, required double zoomScale}) {
    final mode = boxFitMode.clamp(0, 2);
    final zoom = VideoFilterManager.normalizeZoomScale(zoomScale);
    final previous = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    return previous
        .then((_) async {
          try {
            final entries = {..._settings.read(SettingsService.videoDisplayPreferences)};
            entries[_key] = {'boxFitMode': mode, 'zoomScale': zoom};
            await _settings.write(SettingsService.videoDisplayPreferences, entries);
          } catch (error) {
            appLogger.w('Failed to save video display preferences', error: error);
          }
        })
        .whenComplete(completer.complete);
  }
}

import 'package:path/path.dart' as p;

import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_part.dart';
import '../media/media_source_info.dart';
import '../media/media_version.dart';
import 'playback_initialization_types.dart';

/// Server id of a video the system handed to Pleya ("Open in…", Files, Finder).
/// No client is registered under it: such a file belongs to no library, so
/// nothing is fetched for it and no progress is reported.
const kOpenedFileServerId = 'pleya-opened-file';

bool isOpenedFile(MediaItem item) => item.backend == MediaBackend.local && item.serverId == kOpenedFileServerId;

/// The item the player gets for the file at [path]. A clip, like a live
/// channel: it has no series around it and no resume position to fetch.
MediaItem openedFileItem(String path) {
  final title = p.basenameWithoutExtension(path);
  return MediaItem(
    id: path,
    backend: MediaBackend.local,
    kind: MediaKind.clip,
    title: title.isEmpty ? p.basename(path) : title,
    serverId: kOpenedFileServerId,
  );
}

/// Whether playback of [item] without a reachable server queues its progress
/// for a later sync. An opened file has no server, so its queue would never
/// drain and the file would show up under Continue Watching.
bool queuesOfflineProgress(MediaItem item, {required bool offlinePlayback}) => offlinePlayback && !isOpenedFile(item);

/// Playback data for an opened file: the file itself, nothing to negotiate.
/// mpv reads the audio and subtitle tracks from the container.
PlaybackInitializationResult openedFilePlayback(MediaItem item) {
  final path = item.id;
  final container = p.extension(path).replaceFirst('.', '').toLowerCase();
  return PlaybackInitializationResult(
    availableVersions: [
      MediaVersion(
        id: path,
        container: container,
        parts: [MediaPart(id: path, streamPath: path, sizeBytes: null, container: container, streams: const [])],
      ),
    ],
    videoUrl: path,
    mediaInfo: MediaSourceInfo(
      videoUrl: path,
      mediaSourceId: path,
      audioTracks: const [],
      subtitleTracks: const [],
      chapters: const [],
      trickplayByWidth: null,
    ),
    externalSubtitles: const [],
    isOffline: true,
    isTranscoding: false,
    selectedMediaIndex: 0,
  );
}

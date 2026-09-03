import '../../media/media_source_info.dart';
import '../../media/media_version.dart';

/// Consolidated data model containing all information needed for video playback.
/// This model combines data from multiple Plex API endpoints to reduce redundant requests.
class PlexVideoPlaybackData {
  final String? videoUrl;

  final MediaSourceInfo? mediaInfo;

  final List<MediaVersion> availableVersions;

  final List<MediaMarker> markers;

  final int selectedMediaIndex;

  final int selectedPartIndex;

  PlexVideoPlaybackData({
    required this.videoUrl,
    required this.mediaInfo,
    required this.availableVersions,
    this.markers = const [],
    this.selectedMediaIndex = 0,
    this.selectedPartIndex = 0,
  });

  bool get hasValidVideoUrl => videoUrl != null && videoUrl!.isNotEmpty;

  /// False when Plex flagged every version's file as missing or unreadable
  /// (`checkFiles=1`). A [videoUrl] is still built in that case, but opening
  /// it only yields a 404; callers should refuse up front instead.
  bool get hasPlayableVersion => availableVersions.isEmpty || availableVersions.any((v) => v.isPlayable);

  bool get hasMediaInfo => mediaInfo != null;
}

import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_part.dart';
import '../media/media_stream.dart';
import '../media/media_version.dart';
import '../models/pleya_server/pleya_wire.dart';
import '../models/pleya_server/pleya_wire_library.dart';
import '../utils/resolution_label.dart';
import '../utils/track_label_builder.dart';

/// Translates Pleya Protocol wire types into the app's neutral domain model.
///
/// This is the only place the two vocabularies meet. Nothing above it sees a
/// `Pleya*` type and nothing below it sees a `Media*` type, which is what keeps
/// `data_aggregation_service` and the screens free of a backend check. The
/// protocol is itself backend-neutral, so the translation is mostly renaming;
/// where it is not, the reason is written down at the spot.
class PleyaServerMappers {
  const PleyaServerMappers._();

  /// Artwork ids travel as an opaque path the client turns into a URL later.
  /// A bare id would be indistinguishable from a Plex `/library/metadata/...`
  /// path once it sits in `MediaItem.thumbPath`, and both end up in the same
  /// image cache. The prefix keeps them apart and gives `thumbnailUrl` an
  /// unambiguous thing to recognise.
  static const String artworkPathPrefix = 'pleya-artwork:';

  static String artworkPath(String artworkId) => '$artworkPathPrefix$artworkId';

  /// The artwork id inside a path built by [artworkPath], or null when the
  /// path came from somewhere else.
  static String? artworkIdFromPath(String? path) {
    if (path == null || !path.startsWith(artworkPathPrefix)) return null;
    final id = path.substring(artworkPathPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Sidecar subtitle paths get the same treatment for the same reason.
  static const String subtitlePathPrefix = 'pleya-subtitle:';

  static String subtitlePath(String subtitleId) => '$subtitlePathPrefix$subtitleId';

  static String? subtitleIdFromPath(String? path) {
    if (path == null || !path.startsWith(subtitlePathPrefix)) return null;
    final id = path.substring(subtitlePathPrefix.length);
    return id.isEmpty ? null : id;
  }

  static MediaKind kindOf(PleyaItemKind kind) => switch (kind) {
    PleyaItemKind.movie => MediaKind.movie,
    PleyaItemKind.show => MediaKind.show,
    PleyaItemKind.season => MediaKind.season,
    PleyaItemKind.episode => MediaKind.episode,
  };

  /// The kind a library holds. `MediaKind.unknown` for a kind this build does
  /// not know, which is what the contract asks a client to do with an
  /// unknown-safe value.
  static MediaKind libraryKindOf(PleyaLibraryKind? kind) => switch (kind) {
    PleyaLibraryKind.movies => MediaKind.movie,
    PleyaLibraryKind.shows => MediaKind.show,
    null => MediaKind.unknown,
  };

  static MediaLibrary library(PleyaLibrary wire, {required String serverId, String? serverName}) => MediaLibrary(
    id: wire.id,
    backend: MediaBackend.pleyaServer,
    title: wire.title,
    kind: libraryKindOf(wire.kind),
    serverId: serverId,
    serverName: serverName,
  );

  /// A page of items, with the entries this build cannot render left out.
  ///
  /// [libraryId] and [libraryTitle] are stamped from the call site: the
  /// contract puts no library reference on an `Item`, because an item can be
  /// reached through a library, a hub or a search and only the caller knows
  /// which of those happened.
  static List<MediaItem> items(
    Iterable<PleyaItem> wire, {
    required String serverId,
    String? serverName,
    String? libraryId,
    String? libraryTitle,
    Map<String, PleyaItem> parents = const {},
  }) => [
    for (final item in wire)
      if (item.kind != null)
        mediaItem(
          item,
          serverId: serverId,
          serverName: serverName,
          libraryId: libraryId,
          libraryTitle: libraryTitle,
          parent: parents[item.parentId],
          grandparent: _grandparentOf(item, parents),
        ),
  ];

  static PleyaItem? _grandparentOf(PleyaItem item, Map<String, PleyaItem> parents) {
    final parent = parents[item.parentId];
    return parent == null ? null : parents[parent.parentId];
  }

  /// One item.
  ///
  /// [parent] and [grandparent] fill the show/season columns the app's episode
  /// rows read. The contract carries only `parent_id`, so a caller that has the
  /// ancestors in hand passes them; one that has not leaves them null and the
  /// row renders with the ids alone rather than with a wrong title.
  static MediaItem mediaItem(
    PleyaItem wire, {
    required String serverId,
    String? serverName,
    String? libraryId,
    String? libraryTitle,
    PleyaItem? parent,
    PleyaItem? grandparent,
  }) {
    final kind = wire.kind;
    if (kind == null) {
      throw ArgumentError('PleyaServerMappers.mediaItem called with an unknown item kind');
    }
    final userState = wire.userState;
    final isEpisode = kind == PleyaItemKind.episode;
    return MediaItem(
      id: wire.id,
      backend: MediaBackend.pleyaServer,
      kind: kindOf(kind),
      title: wire.title,
      titleSort: wire.sortTitle,
      year: wire.year,
      // An episode hangs under a season and a season under a show, so an
      // episode's `parentId` is its season and its `grandparentId` its show.
      // That is the same shape the Plex and Jellyfin mappers produce, which is
      // why the episode rows need no backend check.
      parentId: wire.parentId,
      parentTitle: parent?.title,
      parentThumbPath: _posterPath(parent),
      parentIndex: isEpisode ? parent?.index : null,
      index: wire.index,
      grandparentId: isEpisode ? grandparent?.id ?? parent?.parentId : null,
      grandparentTitle: isEpisode ? grandparent?.title : null,
      grandparentThumbPath: isEpisode ? _posterPath(grandparent) : null,
      thumbPath: _posterPath(wire),
      artPath: _backdropPath(wire),
      durationMs: wire.durationMs,
      viewOffsetMs: userState?.positionMs,
      viewCount: userState?.playCount,
      // `updated_at` is when the state last moved, which is the closest thing
      // the contract has to "last viewed". Continue Watching sorts on it.
      lastViewedAt: userState == null ? null : userState.updatedAt.millisecondsSinceEpoch ~/ 1000,
      leafCount: wire.episodeCount,
      viewedLeafCount: wire.watchedEpisodeCount,
      childCount: wire.childCount,
      addedAt: wire.addedAt.millisecondsSinceEpoch ~/ 1000,
      mediaVersions: [for (final version in wire.versions) mediaVersion(version)],
      libraryId: libraryId,
      libraryTitle: libraryTitle,
      serverId: serverId,
      serverName: serverName,
    );
  }

  static String? _posterPath(PleyaItem? item) {
    final id = item?.artwork.posterId;
    return id == null ? null : artworkPath(id);
  }

  static String? _backdropPath(PleyaItem? item) {
    final id = item?.artwork.backdropId;
    return id == null ? null : artworkPath(id);
  }

  /// One version, with its streams.
  ///
  /// The contract has no per-version bitrate and no width or height on the
  /// version itself; those live on the video stream. The resolution label is
  /// derived from the first video stream, which is what the Jellyfin mapper
  /// does from the same raw pixel dimensions.
  static MediaVersion mediaVersion(PleyaVersion wire) {
    final video = wire.videoStreams.isEmpty ? null : wire.videoStreams.first;
    return MediaVersion(
      id: wire.id,
      width: video?.width,
      height: video?.height,
      videoResolution: resolutionLabelFromDimensions(video?.width, video?.height),
      videoCodec: video?.codec,
      container: wire.container,
      // The edition is the version's name. It is the whole reason two cuts of
      // one title stay apart in the version picker, so it maps onto the field
      // the picker already reads instead of a new one.
      name: wire.edition,
      parts: [
        MediaPart(
          // A version can span several files, and the contract gives only a
          // count, not per-file ids. The part therefore carries the version's
          // id: it is the unit a stream request names in PS-4, and inventing
          // a per-file id here would invent an identifier the server cannot
          // resolve.
          id: wire.id,
          container: wire.container,
          durationMs: wire.durationMs,
          streams: mediaStreams(wire),
        ),
      ],
    );
  }

  /// Every stream of a version, in the order video, audio, subtitle.
  static List<MediaStream> mediaStreams(PleyaVersion wire) => [
    for (final stream in wire.videoStreams) _videoStream(stream),
    for (final stream in wire.audioStreams) _audioStream(stream),
    for (final stream in wire.subtitleStreams)
      // A format this build cannot render is left out rather than offered and
      // then failed at selection time.
      if (stream.format != null) _subtitleStream(stream),
  ];

  static MediaStream _videoStream(PleyaVideoStream wire) => MediaStream(
    id: wire.id,
    kind: MediaStreamKind.video,
    index: wire.index,
    codec: wire.codec,
    profile: wire.profile,
    frameRate: wire.frameRate,
    // HDR and Dolby Vision are deliberately not derived here. The contract
    // carries `bit_depth` and a codec profile and nothing else, and turning
    // that into an HDR verdict is planner policy that PS-6 owns. Guessing it
    // in a mapper is how a client ends up disagreeing with its own server.
  );

  static MediaStream _audioStream(PleyaAudioStream wire) {
    final label = TrackLabelBuilder.audioLabel(
      title: wire.title,
      languageCode: wire.language,
      codec: wire.codec,
      channels: wire.channels,
      index: wire.index,
    );
    return MediaStream(
      id: wire.id,
      kind: MediaStreamKind.audio,
      index: wire.index,
      codec: wire.codec,
      languageCode: wire.language,
      title: wire.title,
      displayTitle: label.joined,
      selected: wire.isDefault,
      channels: wire.channels,
    );
  }

  static MediaStream _subtitleStream(PleyaSubtitleStream wire) {
    final codec = wire.format?.name;
    final label = TrackLabelBuilder.subtitleLabel(
      title: wire.title,
      languageCode: wire.language,
      codec: codec,
      forced: wire.isForced,
      index: wire.index ?? 0,
    );
    return MediaStream(
      id: wire.id,
      kind: MediaStreamKind.subtitle,
      index: wire.index,
      codec: codec,
      languageCode: wire.language,
      title: wire.title,
      displayTitle: label.joined,
      selected: wire.isDefault,
      forced: wire.isForced,
      // Only an external track gets a sidecar path. `MediaStream.isExternal`
      // reads exactly this field, so an embedded track must leave it null even
      // though the contract would happily let both carry an id.
      sidecarPath: wire.isExternal ? subtitlePath(wire.id) : null,
    );
  }
}

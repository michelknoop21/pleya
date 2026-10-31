part of '../../pleya_server_client.dart';

/// What a detail page can show and the Pleya protocol has no field for: scores,
/// reviews, portraits, a logo, extras, rows of titles and the file's tracks.
///
/// Only a Verify build asks, against the fake server's `/verify/detail/{id}`, so
/// a scenario can walk the page as a viewer on Plex sees it. `kPleyaVerify` is a
/// compile-time constant: everywhere else every override below is the one
/// `super` call, and the protocol stays what `openapi.yaml` says it is.
mixin _PleyaVerifyDetailMethods on _PleyaServerRequests, _PleyaServerBrowseMethods, _PleyaServerUnsupportedMethods {
  PleyaServerConnection get connection;

  Future<Map<String, dynamic>?> _verifyDetail(String id) => _getJson('/verify/detail/${Uri.encodeComponent(id)}');

  /// Where a Verify build reads Trakt's routes instead of api.trakt.tv: this
  /// fixture's, without a token, as Trakt is read without one.
  String get verifyTraktBase => '${connection.baseUrl}$pleyaProtocolPrefix/verify/trakt';

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    if (!kPleyaVerify) return super.fetchExternalIds(itemId);
    final ids = (await _verifyDetail(itemId))?['external_ids'];
    return ids is Map<String, dynamic> ? ExternalIds.fromJson(ids) : const ExternalIds();
  }

  List<Map<String, dynamic>> _verifyList(Object? raw) => [
    for (final entry in raw is List ? raw : const [])
      if (entry is Map<String, dynamic>) entry,
  ];

  Future<List<MediaItem>> _verifyItems(Object? ids) async {
    final wanted = ids is List ? ids.whereType<String>() : const <String>[];
    return (await Future.wait(wanted.map(fetchItem))).nonNulls.toList();
  }

  @override
  Future<MediaItem?> fetchItem(String id) async {
    final item = await super.fetchItem(id);
    if (!kPleyaVerify || item == null) return item;
    final detail = await _verifyDetail(id);
    if (detail == null) return item;
    final logo = detail['clear_logo_id'];
    return item.copyWith(
      clearLogoPath: logo is String ? PleyaServerMappers.artworkPath(logo) : null,
      externalRatings: [for (final json in _verifyList(detail['external_ratings'])) ExternalRating.fromJson(json)],
      reviews: [for (final json in _verifyList(detail['reviews'])) MediaReview.fromJson(json)],
      roles: detail['roles'] == null
          ? item.roles
          : [
              for (final json in _verifyList(detail['roles']))
                MediaRole(
                  id: json['id'] as String?,
                  tag: json['tag'] as String,
                  role: json['role'] as String?,
                  thumbPath: switch (json['thumb_id']) {
                    final String thumb => PleyaServerMappers.artworkPath(thumb),
                    _ => null,
                  },
                ),
            ],
    );
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async {
    if (!kPleyaVerify) return super.fetchExtras(id);
    return [
      for (final json in _verifyList((await _verifyDetail(id))?['extras']))
        MediaItem(
          id: json['id'] as String,
          backend: MediaBackend.pleyaServer,
          kind: MediaKind.clip,
          title: json['title'] as String,
          thumbPath: PleyaServerMappers.artworkPath(json['thumb_id'] as String),
          serverId: serverId.toString(),
          serverName: serverName,
          raw: {'ExtraType': json['type']},
        ),
    ];
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async {
    if (!kPleyaVerify) return super.fetchRelatedHubs(id, count: count);
    return [
      for (final json in _verifyList((await _verifyDetail(id))?['rows']))
        MediaHub(
          id: json['id'] as String,
          identifier: json['identifier'] as String?,
          title: json['title'] as String,
          type: 'movie',
          items: await _verifyItems(json['item_ids']),
        ),
    ];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    if (!kPleyaVerify) return super.fetchPersonMediaPage(personId, start: start, size: size, abort: abort);
    final items = await _verifyItems((await _verifyDetail(personId))?['item_ids']);
    return LibraryPage(items: items, totalCount: items.length);
  }

  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    if (!kPleyaVerify) return super.getFileInfo(item);
    final json = (await _verifyDetail(item.id))?['file_info'];
    if (json is! Map<String, dynamic>) return null;
    return MediaFileInfo(
      videoResolution: json['video_resolution'] as String?,
      videoCodec: json['video_codec'] as String?,
      videoProfile: json['video_profile'] as String?,
      audioTracks: [
        for (final track in _verifyList(json['audio']))
          MediaAudioTrack(
            id: track['id'] as int,
            codec: track['codec'] as String?,
            language: track['language'] as String?,
            languageCode: track['language_code'] as String?,
            displayTitle: track['language'] as String?,
            channels: track['channels'] as int?,
            profile: track['profile'] as String?,
            selected: track['id'] == 0,
          ),
      ],
      subtitleTracks: [
        for (final track in _verifyList(json['subtitles']))
          MediaSubtitleTrack(
            id: track['id'] as int,
            language: track['language'] as String?,
            languageCode: track['language_code'] as String?,
            displayTitle: track['language'] as String?,
            selected: false,
            forced: false,
          ),
      ],
    );
  }
}

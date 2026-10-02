part of 'assistant_tools.dart';

/// Per-title chores: downloads for offline viewing and subtitles.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run. Every field is a thin view on the services the
/// app already uses, so the Assistant takes the same path as the download
/// button and inherits its checks (profile claim, version choice, queue).
class AssistantMediaServices {
  const AssistantMediaServices({
    required this.downloadsSupported,
    required this.downloadStatus,
    required this.queueEpisode,
    required this.blockedOnCellular,
  });

  /// `DownloadManagerService.downloadsSupported` (false on tvOS).
  final bool downloadsSupported;

  /// `DownloadProvider.getProgress(globalKey)?.status`: what this profile
  /// already has on the device, or null.
  final DownloadStatus? Function(String globalKey) downloadStatus;

  /// `DownloadProvider.queueDownload(episode, client) > 0`: queue one episode
  /// as the download button does. False means it was skipped.
  final Future<bool> Function(MediaItem episode, MediaServerClient client) queueEpisode;

  /// `DownloadManagerService.shouldBlockDownloadOnCellular`.
  final Future<bool> Function() blockedOnCellular;
}

const _onDevice = {DownloadStatus.queued, DownloadStatus.downloading, DownloadStatus.paused, DownloadStatus.completed};

/// Subtitle candidates shown in this run, keyed `server|item|subtitle`. Only
/// these can be downloaded, and each at most once.
final _subtitleCandidates = Expando<Map<String, ({PlexSubtitleSearchResult result, String language})>>();

/// The Plex client when this profile may add subtitles to [id]'s shared
/// items right now: the player's own rule (`canOfferSubtitleSearch`), on top
/// of [AssistantToolContext.adminClient]. Jellyfin has no search path in
/// Pleya, so only a backend advertising `externalSubtitleSearch` qualifies.
PlexClient? _subtitleClient(AssistantToolContext ctx, ServerId id) {
  if (ctx.media == null) return null;
  final client = ctx.adminClient(id);
  if (client is! PlexClient || !client.capabilities.externalSubtitleSearch) return null;
  return ctx.servers.canManageServerMetadata(id) ? client : null;
}

bool _downloadsServed(AssistantToolContext ctx, ServerId id) =>
    (ctx.media?.downloadsSupported ?? false) && ctx.userClient(id) != null;

/// An item shown in this run, fetched fresh from the server.
Future<MediaItem> _shownItem(AssistantToolContext ctx, MediaServerClient client, ServerId id, String itemId) async {
  ctx.requireShownItem(id, itemId);
  final item = await client.fetchItem(itemId);
  if (item == null) throw const AssistantToolError('unknown_item_id');
  return item.serverId == null ? item.copyWith(serverId: id.value) : item;
}

Map<String, Object?> _episodeRow(MediaItem episode, String status) => {
  'title': clipText(episode.title),
  if (episode.parentIndex != null) 'season': episode.parentIndex,
  if (episode.index != null) 'episode': episode.index,
  'status': status,
};

final List<AssistantTool> _mediaTools = [
  AssistantTool(
    name: 'download_next',
    description:
        'Download the next unwatched episodes of a series or season (item_id from find_media) to this device. $_serverIdNote',
    risk: AssistantToolRisk.mutation,
    properties: const {
      'item_id': {'type': 'string'},
      'count': {'type': 'integer', 'minimum': 1, 'maximum': 10},
    },
    required: const ['item_id', 'count'],
    serves: _downloadsServed,
    run: (ctx, id, args) async {
      final count = args['count'];
      if (count is! int || count < 1 || count > 10) throw const AssistantToolError('invalid_count');
      final client = ctx.userClient(id!)!;
      final container = await _shownItem(ctx, client, id, _string(args, 'item_id'));
      if (container.kind != MediaKind.show && container.kind != MediaKind.season) {
        throw const AssistantToolError('not_a_series');
      }
      final media = ctx.media!;
      if (await media.blockedOnCellular()) throw const AssistantToolError('downloads_blocked_on_cellular');
      // The download dialog's "next N unwatched": aired order, in progress
      // counts as unwatched, Specials only when the season is that folder.
      final episodes = <MediaItem>[];
      if (container.kind == MediaKind.show) {
        await collectEpisodesForShow(
          client,
          container.id,
          unwatchedOnly: true,
          out: episodes,
          fallback: container,
          includeSpecials: false,
        );
      } else {
        await collectEpisodesForSeason(client, container.id, unwatchedOnly: true, out: episodes, fallback: container);
      }
      var queued = 0;
      final report = <Map<String, Object?>>[];
      for (final episode in episodes.take(count)) {
        if (_onDevice.contains(media.downloadStatus(episode.globalKey))) {
          report.add(_episodeRow(episode, 'already_on_device'));
          continue;
        }
        // Visibility or connectivity may change between episodes.
        final live = ctx.userClient(id) ?? (throw const AssistantToolError('server_not_available'));
        String status;
        try {
          status = await media.queueEpisode(episode, live) ? 'queued' : 'not_downloadable';
        } catch (e) {
          appLogger.w('Assistant: queueing an episode failed', error: e.runtimeType);
          status = 'failed';
        }
        if (status == 'queued') queued++;
        report.add(_episodeRow(episode, status));
      }
      final title = container.kind == MediaKind.season
          ? (container.parentTitle ?? container.title ?? container.id)
          : (container.title ?? container.id);
      return AssistantToolResult(
        {'series': clipText(title), 'episodes': report, if (episodes.isEmpty) 'status': 'nothing_unwatched'},
        record: queued == 0
            ? null
            : AssistantActionRecord(
                kind: AssistantActionKind.downloadEpisodes,
                serverName: ctx.serverName(id),
                subject: title,
              ),
      );
    },
  ),
  AssistantTool(
    name: 'find_subtitles',
    description:
        'Search online subtitles in one language (ISO 639-1 code, e.g. "nl") for a film or episode from find_media. $_serverIdNote',
    risk: AssistantToolRisk.read,
    properties: const {
      'item_id': {'type': 'string'},
      'language': {'type': 'string'},
    },
    required: const ['item_id', 'language'],
    serves: (ctx, id) => _subtitleClient(ctx, id) != null,
    run: (ctx, id, args) async {
      final language = _string(args, 'language').toLowerCase();
      if (!RegExp(r'^[a-z]{2,3}$').hasMatch(language)) throw const AssistantToolError('invalid_language');
      final client = _subtitleClient(ctx, id!)!;
      final item = await _shownItem(ctx, client, id, _string(args, 'item_id'));
      if (item.kind != MediaKind.movie && item.kind != MediaKind.episode) {
        throw const AssistantToolError('not_playable');
      }
      final results = await client.searchSubtitles(item.id, language: language);
      final shown = _subtitleCandidates[ctx] ??= {};
      return AssistantToolResult({
        'title': clipText(item.title),
        'subtitles': [
          for (final r in results.where((r) => r.key.isNotEmpty).take(10))
            () {
              shown['${id.value}|${item.id}|${r.id}'] = (result: r, language: language);
              return {
                'subtitle_id': '${r.id}',
                'language': clipText(r.language ?? r.languageCode ?? language, 32),
                'provider': clipText(r.providerTitle, 40),
                'title': clipText(r.displayTitle ?? r.title),
                'hearing_impaired': r.hearingImpaired,
                'forced': r.forced,
                'already_on_server': r.downloaded,
              };
            }(),
        ],
      });
    },
  ),
  AssistantTool(
    name: 'download_subtitle',
    description:
        'Add one subtitle from find_subtitles to the item on the server, for every user. The user confirms in Pleya. $_serverIdNote',
    risk: AssistantToolRisk.sensitive,
    properties: const {
      'item_id': {'type': 'string'},
      'subtitle_id': {'type': 'string'},
    },
    required: const ['item_id', 'subtitle_id'],
    serves: (ctx, id) => _subtitleClient(ctx, id) != null,
    run: (ctx, id, args) async {
      final itemId = _string(args, 'item_id');
      ctx.requireShownItem(id!, itemId);
      final key = '${id.value}|$itemId|${_string(args, 'subtitle_id')}';
      final candidate = _subtitleCandidates[ctx]?[key];
      if (candidate == null) throw const AssistantToolError('unknown_subtitle_id');
      final item = await _shownItem(ctx, _subtitleClient(ctx, id)!, id, itemId);
      final r = candidate.result;
      return AssistantPendingAction(
        kind: AssistantActionKind.downloadSubtitle,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: clipText(item.title ?? itemId),
        items: [
          [
            r.language ?? r.languageCode ?? candidate.language,
            ?r.providerTitle,
            if (r.hearingImpaired) 'SDH',
            if (r.forced) 'forced',
          ].map((s) => clipText(s, 40)).join(' · '),
        ],
        execute: ({password}) async {
          // One card, one download: the candidate is used up here.
          if (_subtitleCandidates[ctx]?.remove(key) == null) throw const AssistantToolError('unknown_subtitle_id');
          final client = _subtitleClient(ctx, id) ?? (throw const AssistantToolError('server_not_available'));
          // Same arguments as the player's subtitle search sheet.
          final ok = await client.downloadSubtitle(
            itemId,
            key: r.key,
            codec: r.codec ?? 'srt',
            language: r.languageCode ?? candidate.language,
            hearingImpaired: r.hearingImpaired,
            forced: r.forced,
            providerTitle: r.providerTitle ?? '',
          );
          return {'status': ok ? 'subtitle_requested' : 'failed'};
        },
      );
    },
  ),
];

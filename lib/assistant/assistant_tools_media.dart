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

/// More new downloads than this go through a confirmation card, so one
/// planted instruction cannot fill the device unseen.
const _directDownloadLimit = 3;

/// Candidate episodes after [start], in aired order: a show or season gives
/// its next unwatched episodes (in progress counts as unwatched, Specials only
/// when the season is that folder), as the download dialog does; an episode
/// gives itself and every later episode of its series, watched or not.
Future<List<MediaItem>> _episodesFrom(MediaServerClient client, MediaItem start) async {
  final episodes = <MediaItem>[];
  switch (start.kind) {
    case MediaKind.show:
      await collectEpisodesForShow(
        client,
        start.id,
        unwatchedOnly: true,
        out: episodes,
        fallback: start,
        includeSpecials: false,
      );
    case MediaKind.season:
      await collectEpisodesForSeason(client, start.id, unwatchedOnly: true, out: episodes, fallback: start);
    case MediaKind.episode:
      final showId = start.grandparentId ?? (throw const AssistantToolError('not_a_series'));
      await collectEpisodesForShow(
        client,
        showId,
        unwatchedOnly: false,
        out: episodes,
        includeSpecials: isSpecialSeasonNumber(start.parentIndex),
      );
      final at = episodes.indexWhere((e) => e.id == start.id);
      if (at < 0) throw const AssistantToolError('episode_not_in_series');
      return episodes.sublist(at);
    default:
      throw const AssistantToolError('not_a_series');
  }
  return episodes;
}

/// Queues [episodes] one by one, as the download button would.
Future<({List<Map<String, Object?>> report, int queued})> _queueEpisodes(
  AssistantToolContext ctx,
  ServerId id,
  List<MediaItem> episodes,
) async {
  final media = ctx.media!;
  var queued = 0;
  final report = <Map<String, Object?>>[];
  for (final episode in episodes) {
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
  return (report: report, queued: queued);
}

String _episodeLabel(MediaItem e) => clipText(
  [if (e.parentIndex != null) 'S${e.parentIndex}', if (e.index != null) 'E${e.index}', ?e.title].join(' '),
  60,
);

final List<AssistantTool> _mediaTools = [
  AssistantTool(
    name: 'download_next',
    description:
        'Download the next N new episodes to this device. item_id from find_media: a series or season continues '
        'with its next unwatched episodes; an episode starts at that episode. Episodes already on the device are '
        'skipped and do not count. More than $_directDownloadLimit episodes: the user confirms in Pleya. $_serverIdNote',
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
      final start = await _shownItem(ctx, client, id, _string(args, 'item_id'));
      if (start.kind != MediaKind.show && start.kind != MediaKind.season && start.kind != MediaKind.episode) {
        throw const AssistantToolError('not_a_series');
      }
      final media = ctx.media!;
      if (await media.blockedOnCellular()) throw const AssistantToolError('downloads_blocked_on_cellular');
      final episodes = await _episodesFrom(client, start);
      // As DownloadProvider's skipExisting: what is on the device is passed
      // over without counting, so N means N new downloads.
      final picked = <MediaItem>[];
      var onDevice = 0;
      for (final episode in episodes) {
        final withServer = episode.serverId == null ? episode.copyWith(serverId: start.serverId) : episode;
        if (_onDevice.contains(media.downloadStatus(withServer.globalKey))) {
          onDevice++;
          continue;
        }
        picked.add(withServer);
        if (picked.length == count) break;
      }
      final title =
          switch (start.kind) {
            MediaKind.season => start.parentTitle,
            MediaKind.episode => start.grandparentTitle,
            _ => start.title,
          } ??
          start.title ??
          start.id;
      Map<String, Object?> summary(List<Map<String, Object?>> rows) => {
        'series': clipText(title),
        'episodes': rows,
        if (onDevice > 0) 'already_on_device': onDevice,
        if (episodes.isEmpty) 'status': 'nothing_unwatched' else if (picked.isEmpty) 'status': 'all_on_device',
      };
      if (picked.length > _directDownloadLimit) {
        return AssistantPendingAction(
          kind: AssistantActionKind.downloadEpisodes,
          serverId: id,
          serverName: ctx.serverName(id),
          subject: clipText(title),
          items: [for (final e in picked) _episodeLabel(e)],
          execute: ({password}) async {
            // The card may have been open while the device left Wi-Fi.
            if (await media.blockedOnCellular()) throw const AssistantToolError('downloads_blocked_on_cellular');
            final queued = await _queueEpisodes(ctx, id, picked);
            return {...summary(queued.report), if (queued.queued == 0) 'done': false};
          },
        );
      }
      final result = await _queueEpisodes(ctx, id, picked);
      return AssistantToolResult(
        summary(result.report),
        record: result.queued == 0
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
          return {'status': ok ? 'subtitle_requested' : 'failed', if (!ok) 'done': false};
        },
      );
    },
  ),
];

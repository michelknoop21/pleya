part of '../../plex_client.dart';

/// One completed view from the server-wide history. [showTitle] is set for an
/// episode only. [viewedAt] is in epoch seconds. [userName] is null when
/// `/accounts` does not name the account.
typedef PlexHistoryPlay = ({
  int accountId,
  String? userName,
  String type,
  String title,
  String? showTitle,
  int viewedAt,
});

/// One stream from `/status/sessions`, in the same record shape as
/// `JellyfinActiveSession` and `PleyaActiveStream` so a reader treats all
/// three alike. No session id, address or token is carried.
typedef PlexActiveStream = ({
  String userName,
  String title,
  String? episode,
  int progressPercent,
  bool? paused,
  bool? transcoding,
  String? device,
});

/// What a Plex server itself says is being watched, for admins without a
/// (working) Tautulli. Both routes are owner-token only: pass the owner token
/// via `authToken`, like [PlexClient.fetchItemWatchers]. Errors are thrown,
/// not swallowed, so a caller can tell "nobody watched" from "no answer".
extension PlexServerActivity on PlexClient {
  /// Films and episodes viewed since [since], newest first, at most [cap].
  /// Plex is asked to filter (`viewedAt>`, as python-plexapi's
  /// `PlexServer.history(mindate=)` does); rows are filtered here too, and
  /// paging stops at the first older row, in case the server ignores it.
  /// At most four times [cap] rows are read, kept or not (music), so a
  /// history of skipped rows ends too.
  Future<({List<PlexHistoryPlay> plays, bool capped})> fetchServerHistory({
    required DateTime since,
    String? authToken,
    int pageSize = 500,
    int cap = 5000,
  }) async {
    final from = since.millisecondsSinceEpoch ~/ 1000;
    final headers = authToken == null ? null : {'X-Plex-Token': authToken};
    final rows = <({int accountId, String type, String title, String? showTitle, int viewedAt})>[];
    var start = 0;
    var capped = false;
    page:
    while (true) {
      if (start >= cap * 4) {
        capped = true;
        break;
      }
      final response = await _getWithFailover(
        '/status/sessions/history/all',
        queryParameters: {
          'sort': 'viewedAt:desc',
          'viewedAt>': '$from',
          'X-Plex-Container-Start': '$start',
          'X-Plex-Container-Size': '$pageSize',
        },
        headers: headers,
      );
      final page = (_getMediaContainer(response)?['Metadata'] as List?) ?? const [];
      for (final raw in page.whereType<Map<String, dynamic>>()) {
        final viewedAt = flexibleInt(raw['viewedAt']);
        // A row without a date says nothing about the period; the next may.
        if (viewedAt == null) continue;
        if (viewedAt < from) break page;
        final type = raw['type'] as String? ?? '';
        final accountId = flexibleInt(raw['accountID']);
        if (accountId == null || (type != 'movie' && type != 'episode')) continue;
        if (rows.length >= cap) {
          capped = true;
          break page;
        }
        rows.add((
          accountId: accountId,
          type: type,
          title: raw['title'] as String? ?? '',
          showTitle: type == 'episode' ? raw['grandparentTitle'] as String? : null,
          viewedAt: viewedAt,
        ));
      }
      if (page.length < pageSize) break;
      start += page.length;
    }
    if (rows.isEmpty) return (plays: const <PlexHistoryPlay>[], capped: capped);
    final accounts = await fetchServerAccounts(authToken: authToken);
    return (
      plays: [
        for (final r in rows)
          (
            accountId: r.accountId,
            userName: accounts[r.accountId]?.name.isNotEmpty == true ? accounts[r.accountId]!.name : null,
            type: r.type,
            title: r.title,
            showTitle: r.showTitle,
            viewedAt: r.viewedAt,
          ),
      ],
      capped: capped,
    );
  }

  /// Everything playing on the server now, every user's.
  Future<List<PlexActiveStream>> fetchActiveStreams({String? authToken}) async {
    final response = await _getWithFailover(
      '/status/sessions',
      headers: authToken == null ? null : {'X-Plex-Token': authToken},
    );
    final rows = (_getMediaContainer(response)?['Metadata'] as List?) ?? const [];
    return [for (final raw in rows.whereType<Map<String, dynamic>>()) _activeStream(raw)];
  }

  PlexActiveStream _activeStream(Map<String, dynamic> raw) {
    Map<String, dynamic> child(String key) => raw[key] is Map<String, dynamic> ? raw[key] as Map<String, dynamic> : {};
    final player = child('Player');
    final transcode = child('TranscodeSession');
    final isEpisode = raw['type'] == 'episode';
    final name = raw['title'] as String?;
    final season = flexibleInt(raw['parentIndex']), number = flexibleInt(raw['index']);
    final offset = flexibleInt(raw['viewOffset']), duration = flexibleInt(raw['duration']);
    final device = [?player['title'] as String?, ?player['product'] as String?].join(' · ');
    return (
      userName: child('User')['title'] as String? ?? '',
      title: (isEpisode ? raw['grandparentTitle'] as String? : null) ?? name ?? '',
      episode: isEpisode ? [if (season != null && number != null) 'S$season · E$number', ?name].join(' ') : null,
      progressPercent: offset != null && duration != null && duration > 0
          ? (offset * 100 / duration).round().clamp(0, 100).toInt()
          : 0,
      paused: player['state'] is String ? player['state'] == 'paused' : null,
      // No TranscodeSession is a direct play or direct stream.
      transcoding: transcode['videoDecision'] == 'transcode' || transcode['audioDecision'] == 'transcode',
      device: device.isEmpty ? null : device,
    );
  }
}

part of 'assistant_tools.dart';

// The asker's own watching: "a tip for me", "what did I watch". watch_stats
// covers everyone on the servers under their server account names, which need
// not match the profile; this reads the profile's own log, the one Home's
// personal rows are built from (DEC-132), and only ever this profile's.

/// Wired in by the UI layer from the profile session. Each function answers
/// for the active profile only and empty when personalization is off.
class AssistantPersonalServices {
  const AssistantPersonalServices({
    required this.userName,
    required this.recent,
    required this.everSeen,
    required this.taste,
    required this.picks,
  });

  /// The profile's display name, for the system prompt.
  final String userName;

  /// Newest titles this profile watched, newest first.
  final Future<List<RecommendationSeed>> Function() recent;

  /// Global keys of every title in this profile's log, not just the newest few
  /// of [recent]: a title seen months ago is still seen. The log keeps a year.
  final Future<Set<String>> Function() everSeen;
  final Future<AffinityVector> Function() taste;

  /// Home's personal rows, built from [clients].
  final Future<List<MediaHub>> Function(List<MediaServerClient> clients) picks;
}

const _recentShown = 8;
const _picksShown = 12;
const _picksShownConstrained = 6;

final List<AssistantTool> _personalTools = [
  AssistantTool(
    name: 'my_watching',
    description:
        'The user\'s own watching on this Pleya profile, for anything about "I", "me" or "my": what they watched '
        'lately (only the newest titles of the last weeks, see watched_recently_window_days; never say it is all they watched), what they like (genres, actors, directors) and Pleya\'s personal picks for them from their own '
        'libraries, each with the row it comes from ("Because you watched ..."). Use it for a tip for the user or '
        'a question about their history. watch_stats is everyone on the servers under server account names. '
        'Empty lists mean no history yet or personal recommendations switched off; say so. Pass kind when the '
        'user asks for films or for series only, and exclude_kids when they want kids titles left out (a shared '
        'account); the lists and the cards then hold only what fits.',
    risk: AssistantToolRisk.read,
    properties: const {
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show'],
      },
      'exclude_kids': {'type': 'boolean'},
    },
    needsServer: false,
    serves: (ctx, _) => ctx.personal != null,
    run: (ctx, _, args) async {
      final personal = ctx.personal ?? (throw const AssistantToolError('personal_unavailable'));
      // The run's constraints (from the prompt) widened by what the model passed.
      final c = ctx.recommend = ctx.recommend.merge(
        AssistantRecommendConstraints(
          kind: switch (args['kind']) {
            'movie' => MediaKind.movie,
            'show' => MediaKind.show,
            _ => null,
          },
          excludeKids: args['exclude_kids'] == true,
        ),
      );
      final clients = {for (final id in ctx.userServers) id: ?ctx.userClient(id)};
      final (seeds, everSeen, taste, hubs) = await (
        personal.recent(),
        personal.everSeen(),
        personal.taste(),
        personal.picks(clients.values.toList()),
      ).wait;

      final watched = await Future.wait([
        for (final seed in seeds.take(_recentShown))
          if (parseGlobalKey(seed.globalKey) case final key? when clients[key.serverId] != null)
            clients[key.serverId]!
                .fetchItem(key.ratingKey)
                .then<Map<String, Object?>?>(
                  (item) => item?.title == null || (c.excludeKids && AssistantRecommendConstraints.isKids(item!))
                      ? null
                      : {
                          'title': clipText(
                            item!.kind == MediaKind.episode ? item.grandparentTitle ?? item.title : item.title,
                          ),
                          'kind': (item.kind == MediaKind.episode ? MediaKind.show : item.kind).name,
                          if (item.year != null && item.kind != MediaKind.episode) 'year': item.year,
                          'finished': seed.completed,
                        },
                )
                .catchError((Object _) => null),
      ]);

      final watchedList = watched.nonNulls.toList();
      // Another server's copy of a watched title is as seen as this one.
      final seenTitles = {for (final w in watchedList) (assistantTitleKey(w['title'] as String), w['year'] as int?)};
      bool seenBefore(MediaItem item) =>
          c.excludeWatched &&
          (everSeen.contains(item.globalKey) ||
              seenTitles.any(
                (s) =>
                    s.$1 == assistantTitleKey(item.title ?? '') &&
                    (s.$2 == null || item.year == null || s.$2 == item.year),
              ));
      final limit = c.active ? _picksShownConstrained : _picksShown;
      final picks = <MediaItem>[];
      final rows = <Map<String, Object?>>[];
      final seen = <String>{};
      for (final hub in hubs) {
        final titles = <Map<String, Object?>>[];
        for (final item in hub.items) {
          final serverId = item.serverId;
          if (serverId == null || picks.length >= limit || !c.admitsItem(item) || seenBefore(item)) continue;
          if (!seen.add(item.globalKey)) continue;
          ctx.showItem(ServerId(serverId), item.id);
          picks.add(item);
          titles.add({
            'item_id': item.id,
            'server_id': serverId,
            'title': clipText(item.title),
            if (item.year != null) 'year': item.year,
            'kind': item.kind.name,
          });
        }
        if (titles.isNotEmpty) rows.add({'row': clipText(hub.title), 'titles': titles});
      }

      // ponytail: the affinity vector itself still counts kids titles; a vector
      // without them only if this falls short in practice.
      List<String> likes(String dim, int limit) => taste
          .topFeatures(dim, threshold: 0.3, limit: limit + assistantKidsTasteGenres.length)
          .where((f) => !(c.excludeKids && dim == 'genre' && assistantKidsTasteGenres.contains(f.toLowerCase())))
          .take(limit)
          .toList();
      return AssistantToolResult({
        'watched_recently': watchedList,
        // The list is the newest few of the last weeks, not the whole history: say so.
        'watched_recently_window_days': kSeedWindow.inDays,
        'likes': {'genres': likes('genre', 4), 'actors': likes('actor', 3), 'directors': likes('director', 2)},
        'picks': rows,
      }, display: picks.isEmpty ? null : AssistantMediaGrid([for (final item in picks) (item: item, group: null)]));
    },
  ),
];

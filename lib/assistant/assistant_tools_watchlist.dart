part of 'assistant_tools.dart';

// The kijklijst through Big P (BP-12t3): read it, put a title on it, take one
// off. Everything goes through the same provider the kijklijst screen uses,
// so a change made here shows up there and the other way round.

/// Wired into [AssistantToolContext] by the UI layer from `WatchlistProvider`.
class AssistantWatchlistServices {
  const AssistantWatchlistServices({
    required this.load,
    required this.entries,
    required this.add,
    required this.remove,
    required this.available,
  });

  /// Loads the list when it was not loaded yet (`ensureLoaded`).
  final Future<void> Function() load;

  /// The merged list, newest first. Read after [load].
  final List<WatchlistEntry> Function() entries;

  /// `WatchlistProvider.addToWatchlist`, with the device's offline state.
  final Future<WatchlistOutcome> Function(MediaItem item) add;

  /// `WatchlistProvider.removeFromWatchlist`: off every list it was merged from.
  final Future<WatchlistOutcome> Function(WatchlistEntry entry) remove;

  /// False while no source is bound (no account that keeps a list): the tools
  /// then stay out of the run.
  final bool Function() available;
}

/// `w1`, `w2`, ... to the entry key, per run; a key keeps its ref.
final _watchlistRefs = Expando<Map<String, String>>('watchlistRefs');
final _watchlistShown = Expando<Map<String, String>>('watchlistShown');

bool _servesWatchlist(AssistantToolContext ctx, ServerId? _) => ctx.watchlist?.available() ?? false;

AssistantWatchlistServices _watchlist(AssistantToolContext ctx) {
  final services = ctx.watchlist;
  if (services == null || !services.available()) throw const AssistantToolError('watchlist_not_available');
  return services;
}

/// What a change that did not go through means, as a code for the model.
String _watchlistRefusal(WatchlistOutcome outcome) => switch (outcome) {
  WatchlistOutcome.unsupported => 'watchlist_not_supported_for_title',
  WatchlistOutcome.offlineRejected => 'device_offline',
  WatchlistOutcome.partiallyFailed => 'watchlist_partly_changed',
  _ => 'watchlist_failed',
};

String _watchlistTitle(WatchlistEntry entry) => clipText(entry.item.title ?? '', 64);

final List<AssistantTool> _watchlistTools = [
  AssistantTool(
    name: 'my_watchlist',
    description:
        'The user\'s kijklijst in Pleya (Plex watchlist and server favourites merged), newest first, each with '
        'an entry_id for remove_from_watchlist. in_library is true, false or unknown (not looked up: never say '
        'it is missing). Pass kind for films or series only.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show'],
      },
    },
    serves: _servesWatchlist,
    run: (ctx, _, args) async {
      final services = _watchlist(ctx);
      await services.load();
      final kind = switch (args['kind']) {
        'movie' => MediaKind.movie,
        'show' => MediaKind.show,
        null => null,
        _ => throw const AssistantToolError('invalid_kind'),
      };
      final refs = _watchlistRefs[ctx] ??= {};
      final shown = _watchlistShown[ctx] ??= {};
      final all = [
        for (final entry in services.entries())
          if (kind == null || entry.kind == kind) entry,
      ];
      const limit = 30;
      return AssistantToolResult({
        'total': all.length,
        if (all.length > limit) 'shown': limit,
        'entries': [
          for (final entry in all.take(limit))
            () {
              final ref = refs[entry.key] ??= 'w${refs.length + 1}';
              shown[ref] = entry.key;
              return {
                'entry_id': ref,
                'title': _watchlistTitle(entry),
                if (entry.item.year != null) 'year': entry.item.year,
                'kind': entry.kind == MediaKind.movie ? 'movie' : 'show',
                'in_library': switch (entry.availability) {
                  WatchlistAvailability.available => true,
                  WatchlistAvailability.notFound when entry.coverageComplete => false,
                  _ => 'unknown',
                },
              };
            }(),
        ],
      });
    },
  ),
  AssistantTool(
    name: 'add_to_watchlist',
    description:
        'Put a library title shown in this task on the user\'s kijklijst. item_id from a search or find result. '
        'The user confirms in Pleya. $_serverIdNote',
    risk: AssistantToolRisk.mutation,
    properties: const {
      'item_id': {'type': 'string'},
    },
    required: const ['item_id'],
    serves: (ctx, id) => _servesWatchlist(ctx, id) && ctx.userClient(id) != null,
    run: (ctx, id, args) async {
      _watchlist(ctx);
      final client = ctx.userClient(id!) ?? (throw const AssistantToolError('server_not_available'));
      final item = await _shownItem(ctx, client, id, _string(args, 'item_id'));
      if (item.kind != MediaKind.movie && item.kind != MediaKind.show) {
        throw const AssistantToolError('not_a_film_or_series');
      }
      final title = clipText(item.title ?? '', 64);
      final subject = item.year == null ? title : '$title (${item.year})';
      return AssistantPendingAction(
        kind: AssistantActionKind.addToWatchlist,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: subject,
        execute: ({password}) async {
          if (ctx.userClient(id) != client) throw const AssistantToolError('not_allowed');
          final outcome = await _watchlist(ctx).add(item);
          if (outcome != WatchlistOutcome.added) return {'error': _watchlistRefusal(outcome), 'done': false};
          return {'status': 'on_watchlist', 'title': subject};
        },
      );
    },
  ),
  AssistantTool(
    name: 'remove_from_watchlist',
    description:
        'Take a title off the user\'s kijklijst, everywhere it was listed. entry_id from my_watchlist in the '
        'same task. The user confirms in Pleya.',
    risk: AssistantToolRisk.mutation,
    needsServer: false,
    properties: const {
      'entry_id': {'type': 'string'},
    },
    required: const ['entry_id'],
    serves: _servesWatchlist,
    run: (ctx, _, args) async {
      final services = _watchlist(ctx);
      final key =
          _watchlistShown[ctx]?[_string(args, 'entry_id')] ?? (throw const AssistantToolError('unknown_entry_id'));
      WatchlistEntry current() =>
          _watchlist(ctx).entries().where((e) => e.key == key).firstOrNull ??
          (throw const AssistantToolError('not_on_watchlist'));
      final entry = current();
      final title = _watchlistTitle(entry);
      final subject = entry.item.year == null ? title : '$title (${entry.item.year})';
      return AssistantPendingAction(
        kind: AssistantActionKind.removeFromWatchlist,
        serverId: ctx.userServers.firstOrNull ?? (throw const AssistantToolError('no_servers')),
        serverName: '',
        subject: subject,
        execute: ({password}) async {
          // The entry as it is now: its memberships may have changed.
          final outcome = await services.remove(current());
          if (outcome != WatchlistOutcome.removed) return {'error': _watchlistRefusal(outcome), 'done': false};
          return {'status': 'off_watchlist', 'title': subject};
        },
      );
    },
  ),
];

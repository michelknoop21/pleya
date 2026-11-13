part of 'assistant_tools.dart';

// The kijklijst through Big P (BP-12t3): read it, put a title on it, take one
// off. Everything goes through the same provider the kijklijst screen uses,
// so a change made here shows up there and the other way round.

/// Wired into [AssistantToolContext] by the UI layer from `WatchlistProvider`.
/// How the list a read returned came about. [failed] with an empty list is no
/// list at all; a list that is [incomplete] or [fromSnapshot] cannot prove a
/// title is not on it.
typedef AssistantWatchlistRead = ({bool failed, bool incomplete, bool fromSnapshot});

class AssistantWatchlistServices {
  const AssistantWatchlistServices({
    required this.read,
    required this.entries,
    required this.keyFor,
    required this.add,
    required this.remove,
    required this.available,
  });

  /// Brings the list up to date: waits for a load that is running, loads when
  /// nothing was loaded, tries again after a failed load. Says how it ended.
  final Future<AssistantWatchlistRead> Function() read;

  /// The merged list as it stands, newest first.
  final List<WatchlistEntry> Function() entries;

  /// The key [item] gets on the list, or null when no source takes this
  /// title (the same question the kijklijst button asks before it shows).
  final String? Function(MediaItem item) keyFor;

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

/// What a change that did not go through means for the model. After a half
/// change the list was read again and an entry may have another ref.
Map<String, Object?> _watchlistRefusal(WatchlistOutcome outcome) => {
  'error': switch (outcome) {
    WatchlistOutcome.unsupported => 'watchlist_not_supported_for_title',
    WatchlistOutcome.offlineRejected => 'device_offline',
    WatchlistOutcome.partiallyFailed => 'watchlist_partly_changed',
    _ => 'watchlist_failed',
  },
  if (outcome == WatchlistOutcome.partiallyFailed) 'list_again': true,
  'done': false,
};

String _watchlistTitle(WatchlistEntry entry) => clipText(entry.item.title ?? '', 64);

final List<AssistantTool> _watchlistTools = [
  AssistantTool(
    name: 'my_watchlist',
    description:
        'The user\'s kijklijst in Pleya (Plex watchlist and server favourites merged), newest first, each with '
        'an entry_id for remove_from_watchlist. in_library is true, false or unknown (not looked up: never say '
        'it is missing). With incomplete or from_snapshot, never say a title is not on the list. kind narrows to '
        'films or series, title to a name.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show'],
      },
      'title': {'type': 'string'},
    },
    serves: _servesWatchlist,
    run: (ctx, _, args) async {
      final services = _watchlist(ctx);
      final read = await services.read();
      // No list at all is not an empty list.
      if (read.failed && services.entries().isEmpty) throw const AssistantToolError('watchlist_unreachable');
      final wanted = args['title'] is String ? (args['title'] as String).trim().toLowerCase() : '';
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
          if ((kind == null || entry.kind == kind) &&
              (wanted.isEmpty || (entry.item.title ?? '').toLowerCase().contains(wanted)))
            entry,
      ];
      const limit = 30;
      return AssistantToolResult({
        'total': all.length,
        if (all.length > limit) 'shown': limit,
        if (read.failed || read.incomplete) 'incomplete': true,
        if (read.fromSnapshot) 'from_snapshot': true,
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
      // Before the card: a yes that cannot succeed is not asked for.
      final key = _watchlist(ctx).keyFor(item);
      if (key == null) {
        return AssistantToolResult({'status': 'watchlist_not_supported_for_title', 'title': subject, 'done': false});
      }
      if (_watchlist(ctx).entries().any((e) => e.key == key)) {
        return AssistantToolResult({'status': 'already_on_watchlist', 'title': subject, 'done': false});
      }
      return AssistantPendingAction(
        kind: AssistantActionKind.addToWatchlist,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: subject,
        execute: ({password}) async {
          if (ctx.userClient(id) != client) throw const AssistantToolError('not_allowed');
          final outcome = await _watchlist(ctx).add(item);
          if (outcome != WatchlistOutcome.added) return _watchlistRefusal(outcome);
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
          if (outcome != WatchlistOutcome.removed) return _watchlistRefusal(outcome);
          return {'status': 'off_watchlist', 'title': subject};
        },
      );
    },
  ),
];

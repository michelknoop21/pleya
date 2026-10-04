part of 'assistant_tools.dart';

/// No model-supplied title, position, candidates or search variants. The
/// original question and the current player's profile lease are authoritative.
final assistantSpoilerTool = AssistantTool(
  name: 'spoiler_context',
  description:
      'Retrieve spoiler-safe context before the current watch position. No external or general knowledge fallback.',
  risk: AssistantToolRisk.read,
  needsServer: false,
  properties: const {},
  required: const [],
  serves: (_, _) => true,
  run: (ctx, _, _) async {
    final result = await ctx.safeSpoilerContext();
    final position = result.position;
    if (position == null || !result.current()) {
      return const AssistantToolResult({'status': 'insufficient_safe_context'});
    }
    final matches = <AssistantTitleMatch>[];
    for (final (i, doc) in result.matches.indexed) {
      final item = doc.item;
      matches.add(
        AssistantTitleMatch(
          matchId: 'safe-${i + 1}',
          title: clipText(item.title),
          kind: 'episode',
          confidence: 'low',
          targets: [(serverId: ServerId(doc.serverId), serverName: ctx.serverName(ServerId(doc.serverId)), item: item)],
          season: item.parentIndex,
          episode: item.index,
          snippet: clipText(item.summary, 400),
        ),
      );
    }
    return AssistantToolResult({
      'status': 'grounded_snippets_only',
      'position': {'season': position.season, 'episode': position.episode, 'position_ms': position.positionMs},
      'episodes': [
        for (final match in matches)
          {
            'server_id': position.serverId,
            'item_id': match.targets.single.item.id,
            'season': match.season,
            'episode': match.episode,
            'snippet': match.snippet,
          },
      ],
      'detail': 'Insufficient safe source data for character or scene details.',
    }, display: matches.isEmpty ? null : AssistantTitleMatches(ctx, matches));
  },
);

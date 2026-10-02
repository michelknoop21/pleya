import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../theme/mono_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/seerr_poster_card.dart';
import 'tv_assistant_option_card.dart';

/// One title find_title found (38-motion-7): poster, title and year, kind,
/// where it can be played or its Seerr status, and a line of plot. Built
/// from Pleya and Seerr data; selecting it never goes back to the model.
class TvAssistantMatchCard extends StatelessWidget {
  const TvAssistantMatchCard({
    super.key,
    required this.match,
    required this.index,
    required this.onSelect,
    this.focusNode,
    this.compact = false,
  });

  final AssistantTitleMatch match;
  final int index;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  /// The summoned panel: one line of plot instead of two.
  final bool compact;

  String get _kind {
    final m = t.assistant.match;
    return switch (match.kind) {
      'show' => m.show,
      'episode' => [
        m.episode,
        ?match.series,
        if (match.season != null && match.episode != null)
          m.episodeCode(season: match.season!, episode: match.episode!),
      ].join(' · '),
      _ => m.movie,
    };
  }

  /// Library first: a copy to play beats a request.
  (String?, Color?) get _status {
    if (match.targets.isNotEmpty) {
      final servers = {for (final target in match.targets) target.serverName}.join(', ');
      return (t.assistant.match.inLibrary(servers: servers), kSuccess);
    }
    final request = match.request;
    return request == null ? (null, null) : tvAssistantRequestStatus(request.status);
  }

  String get _plot => match.snippet.isNotEmpty
      ? match.snippet
      : clipText(match.targets.firstOrNull?.item.summary ?? match.request?.overview, 160);

  Widget _poster(BuildContext context) {
    final target = match.targets.firstOrNull;
    if (target == null) return SeerrPosterImage(url: match.request?.posterUrl ?? '');
    return OptimizedMediaImage.poster(
      client: context.read<MultiServerProvider?>()?.getClientForServer(target.serverId),
      imagePath: target.item.thumbPath,
      fallbackIcon: Symbols.movie_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final (status, statusColor) = _status;
    final low = match.confidence == 'low';
    final plot = _plot;
    final muted = TextStyle(color: tk.text.withValues(alpha: 0.65), fontSize: TvHig.caption2 * pt);
    return FocusableWrapper(
      focusNode: focusNode,
      borderRadius: 18 * pt,
      disableScale: true,
      semanticLabel: [match.title, ?match.year?.toString(), _kind, ?status].join(', '),
      automationId: AutomationIds.assistantMatch,
      automationInstance: '$index',
      automationRole: 'list.item',
      automationState: () => {
        'title': match.title,
        'kind': match.kind,
        'confidence': match.confidence,
        'inLibrary': match.targets.isNotEmpty,
        'requestStatus': match.request?.status,
      },
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        onSelect();
      },
      child: Container(
        padding: EdgeInsets.all(12 * pt),
        decoration: BoxDecoration(color: const Color(0xE6161616), borderRadius: BorderRadius.circular(18 * pt)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8 * pt),
              child: SizedBox(width: 68 * pt, height: 100 * pt, child: _poster(context)),
            ),
            SizedBox(width: 20 * pt),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: match.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (match.year != null)
                          TextSpan(
                            text: ' (${match.year})',
                            style: TextStyle(color: tk.text.withValues(alpha: 0.6)),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tk.text, fontSize: TvHig.body * pt),
                  ),
                  SizedBox(height: 4 * pt),
                  Text(
                    low ? '$_kind · ${t.assistant.match.maybe}' : _kind,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  if (plot.isNotEmpty) ...[
                    SizedBox(height: 4 * pt),
                    Text(plot, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: muted),
                  ],
                ],
              ),
            ),
            if (status != null) ...[
              SizedBox(width: 16 * pt),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: (compact ? 180 : 280) * pt),
                child: TvAssistantStatusPill(label: status, color: statusColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

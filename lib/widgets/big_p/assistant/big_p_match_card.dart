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
import '../big_p_scale.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/seerr_poster_card.dart';
import 'big_p_option_card.dart';
import 'big_p_title_facts.dart';

/// One title find_title found (38-motion-7): poster, title and year, kind,
/// where it can be played or its Seerr status, and a line of plot. Built
/// from Pleya and Seerr data; selecting it never goes back to the model.
class BigPMatchCard extends StatelessWidget {
  const BigPMatchCard({
    super.key,
    required this.match,
    required this.index,
    required this.onSelect,
    this.focusNode,
    this.compact = false,
    this.dense = false,
    this.rank,
  });

  final AssistantTitleMatch match;
  final int index;

  /// Null: focusable for reading, dimmed and inert (Big P still checking).
  final VoidCallback? onSelect;
  final FocusNode? focusNode;

  /// The summoned panel: one line of plot instead of two.
  final bool compact;

  /// A long list in the summoned panel: a small poster and no plot line, so
  /// more titles show at once.
  final bool dense;

  /// A place in a ranking (most watched), drawn as a badge on the poster.
  final int? rank;

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
    return request == null ? (null, null) : bigPRequestStatus(request.status);
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
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final (status, statusColor) = _status;
    final pill = status == null ? null : BigPStatusPill(label: status, color: statusColor, dense: compact);
    final low = match.confidence == 'low';
    final plot = _plot;
    // The facts take the plot's lines, so a card with them is no taller.
    final plotLines = (compact ? 1 : 2) - BigPTitleFacts.lineCount(match.facts, services: !dense);
    final muted = TextStyle(color: tk.text.withValues(alpha: 0.65), fontSize: TvHig.caption2 * pt);
    return GestureDetector(
      // FocusableWrapper only answers keys; on a touch screen a tap is Select.
      onTap: onSelect,
      behavior: HitTestBehavior.opaque,
      child: FocusableWrapper(
        focusNode: focusNode,
        borderRadius: 18 * pt,
        disableScale: true,
        // Scroll only near the panel's edge: centring the first card would push
        // the question and answer above it out of view.
        useComfortableZone: true,
        // A card already in view stays put: the first card takes the focus as
        // the result opens, and scrolling it to the middle would push the head
        // of a card above it (the watch stats' title and total) out of view.
        scrollOnlyWhenHidden: true,
        // A request card while Big P is still checking stays a stop (dimmed,
        // inert); a title with nothing to open or request is no stop at all.
        canRequestFocus: onSelect != null || match.request != null,
        semanticLabel: [
          match.title,
          ?match.year?.toString(),
          _kind,
          ?status,
          ...BigPTitleFacts.describe(match.facts),
        ].join(', '),
        automationId: AutomationIds.assistantMatch,
        automationInstance: '$index',
        automationRole: 'list.item',
        automationState: () => {
          'title': match.title,
          'kind': match.kind,
          'confidence': match.confidence,
          'inLibrary': match.targets.isNotEmpty,
          'requestStatus': match.request?.status,
          'enabled': onSelect != null,
        },
        onSelect: () {
          SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
          onSelect?.call();
        },
        child: Opacity(
          opacity: onSelect == null ? 0.45 : 1,
          child: Container(
            padding: EdgeInsets.all((dense ? 8 : 12) * pt),
            decoration: BoxDecoration(color: const Color(0xE6161616), borderRadius: BorderRadius.circular(18 * pt)),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8 * pt),
                      child: SizedBox(
                        width: (dense ? 48 : 68) * pt,
                        height: (dense ? 72 : 100) * pt,
                        child: _poster(context),
                      ),
                    ),
                    if (rank case final rank?)
                      Positioned(
                        left: -10 * pt,
                        top: -10 * pt,
                        child: _RankBadge(rank: rank),
                      ),
                  ],
                ),
                SizedBox(width: 20 * pt),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact)
                        // The whole title, over two lines when it needs them: a
                        // cut title does not say which part of a series it is.
                        // The year stands with the kind, under it.
                        Text(
                          match.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tk.text,
                            fontSize: TvHig.body * pt,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        )
                      else
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
                      bigPSecondLine(
                        pt,
                        Text(
                          [_kind, if (compact) ?match.year?.toString(), if (low) t.assistant.match.maybe].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                        pill,
                      ),
                      BigPTitleFacts(facts: match.facts, services: !dense),
                      if (plot.isNotEmpty && !dense && plotLines > 0) ...[
                        SizedBox(height: 4 * pt),
                        Text(plot, maxLines: plotLines, overflow: TextOverflow.ellipsis, style: muted),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The rank on a poster: the brand gradient with the number in the display
/// face, ringed in the card colour so it lifts off the artwork.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    return Container(
      width: 38 * pt,
      height: 38 * pt,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: tokens(context).accentGradient,
        border: Border.all(color: const Color(0xFF161616), width: 3 * pt),
      ),
      child: Text(
        '$rank',
        style: TextStyle(color: Colors.white, fontFamily: 'ArchivoBlack', fontSize: TvHig.caption1 * pt, height: 1),
      ),
    );
  }
}

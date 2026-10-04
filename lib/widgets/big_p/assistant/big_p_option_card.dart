import 'package:flutter/material.dart';

import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../big_p_scale.dart';
import '../../../widgets/seerr_poster_card.dart';
import 'big_p_title_facts.dart';

/// A Seerr status as the option and match cards show it, with its colour.
(String, Color?) bigPRequestStatus(String status) => switch (status) {
  'available' => (t.seerr.available, kSuccess),
  'partially_available' => (t.seerr.partiallyAvailable, kSuccess),
  'requested' => (t.seerr.alreadyRequested, kAccentAlt),
  _ => (t.assistant.option.notRequested, null),
};

/// The rounded status label at the right of a card (38-motion-7).
class BigPStatusPill extends StatelessWidget {
  const BigPStatusPill({super.key, required this.label, this.color, this.dense = false});

  final String label;
  final Color? color;

  /// No vertical padding: on a card's second line (BIGP-UI1) the label is
  /// as tall as the text beside it, so the card keeps its height.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final c = color ?? tokens(context).text;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * pt, vertical: dense ? 0 : 6 * pt),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20 * pt)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c, fontSize: TvHig.caption2 * pt),
      ),
    );
  }
}

/// A card's second line, with the status label after it in the summoned
/// panel (BIGP-UI1); [pill] null keeps the line alone. The label wins over
/// the line, up to three quarters of the width.
Widget bigPSecondLine(double pt, Widget line, Widget? pill) => pill == null
    ? line
    : LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Expanded(child: line),
            SizedBox(width: 12 * pt),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.75),
              child: pill,
            ),
          ],
        ),
      );

/// Title and year in the summoned panel (BIGP-UI1): only the title shortens,
/// the year stays readable to tell results apart.
Widget bigPCompactTitle(double pt, MonoTokens tk, String title, int? year) => Row(
  children: [
    Flexible(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // As wide as what is drawn, so the year follows the ellipsis directly.
        textWidthBasis: TextWidthBasis.longestLine,
        style: TextStyle(color: tk.text, fontSize: TvHig.body * pt, fontWeight: FontWeight.w700),
      ),
    ),
    if (year != null)
      Text(
        ' ($year)',
        maxLines: 1,
        style: TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.body * pt),
      ),
  ],
);

/// One title Big P found for a description (motion still 7): poster, title,
/// year, one line of overview and the Seerr status. Built from Seerr data;
/// selecting it hands the option to Pleya, never to the model.
class BigPOptionCard extends StatelessWidget {
  const BigPOptionCard({
    super.key,
    required this.option,
    required this.index,
    required this.onSelect,
    this.focusNode,
    this.compact = false,
  });

  final AssistantRequestOption option;

  /// The summoned panel (BIGP-UI1): the status moves under the title, next
  /// to the overview, so title and year keep the full width.
  final bool compact;
  final int index;

  /// Null: focusable for reading, dimmed and inert (Big P still checking).
  final VoidCallback? onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final (status, statusColor) = bigPRequestStatus(option.status);
    final pill = BigPStatusPill(label: status, color: statusColor, dense: compact);
    return GestureDetector(
      // FocusableWrapper only answers keys; on a touch screen a tap is Select.
      onTap: onSelect,
      behavior: HitTestBehavior.opaque,
      child: FocusableWrapper(
        focusNode: focusNode,
        borderRadius: 18 * pt,
        disableScale: true,
        scrollOnlyWhenHidden: true,
        semanticLabel: [option.title, status, ...BigPTitleFacts.describe(option.facts)].join(', '),
        automationId: AutomationIds.assistantOption,
        automationInstance: '$index',
        automationRole: 'list.item',
        automationState: () => {'title': option.title, 'status': option.status, 'enabled': onSelect != null},
        onSelect: () {
          SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
          onSelect?.call();
        },
        child: Opacity(
          opacity: onSelect == null ? 0.45 : 1,
          child: Container(
            padding: EdgeInsets.all(12 * pt),
            decoration: BoxDecoration(color: const Color(0xE6161616), borderRadius: BorderRadius.circular(18 * pt)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8 * pt),
                  child: SizedBox(
                    width: 68 * pt,
                    height: 100 * pt,
                    child: SeerrPosterImage(url: option.posterUrl),
                  ),
                ),
                SizedBox(width: 20 * pt),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact)
                        bigPCompactTitle(pt, tk, option.title, option.year)
                      else
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: option.title,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              if (option.year != null)
                                TextSpan(
                                  text: ' (${option.year})',
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
                          option.overview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tk.text.withValues(alpha: 0.65), fontSize: TvHig.caption2 * pt),
                        ),
                        compact ? pill : null,
                      ),
                      BigPTitleFacts(facts: option.facts),
                    ],
                  ),
                ),
                if (!compact) ...[SizedBox(width: 16 * pt), pill],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

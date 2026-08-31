/// The line that names a discovery rail (hoofdstuk 10.2a of
/// docs/tvos-unified-experience.md).
///
/// Not focusable, and that is the whole design. On a 10-foot surface every
/// focusable object is one more press between the user and the content, and a
/// heading has nothing to activate: the rail under it is the destination. So
/// this draws, the rail below owns the focus, and D-pad UP from a rail lands on
/// the *previous rail* rather than on a row of inert labels.
///
/// It carries one optional signal: [isPartial], hoofdstuk 41's "a hub may carry
/// partial state and signal it subtly where relevant". Subtly is load-bearing —
/// a source that did not answer is a footnote next to a row that still has
/// content in it, not a banner over the page (hoofdstuk 21.4).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';

class TvSectionHeader extends StatelessWidget {
  const TvSectionHeader({super.key, required this.title, this.isPartial = false, this.partialLabel});

  final String title;

  /// True when at least one source that should have contributed to this rail
  /// did not answer. The rail still shows what it has.
  final bool isPartial;

  /// Localized wording for that state; required in practice whenever
  /// [isPartial] is set, and typed as nullable so the common case passes
  /// neither.
  final String? partialLabel;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final label = partialLabel;

    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text,
              fontSize: TvDiscoveryLayout.sectionTitleFontSize * scale,
              height: TvDiscoveryLayout.metaLineHeight,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        // Icon only, no visible sentence. A written "some sources did not
        // answer" beside every affected heading competed with the row title it
        // was supposed to be a footnote to; the glyph at tertiary ink is the
        // subtle signal hoofdstuk 41 asks for, and the full wording stays
        // available to assistive tech through the Semantics label.
        if (isPartial && label != null) ...[
          SizedBox(width: TvDiscoveryLayout.viewAllIconGap * scale),
          Semantics(
            label: label,
            child: Icon(
              Symbols.cloud_off_rounded,
              size: TvDiscoveryLayout.metaContextFontSize * scale * 1.2,
              color: tk.text.withValues(alpha: TvDiscoveryLayout.inkTertiary),
            ),
          ),
        ],
      ],
    );
  }
}

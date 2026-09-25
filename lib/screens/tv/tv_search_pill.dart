import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill_input_decoration.dart';
import '../../widgets/tv/tv_unified_layout.dart';

/// The TV search pill: the query, and the count of what it found (36 B).
///
/// The pill holds half the content column and starts on its left edge, the
/// width 36 B draws. The full width was nobody's decision (VIS1).
class TvSearchPill extends StatelessWidget {
  const TvSearchPill({super.key, required this.controller, required this.countLabel, this.wrap, this.focusNode});

  final TextEditingController controller;

  /// "14 resultaten", or null while there is nothing to count.
  final String? countLabel;

  /// Wraps the drawn pill, so the focusable around it takes the pill's width
  /// and its ring hugs the pill instead of the row.
  final Widget Function(Widget pill)? wrap;

  /// The focus node of whatever [wrap] puts around the pill. Given to the
  /// automation node so it reports whether the pill can take focus: while the
  /// search screen sits offstage in the shell's IndexedStack it cannot, and a
  /// Verify walk on Home must not count it as a stop it passed over.
  final FocusNode? focusNode;

  static const double widthFactor = 0.5;

  @override
  Widget build(BuildContext context) {
    final label = countLabel;
    final glass = glassTierFor(context) != GlassTier.off;
    final field = ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = controller.text;
        return InputDecorator(
          decoration: pillInputDecoration(
            context,
            hintText: t.search.hint,
            prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
            glass: glass,
            // 36 B puts "14 resultaten" inside the pill, at tertiary ink. It is
            // a statement about the query, so it belongs to the field that
            // holds the query rather than to a line above the first band.
            // The decorator gives a suffix a 48-point minimum box and puts a
            // bare Text at its top; Center keeps it on the pill's midline.
            suffixIcon: label == null
                ? null
                : Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: TvCatalogLayout.inkTertiary),
                        ),
                      ),
                    ),
                  ),
            // Half a row is too narrow for some locales' hint on one line; a
            // second line would make the pill taller than the one in 36 B.
          ).copyWith(hintMaxLines: 1),
          isEmpty: text.isEmpty,
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
    // LG-06: glass on puts the field on a capsule of tvOS fake glass. At rest
    // it sits on the page ground under the top bar; results scroll under it.
    final pill = GlassSurface(shape: const StadiumBorder(), tokens: const GlassTokens.tv(), child: field);
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: AutomationNode(
          id: AutomationIds.tvSearchPill,
          role: 'field',
          focusNode: focusNode,
          state: () => {'count': label},
          child: wrap?.call(pill) ?? pill,
        ),
      ),
    );
  }
}

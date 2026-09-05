/// The pieces the new-row wizard is drawn from (ROW1, mockup 32 C1 to C4,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100) (5) and (6)).
///
/// Separated from `tv_home_row_wizard.dart` so that file stays the three steps,
/// their state and the two panels they open. Nothing here holds state of its
/// own; every one of these takes what it draws as an argument, which is what
/// makes the wizard's own file readable as a flow.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../focus/dpad_navigator.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/home_custom_row_loader.dart';
import '../../theme/mono_tokens.dart';
import '../optimized_media_image.dart';
import 'tv_expandable_media_tile.dart' show discoveryPosterPath;
import 'tv_unified_layout.dart';

class TvHomeWizardStepRow extends StatelessWidget {
  const TvHomeWizardStepRow({
    super.key,
    required this.index,
    required this.label,
    required this.isActive,
    required this.isDone,
    required this.scale,
  });

  final int index;
  final String label;
  final bool isActive;
  final bool isDone;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final size = TvHomeRowsLayout.stepBadgeSize * scale;
    return Container(
      height: TvHomeRowsLayout.stepRowHeight * scale,
      padding: EdgeInsets.symmetric(horizontal: TvHomeRowsLayout.rowPaddingHorizontal * scale),
      decoration: BoxDecoration(
        color: isActive ? mono.text.withValues(alpha: TvHomeRowsLayout.rowFill) : Colors.transparent,
        borderRadius: BorderRadius.circular(TvHomeRowsLayout.rowRadius * scale),
      ),
      child: Row(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? mono.text : Colors.transparent,
              border: isActive ? null : Border.all(color: mono.outline),
            ),
            child: isDone
                ? Icon(Symbols.check_rounded, size: size * 0.6, color: mono.textMuted)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: TvHomeRowsLayout.subtitleFontSize * scale,
                      fontWeight: FontWeight.w700,
                      color: isActive ? mono.surface : mono.textMuted,
                    ),
                  ),
          ),
          SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvHomeRowsLayout.titleFontSize * scale,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? mono.text : mono.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TvHomeWizardFieldLabel extends StatelessWidget {
  const TvHomeWizardFieldLabel({super.key, required this.text, required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Padding(
      padding: EdgeInsets.only(bottom: TvHomeRowsLayout.rowGap * scale),
      child: Text(
        text,
        style: TextStyle(fontSize: TvHomeRowsLayout.subtitleFontSize * scale, color: mono.textMuted),
      ),
    );
  }
}

/// One line of the filters step: icon, label, what it is set to, chevron.
class TvHomeWizardFilterLine extends StatelessWidget {
  const TvHomeWizardFilterLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.scale,
    required this.focusNode,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String value;
  final double scale;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return FocusableWrapper(
      focusNode: focusNode,
      semanticLabel: '$label, $value',
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        onPressed();
      },
      child: Padding(
        padding: EdgeInsets.all(TvHomeRowsLayout.rowFocusRingGap * scale),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: TvHomeRowsLayout.rowPaddingHorizontal * scale,
            vertical: TvHomeRowsLayout.rowGap * scale,
          ),
          decoration: BoxDecoration(
            color: mono.text.withValues(alpha: TvHomeRowsLayout.rowFill),
            borderRadius: BorderRadius.circular(TvHomeRowsLayout.rowRadius * scale),
          ),
          child: Row(
            children: [
              Icon(icon, size: TvHomeRowsLayout.leadingIconSize * scale, color: mono.textMuted),
              SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: TvHomeRowsLayout.titleFontSize * scale,
                        fontWeight: FontWeight.w600,
                        color: mono.text,
                      ),
                    ),
                    SizedBox(height: TvHomeRowsLayout.titleGap * scale),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: TvHomeRowsLayout.subtitleFontSize * scale, color: mono.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(
                Symbols.chevron_right_rounded,
                size: TvHomeRowsLayout.leadingIconSize * scale,
                color: mono.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TvHomeWizardPreviewPosters extends StatelessWidget {
  const TvHomeWizardPreviewPosters({super.key, required this.content, required this.scale, this.clientFor});

  final HomeCustomRowContent content;
  final double scale;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final width = TvHomeRowsLayout.previewPosterWidth * scale;
    final height = TvHomeRowsLayout.previewPosterHeight * scale;
    final shown = content.groups.take(TvHomeRowsLayout.previewPosterCount).toList();
    final rest = content.loadedCount - shown.length;
    return SizedBox(
      height: height,
      // Horizontal, so a narrow panel clips the strip instead of asserting on
      // it: the count beside the title is what carries "how many", the posters
      // are only the picture of it.
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) SizedBox(width: TvHomeRowsLayout.previewPosterGap * scale),
            ClipRRect(
              borderRadius: BorderRadius.circular(TvHomeRowsLayout.posterRadius * scale * 2),
              child: OptimizedMediaImage.poster(
                client: clientFor?.call(shown[i].representativeSource.item.serverId ?? ''),
                imagePath: discoveryPosterPath(shown[i].representativeSource.item),
                width: width,
                height: height,
                fit: BoxFit.cover,
              ),
            ),
          ],
          // Only when there genuinely are more. The number is the loaded count,
          // not a claimed total: hoofdstuk 10.7 again.
          if (rest > 0) ...[
            SizedBox(width: TvHomeRowsLayout.previewPosterGap * scale),
            Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: mono.text.withValues(alpha: TvHomeRowsLayout.rowFill),
                borderRadius: BorderRadius.circular(TvHomeRowsLayout.posterRadius * scale * 2),
              ),
              child: Text(
                t.unifiedCatalog.homeRows.morePosters(count: rest),
                style: TextStyle(fontSize: TvHomeRowsLayout.titleFontSize * scale, color: mono.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TvHomeWizardEmptyPreview extends StatelessWidget {
  const TvHomeWizardEmptyPreview({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Container(
      height: TvHomeRowsLayout.previewPosterHeight * scale,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: mono.outline),
        borderRadius: BorderRadius.circular(TvHomeRowsLayout.rowRadius * scale),
      ),
      child: Text(
        t.unifiedCatalog.homeRows.emptyPreviewTitle,
        style: TextStyle(fontSize: TvHomeRowsLayout.titleFontSize * scale, color: mono.textMuted),
      ),
    );
  }
}

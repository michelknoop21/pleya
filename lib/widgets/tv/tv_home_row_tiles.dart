/// The pieces one row of the customise panel is drawn from (ROW1, mockup 32 B,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100) (4)).
///
/// Separated from `tv_home_customize_panel.dart` so that file stays what it
/// says it is: the panel's list, its focus grid and its four actions. These are
/// the shapes those actions live in, and one of them ([DottedRowBorder]) is
/// borrowed by the Home footer as well, which is what makes "Nieuwe rij" and
/// "Home aanpassen" read as the same affordance in two places.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../focus/dpad_navigator.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../optimized_media_image.dart';
import 'tv_expandable_media_tile.dart' show discoveryPosterPath;
import 'tv_home_customize_panel.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

/// A locked row: the same shape as a movable one, minus every focus stop.
class TvHomeFixedRowTile extends StatelessWidget {
  const TvHomeFixedRowTile({super.key, required this.fixed, required this.scale, this.clientFor});

  final TvHomeFixedRow fixed;
  final double scale;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return _RowShell(
      scale: scale,
      fill: TvHomeRowsLayout.lockedFill,
      leading: Icon(
        Symbols.lock_rounded,
        size: TvHomeRowsLayout.leadingIconSize * scale,
        color: mono.text.withValues(alpha: TvHomeRowsLayout.dimmed),
      ),
      posters: _MiniPosters(groups: fixed.groups, scale: scale, clientFor: clientFor),
      title: fixed.title,
      subtitle: fixed.subtitle,
      dimmed: false,
      trailing: _FixedTag(scale: scale),
    );
  }
}

class _FixedTag extends StatelessWidget {
  const _FixedTag({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        border: Border.all(color: mono.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.lock_rounded,
            size: TvHomeRowsLayout.subtitleFontSize * scale,
            color: mono.text.withValues(alpha: TvHomeRowsLayout.dimmed),
          ),
          SizedBox(width: 5 * scale),
          Text(
            t.unifiedCatalog.homeRows.fixed,
            style: TextStyle(
              fontSize: TvHomeRowsLayout.subtitleFontSize * scale,
              color: mono.text.withValues(alpha: TvHomeRowsLayout.dimmed),
            ),
          ),
        ],
      ),
    );
  }
}

class TvHomeEntryRowTile extends StatelessWidget {
  const TvHomeEntryRowTile({
    super.key,
    required this.entry,
    required this.scale,
    required this.upNode,
    required this.downNode,
    required this.primaryNode,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onPrimary,
    required this.onNavigateUp,
    required this.onNavigateDown,
    this.removeNode,
    this.onRemove,
    this.clientFor,
  });

  final TvHomeRowEntry entry;
  final double scale;
  final FocusNode upNode;
  final FocusNode downNode;
  final FocusNode primaryNode;
  final FocusNode? removeNode;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onPrimary;
  final VoidCallback? onRemove;
  final void Function(TvHomeRowColumn column) onNavigateUp;
  final void Function(TvHomeRowColumn column) onNavigateDown;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final custom = entry.custom;
    return _RowShell(
      scale: scale,
      fill: TvHomeRowsLayout.rowFill,
      dimmed: entry.isHidden,
      leading: Icon(
        custom == null ? Symbols.view_carousel_rounded : Symbols.filter_list_rounded,
        size: TvHomeRowsLayout.leadingIconSize * scale,
        color: mono.textMuted,
      ),
      posters: _MiniPosters(groups: entry.row.groups, scale: scale, clientFor: clientFor),
      title: entry.row.title,
      subtitle: entry.subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ArrowButton(
            icon: Symbols.keyboard_arrow_up_rounded,
            semanticLabel: t.unifiedCatalog.homeRows.moveUp,
            scale: scale,
            focusNode: upNode,
            enabled: canMoveUp,
            onPressed: onMoveUp,
            onNavigateUp: () => onNavigateUp(TvHomeRowColumn.up),
            onNavigateDown: () => onNavigateDown(TvHomeRowColumn.up),
            onNavigateLeft: () {},
          ),
          SizedBox(width: TvHomeRowsLayout.actionGap * scale),
          _ArrowButton(
            icon: Symbols.keyboard_arrow_down_rounded,
            semanticLabel: t.unifiedCatalog.homeRows.moveDown,
            scale: scale,
            focusNode: downNode,
            enabled: canMoveDown,
            onPressed: onMoveDown,
            onNavigateUp: () => onNavigateUp(TvHomeRowColumn.down),
            onNavigateDown: () => onNavigateDown(TvHomeRowColumn.down),
          ),
          SizedBox(width: TvHomeRowsLayout.actionGap * scale),
          TvPanelButton(
            scale: scale,
            primary: false,
            focusNode: primaryNode,
            label: custom == null
                ? (entry.isHidden ? t.unifiedCatalog.homeRows.show : t.unifiedCatalog.homeRows.hide)
                : t.unifiedCatalog.homeRows.edit,
            onPressed: onPrimary,
            onNavigateUp: () => onNavigateUp(TvHomeRowColumn.primary),
            onNavigateDown: () => onNavigateDown(TvHomeRowColumn.primary),
          ),
          if (onRemove != null) ...[
            SizedBox(width: TvHomeRowsLayout.actionGap * scale),
            TvPanelButton(
              scale: scale,
              primary: false,
              focusNode: removeNode,
              label: t.unifiedCatalog.homeRows.remove,
              onPressed: onRemove!,
              onNavigateUp: () => onNavigateUp(TvHomeRowColumn.remove),
              onNavigateDown: () => onNavigateDown(TvHomeRowColumn.remove),
              onNavigateRight: () {},
            ),
          ],
        ],
      ),
    );
  }
}

/// The shared frame: fill, leading glyph, posters, two tiers of text, actions.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.scale,
    required this.fill,
    required this.leading,
    required this.posters,
    required this.title,
    required this.trailing,
    required this.dimmed,
    this.subtitle,
  });

  final double scale;
  final double fill;
  final Widget leading;
  final Widget posters;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final ink = dimmed ? TvHomeRowsLayout.dimmed : 1.0;
    return Container(
      constraints: BoxConstraints(minHeight: TvHomeRowsLayout.rowHeight * scale),
      padding: EdgeInsets.symmetric(
        horizontal: TvHomeRowsLayout.rowPaddingHorizontal * scale,
        vertical: TvHomeRowsLayout.rowGap * scale,
      ),
      decoration: BoxDecoration(
        color: mono.text.withValues(alpha: fill),
        borderRadius: BorderRadius.circular(TvHomeRowsLayout.rowRadius * scale),
      ),
      child: Row(
        children: [
          leading,
          SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
          Opacity(opacity: ink, child: posters),
          SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvHomeRowsLayout.titleFontSize * scale,
                    fontWeight: FontWeight.w600,
                    color: mono.text.withValues(alpha: ink),
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: TvHomeRowsLayout.titleGap * scale),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TvHomeRowsLayout.subtitleFontSize * scale,
                      color: mono.textMuted.withValues(alpha: ink),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
          trailing,
        ],
      ),
    );
  }
}

class _MiniPosters extends StatelessWidget {
  const _MiniPosters({required this.groups, required this.scale, this.clientFor});

  final List<UnifiedMediaGroup> groups;
  final double scale;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final shown = groups.take(TvHomeRowsLayout.posterCount).toList();
    final width = TvHomeRowsLayout.posterWidth * scale;
    final height = TvHomeRowsLayout.posterHeight * scale;
    return SizedBox(
      width:
          width * TvHomeRowsLayout.posterCount +
          TvHomeRowsLayout.posterGap * scale * (TvHomeRowsLayout.posterCount - 1),
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < TvHomeRowsLayout.posterCount; i++) ...[
            if (i > 0) SizedBox(width: TvHomeRowsLayout.posterGap * scale),
            ClipRRect(
              borderRadius: BorderRadius.circular(TvHomeRowsLayout.posterRadius * scale),
              child: SizedBox(
                width: width,
                height: height,
                child: i < shown.length
                    ? OptimizedMediaImage.poster(
                        client: clientFor?.call(shown[i].representativeSource.item.serverId ?? ''),
                        imagePath: discoveryPosterPath(shown[i].representativeSource.item),
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                      )
                    // An empty slot rather than a shorter strip: four boxes of
                    // constant width are what keeps every row's text column
                    // starting at the same x, which is most of what makes a
                    // list of rows readable at three metres.
                    : ColoredBox(color: mono.text.withValues(alpha: TvHomeRowsLayout.lockedFill)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A round icon button. Disabled means "does nothing", never "cannot be
/// reached" — see the library doc.
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.semanticLabel,
    required this.scale,
    required this.focusNode,
    required this.enabled,
    required this.onPressed,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
  });

  final IconData icon;
  final String semanticLabel;
  final double scale;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final size = TvHomeRowsLayout.arrowButtonSize * scale;
    return FocusableWrapper(
      focusNode: focusNode,
      semanticLabel: semanticLabel,
      focusShapeBorder: const CircleBorder(),
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onSelect: enabled
          ? () {
              SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
              onPressed();
            }
          : null,
      child: Padding(
        padding: EdgeInsets.all(TvHomeRowsLayout.rowFocusRingGap * scale),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: mono.text.withValues(alpha: TvHomeRowsLayout.rowFill),
          ),
          child: Icon(
            icon,
            size: TvHomeRowsLayout.leadingIconSize * scale,
            color: mono.text.withValues(alpha: enabled ? 1 : TvHomeRowsLayout.dimmed),
          ),
        ),
      ),
    );
  }
}

/// "Nieuwe rij", in the dotted tile language A1a borrows for its footer.
class TvHomeNewRowTile extends StatelessWidget {
  const TvHomeNewRowTile({
    super.key,
    required this.scale,
    required this.focusNode,
    required this.onPressed,
    this.onNavigateUp,
  });

  final double scale;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onNavigateUp;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return FocusableWrapper(
      focusNode: focusNode,
      semanticLabel: t.unifiedCatalog.homeRows.newRow,
      onNavigateUp: onNavigateUp,
      onNavigateDown: () {},
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        onPressed();
      },
      child: Padding(
        padding: EdgeInsets.all(TvHomeRowsLayout.rowFocusRingGap * scale),
        child: DottedRowBorder(
          scale: scale,
          child: Row(
            children: [
              Icon(Symbols.add_rounded, size: TvHomeRowsLayout.leadingIconSize * scale, color: mono.text),
              SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.unifiedCatalog.homeRows.newRow,
                    style: TextStyle(
                      fontSize: TvHomeRowsLayout.titleFontSize * scale,
                      fontWeight: FontWeight.w600,
                      color: mono.text,
                    ),
                  ),
                  SizedBox(height: TvHomeRowsLayout.titleGap * scale),
                  Text(
                    t.unifiedCatalog.homeRows.newRowSubtitle,
                    style: TextStyle(fontSize: TvHomeRowsLayout.subtitleFontSize * scale, color: mono.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dashed frame both "Nieuwe rij" and the Home footer row wear, so the two
/// read as the same affordance in two places.
class DottedRowBorder extends StatelessWidget {
  const DottedRowBorder({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Container(
      constraints: BoxConstraints(minHeight: TvHomeRowsLayout.rowHeight * scale),
      padding: EdgeInsets.symmetric(
        horizontal: TvHomeRowsLayout.rowPaddingHorizontal * scale,
        vertical: TvHomeRowsLayout.rowGap * scale,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: mono.outline),
        borderRadius: BorderRadius.circular(TvHomeRowsLayout.rowRadius * scale),
      ),
      child: child,
    );
  }
}

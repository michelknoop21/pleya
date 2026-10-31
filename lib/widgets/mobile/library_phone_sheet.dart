/// Pieces of the floating sheets of the iPhone library look: a centred bold
/// heading, a 46 pt row with the choice's check on the right or an icon and a
/// label, and the rule between two groups of rows.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import '../focusable_list_tile.dart';
import 'library_phone_look.dart';

/// Centred, bold heading under the grip. [onBack] leads back to the list above
/// it, [action] sits on the right: neither moves the title off the centre.
class LibraryPhoneSheetHeading extends StatelessWidget {
  const LibraryPhoneSheetHeading({super.key, required this.title, this.onBack, this.action});

  final String title;
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    final trailing = action;
    return SizedBox(
      width: double.infinity,
      height: kMinInteractiveDimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: back != null || trailing != null
                  ? LibraryPhoneMetrics.sheetHeadingActionInset
                  : LibraryPhoneMetrics.sortRowInset,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: LibraryPhoneMetrics.sheetHeadingFontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: LibraryPhoneMetrics.letterSpacing,
              ),
            ),
          ),
          if (back != null)
            PositionedDirectional(
              start: 4,
              child: IconButton(
                icon: const AppIcon(Symbols.arrow_back_rounded),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: back,
              ),
            ),
          if (trailing != null) PositionedDirectional(end: 8, child: trailing),
        ],
      ),
    );
  }
}

/// One choice. The check is the accent colour; an unchosen row has no mark. A
/// category shows the value that is set in the same colour, [value].
class LibraryPhoneSheetRow extends StatelessWidget {
  const LibraryPhoneSheetRow({super.key, required this.title, required this.selected, required this.onTap, this.value});

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final accent = tokens(context).accent;
    final shown = value;
    return SizedBox(
      height: LibraryPhoneMetrics.sheetRowHeight,
      child: FocusableListTile(
        dense: false,
        visualDensity: LibraryPhoneMetrics.sheetRowDensity,
        contentPadding: const EdgeInsets.symmetric(horizontal: LibraryPhoneMetrics.sortRowInset),
        title: Text(title, style: _rowTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected
            ? AppIcon(
                Symbols.check_rounded,
                color: accent,
                size: LibraryPhoneMetrics.sheetIconSize,
                weight: LibraryPhoneMetrics.sheetIconWeight,
              )
            : shown == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _valueMaxWidth),
                child: Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowTextStyle.copyWith(color: accent),
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}

/// One action: an icon and a label. Taller only when a subtitle needs the room.
class LibraryPhoneSheetActionRow extends StatelessWidget {
  const LibraryPhoneSheetActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filledIcon = false,
    this.iconScale = 1,
    this.subtitle,
    this.destructive = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filledIcon;

  /// Paint only: a larger icon must not push the label off its edge.
  final double iconScale;
  final String? subtitle;
  final bool destructive;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    final note = subtitle;
    final tile = FocusableListTile(
      dense: false,
      autofocus: autofocus,
      visualDensity: LibraryPhoneMetrics.sheetRowDensity,
      contentPadding: const EdgeInsets.symmetric(horizontal: LibraryPhoneMetrics.sheetActionRowInset),
      minLeadingWidth: LibraryPhoneMetrics.sheetActionIconSize,
      horizontalTitleGap: LibraryPhoneMetrics.sheetActionIconGap,
      leading: Transform.scale(
        scale: iconScale,
        child: AppIcon(
          icon,
          fill: filledIcon ? 1 : 0,
          size: LibraryPhoneMetrics.sheetActionIconSize,
          weight: LibraryPhoneMetrics.sheetIconWeight,
          color: color,
        ),
      ),
      title: Text(
        label,
        style: _rowTextStyle.copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: note == null ? null : Text(note),
      onTap: onTap,
    );
    return note == null ? SizedBox(height: LibraryPhoneMetrics.sheetRowHeight, child: tile) : tile;
  }
}

/// Rule between the quick choices and the categories, on the rows' text edges.
class LibraryPhoneSheetDivider extends StatelessWidget {
  const LibraryPhoneSheetDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(
    height: 1,
    thickness: 1,
    indent: LibraryPhoneMetrics.sortRowInset,
    endIndent: LibraryPhoneMetrics.sortRowInset,
  );
}

const double _valueMaxWidth = 160;

const TextStyle _rowTextStyle = TextStyle(
  fontSize: LibraryPhoneMetrics.sortRowFontSize,
  letterSpacing: LibraryPhoneMetrics.letterSpacing,
);

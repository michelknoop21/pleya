/// Pieces of the floating sheets of the iPhone library look: a centred bold
/// heading and a 46 pt row with the choice's check on the right.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import '../focusable_list_tile.dart';
import 'library_phone_look.dart';

/// Centred, bold heading under the grip.
class LibraryPhoneSheetHeading extends StatelessWidget {
  const LibraryPhoneSheetHeading({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: kMinInteractiveDimension,
    child: Center(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: LibraryPhoneMetrics.letterSpacing,
        ),
      ),
    ),
  );
}

/// One choice. The check is the accent colour; an unchosen row has no mark.
class LibraryPhoneSheetRow extends StatelessWidget {
  const LibraryPhoneSheetRow({super.key, required this.title, required this.selected, required this.onTap});

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: LibraryPhoneMetrics.sheetRowHeight,
    child: FocusableListTile(
      dense: false,
      visualDensity: VisualDensity.standard,
      contentPadding: const EdgeInsets.symmetric(horizontal: LibraryPhoneMetrics.sortRowInset),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: LibraryPhoneMetrics.sortRowFontSize,
          letterSpacing: LibraryPhoneMetrics.letterSpacing,
        ),
      ),
      trailing: selected ? AppIcon(Symbols.check_rounded, color: tokens(context).accent, size: 22) : null,
      onTap: onTap,
    ),
  );
}

import 'package:flutter/material.dart';

import '../../../widgets/bottom_sheet_page_scaffold.dart';
import '../film_frame_palette.dart';

/// Base class for video control bottom sheets providing common UI structure
class BaseVideoControlSheet extends StatelessWidget {
  final String title;
  final IconData? icon;

  /// Replaces [icon] as the header's leading widget (e.g. an SVG glyph).
  final Widget? leading;
  final Widget child;
  final Color? iconColor;
  final VoidCallback? onBack;

  /// Size the sheet to its content instead of filling the host's height. For
  /// a short list (the handoff picker's two rows), not for a long one.
  final bool shrinkWrap;

  const BaseVideoControlSheet({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    required this.child,
    this.iconColor,
    this.onBack,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    // The player's sheets mark the chosen row, its check and an enabled switch
    // in the Filmbeeld mint, not the app's red primary (mockup A). Every
    // player sheet goes through here, so they all read `colorScheme.primary`.
    // A light sheet keeps the app primary: mint on white is about 1.2:1.
    final theme = Theme.of(context);
    if (theme.brightness != Brightness.dark) return _scaffold();
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: kFilmFocus, onPrimary: kFilmInk),
      ),
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return BottomSheetPageScaffold(
      title: title,
      icon: icon,
      leading: leading,
      iconColor: iconColor,
      onBack: onBack,
      titleStyle: const TextStyle(fontSize: 18, fontWeight: .bold),
      showHeaderBorder: false,
      showHeaderDivider: true,
      shrinkWrap: shrinkWrap,
      child: child,
    );
  }
}

/// The accent a player sheet marks a choice with: the Filmbeeld mint on a
/// dark sheet, the app primary on a light one. For code that sits above the
/// sheet's own theme (its header icon) as well as inside it.
Color playerSheetAccent(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark ? kFilmFocus : theme.colorScheme.primary;
}

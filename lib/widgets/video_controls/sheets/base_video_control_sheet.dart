import 'package:flutter/material.dart';

import '../../../widgets/bottom_sheet_page_scaffold.dart';

/// Base class for video control bottom sheets providing common UI structure
class BaseVideoControlSheet extends StatelessWidget {
  final String title;
  final IconData? icon;

  /// Replaces [icon] as the header's leading widget (e.g. an SVG glyph).
  final Widget? leading;
  final Widget child;
  final Color? iconColor;
  final VoidCallback? onBack;

  const BaseVideoControlSheet({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    required this.child,
    this.iconColor,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return BottomSheetPageScaffold(
      title: title,
      icon: icon,
      leading: leading,
      iconColor: iconColor,
      onBack: onBack,
      titleStyle: const TextStyle(fontSize: 18, fontWeight: .bold),
      showHeaderBorder: false,
      showHeaderDivider: true,
      child: child,
    );
  }
}

import 'package:flutter/material.dart';

import '../../../widgets/bottom_sheet_page_scaffold.dart';

/// Base class for video control bottom sheets providing common UI structure
class BaseVideoControlSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? iconColor;
  final VoidCallback? onBack;

  /// Size the sheet to its content instead of filling the host's height. For
  /// a short list (the handoff picker's two rows), not for a long one.
  final bool shrinkWrap;

  const BaseVideoControlSheet({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor,
    this.onBack,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return BottomSheetPageScaffold(
      title: title,
      icon: icon,
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

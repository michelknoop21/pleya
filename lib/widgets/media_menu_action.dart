import 'package:flutter/widgets.dart';

/// One row of the long-press menu. [value] is what [MediaContextMenuState]
/// dispatches on.
class MediaMenuAction {
  const MediaMenuAction({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
    this.subtitle,
  });

  final String value;
  final IconData icon;
  final String label;
  final bool destructive;
  final String? subtitle;
}

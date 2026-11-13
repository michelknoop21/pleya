import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/card_focus_scope.dart';
import '../focus/focusable_wrapper.dart';
import 'app_icon.dart';

/// One server found on the local network, on an add-server screen: its name,
/// its address, and a chevron. Shared by the Jellyfin/Emby and the Pleya
/// Server screens so both lists look and steer the same.
class DiscoveredServerTile extends StatelessWidget {
  final String name;
  final String address;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onTap;
  final String? automationId;
  final String? automationInstance;

  const DiscoveredServerTile({
    super.key,
    required this.name,
    required this.address,
    required this.focusNode,
    required this.onNavigateUp,
    required this.onNavigateDown,
    required this.onTap,
    this.automationId,
    this.automationInstance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableWrapper(
      focusNode: focusNode,
      disableScale: true,
      // Border drawn by CardFocusBorder so it paints over the opaque Material.
      mode: FocusIndicatorMode.delegated,
      descendantsAreFocusable: false,
      onSelect: onTap,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      automationId: automationId,
      automationInstance: automationInstance,
      automationRole: automationId == null ? null : 'button',
      child: CardFocusBorder(
        borderRadius: 12,
        strokeAlign: BorderSide.strokeAlignInside,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const AppIcon(Symbols.dns_rounded, fill: 1),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      children: [
                        Text(name, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          address,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

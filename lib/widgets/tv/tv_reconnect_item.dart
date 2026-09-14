/// OFF-1's reconnect item, extracted out of [TvTopNavigation] because it has
/// no dependency on that widget's private state beyond its own constructor
/// params — see docs/tvos-fysieke-correctieronde.md's OFF-1 row.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import 'tv_unified_layout.dart';

/// The reconnect item's focus key. Not a `TvDestinationId`: it triggers an
/// action rather than selecting a tab, so it carries no `.tab` and never
/// becomes `active`.
///
/// Public: `MainScreen` needs it to detect that the remote was on this item
/// right before a reconnect makes it disappear, so it can hand focus
/// somewhere else instead of leaving it orphaned.
const String tvReconnectFocusKey = 'tvNav_reconnect';

/// OFF-1: the TV bar's only offline affordance before this was Mijn Pleya
/// itself (Servers, reachable from there). Mirrors `SideNavigationRail`'s
/// `_buildReconnectItem` — same icon swap, same label, same disabled-while-
/// reconnecting tap — drawn as one more pill in the bar rather than a new
/// kind of control, so it inherits the bar's existing focus ring and D-pad
/// contract for free.
class TvReconnectItem extends StatelessWidget {
  const TvReconnectItem({
    super.key,
    required this.node,
    required this.scale,
    required this.isReconnecting,
    required this.onSelect,
    required this.onNavigateDown,
    required this.onNavigateLeft,
    required this.onNavigateRight,
  });

  final FocusNode node;
  final double scale;
  final bool isReconnecting;
  final VoidCallback onSelect;
  final VoidCallback onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    const shape = StadiumBorder();

    return FocusableWrapper(
      focusNode: node,
      // A no-op, not null: `FocusableWrapper` only claims the Select key when
      // `onSelect != null` (`focusable_wrapper.dart`'s `key.isSelectKey`
      // branch), so `null` here would let a Select press while reconnecting
      // fall through unhandled to the shell's own key handler instead of
      // being consumed. Same contract as the rail's item, which uses the
      // same no-op-not-null pattern for the identical reason.
      // ignore: no-empty-block - deliberate no-op while reconnecting
      onSelect: isReconnecting ? () {} : onSelect,
      automationId: AutomationIds.navReconnect,
      automationRole: 'nav',
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      focusShapeBorder: shape,
      disableScale: true,
      semanticLabel: t.common.reconnect,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvTopNavLayout.focusRingGap * scale),
          child: DecoratedBox(
            decoration: const ShapeDecoration(shape: shape, color: Colors.transparent),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: TvTopNavLayout.pillPaddingHorizontal * scale,
                vertical: TvTopNavLayout.pillPaddingVertical * scale,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isReconnecting)
                    SizedBox(
                      width: TvTopNavLayout.searchIconSize * scale,
                      height: TvTopNavLayout.searchIconSize * scale,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tk.text.withValues(alpha: TvTopNavLayout.inactiveInk),
                      ),
                    )
                  else
                    Icon(
                      Symbols.wifi_rounded,
                      size: TvTopNavLayout.searchIconSize * scale,
                      color: tk.text.withValues(alpha: TvTopNavLayout.inactiveInk),
                    ),
                  SizedBox(width: TvTopNavLayout.focusRingGap * 2 * scale),
                  Text(
                    t.common.reconnect,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: TvTopNavLayout.itemFontSize * scale,
                      fontWeight: FontWeight.w500,
                      color: tk.text.withValues(alpha: TvTopNavLayout.inactiveInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

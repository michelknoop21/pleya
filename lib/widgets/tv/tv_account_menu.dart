/// The small account menu under the profile avatar in the TV top navigation
/// (A-24c, northstar `docs/assets/a24c-northstars/02-Mijn-Pleya-v4/images/A14-profiel-acties.png`).
///
/// Two actions and nothing else: `Wissel profiel` and `Uitloggen`. The menu
/// only chooses; the caller runs the action through the same doors it always
/// used (`AccountUiActions.openProfiles(asGate: true)` through the shell's
/// callback, and `AccountUiActions.logout` with its own confirmation), so
/// there is no second sign-out semantics.
///
/// A modal route: the page and the top navigation behind it are not
/// focusable while it is open. Up and down move between the two actions,
/// Back or Menu closes it, and the caller puts the focus back on the avatar.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/dialogs.dart';
import '../../utils/layout_constants.dart';
import '../../utils/tv_hig.dart';
import 'tv_unified_layout.dart';

/// What the viewer chose in the account menu. Null from [showTvAccountMenu]
/// means the menu was closed without a choice.
enum TvAccountAction {
  switchProfile,
  logout;

  /// The automation instance: `account_menu.action[switch_profile]`.
  String get automationInstance => switch (this) {
    TvAccountAction.switchProfile => 'switch_profile',
    TvAccountAction.logout => 'logout',
  };
}

/// Opens the account menu over the shell and completes with the choice, or
/// null after Back.
Future<TvAccountAction?> showTvAccountMenu(BuildContext context, {required String? profileName}) =>
    showScopedDialog<TvAccountAction>(
      context: context,
      builder: (context) => TvAccountMenu(profileName: profileName),
    );

class TvAccountMenu extends StatefulWidget {
  const TvAccountMenu({super.key, required this.profileName});

  final String? profileName;

  @override
  State<TvAccountMenu> createState() => _TvAccountMenuState();
}

class _TvAccountMenuState extends State<TvAccountMenu> {
  final Map<TvAccountAction, FocusNode> _nodes = {
    for (final action in TvAccountAction.values) action: FocusNode(debugLabel: 'tvAccountMenu_${action.name}'),
  };

  /// A14, in HIG points on the 1920 x 1080 canvas.
  static const double _widthPt = 610;
  static const double _paddingPt = 30;
  static const double _radiusPt = 28;
  static const double _actionRadiusPt = 16;
  static const double _actionGapPt = 16;
  static const double _belowBarPt = 16;

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focus(TvAccountAction action) => _nodes[action]!.requestFocus();

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final name = widget.profileName;

    // Directly under the avatar: the bar's own inset and height, so the menu
    // hangs from the control that opened it.
    return AutomationNode(
      id: AutomationIds.accountMenu,
      role: 'dialog',
      label: t.tvAccountMenu.title,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: TvTopNavLayout.pageInset * scale,
            top: (TvTopNavLayout.topInset + TvTopNavLayout.barHeight) * scale + _belowBarPt * pt,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: _widthPt * pt,
              padding: EdgeInsets.all(_paddingPt * pt),
              decoration: BoxDecoration(
                color: tk.surfaceElevated,
                borderRadius: BorderRadius.circular(_radiusPt * pt),
                border: Border.all(color: tk.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.only(start: 12 * pt),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            t.tvAccountMenu.title,
                            style: TextStyle(
                              color: tk.text,
                              fontSize: TvHig.headline * pt,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (name != null && name.isNotEmpty)
                          Text(
                            t.tvAccountMenu.signedInAs(name: name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                              fontSize: TvHig.caption1 * pt,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20 * pt),
                  _ActionRow(
                    action: TvAccountAction.switchProfile,
                    node: _nodes[TvAccountAction.switchProfile]!,
                    autofocus: true,
                    icon: Symbols.swap_horiz_rounded,
                    title: t.tvAccountMenu.switchProfile,
                    subtitle: t.tvAccountMenu.switchProfileSubtitle,
                    radius: _actionRadiusPt * pt,
                    onNavigateDown: () => _focus(TvAccountAction.logout),
                  ),
                  SizedBox(height: _actionGapPt * pt),
                  _ActionRow(
                    action: TvAccountAction.logout,
                    node: _nodes[TvAccountAction.logout]!,
                    icon: Symbols.logout_rounded,
                    title: t.tvAccountMenu.logout,
                    subtitle: t.tvAccountMenu.logoutSubtitle,
                    destructive: true,
                    radius: _actionRadiusPt * pt,
                    onNavigateUp: () => _focus(TvAccountAction.switchProfile),
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.node,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.radius,
    this.autofocus = false,
    this.destructive = false,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final TvAccountAction action;
  final FocusNode node;
  final IconData icon;
  final String title;
  final String subtitle;
  final double radius;
  final bool autofocus;
  final bool destructive;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final titleInk = destructive ? tvAccountMenuDestructiveInk(tk) : tk.text;
    // Ends of the list stay put rather than wrap, and left/right have nowhere
    // to go: the menu is the only thing the remote can reach.
    void stay() {}

    return FocusableWrapper(
      focusNode: node,
      autofocus: autofocus,
      onSelect: () => Navigator.of(context).pop(action),
      onBack: () => Navigator.of(context).pop(),
      onNavigateUp: onNavigateUp ?? stay,
      onNavigateDown: onNavigateDown ?? stay,
      onNavigateLeft: stay,
      onNavigateRight: stay,
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: ringGap),
      disableScale: true,
      automationId: AutomationIds.accountMenuAction,
      automationInstance: action.automationInstance,
      automationRole: 'button',
      automationState: () => <String, Object?>{'title': title},
      semanticLabel: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(ringGap),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(horizontal: 22 * pt, vertical: 16 * pt),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  // The focused action carries a warm wash of the brand red
                  // under the ring (A14); the other one stays a quiet card.
                  color: focused
                      ? Color.alphaBlend(tk.accent.withValues(alpha: 0.22), tk.surfaceElevated)
                      : tk.text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
                  border: Border.all(color: tk.outline),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 34 * pt, weight: 300, color: titleInk),
                    SizedBox(width: 22 * pt),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: titleInk, fontSize: TvHig.body * pt, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                              fontSize: TvHig.caption2 * pt,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// `Uitloggen` in the brand red, as A14 draws it, lifted towards the ink on a
/// dark card so it still reads at WCAG AA there (`tv_text_contrast_audit_test`).
Color tvAccountMenuDestructiveInk(MonoTokens tk) => tk.isLight ? tk.accent : Color.lerp(tk.accent, tk.text, 0.2)!;

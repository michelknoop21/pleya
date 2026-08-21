import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart' as i18n;
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import '../pressable.dart';
import 'notice.dart';
import 'notice_controller.dart';

/// Renders one [NoticeEntry]: icon (colored by level), title, optional body,
/// a "×N" counter when [NoticeEntry.count] > 1, and up to two action
/// buttons. [tv] swaps [Pressable] buttons for D-pad-focusable
/// [FocusableButton]s and applies [scale] (from `TvLayoutConstants.scaleOf`)
/// to every dimension — the host decides platform and passes both in.
///
/// Ground is always `tokens(context).surfaceElevated`; the level lives only
/// in the icon color (see the contrast table on the `kNotice*` constants in
/// `mono_theme.dart`), never in the card background.
/// Identifies the close affordance so a test can measure the real hit
/// target instead of the glyph inside it.
const Key kNoticeCloseKey = Key('notice-close');

/// Touch/pointer close target. [kMinInteractiveDimension] is 48, above the
/// 44pt HIG floor and the same figure the bottom-sheet header already uses.
const double kNoticeCloseTargetTouch = kMinInteractiveDimension;

/// TV close target before `TvLayoutConstants.scaleOf` is applied. Read from
/// three metres away and hit with a remote, not a fingertip.
const double kNoticeCloseTargetTv = 56;

class NoticeCard extends StatelessWidget {
  final NoticeEntry entry;
  final VoidCallback onDismiss;
  final bool tv;
  final double scale;

  const NoticeCard({super.key, required this.entry, required this.onDismiss, this.tv = false, this.scale = 1.0});

  (IconData, Color) _iconAndColor(MonoTokens t) {
    final isLight = t.isLight;
    return switch (entry.notice.level) {
      NoticeLevel.success => (Symbols.check_circle_rounded, isLight ? kNoticeSuccessLight : kNoticeSuccessDark),
      NoticeLevel.info => (Symbols.info_rounded, isLight ? kNoticeInfoLight : kNoticeInfoDark),
      NoticeLevel.warning => (Symbols.warning_rounded, isLight ? kNoticeWarningLight : kNoticeWarningDark),
      NoticeLevel.error => (Symbols.error_rounded, isLight ? kNoticeErrorLight : kNoticeErrorDark),
    };
  }

  // Text is always `t.text` — never `levelColor` — even on the tinted
  // primary button. `levelColor` only clears AA as *icon* ink against a bare
  // `surfaceElevated` (see the contrast table in mono_theme.dart); measured
  // as 13px text against the 16%-tinted fill, several combinations (e.g.
  // error-dark ~3.8:1, success-light ~3.7:1) fall under 4.5:1. `t.text` on
  // the same tinted fill clears 9:1+ in every case, since the tint is only a
  // mild wash over `surfaceElevated`, not a solid color swap.
  Widget _actionButton(
    BuildContext context,
    MonoTokens t,
    Color levelColor,
    NoticeAction action, {
    required bool primary,
  }) {
    void onPressed() => noticeController.runAction(entry.id, action);
    final child = Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        color: primary ? levelColor.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      child: Text(
        action.label,
        style: TextStyle(color: primary ? t.text : t.textMuted, fontWeight: FontWeight.w600, fontSize: 13 * scale),
      ),
    );
    return tv
        ? FocusableButton(onPressed: onPressed, dimWhenUnfocused: false, child: child)
        : Pressable(onTap: onPressed, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final (icon, levelColor) = _iconAndColor(t);
    final notice = entry.notice;

    // Listener, not GestureDetector: with `opaque` its render object answers
    // hitTestSelf, which stops the Stack from descending into the app layer
    // behind the card, and it does so without entering the gesture arena —
    // so it can't compete with the close button or the mobile swipe. Without
    // it a tap on the card's own padding falls straight through, since
    // Container and Padding are all RenderProxyBox.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(t.space * scale),
        decoration: BoxDecoration(
          color: t.surfaceElevated,
          borderRadius: BorderRadius.circular(t.radiusSm),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 16, offset: Offset(0, 4 * scale)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(icon, color: levelColor, size: 22 * scale, fill: 1, weight: 700),
            SizedBox(width: t.space * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notice.title,
                          style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14 * scale),
                        ),
                      ),
                      if (entry.count > 1) ...[
                        SizedBox(width: 6 * scale),
                        Text(
                          '×${entry.count}',
                          style: TextStyle(color: t.textMuted, fontSize: 12 * scale),
                        ),
                      ],
                      if (notice.reportCode != null) ...[
                        SizedBox(width: 6 * scale),
                        Text(
                          notice.reportCode!,
                          style: TextStyle(
                            color: t.textMuted,
                            fontSize: 11 * scale,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (notice.body != null) ...[
                    SizedBox(height: 2 * scale),
                    Text(
                      notice.body!,
                      style: TextStyle(color: t.textMuted, fontSize: 13 * scale),
                    ),
                  ],
                  if (notice.primary != null || notice.secondary != null) ...[
                    SizedBox(height: t.space * 0.75 * scale),
                    Row(
                      children: [
                        if (notice.primary != null)
                          _actionButton(context, t, levelColor, notice.primary!, primary: true),
                        if (notice.primary != null && notice.secondary != null) SizedBox(width: 8 * scale),
                        if (notice.secondary != null)
                          _actionButton(context, t, levelColor, notice.secondary!, primary: false),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 4 * scale),
            _closeAffordance(t),
          ],
        ),
      ),
    );
  }

  /// The close button, sized to a real touch target rather than to its glyph.
  ///
  /// The ground is an explicit [DecoratedBox] and not a Material button:
  /// `monoTheme` maps every *Container role onto `c.surface` and installs
  /// `NoSplash`, so an [IconButton] here would have no visible pressed or
  /// hovered state at all (DEC-031). [Pressable]'s scale is the feedback.
  Widget _closeAffordance(MonoTokens t) {
    final label = i18n.t.common.close;
    final side = (tv ? kNoticeCloseTargetTv : kNoticeCloseTargetTouch) * scale;
    final target = SizedBox(
      width: side,
      height: side,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.text.withValues(alpha: 0.06), shape: BoxShape.circle),
          child: Padding(
            padding: EdgeInsets.all(6 * scale),
            child: AppIcon(Symbols.close_rounded, color: t.textMuted, size: 18 * scale, fill: 0, weight: 500),
          ),
        ),
      ),
    );

    if (tv) {
      // FocusableWrapper answers select keys and nothing else, so on its own
      // this would be unreachable for an Android TV box with a mouse or
      // trackpad attached. The Pressable adds that without touching focus.
      return Pressable(
        key: kNoticeCloseKey,
        onTap: onDismiss,
        haptic: false,
        behavior: HitTestBehavior.opaque,
        child: FocusableButton(onPressed: onDismiss, semanticLabel: label, dimWhenUnfocused: false, child: target),
      );
    }
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        // The action is declared here rather than inherited from the gesture
        // detector, because excludeSemantics drops the child's own node —
        // without it a screen reader announces the button but cannot activate
        // it.
        onTap: onDismiss,
        excludeSemantics: true,
        // The key sits on Pressable and not on the SizedBox inside it:
        // RenderConstrainedBox.hitTestSelf is false, so at a corner of the
        // box it is the opaque gesture handler that is in the hit path.
        child: Pressable(
          key: kNoticeCloseKey,
          onTap: onDismiss,
          haptic: false,
          behavior: HitTestBehavior.opaque,
          child: target,
        ),
      ),
    );
  }
}

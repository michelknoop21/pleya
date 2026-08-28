import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_button.dart';
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
        ? FocusableButton(
            onPressed: onPressed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
            child: child,
          )
        : Pressable(onTap: onPressed, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final (icon, levelColor) = _iconAndColor(t);
    final notice = entry.notice;

    final closeButton = AppIcon(Symbols.close_rounded, color: t.textMuted, size: 18 * scale, fill: 0, weight: 500);
    final closeTap = tv
        ? FocusableButton(onPressed: onDismiss, shape: const CircleBorder(), child: closeButton)
        : Pressable(onTap: onDismiss, haptic: false, child: closeButton);

    return Container(
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
                      if (notice.primary != null) _actionButton(context, t, levelColor, notice.primary!, primary: true),
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
          closeTap,
        ],
      ),
    );
  }
}

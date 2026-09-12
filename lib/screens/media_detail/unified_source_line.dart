part of '../media_detail_screen.dart';

/// The unified-group source line, split out of `action_buttons.dart`
/// (CLAUDE.md's file-size guideline) when the phone redesign (I6) touched
/// that file. Pure move, no behavior change.
extension _MediaDetailUnifiedSourceLine on _MediaDetailScreenState {
  /// Hoofdstuk 15's `Bron: NAS • Films 4K   [ Wijzigen ]`.
  ///
  /// Rendered only when the page was reached through a unified group that
  /// actually has more than one source — a single-source title has nothing to
  /// change to, and a line saying so would be chrome. Returns a zero-size box
  /// otherwise, which is every entry point that is not a unified activation.
  Widget _buildUnifiedSourceLine() {
    final routeContext = widget.unifiedRouteContext;
    if (routeContext == null || !routeContext.hasAlternativeSources) return const SizedBox.shrink();

    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final parts = [
      _metadata.serverName ?? routeContext.sourceKey.split(':').first,
      if ((_metadata.libraryTitle ?? '').trim().isNotEmpty) _metadata.libraryTitle!.trim(),
    ];
    final label = t.sourcePicker.sourceLabel(source: parts.join(' • '));
    final fontSize = isTv ? 13.0 * tvScale : 13.0;
    final onChangeSource = widget.onChangeSource;

    return Padding(
      padding: EdgeInsets.only(top: isTv ? 10 * tvScale : 12),
      child: Row(
        mainAxisSize: .min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(color: mono.textMuted, fontSize: fontSize, fontWeight: .w500),
            ),
          ),
          if (onChangeSource != null) ...[
            SizedBox(width: isTv ? 10 * tvScale : 12),
            FocusableWrapper(
              borderRadius: 999,
              disableScale: true,
              semanticLabel: t.sourcePicker.change,
              onSelect: () {
                // The picker opens a route; suppress this press's key-up so it
                // does not land on whatever takes focus next (CLAUDE.md).
                SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
                unawaited(onChangeSource(context));
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: isTv ? 14 * tvScale : 14, vertical: isTv ? 6 * tvScale : 6),
                decoration: BoxDecoration(
                  color: mono.text.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  t.sourcePicker.change,
                  style: TextStyle(color: mono.text, fontSize: fontSize, fontWeight: .w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The height [_buildUnifiedSourceLine] actually renders, so the two hero
  /// layouts in media_detail_screen.dart can reserve room for it before
  /// laying out their Column.
  ///
  /// Measures the real text line height via [TextPainter] against the same
  /// ambient [DefaultTextStyle] `_buildUnifiedSourceLine`'s `Text` widgets
  /// resolve against (fontFamily, any theme-level `height` multiplier, text
  /// scaling) instead of guessing a line-height multiplier — a guessed
  /// constant here and the real render can only drift apart; a measurement
  /// against the same style authority can't. The chip is wrapped in a
  /// [FocusableWrapper], whose ring decoration always carries a
  /// [FocusTheme.focusBorderWidth]-wide border (transparent when unfocused,
  /// but still there) — `Container`/`AnimatedContainer` folds a decoration's
  /// border into its own effective padding, so the wrapper is
  /// `2 * FocusTheme.focusBorderWidth` taller than its child, unscaled by
  /// `tvScale` since the border itself never scales.
  double _unifiedSourceLineHeight(BuildContext context) {
    final routeContext = widget.unifiedRouteContext;
    if (routeContext == null || !routeContext.hasAlternativeSources) return 0.0;
    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final fontSize = isTv ? 13.0 * tvScale : 13.0;
    final topPadding = isTv ? 10 * tvScale : 12.0;
    final chipVerticalPadding = isTv ? 6 * tvScale : 6.0;
    final baseStyle = DefaultTextStyle.of(context).style;
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Mg',
        style: baseStyle.copyWith(fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final textLineHeight = textPainter.height;
    final rowHeight = widget.onChangeSource != null
        ? (chipVerticalPadding * 2) + textLineHeight + (2 * FocusTheme.focusBorderWidth)
        : textLineHeight;
    return topPadding + rowHeight;
  }
}

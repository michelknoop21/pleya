library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_panel_primitives.dart';
import '../../widgets/tv/tv_unified_layout.dart';

enum TvAuthPanelState { initial, waiting, qr, plexError, timedOut, authenticating, noServersFound, networkError }

/// Viewport-derived composition geometry for the Apple TV first-start screen.
///
/// The reference values are measurements on the 1920×1080 north star. They
/// scale with the actual viewport rather than the clamped ten-foot density
/// scale, so the two columns always consume exactly the available frame.
class TvAuthGeometry {
  const TvAuthGeometry._({
    required this.safeInsets,
    required this.columnGap,
    required this.leftColumnWidth,
    required this.panelSize,
  });

  factory TvAuthGeometry.forViewport(Size viewport) {
    final horizontalScale = viewport.width / 1920;
    final verticalScale = viewport.height / 1080;
    return TvAuthGeometry._(
      safeInsets: EdgeInsets.fromLTRB(
        72 * horizontalScale,
        56 * verticalScale,
        72 * horizontalScale,
        56 * verticalScale,
      ),
      columnGap: 96 * horizontalScale,
      leftColumnWidth: 720 * horizontalScale,
      panelSize: Size(960 * horizontalScale, 740 * verticalScale),
    );
  }

  final EdgeInsets safeInsets;
  final double columnGap;
  final double leftColumnWidth;
  final Size panelSize;
}

/// Pure ten-foot presentation for the first-start authentication routes.
///
/// Authentication, navigation and persistence stay with the parent. This
/// widget owns the two visible backend rows, their focus order and the stable
/// automation nodes that operate those rows.
class TvAuthView extends StatelessWidget {
  const TvAuthView({
    super.key,
    required this.brand,
    required this.content,
    required this.state,
    required this.plexEnabled,
    required this.jellyfinEnabled,
    required this.onPlexSelected,
    required this.onJellyfinSelected,
  });

  final Widget brand;
  final Widget content;
  final TvAuthPanelState state;
  final bool plexEnabled;
  final bool jellyfinEnabled;
  final VoidCallback onPlexSelected;
  final VoidCallback onJellyfinSelected;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry = TvAuthGeometry.forViewport(viewport);
        final scale = TvLayoutConstants.scaleOf(context);

        return ColoredBox(
          color: mono.bg,
          child: Padding(
            padding: geometry.safeInsets,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  key: const ValueKey('tv-auth-left-column'),
                  width: geometry.leftColumnWidth,
                  height: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      brand,
                      const Spacer(),
                      AutomationNode(
                        id: AutomationIds.authHeading,
                        role: 'heading',
                        child: Text(
                          t.auth.chooseHowToSignIn,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mono.text,
                            fontSize: TvAuthLayout.headingFontSize * scale,
                            fontWeight: FontWeight.w700,
                            height: 1.08,
                          ),
                        ),
                      ),
                      SizedBox(height: TvAuthLayout.headingGap * scale),
                      Text(
                        t.auth.chooseHowToSignInDescription,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mono.textMuted,
                          fontSize: TvAuthLayout.bodyFontSize * scale,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: TvAuthLayout.choicesTopGap * scale),
                      _TvAuthChoiceRow(
                        label: t.auth.signInWithPlex,
                        subtitle: t.auth.scanQRToSignIn,
                        instance: 'plex',
                        enabled: plexEnabled,
                        autofocus: plexEnabled,
                        onSelected: onPlexSelected,
                      ),
                      SizedBox(height: TvAuthLayout.choiceGap * scale),
                      _TvAuthChoiceRow(
                        label: t.auth.connectToJellyfin,
                        subtitle: t.addServer.connectToJellyfinCardSubtitle,
                        instance: 'jellyfin',
                        enabled: jellyfinEnabled,
                        autofocus: !plexEnabled && jellyfinEnabled,
                        onSelected: onJellyfinSelected,
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                SizedBox(width: geometry.columnGap),
                AutomationNode(
                  id: AutomationIds.authPanel,
                  role: 'region',
                  state: () => {'state': state.name},
                  child: Container(
                    key: ValueKey('tv-auth-panel-${state.name}'),
                    width: geometry.panelSize.width,
                    height: geometry.panelSize.height,
                    padding: EdgeInsets.all(TvAuthLayout.panelPadding * scale),
                    decoration: tvPanelDecoration(mono, TvAuthLayout.panelRadius * scale),
                    alignment: Alignment.topLeft,
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TvAuthChoiceRow extends StatefulWidget {
  const _TvAuthChoiceRow({
    required this.label,
    required this.subtitle,
    required this.instance,
    required this.enabled,
    required this.autofocus,
    required this.onSelected,
  });

  final String label;
  final String subtitle;
  final String instance;
  final bool enabled;
  final bool autofocus;
  final VoidCallback onSelected;

  @override
  State<_TvAuthChoiceRow> createState() => _TvAuthChoiceRowState();
}

class _TvAuthChoiceRowState extends State<_TvAuthChoiceRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = TvAuthLayout.choiceRadius * scale;

    return FocusableWrapper(
      key: ValueKey('tv-auth-choice-${widget.instance}'),
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onSelect: widget.enabled ? widget.onSelected : null,
      onFocusChange: (focused) => setState(() => _focused = focused),
      semanticLabel: widget.label,
      borderRadius: radius + TvAuthLayout.focusRingGap * scale,
      automationId: AutomationIds.authChoice,
      automationInstance: widget.instance,
      automationRole: 'button',
      automationState: () => {'enabled': widget.enabled},
      child: Padding(
        padding: EdgeInsets.all(TvAuthLayout.focusRingGap * scale),
        child: AnimatedContainer(
          duration: mono.fast,
          constraints: BoxConstraints(minHeight: TvAuthLayout.choiceMinHeight * scale),
          padding: EdgeInsets.symmetric(
            horizontal: TvAuthLayout.choicePaddingHorizontal * scale,
            vertical: TvAuthLayout.choicePaddingVertical * scale,
          ),
          decoration: BoxDecoration(
            color: _focused ? mono.surfaceElevated : mono.surface,
            border: Border.all(color: _focused ? mono.text.withValues(alpha: 0.18) : mono.outline),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.42,
            child: Row(
              children: [
                Icon(Icons.chevron_right_rounded, size: TvAuthLayout.choiceIconSize * scale, color: mono.text),
                SizedBox(width: 14 * scale),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mono.text,
                          fontSize: TvAuthLayout.choiceTitleFontSize * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: TvAuthLayout.choiceLineGap * scale),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mono.textMuted,
                          fontSize: TvAuthLayout.choiceSubtitleFontSize * scale,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10 * scale),
                Icon(Icons.chevron_right_rounded, size: TvAuthLayout.choiceIconSize * scale, color: mono.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

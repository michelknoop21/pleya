import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_source_info.dart';
import '../../../theme/glass/glass_settings.dart';
import '../../../theme/glass/glass_surface.dart';
import '../../../theme/glass/glass_text.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../app_icon.dart';
import '../mobile_video_controls_glass.dart';

/// [kPlayerGlassTokens] with black 60% instead of 55% (the phone's
/// `realTint`). The label is text, so 4.5:1 applies, not the 3:1 of the
/// player's icon plates: on 55% over a white frame the plate's top highlight
/// held the label at 4.48 (LG-SKIP1, `skip_marker_glass_test.dart`).
const GlassTokens _kPhoneSkipTokens = GlassTokens(blur: 0, saturation: 1, dim: 1, tint: Color(0x99000000), edge: 0.3);

class SkipMarkerButton extends StatelessWidget {
  final MediaMarker marker;
  final Duration playerDuration;
  final bool hasNextEpisode;
  final bool isAutoSkipActive;
  final bool shouldShowAutoSkip;
  final int autoSkipDelay;
  final double autoSkipProgress;
  final FocusNode focusNode;
  final VoidCallback onActivate;
  final VoidCallback onFocusDown;

  /// Called on UP/LEFT/RIGHT. The button sits outside the controls focus scope,
  /// so without this it is a dead end in those directions.
  final VoidCallback onFocusExit;

  const SkipMarkerButton({
    super.key,
    required this.marker,
    required this.playerDuration,
    required this.hasNextEpisode,
    required this.isAutoSkipActive,
    required this.shouldShowAutoSkip,
    required this.autoSkipDelay,
    required this.autoSkipProgress,
    required this.focusNode,
    required this.onActivate,
    required this.onFocusDown,
    required this.onFocusExit,
  });

  @override
  Widget build(BuildContext context) {
    final isCredits = marker.isCredits;
    final creditsAtEnd =
        isCredits && playerDuration > Duration.zero && (playerDuration - marker.endTime).inMilliseconds <= 1000;
    final showNextEpisode = creditsAtEnd && hasNextEpisode;
    String baseButtonText;
    if (showNextEpisode) {
      baseButtonText = t.videoControls.nextEpisode;
    } else if (isCredits) {
      baseButtonText = t.videoControls.skipCredits;
    } else {
      baseButtonText = t.videoControls.skipIntro;
    }

    final remainingSeconds = isAutoSkipActive && shouldShowAutoSkip
        ? (autoSkipDelay - (autoSkipProgress * autoSkipDelay)).ceil().clamp(0, autoSkipDelay)
        : 0;

    final showAutoSkipCountdown = isAutoSkipActive && shouldShowAutoSkip;
    final buttonText = showAutoSkipCountdown && remainingSeconds > 0
        ? '$baseButtonText ($remainingSeconds)'
        : baseButtonText;
    final buttonIcon = showNextEpisode ? Symbols.skip_next_rounded : Symbols.fast_forward_rounded;

    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: _activate,
      borderRadius: tokens(context).radiusSm,
      // Border ring, not the background tint: the tint sits behind an opaque
      // white button and is invisible.
      autoScroll: false,
      onNavigateUp: onFocusExit,
      onNavigateLeft: onFocusExit,
      onNavigateRight: onFocusExit,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onFocusDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _activate,
          borderRadius: BorderRadius.circular(tokens(context).radiusSm),
          child: Stack(
            children: [
              _pill(context, buttonText, buttonIcon),
              if (isAutoSkipActive && shouldShowAutoSkip)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                    child: Row(
                      children: [
                        Expanded(
                          flex: (autoSkipProgress * 100).round(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: ((1.0 - autoSkipProgress) * 100).round(),
                          child: Container(decoration: const BoxDecoration(color: Colors.transparent)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The pill behind the label. Glass off: today's white pill. Glass on
  /// (iPhone and Apple TV, the gate the rest of the player uses): the
  /// player's plate without backdrop, because the video is a native layer
  /// under the FlutterView. White ink with the glass text shadow; same
  /// padding, so the button keeps its size.
  Widget _pill(BuildContext context, String label, IconData icon) {
    final radius = BorderRadius.circular(tokens(context).radiusSm);
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    if (!playerGlassOn(context)) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: radius,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: .min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: .w600),
            ),
            const SizedBox(width: 8),
            AppIcon(icon, fill: 1, color: Colors.black, size: 20),
          ],
        ),
      );
    }
    return GlassSurface(
      shape: RoundedRectangleBorder(borderRadius: radius),
      tokens: PlatformDetector.isTV() ? GlassTokens.tvFor(context, panel: true) : _kPhoneSkipTokens,
      backdrop: false,
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: .min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: .w600, shadows: kGlassTextShadows),
            ),
            const SizedBox(width: 8),
            AppIcon(icon, fill: 1, color: Colors.white, size: 20, shadows: kGlassIconShadows),
          ],
        ),
      ),
    );
  }

  void _activate() => onActivate();
}

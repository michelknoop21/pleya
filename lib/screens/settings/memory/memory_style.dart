import 'package:flutter/material.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/tv_hig.dart';

/// Type, scale and the one focus stop every control of the memory screens is
/// built from.

/// The size the shared pieces are drawn at. Unset on a phone and a tablet
/// (1). On TV the sheet and the dialogs set it, so the same widgets land on
/// tvOS type sizes: a 16 pt phone label becomes 29.6 pt, tvOS body.
class MemoryScale extends InheritedWidget {
  const MemoryScale({super.key, required this.k, required super.child});

  final double k;

  /// Phone points to tvOS points: the 1080 pt canvas over a 584 pt panel.
  static const double _tvPerPhone = 1.85;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MemoryScale>()?.k ?? 1;

  /// [child] at TV size on a TV, untouched elsewhere.
  static Widget forPlatform(BuildContext context, Widget child) =>
      PlatformDetector.isTV() ? MemoryScale(k: TvHig.of(context) * _tvPerPhone, child: child) : child;

  @override
  bool updateShouldNotify(MemoryScale oldWidget) => oldWidget.k != k;
}

/// The app's font at [size]: the theme gives only bodyMedium the app font.
TextStyle memoryText(BuildContext context, double size, {FontWeight? weight, Color? color, double? height}) =>
    Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: size * MemoryScale.of(context),
      fontWeight: weight,
      color: color ?? tokens(context).text,
      height: height,
    );

/// The third ink of the mockup: hints, chevrons, group labels.
Color memoryFaint(BuildContext context) => tokens(context).text.withValues(alpha: 0.5);

/// One focus stop that a tap and Select both activate. The focus ring is the
/// wrapper's own, shown in remote and keyboard mode only.
class MemoryPressable extends StatelessWidget {
  const MemoryPressable({
    super.key,
    required this.child,
    required this.onPressed,
    this.shape,
    this.radius = 14,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.automationId,
    this.automationInstance,
    this.automationRole = 'button',
    this.automationState,
  });

  final Widget child;

  /// Null draws the control but takes it out of the focus order.
  final VoidCallback? onPressed;
  final OutlinedBorder? shape;
  final double radius;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final String? automationId;
  final String? automationInstance;
  final String automationRole;
  final Object? Function()? automationState;

  @override
  Widget build(BuildContext context) {
    final press = onPressed;
    return GestureDetector(
      // FocusableWrapper only answers keys; on a touch screen a tap is Select.
      onTap: press,
      behavior: HitTestBehavior.opaque,
      child: FocusableWrapper(
        focusNode: focusNode,
        autofocus: autofocus,
        canRequestFocus: press != null,
        disableScale: true,
        borderRadius: radius * MemoryScale.of(context),
        focusShapeBorder: shape,
        semanticLabel: semanticLabel,
        automationId: automationId,
        automationInstance: automationInstance,
        automationRole: automationRole,
        automationState: automationState,
        onSelect: press == null
            ? null
            : () {
                // What opens next takes the focus: the release of this press
                // must not activate it.
                SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
                press();
              },
        child: child,
      ),
    );
  }
}

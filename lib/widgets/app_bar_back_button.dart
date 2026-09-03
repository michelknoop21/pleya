import 'package:flutter/material.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Whether this platform draws a *visible* back affordance at all.
///
/// PB-2 of `docs/tvos-redesign-implementatiecontract.md`: on the remote-first
/// TV surfaces there is no visible back button, because there cannot be a
/// usable one. [AppBarBackButton] is a `MouseRegion` around a
/// `GestureDetector` and carries no `FocusNode` of any kind, so it is not in
/// the remote's traversal set, and tvOS has no cursor to aim at it with
/// either. Drawn on TV it is a control that claims to be pressable and
/// provably is not: `InputModeTracker` pins `InputMode.keyboard` for the whole
/// session there and never leaves it.
///
/// Back on TV belongs to the Menu/Back key instead: `handleBackKeyAction` and
/// `handleBackKeyNavigation` in `lib/focus/key_event_utils.dart`, the shell's
/// own chain via `tvBackStep`, and `TvNestedRouteScope.dismiss` for a nested
/// route. Android TV's hardware BACK arrives on that same key path, so nothing
/// is lost there either.
///
/// Touch and pointer surfaces keep their back button: this returns true
/// everywhere else, and no non-TV platform changes behaviour.
bool showsVisibleBackAffordance() => !PlatformDetector.isTV();

/// Defines the visual style of the back button
enum BackButtonStyle {
  /// Back button with circular semi-transparent background (used in detail screens)
  circular,

  /// Plain back button without background (used in sheets and simple contexts)
  plain,

  /// Back button styled for video player overlay
  video,
}

/// A reusable back button widget that provides consistent styling across the app.
///
/// This widget supports different visual styles through [BackButtonStyle] enum:
/// - [BackButtonStyle.circular]: Semi-transparent circular background for detail screens
/// - [BackButtonStyle.plain]: Simple IconButton for sheets and simple contexts
/// - [BackButtonStyle.video]: Styled for video player overlay
///
/// Example usage:
/// ```dart
/// AppBarBackButton(style: BackButtonStyle.circular)
/// ```
class AppBarBackButton extends StatefulWidget {
  /// Creates a back button with the specified style.
  ///
  /// [style] determines the visual appearance of the back button.
  /// [onPressed] is called when the button is tapped. If null, defaults to Navigator.pop.
  /// [color] overrides the default icon color. If null, uses white for circular/video, theme default for plain.
  /// [semanticLabel] provides accessibility label for screen readers.
  const AppBarBackButton({
    super.key,
    this.style = BackButtonStyle.circular,
    this.onPressed,
    this.color,
    this.semanticLabel,
  });

  final BackButtonStyle style;

  /// Callback when the button is pressed. Defaults to Navigator.of(context).pop()
  final VoidCallback? onPressed;

  /// The color of the back arrow icon. If null, uses style-appropriate default.
  final Color? color;

  final String? semanticLabel;

  @override
  State<AppBarBackButton> createState() => _AppBarBackButtonState();
}

class _AppBarBackButtonState extends State<AppBarBackButton> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _backgroundAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: const Duration(milliseconds: 150), vsync: this);
    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHoverChange(bool isHovered) {
    if (isHovered) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _handlePressed() {
    if (widget.onPressed != null) {
      widget.onPressed!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The backstop under [showsVisibleBackAffordance]. Every call site checks
    // it too, because a site that knows the button is gone can also drop the
    // layout it reserved for one; this guard is what stops a *new* caller from
    // reintroducing BACK1 without noticing.
    if (!showsVisibleBackAffordance()) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDarkTheme = theme.brightness == Brightness.dark;

    final Color effectiveColor;
    switch (widget.style) {
      case BackButtonStyle.plain:
        effectiveColor = widget.color ?? (isDarkTheme ? Colors.white : Colors.black);
        break;
      case BackButtonStyle.circular:
      case BackButtonStyle.video:
        effectiveColor = widget.color ?? Colors.white;
        break;
    }

    final Color baseColor;
    final Color hoverColor;
    switch (widget.style) {
      case BackButtonStyle.circular:
        baseColor = Colors.black.withValues(alpha: 0.3);
        hoverColor = Colors.black.withValues(alpha: 0.5);
        break;
      case BackButtonStyle.plain:
        hoverColor = (isDarkTheme ? Colors.white : Colors.black).withValues(alpha: 0.2);
        baseColor = Colors.transparent;
        break;
      case BackButtonStyle.video:
        baseColor = Colors.transparent;
        hoverColor = Colors.black.withValues(alpha: 0.3);
        break;
    }

    final buttonWidget = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onHoverChange(true),
      onExit: (_) => _onHoverChange(false),
      child: GestureDetector(
        onTap: _handlePressed,
        child: AnimatedBuilder(
          animation: _backgroundAnimation,
          builder: (context, child) {
            final currentColor = Color.lerp(baseColor, hoverColor, _backgroundAnimation.value);

            return Container(
              margin: const EdgeInsets.all(8),
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: currentColor, shape: BoxShape.circle),
              child: AppIcon(Symbols.arrow_back_rounded, fill: 1, color: effectiveColor, size: 20),
            );
          },
        ),
      ),
    );

    final button = widget.semanticLabel != null
        ? Semantics(label: widget.semanticLabel, button: true, excludeSemantics: true, child: buttonWidget)
        : buttonWidget;

    return widget.style == BackButtonStyle.circular ? SafeArea(child: button) : button;
  }
}

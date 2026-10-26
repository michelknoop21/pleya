/// The frame of a settings page with a Studio header (A-24, redrawn in A-24b)
/// and the scroll tracking that hands the title over from the header to the
/// compact bar.
///
/// The Studio series (`ios/01`-`14`) has no bar above the header: the header
/// starts under the status bar and carries the back chevron on the line of
/// its large title. So the page scrolls from the top of the screen, and the
/// compact bar is laid over it only once the large title has gone under the
/// status bar: the page colour, the back chevron and the title, as on iOS.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/mono_tokens.dart';
import '../app_bar_back_button.dart' show showsVisibleBackAffordance;
import '../app_icon.dart';

/// Scroll offset past which the large title sits under the status bar and the
/// compact bar takes over.
const double kSettingsStudioCollapseOffset = 56;

/// Height of the compact bar under the status bar, the iOS navigation bar.
const double kSettingsStudioBarHeight = 44;

/// The top colour of the Studio header's warm wash: brand red, faint, over the
/// page.
Color settingsStudioWashTop(MonoTokens tokens) =>
    Color.alphaBlend(tokens.accent.withValues(alpha: tokens.isLight ? 0.08 : 0.16), tokens.bg);

/// Whether a Studio page draws a back chevron: a route to go back to, a page
/// that asks for one, and a pointer surface (never on TV).
bool settingsStudioCanGoBack(BuildContext context, {bool automaticallyImplyLeading = true}) =>
    automaticallyImplyLeading && showsVisibleBackAffordance() && (ModalRoute.of(context)?.canPop ?? false);

/// A Studio settings page: [child], a scroll view that starts at the top of
/// the screen with the header as its first sliver, and the compact bar over
/// it once [collapsed]. [actions] stay reachable at the top right throughout.
class SettingsStudioFrame extends StatelessWidget {
  const SettingsStudioFrame({
    super.key,
    required this.collapsed,
    required this.title,
    required this.child,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  final ValueListenable<bool> collapsed;
  final Widget title;
  final Widget child;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    // No AppBar sets the status bar's ink any more, so the page does: dark
    // glyphs on the light page, light ones on the dark and OLED pages.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tk.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Stack(
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // A pointer surface, like the header's chevron; the keyboard goes
            // back with Escape through the page's own key handler.
            child: ExcludeFocus(
              child: SettingsStudioCompactBar(
                collapsed: collapsed,
                title: title,
                actions: actions,
                automaticallyImplyLeading: automaticallyImplyLeading,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bar laid over a scrolled Studio page: absent while the header is in
/// view (it neither paints nor takes a tap then, so the header's own chevron
/// stays reachable), the page colour (translucent glass, solid where glass is off) with the
/// back chevron and the title once [collapsed]. Absent rather than transparent, so the page has one title for
/// screen readers and for finders at rest, not two.
class SettingsStudioCompactBar extends StatelessWidget {
  const SettingsStudioCompactBar({
    super.key,
    required this.collapsed,
    required this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  final ValueListenable<bool> collapsed;
  final Widget title;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final top = MediaQuery.paddingOf(context).top;
    final canGoBack = settingsStudioCanGoBack(context, automaticallyImplyLeading: automaticallyImplyLeading);
    final actions = this.actions;
    return SizedBox(
      height: top + kSettingsStudioBarHeight,
      child: ValueListenableBuilder<bool>(
        valueListenable: collapsed,
        builder: (context, isCollapsed, _) => Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: reduceMotion(context, tk.fast),
              child: !isCollapsed
                  ? const SizedBox.shrink(key: ValueKey(false))
                  : GlassSurface(
                      key: const ValueKey(true),
                      shape: const RoundedRectangleBorder(),
                      // The page colour at 80%: the page shows through, the
                      // title stays readable.
                      tokens: GlassTokens(
                        blur: 16,
                        saturation: 1.4,
                        dim: 1,
                        tint: tk.bg.withValues(alpha: 0.8),
                        realTint: tk.bg.withValues(alpha: 0.8),
                        edge: 0,
                      ),
                      // Glass off (or reduced transparency): the solid bar.
                      legacy: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tk.bg,
                          border: Border(bottom: BorderSide(color: tk.outline.withValues(alpha: 0.5), width: 0.5)),
                        ),
                        child: _barRow(context, tk, top, canGoBack),
                      ),
                      child: _barRow(context, tk, top, canGoBack),
                    ),
            ),
            if (actions != null && actions.isNotEmpty)
              Positioned(
                top: top,
                right: 4,
                height: kSettingsStudioBarHeight,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
          ],
        ),
      ),
    );
  }

  Widget _barRow(BuildContext context, MonoTokens tk, double top, bool canGoBack) => Padding(
    padding: EdgeInsets.only(top: top),
    child: Row(
      children: [
        SizedBox(width: 52, child: canGoBack ? const SettingsStudioBackButton() : null),
        Expanded(
          child: Center(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: tk.text, fontSize: 17, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: title,
            ),
          ),
        ),
        // Keeps the title centred against the chevron.
        const SizedBox(width: 52),
      ],
    ),
  );
}

/// The Studio back chevron: a 44 pt target around a plain chevron, as in the
/// series, where it sits on the line of the large title.
class SettingsStudioBackButton extends StatelessWidget {
  const SettingsStudioBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      onTap: back,
      excludeSemantics: true,
      child: InkResponse(
        onTap: back,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AppIcon(Symbols.chevron_left_rounded, fill: 0, weight: 500, size: 30, color: tokens(context).text),
          ),
        ),
      ),
    );
  }
}

/// Flips [collapsed] from the offset of the page's own scroll view. Returns
/// false so the notification keeps bubbling to the scroll crown and others.
bool settingsStudioTrackScroll(ValueNotifier<bool> collapsed, ScrollNotification notification) {
  if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
    collapsed.value = notification.metrics.pixels > kSettingsStudioCollapseOffset;
  }
  return false;
}

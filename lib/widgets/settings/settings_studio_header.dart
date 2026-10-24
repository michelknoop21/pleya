/// The large Studio header of the settings pages off TV (A-24, Michel's
/// choice of 24 October 2026 for "Apple TV+ Studio").
///
/// A large title with a small-caps `PLEYA · <SECTION>` line under it, and on
/// the right a backdrop from the viewer's own library that fades into the page.
/// The header scrolls away with the content; the pinned compact bar above it
/// keeps its back button and actions, and only shows its own title once this
/// one has gone under it ([SettingsStudioCompactTitle]).
///
/// The artwork is whatever [DiscoverProvider] already holds: no request is
/// made for it, and without a provider or without an item that has a backdrop
/// the panel falls back to the warm brand gradient with the Pleya mark.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../providers/discover_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/media_image_helper.dart';
import '../optimized_media_image.dart';
import '../pleya_logo.dart';
import 'settings_studio_style.dart';

/// Size of the large title, the iOS large-title size.
const double kSettingsStudioTitleSize = 34;

/// Smallest the large title shrinks to while it stays beside the artwork.
/// A word that needs smaller still takes the full width instead, down to
/// [kSettingsStudioMinTitleSize] ("Bibliotheekzichtbaarheid" on 320 pt).
const double kSettingsStudioBesideArtMinTitleSize = 26;

/// Smallest the large title ever gets.
const double kSettingsStudioMinTitleSize = 20;

/// Lowest the header gets, so the artwork panel keeps a real height when the
/// title is short.
const double kSettingsStudioMinHeight = 136;

/// Share of the header width the artwork panel takes, capped at
/// [kSettingsStudioMaxArtWidth] so an iPad or a desktop window does not get a
/// poster half a screen wide.
const double kSettingsStudioArtFraction = 0.44;
const double kSettingsStudioMaxArtWidth = 360;

/// Scroll offset past which the large title sits under the pinned bar and the
/// bar's compact title takes over.
const double kSettingsStudioCollapseOffset = 56;

/// The backdrop the header shows: the first item [DiscoverProvider] already
/// loaded (Verder kijken first, then the newest films) that has wide art.
typedef SettingsStudioArt = ({String? serverId, String path});

SettingsStudioArt? settingsStudioArtOf(DiscoverProvider? discover) {
  if (discover == null) return null;
  for (final item in [...discover.onDeck, ...discover.latestMovies]) {
    final path = item.artPath ?? item.grandparentArtPath;
    if (path != null && path.isNotEmpty) return (serverId: item.serverId, path: path);
  }
  return null;
}

class SettingsStudioHeader extends StatelessWidget {
  const SettingsStudioHeader({super.key, required this.title, this.section});

  /// The page title, drawn large.
  final String title;

  /// What follows `PLEYA ·` on the eyebrow line. Defaults to the settings
  /// title, so a sub-page reads "PLEYA · INSTELLINGEN".
  final String? section;

  @override
  Widget build(BuildContext context) {
    final art = context.select<DiscoverProvider?, SettingsStudioArt?>(settingsStudioArtOf);
    final tk = tokens(context);
    final eyebrow = 'Pleya · ${section ?? t.settings.title}'.toUpperCase();
    return AutomationNode(
      id: AutomationIds.settingsHeader,
      role: 'region',
      state: () => {'artwork': art != null},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final artWidth = math.min(width * kSettingsStudioArtFraction, kSettingsStudioMaxArtWidth);
          // The title may run into the first third of the panel, where the
          // fade still covers the artwork almost completely.
          final (:size, :textWidth) = _titleFit(
            context,
            besideArt: width - _kInsetStart - artWidth * 0.65,
            full: width - _kInsetStart - 16,
          );
          final titleStyle = TextStyle(
            color: tk.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.1,
            fontSize: size,
          );
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kSettingsStudioMinHeight),
            child: Stack(
              children: [
                Positioned.fill(child: _WarmWash(tokens: tk)),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: artWidth,
                  child: ExcludeSemantics(
                    child: _ArtPanel(art: art, tokens: tk),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(_kInsetStart, 8, 16, 20),
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: math.max(0, textWidth)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(title, style: titleStyle, maxLines: 3, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              eyebrow,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: settingsSectionInk(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The large title's size and column. A word cannot wrap, so the widest one
  /// decides: at 34 pt beside the artwork when it fits, shrunk to no less than
  /// 26 pt beside it, and otherwise across the full width down to 20 pt.
  ({double size, double textWidth}) _titleFit(BuildContext context, {required double besideArt, required double full}) {
    final style = const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.6, fontSize: kSettingsStudioTitleSize);
    var widest = 0.0;
    for (final word in title.split(RegExp(r'\s+'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    // One point of slack: a word measured at exactly the column width wraps.
    double fit(double column) => kSettingsStudioTitleSize * (column - 1) / widest;
    if (widest <= 0 || widest < besideArt) return (size: kSettingsStudioTitleSize, textWidth: besideArt);
    final beside = fit(besideArt);
    if (beside >= kSettingsStudioBesideArtMinTitleSize) return (size: beside, textWidth: besideArt);
    return (
      size: math.max(kSettingsStudioMinTitleSize, math.min(kSettingsStudioTitleSize, fit(full))),
      textWidth: full,
    );
  }
}

const double _kInsetStart = 20;

/// A faint warm tint over the top of the header, the Studio anchors' wash
/// behind the title. Brand red at low strength, fading out downwards.
class _WarmWash extends StatelessWidget {
  const _WarmWash({required this.tokens});

  final MonoTokens tokens;

  @override
  Widget build(BuildContext context) {
    final strength = tokens.isLight ? 0.08 : 0.16;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.accent.withValues(alpha: strength),
            tokens.accent.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// The right-hand panel: the backdrop, or the brand fallback, faded into the
/// page on its leading and bottom edges so nothing ends in a hard poster edge.
class _ArtPanel extends StatelessWidget {
  const _ArtPanel({required this.art, required this.tokens});

  final SettingsStudioArt? art;
  final MonoTokens tokens;

  @override
  Widget build(BuildContext context) {
    final art = this.art;
    final fallback = _BrandFallback(tokens: tokens);
    final Widget picture;
    if (art == null) {
      picture = fallback;
    } else {
      final serverId = serverIdOrNull(art.serverId);
      final client = serverId == null ? null : context.read<MultiServerProvider?>()?.getClientForServer(serverId);
      picture = Stack(
        fit: StackFit.expand,
        children: [
          OptimizedMediaImage(
            client: client,
            imagePath: art.path,
            imageType: ImageType.art,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          ),
          const PositionedDirectional(top: 10, end: 12, child: PleyaLogo(size: 22)),
        ],
      );
    }
    final bg = tokens.bg;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          picture,
          // Leading edge: page colour to clear over the first 75% of the panel.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [bg, bg.withValues(alpha: 0.85), bg.withValues(alpha: 0)],
                stops: const [0, 0.35, 0.75],
              ),
            ),
          ),
          // Bottom edge, so the panel ends in the page and not on a line.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0), bg],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// No backdrop: the brand gradient, faint, with the Pleya mark.
class _BrandFallback extends StatelessWidget {
  const _BrandFallback({required this.tokens});

  final MonoTokens tokens;

  @override
  Widget build(BuildContext context) {
    final strength = tokens.isLight ? 0.18 : 0.32;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.accent.withValues(alpha: strength),
            tokens.accentAlt.withValues(alpha: strength * 0.6),
          ],
        ),
      ),
      child: const Align(alignment: Alignment(0.35, -0.1), child: PleyaLogo(size: 52)),
    );
  }
}

/// The pinned bar's title on a page with a [SettingsStudioHeader]: absent
/// while the large title is in view, faded in once it has scrolled under the
/// bar. Absent rather than transparent, so the page has one title for screen
/// readers and for finders at rest, not two.
class SettingsStudioCompactTitle extends StatelessWidget {
  const SettingsStudioCompactTitle({super.key, required this.collapsed, required this.child});

  final ValueListenable<bool> collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: collapsed,
      builder: (context, isCollapsed, _) => AnimatedSwitcher(
        duration: reduceMotion(context, tokens(context).fast),
        child: isCollapsed
            ? KeyedSubtree(key: const ValueKey(true), child: child)
            : const SizedBox.shrink(key: ValueKey(false)),
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

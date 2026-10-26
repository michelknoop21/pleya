/// The large Studio header of the settings pages on an iPhone (A-24, Michel's
/// choice of 24 October 2026 for "Apple TV+ Studio"; see
/// [settingsStudioHeaderApplies]), redrawn after the series in A-24b.
///
/// The header scrolls away with the content; the compact bar laid over the
/// page takes the title and the back chevron once this one has gone under
/// the status bar ([SettingsStudioFrame]).
///
/// The artwork is whatever [DiscoverProvider] already holds: no data request
/// is made for it, only the backdrop image itself is loaded at the panel's
/// size, from the image cache when that size is already there. Without a
/// provider or without an item that has a backdrop the panel falls back to the
/// warm brand gradient with the Pleya mark.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_server_client.dart';
import '../../providers/discover_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/media_image_helper.dart';
import '../optimized_media_image.dart';
import '../pleya_logo.dart';
import 'settings_studio_bar.dart';
import 'settings_studio_style.dart';

export 'settings_studio_bar.dart';

/// Size of the large title. The series draws it at about 27 pt on a 380 pt
/// frame ("Downloads", "Weergave"), smaller than the iOS large title.
const double kSettingsStudioTitleSize = 28;

/// Smallest the large title shrinks to so that it stays on one line; below
/// it the title wraps between its words instead.
const double kSettingsStudioOneLineMinTitleSize = 23;

/// Smallest the large title shrinks to when its longest word does not fit the
/// line ("Bibliotheekzichtbaarheid" on 320 pt).
const double kSettingsStudioMinTitleSize = 18;

/// Room kept between the end of the title, eyebrow or tagline and the start
/// of the artwork panel: no text runs over the picture.
const double kSettingsStudioArtGap = 8;

/// Lowest the header block under the status bar gets: a subpage
/// (`ios/02`-`14`: chevron and title, eyebrow) and the main page, which adds
/// the tagline (anchor `01`).
const double kSettingsStudioMinHeight = 128;
const double kSettingsStudioMainMinHeight = 150;

/// Share of the header width the artwork panel takes (the series: about a
/// third), capped at [kSettingsStudioMaxArtWidth] so an iPad or a desktop
/// window does not get a panel half a screen wide.
const double kSettingsStudioArtFraction = 0.34;
const double kSettingsStudioMaxArtWidth = 320;

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

/// The Studio header (A-24b, series `ios/01`-`14` and anchors `01`/`03`):
/// under the status bar, the back chevron on the line of the large title, the
/// `PLEYA · <SECTION>` eyebrow, on the main page the tagline, and on the right
/// a sharp panel of the viewer's own artwork with the Pleya mark.
class SettingsStudioHeader extends StatelessWidget {
  const SettingsStudioHeader({
    super.key,
    required this.title,
    this.section,
    this.tagline,
    this.automaticallyImplyLeading = true,
  });

  /// The page title, drawn large.
  final String title;

  /// What follows `PLEYA ·` on the eyebrow line. Defaults to the settings
  /// title, so a sub-page reads "PLEYA · INSTELLINGEN".
  final String? section;

  /// The line under the eyebrow on the main page ("Maak Pleya helemaal van
  /// jou."). Null on a subpage.
  final String? tagline;

  /// Whether the header may draw the back chevron when there is a route to
  /// go back to.
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    final art = context.select<DiscoverProvider?, SettingsStudioArt?>(settingsStudioArtOf);
    final tk = tokens(context);
    final eyebrow = 'Pleya · ${section ?? t.settings.title}'.toUpperCase();
    final top = MediaQuery.paddingOf(context).top;
    final back = settingsStudioCanGoBack(context, automaticallyImplyLeading: automaticallyImplyLeading);
    final tagline = this.tagline;
    return AutomationNode(
      id: AutomationIds.settingsHeader,
      role: 'region',
      state: () => {'artwork': art != null},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final artWidth = math.min(width * kSettingsStudioArtFraction, kSettingsStudioMaxArtWidth);
          // The title starts after the chevron's 44 pt target, or at the
          // inset, and ends before the artwork panel.
          final titleStart = back ? _kBackStart + 44 + 2 : _kInsetStart;
          final textEnd = artWidth + kSettingsStudioArtGap;
          final size = _titleSize(context, width - titleStart - textEnd);
          final titleStyle = TextStyle(
            color: tk.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.1,
            fontSize: size,
          );
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: top + (tagline == null ? kSettingsStudioMinHeight : kSettingsStudioMainMinHeight),
            ),
            child: Stack(
              children: [
                // Wash and artwork run up to the top edge, under the status
                // bar and the Dynamic Island; only the text below keeps to the
                // safe area (edge-to-edge, DEC-163).
                Positioned.fill(child: _WarmWash(tokens: tk)),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: artWidth,
                  child: ExcludeSemantics(
                    child: _ArtPanel(art: art, tokens: tk, statusInset: top),
                  ),
                ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(0, top + 14, textEnd, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (back)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: _kBackStart, end: 2),
                              // Only the page on top answers to `settings.back`: a page
                              // under it keeps its chevron (scrolled out of view,
                              // perhaps) but not the id, so a scenario taps the one
                              // a viewer would.
                              child: ModalRoute.isCurrentOf(context) ?? true
                                  ? const AutomationNode(
                                      id: AutomationIds.settingsBack,
                                      role: 'button',
                                      child: SettingsStudioBackButton(),
                                    )
                                  : const SettingsStudioBackButton(),
                            )
                          else
                            const SizedBox(width: _kInsetStart),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Semantics(
                                  header: true,
                                  child: Text(title, style: titleStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: _kInsetStart, top: 4),
                        child: Text(
                          eyebrow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: settingsSectionInk(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      if (tagline != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: _kInsetStart, top: 16),
                          child: Text(
                            tagline,
                            style: TextStyle(color: tk.text.withValues(alpha: 0.86), fontSize: 13, height: 1.3),
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
    );
  }

  /// The large title's size. A word cannot wrap, so the widest one decides:
  /// 34 pt when it fits [column], otherwise as large as fits, down to 22 pt.
  /// Several words wrap onto a second line at full size instead.
  double _titleSize(BuildContext context, double column) {
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
    if (widest <= 0) return kSettingsStudioTitleSize;
    // One line where the whole title fits beside the artwork, shrunk to no
    // less than 23 pt; otherwise it wraps between its words, at full size
    // while its longest word fits.
    final whole = _width(context, title, style);
    if (whole < column - 1) return kSettingsStudioTitleSize;
    final oneLine = kSettingsStudioTitleSize * (column - 1) / whole;
    if (oneLine >= kSettingsStudioOneLineMinTitleSize) return oneLine;
    if (widest < column - 1) return kSettingsStudioTitleSize;
    return math.max(kSettingsStudioMinTitleSize, kSettingsStudioTitleSize * (column - 1) / widest);
  }

  static double _width(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// Where the back chevron's target starts: its glyph then lands on the 20 pt
/// inset the eyebrow keeps.
const double _kBackStart = 4;
const double _kInsetStart = 20;

/// How far the artwork's top fade reaches below the status bar.
const double _kStatusFadeExtra = 12;

/// A faint warm tint over the top of the header, the Studio anchors' wash
/// behind the title. Brand red at low strength, fading out downwards.
class _WarmWash extends StatelessWidget {
  const _WarmWash({required this.tokens});

  final MonoTokens tokens;

  @override
  Widget build(BuildContext context) {
    // Starts at the top edge, under the status bar, so the wash runs on from
    // the screen's edge instead of starting on a line below it.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [settingsStudioWashTop(tokens), tokens.bg],
        ),
      ),
    );
  }
}

/// The right-hand panel: the backdrop, or the brand fallback, faded out on its
/// leading, top and bottom edges so nothing ends in a hard poster edge.
class _ArtPanel extends StatelessWidget {
  const _ArtPanel({required this.art, required this.tokens, this.statusInset = 0});

  final SettingsStudioArt? art;
  final MonoTokens tokens;

  /// The status bar's height, now that the panel runs under it: the mark
  /// stays below it and a fade over the top keeps the glyphs readable over the
  /// picture. 0 when there is no status bar.
  final double statusInset;

  @override
  Widget build(BuildContext context) {
    final art = this.art;
    final fallback = _BrandFallback(tokens: tokens);
    final Widget picture;
    if (art == null) {
      picture = fallback;
    } else {
      final serverId = serverIdOrNull(art.serverId);
      // Watched, so the panel fills in once the server's client is there.
      final hasServers = context.read<MultiServerProvider?>() != null;
      final client = serverId == null
          ? null
          : context.select<MultiServerProvider?, MediaServerClient?>((p) => p?.getClientForServer(serverId));
      // No client yet: no URL can be built for the backdrop, and the image
      // widget would draw its own broken-image tile. The brand panel stands
      // in until the client is registered.
      if (hasServers && client == null) return ClipRect(child: fallback);
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
          PositionedDirectional(top: statusInset + 10, end: 12, child: const PleyaLogo(size: 22)),
        ],
      );
    }
    // The leading edge fades into the header, so the picture sits behind the
    // page rather than beside it on a hard line; the text never reaches it.
    final direction = Directionality.of(context);
    final washTop = settingsStudioWashTop(tokens);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: AlignmentDirectional.centerStart.resolve(direction),
              end: AlignmentDirectional.centerEnd.resolve(direction),
              colors: const [Color(0x00000000), Color(0xFF000000)],
              stops: const [0, 0.22],
            ).createShader(rect),
            child: picture,
          ),
          if (statusInset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusInset + _kStatusFadeExtra,
              child: DecoratedBox(
                key: const ValueKey('settings-studio-status-fade'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [washTop.withValues(alpha: 0.85), washTop.withValues(alpha: 0)],
                  ),
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

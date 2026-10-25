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
import '../../providers/discover_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/media_image_helper.dart';
import '../optimized_media_image.dart';
import '../pleya_logo.dart';
import 'settings_studio_bar.dart';
import 'settings_studio_style.dart';

export 'settings_studio_bar.dart';

/// Size of the large title, the iOS large-title size.
const double kSettingsStudioTitleSize = 34;

/// Smallest the large title shrinks to when its longest word does not fit the
/// line ("Bibliotheekzichtbaarheid" on 320 pt).
const double kSettingsStudioMinTitleSize = 22;

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
          // inset. Like the series it may run over the artwork panel.
          final titleStart = back ? _kBackStart + 44 + 2 : _kInsetStart;
          final size = _titleSize(context, width - titleStart - 16);
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
                Positioned.fill(
                  top: top,
                  child: _WarmWash(tokens: tk),
                ),
                Positioned(
                  top: top,
                  bottom: 0,
                  right: 0,
                  width: artWidth,
                  child: ExcludeSemantics(
                    child: _ArtPanel(art: art, tokens: tk),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(0, top + 14, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (back)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(start: _kBackStart, end: 2),
                              child: AutomationNode(
                                id: AutomationIds.settingsBack,
                                role: 'button',
                                child: SettingsStudioBackButton(),
                              ),
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
                                  child: Text(title, style: titleStyle, maxLines: 3, overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: EdgeInsetsDirectional.only(start: _kInsetStart, top: 4, end: artWidth * 0.2),
                        child: Text(
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
                      ),
                      if (tagline != null)
                        Padding(
                          // Beside the artwork, as the anchor sets it: one line where it fits.
                          padding: EdgeInsetsDirectional.only(start: _kInsetStart, top: 18, end: artWidth * 0.6),
                          child: Text(
                            tagline,
                            style: TextStyle(color: tk.text.withValues(alpha: 0.86), fontSize: 14, height: 1.3),
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
    if (widest <= 0 || widest < column - 1) return kSettingsStudioTitleSize;
    return math.max(kSettingsStudioMinTitleSize, kSettingsStudioTitleSize * (column - 1) / widest);
  }
}

/// Where the back chevron's target starts: its glyph then lands on the 20 pt
/// inset the eyebrow keeps.
const double _kBackStart = 4;
const double _kInsetStart = 20;

/// A faint warm tint over the top of the header, the Studio anchors' wash
/// behind the title. Brand red at low strength, fading out downwards.
class _WarmWash extends StatelessWidget {
  const _WarmWash({required this.tokens});

  final MonoTokens tokens;

  @override
  Widget build(BuildContext context) {
    // Starts at exactly the colour the pinned bar carries above it, so the
    // wash runs on from the status bar instead of starting on a line.
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
    // Sharp, as in the series: the panel is a photograph beside the title,
    // not a fade behind it.
    return ClipRect(child: picture);
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

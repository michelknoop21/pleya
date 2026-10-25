/// The live preview beside the TV settings rows (A-24, generalised in A-24b):
/// an eyebrow, up to three posters from the library, a title, the mode line
/// and an optional action, as anchor `02` draws it ("LIVE VOORBEELD", "Jouw
/// bibliotheek", "Donkere modus · Posterweergave", "Bekijk voorbeeld").
///
/// It asks for nothing. The posters are items Home has already loaded into
/// [DiscoverProvider]; before that, or without a provider at all, the card
/// shows its text on its own, which is the empty production path.
library;

import 'package:flutter/material.dart' hide ThemeMode;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../navigation/main_screen_scope.dart';
import '../../providers/discover_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/settings_service.dart' show ThemeMode, ViewMode;
import '../../theme/mono_tokens.dart';
import '../../utils/tv_hig.dart';
import '../optimized_media_image.dart';
import 'tv_expandable_media_tile.dart' show discoveryPosterPath;
import 'tv_panel_primitives.dart';
import 'tv_settings_categories.dart' show TvStudioEyebrow;
import 'tv_settings_studio_style.dart';
import 'tv_unified_layout.dart';

/// Up to [count] items with a poster, first seen first, one per poster.
List<MediaItem> pickSettingsPreviewPosters(Iterable<MediaItem> candidates, {int count = 3}) {
  final seen = <String>{};
  final picked = <MediaItem>[];
  for (final item in candidates) {
    final path = discoveryPosterPath(item);
    if (path == null || path.isEmpty || !seen.add(path)) continue;
    picked.add(item);
    if (picked.length == count) break;
  }
  return picked;
}

/// The preview's mode line: the theme as a mode and the library view, as the
/// anchors word it ("Donkere modus · Posterweergave"). Meant for the TV card
/// and the iPhone Weergave card alike, so the two say the same thing.
String settingsPreviewModeLine(ThemeMode theme, ViewMode view) {
  final s = t.settingsStudio;
  final mode = switch (theme) {
    ThemeMode.system => s.systemMode,
    ThemeMode.light => s.lightMode,
    ThemeMode.dark => s.darkMode,
    ThemeMode.oled => s.oledMode,
  };
  final layout = switch (view) {
    ViewMode.grid => s.posterView,
    ViewMode.list => s.listView,
  };
  return '$mode · $layout';
}

/// A button on the preview card.
typedef SettingsPreviewAction = ({String label, VoidCallback onSelect});

/// "Bekijk voorbeeld": opens the existing Bibliotheken destination (Michel's
/// decision for A-24b; there is no separate preview screen). Null where no
/// shell offers it, so the card then shows no button rather than a dead one.
SettingsPreviewAction? settingsViewPreviewAction(BuildContext context) {
  final open = MainScreenFocusScope.of(context, listen: false)?.openLibraries;
  if (open == null) return null;
  return (label: t.settingsStudio.viewPreview, onSelect: open);
}

/// Reads what Home already holds and hands it to [TvSettingsPreviewCard].
class TvSettingsLibraryPreview extends StatelessWidget {
  const TvSettingsLibraryPreview({super.key, required this.modeLine, this.action});

  /// The current look, from [settingsPreviewModeLine].
  final String modeLine;
  final SettingsPreviewAction? action;

  static Iterable<MediaItem> _candidates(DiscoverProvider discover) sync* {
    yield* discover.onDeck;
    for (final hub in discover.hubs) {
      yield* hub.items;
    }
    yield* discover.latestMovies;
  }

  @override
  Widget build(BuildContext context) {
    // Nullable on purpose: a page mounted without Home (a test, a profile
    // that never opened it) simply has no posters to show.
    final discover = context.watch<DiscoverProvider?>();
    final items = discover == null ? const <MediaItem>[] : pickSettingsPreviewPosters(_candidates(discover));
    return TvSettingsPreviewCard(
      eyebrow: t.settingsStudio.livePreview,
      title: t.settingsStudio.yourLibrary,
      modeLine: modeLine,
      items: items,
      action: action,
      clientFor: (serverId) => context.read<MultiServerProvider?>()?.serverManager.getClient(ServerId(serverId)),
    );
  }
}

class TvSettingsPreviewCard extends StatelessWidget {
  const TvSettingsPreviewCard({
    super.key,
    required this.eyebrow,
    required this.modeLine,
    required this.items,
    this.title,
    this.action,
    this.clientFor,
  });

  /// The accent label at the top ("LIVE VOORBEELD").
  final String eyebrow;

  /// The large line under the posters ("Jouw bibliotheek"). Optional.
  final String? title;

  /// What the preview shows, in words ("Donkere modus · Posterweergave").
  final String modeLine;
  final List<MediaItem> items;

  /// A button under the text. Optional: a card without one has no stop for
  /// the remote at all.
  final SettingsPreviewAction? action;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final radius = tk.radiusMd;
    final title = this.title;
    final action = this.action;

    return Container(
      padding: EdgeInsets.all(32 * pt),
      decoration: BoxDecoration(
        color: tvStudioPreviewFill(tk),
        borderRadius: BorderRadius.circular(radius * 1.5),
        border: Border.all(color: tvStudioSeparator(tk)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TvStudioEyebrow(eyebrow),
          if (items.isNotEmpty) ...[
            SizedBox(height: 12 * pt),
            Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(width: 14 * pt),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: ColoredBox(
                          color: tk.text.withValues(alpha: 0.06),
                          child: OptimizedMediaImage.poster(
                            client: items[i].serverId == null ? null : clientFor?.call(items[i].serverId!),
                            imagePath: discoveryPosterPath(items[i]),
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            fallbackIcon: items[i].kind == MediaKind.show
                                ? Symbols.live_tv_rounded
                                : Symbols.movie_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // Fewer than three keeps the poster size of three.
                for (var i = items.length; i < 3; i++) ...[SizedBox(width: 14 * pt), const Spacer()],
              ],
            ),
          ],
          SizedBox(height: 24 * pt),
          if (title != null) ...[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tk.text,
                fontSize: TvHig.headline * pt,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 6 * pt),
          ],
          Text(
            modeLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
              fontSize: TvHig.caption1 * pt,
              height: TvHig.caption1Leading / TvHig.caption1,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (action != null) ...[
            SizedBox(height: 24 * pt),
            TvPanelButton(scale: pt, label: action.label, onPressed: action.onSelect, primary: true),
          ],
        ],
      ),
    );
  }
}

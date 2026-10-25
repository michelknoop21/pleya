/// The live preview at the top of Weergave on a phone (A-24b, anchors `01`
/// and `03`): a poster from the viewer's own library beside the accent label
/// "Live voorbeeld", the title "Jouw bibliotheek" and the current look in
/// words ("Donkere modus · Posterweergave").
///
/// It asks for nothing: the poster is one Home already loaded into
/// [DiscoverProvider], the same pick the TV preview makes. Without one (before
/// Home has loaded, or with no provider at all) the card shows its text beside
/// an empty frame, which is the production path for an empty library.
library;

import 'package:flutter/material.dart' hide ThemeMode;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../providers/discover_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/settings_service.dart' show SettingsService;
import '../../theme/mono_tokens.dart';
import '../optimized_media_image.dart';
import '../settings_builder.dart';
import '../settings_section.dart';
import '../tv/tv_expandable_media_tile.dart' show discoveryPosterPath;
import '../tv/tv_settings_library_preview.dart' show pickSettingsPreviewPosters, settingsPreviewModeLine;

/// Width of the poster on the card; 2:3 like every poster in the app.
const double kSettingsPreviewPosterWidth = 72;

/// The card, placed by [SettingsPage] above the first group rather than as a
/// row inside it.
class SettingsLivePreviewCard extends StatelessWidget implements SettingsStandaloneBlock {
  const SettingsLivePreviewCard({super.key});

  static Iterable<MediaItem> _candidates(DiscoverProvider discover) sync* {
    yield* discover.onDeck;
    for (final hub in discover.hubs) {
      yield* hub.items;
    }
    yield* discover.latestMovies;
  }

  @override
  Widget build(BuildContext context) {
    final discover = context.watch<DiscoverProvider?>();
    final posters = discover == null
        ? const <MediaItem>[]
        : pickSettingsPreviewPosters(_candidates(discover), count: 1);
    final theme = context.watch<ThemeProvider>().themeMode;
    final tk = tokens(context);
    return SettingsBuilder(
      prefs: const [SettingsService.viewMode],
      builder: (context) {
        final modeLine = settingsPreviewModeLine(theme, SettingsService.instance.read(SettingsService.viewMode));
        return Semantics(
          container: true,
          label: '${t.settingsStudio.livePreview}, ${t.settingsStudio.yourLibrary}, $modeLine',
          excludeSemantics: true,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: settingsCardColor(context),
              borderRadius: BorderRadius.circular(kSettingsCardRadius),
              border: Border.all(color: settingsOutlineColor(context)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: kSettingsPreviewPosterWidth,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(tk.radiusSm),
                      child: ColoredBox(
                        color: tk.text.withValues(alpha: 0.06),
                        child: posters.isEmpty ? null : _poster(context, posters.first),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.settingsStudio.livePreview,
                        style: TextStyle(color: settingsAccentInk(context), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.settingsStudio.yourLibrary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tk.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        modeLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tk.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _poster(BuildContext context, MediaItem item) {
    final serverId = item.serverId;
    return OptimizedMediaImage.poster(
      client: serverId == null
          ? null
          : context.read<MultiServerProvider?>()?.serverManager.getClient(ServerId(serverId)),
      imagePath: discoveryPosterPath(item),
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fallbackIcon: item.kind == MediaKind.show ? Symbols.live_tv_rounded : Symbols.movie_rounded,
    );
  }
}

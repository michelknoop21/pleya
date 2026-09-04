/// The grouped search result list — iOS Unified 2026 fase 4, mockup
/// `05-zoeken.png`.
///
/// A list row family, not a variant of [MobileMediaCard]. The card is a
/// poster with a caption under it and lives in a rail or a grid; this is a
/// 44×66 thumbnail with two lines beside it inside a grouped card, and the two
/// shapes share no line. What they do share is the source rule and the
/// tokens.
///
/// Every number in [MobileSearchMetrics] was measured off the frozen PNG
/// rather than chosen, and the colours resolve through `tokens()` so the
/// light theme is not a set of hard-coded darks.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../services/unified_catalog/search_text.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/provider_extensions.dart';
import '../app_icon.dart';
import '../optimized_media_image.dart';
import '../pressable.dart';
import '../seerr_poster_card.dart' show SeerrPosterImage;

/// Mockup 05's geometry, in logical points on a 393×852 viewport.
///
/// Read off `docs/assets/ios-unified/northstar/05-zoeken.png` (1179×2556 at
/// 3×): the grouped card runs 16 to 377, a row is 86 tall, the thumbnail is
/// 44×66 sitting 16 in from the card's left edge, and the hairline between
/// rows is a full-width 1 pt.
class MobileSearchMetrics {
  const MobileSearchMetrics._();

  static const double pageInset = 16;
  static const double rowHeight = 86;
  static const double posterWidth = 44;
  static const double posterHeight = 66;
  static const double posterGap = 14;
  static const double groupRadius = 14;
  static const double dividerThickness = 1;

  /// A section that follows the chip row sits closer to it than one that
  /// follows a grouped card: 15 against 27, both measured.
  static const double firstSectionHeaderTop = 15;
  static const double sectionHeaderTop = 27;
  static const double sectionHeaderBottom = 7;

  static const double sectionHeaderFontSize = 12;
  static const double titleFontSize = 17;
  static const double metaFontSize = 14;
  static const double trailingFontSize = 15;
  static const double requestChipHeight = 30;
}

/// One result section: an upper-cased heading and the rows beneath it in a
/// single grouped card.
///
/// [instance] is the section key the automation id carries — a name rather
/// than an index, because which sections exist depends on the query and an
/// index would address a different section on a different search.
class MobileSearchSection extends StatelessWidget {
  final String instance;
  final String title;
  final List<Widget> rows;
  final bool isFirst;

  const MobileSearchSection({
    super.key,
    required this.instance,
    required this.title,
    required this.rows,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(height: MobileSearchMetrics.dividerThickness, thickness: 1, color: tk.surfaceElevated));
      }
      children.add(rows[i]);
    }

    return AutomationNode(
      id: AutomationIds.searchSection,
      instance: instance,
      role: 'region',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              MobileSearchMetrics.pageInset,
              isFirst ? MobileSearchMetrics.firstSectionHeaderTop : MobileSearchMetrics.sectionHeaderTop,
              MobileSearchMetrics.pageInset,
              MobileSearchMetrics.sectionHeaderBottom,
            ),
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: MobileSearchMetrics.sectionHeaderFontSize,
                fontWeight: FontWeight.w700,
                color: tk.textMuted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MobileSearchMetrics.pageInset),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tk.surface,
                borderRadius: BorderRadius.circular(MobileSearchMetrics.groupRadius),
              ),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shell every row in a section shares: thumbnail, two lines, trailing.
///
/// Private, and the three public rows below are thin over it. They differ in
/// what they know (a group, a bare item, a title that is not on any server),
/// never in how a row is laid out.
class _SearchRow extends StatelessWidget {
  final String instance;
  final Widget leading;
  final String title;
  final String meta;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SearchRow({
    required this.instance,
    required this.leading,
    required this.title,
    required this.meta,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return AutomationNode(
      id: AutomationIds.searchResult,
      instance: instance,
      role: 'list.item',
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          height: MobileSearchMetrics.rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MobileSearchMetrics.pageInset),
            child: Row(
              children: [
                leading,
                const SizedBox(width: MobileSearchMetrics.posterGap),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: MobileSearchMetrics.titleFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: MobileSearchMetrics.metaFontSize, color: tk.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 44×66 thumbnail: a server item's poster, an external poster URL, or a
/// neutral placeholder carrying the year — which is what mockup 05 draws for a
/// title that is on none of your servers and has no artwork to ask for.
class _RowThumbnail extends StatelessWidget {
  final MediaItem? item;
  final String? posterUrl;
  final String? placeholder;

  const _RowThumbnail({this.item, this.posterUrl, this.placeholder});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final media = item;
    final url = posterUrl;
    final Widget child;
    if (media == null && url != null && url.isNotEmpty) {
      child = SeerrPosterImage(url: url);
    } else if (media == null) {
      child = ColoredBox(
        color: tk.surfaceElevated,
        child: Center(
          child: Text(placeholder ?? '', style: TextStyle(fontSize: 12, color: tk.textMuted)),
        ),
      );
    } else {
      child = OptimizedMediaImage.poster(
        client: context.tryGetMediaClientWithFallback(serverIdOrNull(media.serverId)),
        imagePath: media.posterThumb(),
        width: MobileSearchMetrics.posterWidth,
        height: MobileSearchMetrics.posterHeight,
        fallbackIcon: switch (media.kind) {
          MediaKind.show || MediaKind.season || MediaKind.episode => Symbols.tv_rounded,
          MediaKind.collection => Symbols.collections_bookmark_rounded,
          MediaKind.playlist => Symbols.playlist_play_rounded,
          _ => Symbols.movie_rounded,
        },
        blurHash: media.posterBlurHash,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(tk.radiusSm),
      child: SizedBox(width: MobileSearchMetrics.posterWidth, height: MobileSearchMetrics.posterHeight, child: child),
    );
  }
}

/// The chevron every navigable row carries.
class _RowChevron extends StatelessWidget {
  const _RowChevron();

  @override
  Widget build(BuildContext context) {
    return AppIcon(Symbols.chevron_right_rounded, size: 20, color: tokens(context).textMuted);
  }
}

/// A unified result: one logical title, its sources kept behind it.
class MobileSearchGroupRow extends StatelessWidget {
  final String instance;
  final UnifiedMediaGroup group;
  final VoidCallback? onTap;

  const MobileSearchGroupRow({super.key, required this.instance, required this.group, this.onTap});

  @override
  Widget build(BuildContext context) {
    final item = group.representativeSource.item;
    final count = searchSourceCountFor(group);
    return _SearchRow(
      instance: instance,
      leading: _RowThumbnail(item: item),
      title: searchTitleFor(item),
      meta: searchMetaLineFor(item),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count != null) ...[
            Text(
              count,
              style: TextStyle(fontSize: MobileSearchMetrics.trailingFontSize, color: tokens(context).textMuted),
            ),
            const SizedBox(width: 8),
          ],
          const _RowChevron(),
        ],
      ),
    );
  }
}

/// A source-concrete result: a collection, a playlist, or anything hoofdstuk
/// 16.1 does not name and the projection kept rather than dropped.
///
/// These never merge, so they carry a server name instead of a source count —
/// and only when there is more than one server to tell apart, the same
/// condition the flat list used before this screen was grouped.
class MobileSearchItemRow extends StatelessWidget {
  final String instance;
  final MediaItem item;
  final String? serverName;
  final VoidCallback? onTap;

  const MobileSearchItemRow({super.key, required this.instance, required this.item, this.serverName, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = serverName;
    return _SearchRow(
      instance: instance,
      leading: _RowThumbnail(item: item),
      title: searchTitleFor(item),
      meta: searchMetaLineFor(item),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (name != null && name.isNotEmpty) ...[
            Text(
              name,
              style: TextStyle(fontSize: MobileSearchMetrics.trailingFontSize, color: tokens(context).textMuted),
            ),
            const SizedBox(width: 8),
          ],
          const _RowChevron(),
        ],
      ),
    );
  }
}

/// A row that is an action rather than a result: the tile that asks the
/// requests server, once.
///
/// Built from the same primitives as the other rows instead of a `ListTile`,
/// which paints its background on the nearest `Material` and asserts when it
/// finds a decorated box in between — which the grouped card is.
class MobileSearchActionRow extends StatelessWidget {
  final String instance;
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const MobileSearchActionRow({
    super.key,
    required this.instance,
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return AutomationNode(
      id: AutomationIds.searchResult,
      instance: instance,
      role: 'list.item',
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MobileSearchMetrics.pageInset),
            child: Row(
              children: [
                AppIcon(icon, fill: 1, size: 22, color: tk.textMuted),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: MobileSearchMetrics.metaFontSize + 1),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A title that is on none of your servers, with the chip that asks for it.
///
/// The chip is the row's action and the row itself opens the title's page, so
/// the two do different things and the chip takes the tap it is under.
class MobileSearchRequestRow extends StatelessWidget {
  final String instance;
  final String title;
  final String meta;
  final String? year;
  final String? posterUrl;
  final String requestLabel;
  final VoidCallback? onRequest;
  final VoidCallback? onTap;

  const MobileSearchRequestRow({
    super.key,
    required this.instance,
    required this.title,
    required this.meta,
    required this.requestLabel,
    this.year,
    this.posterUrl,
    this.onRequest,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return _SearchRow(
      instance: instance,
      leading: _RowThumbnail(posterUrl: posterUrl, placeholder: year),
      title: title,
      meta: meta,
      onTap: onTap,
      trailing: SizedBox(
        height: MobileSearchMetrics.requestChipHeight,
        child: TextButton.icon(
          onPressed: onRequest,
          icon: const AppIcon(Symbols.add_rounded, size: 18),
          label: Text(requestLabel, style: const TextStyle(fontSize: 15)),
          // No local `shape:`. The capsule comes from `MonoShapes.cta` through
          // the theme, which is the same shape the focus ring is drawn to
          // follow; overriding it here would fork the two apart.
          style: TextButton.styleFrom(
            foregroundColor: tk.text,
            backgroundColor: tk.surfaceElevated,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}

/// The full Verder kijken overview on the iPhone (mockup 23, DEC-144 fase 2):
/// four fixed sections of list rows, each row a 16:9 still, the series or film
/// title, the episode's own place and title, and the status line with when
/// it was last watched. This is the one place that line carries the date;
/// the Home card does not.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../providers/continue_watching_hidden_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/offline_mode_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../screens/tv/tv_unified_activation.dart';
import '../../services/unified_catalog/mobile_media_source_picker_route.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/continue_watching_labels.dart';
import '../../utils/continue_watching_sections.dart';
import '../../utils/formatters.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/continue_watching_hidden_items.dart';
import '../../widgets/media_markers.dart';
import '../../widgets/mobile/mobile_unified_context_menu.dart';
import '../../widgets/optimized_media_image.dart';
import '../../widgets/pressable.dart';

class MobileContinueWatchingScreen extends StatelessWidget {
  const MobileContinueWatchingScreen({super.key});

  SourceAvailability Function(UnifiedMediaSource source) _availabilityFor(BuildContext context) {
    final manager = context.read<MultiServerProvider>().serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );
    return (source) => unifiedSourceAvailability(source, health);
  }

  Future<void> _open(BuildContext context, UnifiedMediaGroup group) => openMobileMediaGroup(
    context,
    group: group,
    intent: UnifiedActivationIntent.details,
    availabilityFor: _availabilityFor(context),
    coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
  );

  Future<void> _menu(BuildContext context, UnifiedMediaGroup group) => showMobileUnifiedContextMenu(
    context,
    group: group,
    availabilityFor: _availabilityFor(context),
    isInContinueWatching: true,
    isOffline: context.read<OfflineModeProvider?>()?.isOffline ?? false,
  );

  @override
  Widget build(BuildContext context) {
    final projection = context.watch<TvHomeProjectionProvider>();
    final groups = projection.continueWatchingAll?.groups ?? const <UnifiedMediaGroup>[];
    final sections = continueWatchingSections(groups, itemOf: (g) => g.representativeSource.item);
    final muted = tokens(context).textMuted;
    final hiddenCount = context.watch<ContinueWatchingHiddenProvider?>()?.count ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.discover.continueWatching),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${groups.length}', style: TextStyle(color: muted)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
              child: Center(
                child: Text(t.discover.noContentAvailable, style: TextStyle(color: muted)),
              ),
            ),
          for (final (section, items) in sections) ...[
            _SectionLabel(continueWatchingSectionTitle(section), count: items.length),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens(context).surface,
                  borderRadius: BorderRadius.circular(tokens(context).radiusMd),
                ),
                child: Column(
                  children: [
                    for (final (i, group) in items.indexed)
                      _Row(
                        group: group,
                        dim: section == ContinueWatchingSection.stale,
                        first: i == 0,
                        onTap: () => _open(context, group),
                        onLongPress: () => _menu(context, group),
                      ),
                  ],
                ),
              ),
            ),
          ],
          // Mockup 23: the way back for a title hidden on this device.
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showContinueWatchingHiddenItems(context),
                  icon: AppIcon(Symbols.visibility_off_rounded, size: 20, color: muted),
                  label: Text(continueWatchingHiddenLabel(hiddenCount), style: TextStyle(color: muted)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: tokens(context).textMuted, letterSpacing: 0.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: style)),
          Text('$count', style: style),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.group,
    required this.dim,
    required this.first,
    required this.onTap,
    required this.onLongPress,
  });

  final UnifiedMediaGroup group;
  final bool dim;
  final bool first;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final item = group.representativeSource.item;
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    final tk = tokens(context);
    final resume = resumeFractionFor(group);
    final still = OptimizedMediaImage.thumb(
      client: client,
      imagePath: item.thumbPath ?? item.artPath,
      width: 96,
      height: 54,
      fallbackIcon: item.isEpisode ? Symbols.tv_rounded : Symbols.movie_rounded,
      blurHash: item.posterBlurHash,
    );
    final place = item.isEpisode
        ? [?formatSeasonEpisodeLabel(item.parentIndex, item.index), ?item.displaySubtitle].join(' · ')
        : [if (item.genres?.isNotEmpty ?? false) item.genres!.first, if (item.year != null) '${item.year}'].join(' · ');
    final status = [
      continueWatchingStatusLine(item, includePlace: false),
      ?lastWatchedLabel(item),
      if (group.hasMultipleSources) t.unifiedCatalog.sources(count: group.sources.length),
    ].where((s) => s.isNotEmpty).join(' · ');
    final subtitleStyle = TextStyle(fontSize: 13, color: tk.textMuted, height: 1.2);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Pressable(
        onTap: onTap,
        child: Container(
          decoration: first
              ? null
              : BoxDecoration(
                  border: Border(top: BorderSide(color: tk.outline)),
                ),
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Opacity(
                  opacity: dim ? 0.7 : 1,
                  child: SizedBox(
                    width: 96,
                    height: 54,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        still,
                        if (resume != null)
                          Positioned(left: 0, right: 0, bottom: 0, child: ResumeLine(fraction: resume)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    if (place.isNotEmpty)
                      Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle.copyWith(color: tk.text.withValues(alpha: 0.72)),
                    ),
                  ],
                ),
              ),
              AppIcon(Symbols.more_horiz_rounded, size: 20, color: tk.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "2 days ago" from [MediaItem.lastViewedAt] (epoch seconds), or null when the
/// source gave no date. Days up to a fortnight, then weeks, then months.
String? lastWatchedLabel(MediaItem item, {DateTime? now}) {
  final seconds = item.lastViewedAt;
  if (seconds == null) return null;
  final reference = now ?? DateTime.now();
  final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return t.discover.watchedAgo.today;
  if (days == 1) return t.discover.watchedAgo.yesterday;
  if (days < 14) return t.discover.watchedAgo.days(count: days);
  if (days < 60) return t.discover.watchedAgo.weeks(count: days ~/ 7);
  return t.discover.watchedAgo.months(count: days ~/ 30);
}

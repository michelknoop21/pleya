/// The iPhone Aanvragen page, northstar 19
/// (`docs/assets/ios-unified/northstar/19-aanvragen.png`).
///
/// Presentation only. `SeerrDiscoverScreen` keeps the search, the type and genre
/// state and the discover rows, the same split DEC-108 made for TV with
/// `TvSeerrDiscoverView`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_request.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/pressable.dart';
import '../../widgets/seerr_poster_card.dart';
import 'seerr_discover_filter_bar.dart';

enum MobileSeerrRequestTone { available, inProgress, waiting, problem }

/// The status line and dot colour of one request. A declined or failed request says so
/// even when the title became available another way; otherwise availability comes first.
@visibleForTesting
({String label, MobileSeerrRequestTone tone}) mobileSeerrRequestStatus(SeerrRequest request) {
  final ({String label, MobileSeerrRequestTone tone}) status = switch ((request.status, request.mediaStatus)) {
    (SeerrRequestStatus.declined, _) => (label: t.seerr.declined, tone: MobileSeerrRequestTone.problem),
    (SeerrRequestStatus.failed, _) => (label: t.seerr.failed, tone: MobileSeerrRequestTone.problem),
    (_, SeerrMediaStatus.available) => (label: t.seerr.available, tone: MobileSeerrRequestTone.available),
    (_, SeerrMediaStatus.partiallyAvailable) => (
      label: t.seerr.partiallyAvailable,
      tone: MobileSeerrRequestTone.available,
    ),
    (_, SeerrMediaStatus.processing) => (
      label: '${t.seerr.approved} · ${t.seerr.processing}',
      tone: MobileSeerrRequestTone.inProgress,
    ),
    (SeerrRequestStatus.approved, _) => (label: t.seerr.approved, tone: MobileSeerrRequestTone.inProgress),
    (SeerrRequestStatus.completed, _) => (label: t.seerr.completed, tone: MobileSeerrRequestTone.available),
    (SeerrRequestStatus.pending, _) => (label: t.seerr.pending, tone: MobileSeerrRequestTone.waiting),
  };
  if (!request.is4k) return status;
  return (label: '${status.label} · ${t.seerr.fourKBadge}', tone: status.tone);
}

Color _toneColor(BuildContext context, MobileSeerrRequestTone tone) => switch (tone) {
  MobileSeerrRequestTone.available => kSuccess,
  MobileSeerrRequestTone.inProgress => kAccentAlt,
  MobileSeerrRequestTone.waiting => tokens(context).textMuted,
  MobileSeerrRequestTone.problem => Theme.of(context).colorScheme.error,
};

/// Alles, Films and Series as pills, plus the genre pill once a type is picked.
class MobileSeerrTypeChips extends StatelessWidget {
  const MobileSeerrTypeChips({
    super.key,
    required this.type,
    required this.genres,
    required this.genreId,
    required this.onTypeSelected,
    required this.onPickGenre,
  });

  final SeerrDiscoverType type;
  final List<SeerrDiscoverGenre> genres;
  final int? genreId;
  final ValueChanged<SeerrDiscoverType> onTypeSelected;
  final VoidCallback onPickGenre;

  @override
  Widget build(BuildContext context) {
    final labels = {
      SeerrDiscoverType.all: t.seerr.filterAll,
      SeerrDiscoverType.movies: t.seerr.filterMovies,
      SeerrDiscoverType.tv: t.seerr.filterShows,
    };
    // Same rule as `SeerrDiscoverFilterBar`: "Alles" has no single genre list to offer.
    final showGenre = type != SeerrDiscoverType.all && genres.isNotEmpty;
    final genreName = genres.where((genre) => genre.id == genreId).firstOrNull?.name;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          for (final entry in labels.entries) ...[
            FocusableFilterChip(
              label: entry.value,
              selected: type == entry.key,
              onPressed: () => onTypeSelected(entry.key),
            ),
            const SizedBox(width: 8),
          ],
          if (showGenre)
            FocusableFilterChip(
              label: genreName ?? t.libraries.filterCategories.genre,
              icon: Symbols.expand_more_rounded,
              selected: genreId != null,
              onPressed: onPickGenre,
            ),
        ],
      ),
    );
  }
}

/// "Mijn aanvragen": the viewer's latest requests above the discover rows. The header
/// opens the full list.
class MobileSeerrMyRequestsSection extends StatefulWidget {
  const MobileSeerrMyRequestsSection({
    super.key,
    required this.load,
    required this.onOpenAll,
    required this.onOpenRequest,
  });

  static const int visibleCount = 3;

  final Future<({List<SeerrRequest> items, int totalPages})> Function() load;
  final VoidCallback onOpenAll;
  final ValueChanged<SeerrRequest> onOpenRequest;

  @override
  State<MobileSeerrMyRequestsSection> createState() => _MobileSeerrMyRequestsSectionState();
}

class _MobileSeerrMyRequestsSectionState extends State<MobileSeerrMyRequestsSection> {
  List<SeerrRequest> _items = const [];
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await widget.load();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _totalPages = result.totalPages;
      });
    } catch (e, st) {
      // A preview above discover: a failure hides the section, not the page.
      appLogger.w('Seerr: own requests failed to load', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final tk = tokens(context);
    final title = t.seerr.myRequests.toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            onTap: widget.onOpenAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _totalPages == 1 ? '$title · ${_items.length}' : title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: tk.textMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  AppIcon(Symbols.chevron_right_rounded, size: 20, color: tk.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(tk.radiusMd),
            child: ColoredBox(
              color: tk.surface,
              child: Column(
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) Divider(height: 1, thickness: 1, color: tk.outline.withValues(alpha: 0.4)),
                    _RequestRow(
                      index: i,
                      request: _items[i],
                      onTap: _items[i].tmdbId == null ? null : () => widget.onOpenRequest(_items[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.index, required this.request, required this.onTap});

  final int index;
  final SeerrRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final status = mobileSeerrRequestStatus(request);
    final title = request.mediaTitle;
    final seasons = request.seasons;
    final displayTitle = title == null || seasons.length != 1
        ? title
        : '$title · ${t.seerr.season(number: seasons.first).toLowerCase()}';
    return AutomationNode(
      id: AutomationIds.requestsMineItem,
      instance: '$index',
      role: 'button',
      label: displayTitle,
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(tk.radiusSm),
                child: SizedBox(
                  width: 52,
                  height: 78,
                  child: SeerrPosterImage(url: SeerrConstants.tmdbPosterUrl(request.posterPath)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (displayTitle != null)
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: tk.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: _toneColor(context, status.tone), shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Alles bekijken ›" beside a row title, where desktop keeps its outlined chip.
class MobileSeerrSeeAllLink extends StatelessWidget {
  const MobileSeerrSeeAllLink({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Pressable(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.watchlist.seeAll, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tk.textMuted)),
            AppIcon(Symbols.chevron_right_rounded, size: 18, color: tk.textMuted),
          ],
        ),
      ),
    );
  }
}

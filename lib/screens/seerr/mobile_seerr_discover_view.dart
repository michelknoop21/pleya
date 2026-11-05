/// The iPhone Aanvragen page, northstar 19
/// (`docs/assets/ios-unified/northstar/19-aanvragen.png`).
///
/// Presentation only. `SeerrDiscoverScreen` keeps the search, catalog filters
/// and pagination state, the same split DEC-108 made for TV with
/// `TvSeerrDiscoverView`.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_discovery_filters.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_header.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/overlay_sheet_geometry.dart';
import '../../widgets/pressable.dart';
import 'seerr_discover_filter_bar.dart';

export '../../models/seerr/seerr_discovery_filters.dart' show MobileSeerrCatalogSort;

enum MobileSeerrAvailability { all, requestable, processing, available }

String mobileSeerrSortWire(MobileSeerrCatalogSort sort, SeerrDiscoverType type) => switch (sort) {
  MobileSeerrCatalogSort.popularity => 'popularity.desc',
  MobileSeerrCatalogSort.newest => type == SeerrDiscoverType.tv ? 'first_air_date.desc' : 'primary_release_date.desc',
  MobileSeerrCatalogSort.oldest => type == SeerrDiscoverType.tv ? 'first_air_date.asc' : 'primary_release_date.asc',
  MobileSeerrCatalogSort.rating => 'vote_average.desc',
  MobileSeerrCatalogSort.title => type == SeerrDiscoverType.tv ? 'original_name.asc' : 'original_title.asc',
};

bool mobileSeerrMatchesAvailability(SeerrMediaStatus status, MobileSeerrAvailability filter) => switch (filter) {
  MobileSeerrAvailability.all => true,
  MobileSeerrAvailability.requestable => status == SeerrMediaStatus.unknown,
  MobileSeerrAvailability.processing => status == SeerrMediaStatus.pending || status == SeerrMediaStatus.processing,
  MobileSeerrAvailability.available =>
    status == SeerrMediaStatus.partiallyAvailable || status == SeerrMediaStatus.available,
};

String mobileSeerrSortLabel(MobileSeerrCatalogSort sort, SeerrDiscoverType type) => switch (sort) {
  MobileSeerrCatalogSort.popularity => type == SeerrDiscoverType.tv ? t.seerr.popularTv : t.seerr.popularMovies,
  MobileSeerrCatalogSort.newest => t.unifiedCatalog.sort.newestRelease,
  MobileSeerrCatalogSort.oldest => t.unifiedCatalog.sort.oldestRelease,
  MobileSeerrCatalogSort.rating => t.libraries.sortLabels.rating,
  MobileSeerrCatalogSort.title => t.unifiedCatalog.sort.titleAsc,
};

String mobileSeerrAvailabilityLabel(MobileSeerrAvailability availability) => switch (availability) {
  MobileSeerrAvailability.all => t.libraries.all,
  MobileSeerrAvailability.requestable => t.seerr.request,
  MobileSeerrAvailability.processing => t.seerr.processing,
  MobileSeerrAvailability.available => t.seerr.available,
};

/// The compact catalog controls used on the phone, matching Alle films.
class MobileSeerrCatalogControls extends StatelessWidget {
  const MobileSeerrCatalogControls({
    super.key,
    required this.type,
    required this.activeFilterCount,
    required this.sortLabel,
    required this.onTypePressed,
    required this.onFiltersPressed,
    required this.onSortPressed,
    this.automationInstance,
    this.discoveryEnabled = true,
  });

  final SeerrDiscoverType type;
  final int activeFilterCount;
  final String sortLabel;
  final VoidCallback onTypePressed;
  final VoidCallback onFiltersPressed;
  final VoidCallback onSortPressed;
  final String? automationInstance;
  final bool discoveryEnabled;

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (type) {
      SeerrDiscoverType.all => t.seerr.filterAll,
      SeerrDiscoverType.tv => t.seerr.filterShows,
      SeerrDiscoverType.movies => t.seerr.filterMovies,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          AutomationNode(
            id: AutomationIds.catalogChipSources,
            instance: automationInstance,
            role: 'button',
            child: FocusableFilterChip(
              variant: FilterChipVariant.filled,
              icon: Symbols.dns_rounded,
              label: typeLabel,
              onPressed: onTypePressed,
            ),
          ),
          const SizedBox(width: 8),
          AutomationNode(
            id: AutomationIds.catalogChipFilters,
            instance: automationInstance,
            role: 'button',
            child: FocusableFilterChip(
              variant: FilterChipVariant.filled,
              icon: Symbols.filter_list_rounded,
              label: t.unifiedCatalog.filters.title,
              badgeCount: activeFilterCount,
              onPressed: onFiltersPressed,
            ),
          ),
          const SizedBox(width: 8),
          if (discoveryEnabled)
            AutomationNode(
              id: AutomationIds.catalogChipSort,
              instance: automationInstance,
              role: 'button',
              child: FocusableFilterChip(
                variant: FilterChipVariant.filled,
                icon: Symbols.swap_vert_rounded,
                label: sortLabel,
                onPressed: onSortPressed,
              ),
            ),
        ],
      ),
    );
  }
}

Future<T?> showMobileSeerrChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<({T value, String label})> choices,
  required T selected,
  String? automationPrefix,
}) async {
  final initialFocus = FocusNode(debugLabel: 'SeerrChoice');
  try {
    return await OverlaySheetController.showAdaptive<T>(
      context,
      presentation: OverlaySheetPresentation.panel,
      isScrollControlled: true,
      initialFocusNode: initialFocus,
      restoreLauncherFocus: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(title: title),
          Flexible(
            child: ListView(
              primary: false,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final choice in choices)
                  AutomationNode(
                    id: automationPrefix == null ? null : AutomationIds.seerrDiscoverFilter,
                    instance: automationPrefix == null ? null : '$automationPrefix.${choice.value}',
                    role: 'button',
                    state: () => {'selected': choice.value == selected},
                    focusNode: choice.value == selected ? initialFocus : null,
                    child: FocusableListTile(
                      focusNode: choice.value == selected ? initialFocus : null,
                      leading: AppIcon(
                        choice.value == selected
                            ? Symbols.radio_button_checked_rounded
                            : Symbols.radio_button_unchecked_rounded,
                        fill: 1,
                      ),
                      title: Text(choice.label),
                      onTap: () => OverlaySheetController.closeAdaptive(sheetContext, choice.value),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  } finally {
    initialFocus.dispose();
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

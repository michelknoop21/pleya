/// Zoeken on a phone — iOS Unified 2026 fase 4, mockup `05-zoeken.png`.
///
/// Presentation only. `SearchScreen` keeps the query, the debounce, the
/// staleness generation and the platform input paths, because those are the
/// same on a phone as on a television and splitting them would give one
/// screen two brains. What lands here is the half mockup 05 changed: a
/// compact header instead of an app bar, four fixed type chips, and results
/// grouped per section instead of one flat list.
///
/// The grouping is [UnifiedSearchProjection]'s, so a title that lives on three
/// servers is one row with "3 sources" behind it rather than three rows a
/// viewer has to recognise as the same film (hoofdstuk 16.2).
///
/// Sections without a chip — Collections, Playlists, and whatever hoofdstuk
/// 16.1 does not name — show under Alles only. A chip narrows to its kind;
/// something the chips cannot express is not silently dropped, it simply
/// belongs to the unnarrowed view.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../models/seerr/seerr_media.dart';
import '../../services/unified_catalog/search_projection.dart';
import '../../focus/focusable_text_field.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/mobile/mobile_catalog_header.dart';
import '../../widgets/mobile/mobile_search_results.dart';
import '../../widgets/pill_input_decoration.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/state_view.dart';
import 'search_failure.dart';

/// Everything the body needs to know about the last search, in one value
/// rather than five loose flags threaded through a constructor.
class MobileSearchStatus {
  /// A query is in flight, or its projection is still resolving. Both draw
  /// skeletons: to a viewer they are one wait.
  final bool isBusy;

  /// A query has been run at least once since the field was last emptied.
  final bool hasSearched;

  final SearchFailure? failure;

  /// Null until the first projection lands.
  final UnifiedSearchProjection? projection;

  const MobileSearchStatus({
    required this.isBusy,
    required this.hasSearched,
    required this.failure,
    required this.projection,
  });
}

/// The Jellyseerr/Overseerr half, which stays an explicit one-shot the viewer
/// asks for. Pleya never sends a query to a third party per keystroke.
class MobileSearchRequests {
  final bool isConfigured;
  final bool isSearching;
  final bool hasSearched;
  final List<SeerrMedia> results;

  const MobileSearchRequests({
    required this.isConfigured,
    required this.isSearching,
    required this.hasSearched,
    required this.results,
  });
}

class MobileSearchBody extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final MobileSearchStatus status;
  final MobileSearchRequests requests;

  /// Null for "Alles"; otherwise the single kind the active chip narrows to.
  final MediaKind? kindFilter;
  final ValueChanged<MediaKind?> onFilterChanged;

  final VoidCallback onBack;
  final VoidCallback onClear;
  final VoidCallback onRetry;
  final ValueChanged<String> onSubmit;

  final List<String> history;
  final ValueChanged<String> onRunHistoryQuery;
  final VoidCallback onClearHistory;

  final void Function(UnifiedMediaGroup group) onGroupTap;
  final void Function(MediaItem item) onItemTap;

  /// More than one server is registered, so a source-concrete row says which
  /// one it came from.
  final String Function(MediaItem item)? serverNameFor;

  final VoidCallback onSearchRequests;
  final void Function(SeerrMedia media) onOpenRequest;
  final void Function(SeerrMedia media) onRequest;

  const MobileSearchBody({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.status,
    required this.requests,
    required this.kindFilter,
    required this.onFilterChanged,
    required this.onBack,
    required this.onClear,
    required this.onRetry,
    required this.onSubmit,
    required this.history,
    required this.onRunHistoryQuery,
    required this.onClearHistory,
    required this.onGroupTap,
    required this.onItemTap,
    required this.onSearchRequests,
    required this.onOpenRequest,
    required this.onRequest,
    this.serverNameFor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        primary: false,
        slivers: [
          SliverToBoxAdapter(
            child: MobileCatalogHeader(
              title: t.common.search,
              onBack: onBack,
              // No search glyph on the search page. `MobileCatalogHeader`
              // takes a nullable action for exactly this: the shape is the
              // same compact header the northstar draws on 03, 05 and 19, and
              // only 03 has something to put on its right.
              onSearch: null,
              automationId: AutomationIds.searchHeader,
            ),
          ),
          SliverToBoxAdapter(
            child: _Field(controller: controller, focusNode: focusNode, onClear: onClear, onSubmit: onSubmit),
          ),
          SliverToBoxAdapter(
            child: _Chips(kindFilter: kindFilter, onFilterChanged: onFilterChanged),
          ),
          ..._body(context),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    if (status.isBusy) {
      return [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.builder(itemCount: 6, itemBuilder: (context, index) => const SkeletonListTile()),
        ),
      ];
    }

    final failure = status.failure;
    if (failure != null) {
      return [
        SliverFillRemaining(
          child: switch (failure) {
            SearchFailure.noServers => StateView.error(
              title: t.search.noServersTitle,
              message: t.search.noServersBody,
              icon: Symbols.dns_rounded,
            ),
            SearchFailure.network => StateView.error(
              title: t.search.errorTitle,
              message: t.search.errorNetwork,
              icon: Symbols.wifi_off_rounded,
              onRetry: onRetry,
            ),
          },
        ),
      ];
    }

    if (!status.hasSearched) {
      if (history.isEmpty) {
        return [
          SliverFillRemaining(
            child: StateView.empty(
              title: t.search.searchYourMedia,
              message: t.search.enterTitleActorOrKeyword,
              icon: Symbols.search_rounded,
            ),
          ),
        ];
      }
      return [
        SliverToBoxAdapter(
          child: _RecentSearches(history: history, onRun: onRunHistoryQuery, onClear: onClearHistory),
        ),
      ];
    }

    final sections = _sections(context);
    final requestSection = _requestSection(context, isFirst: sections.isEmpty);

    if (sections.isEmpty && requestSection == null) {
      return [
        SliverFillRemaining(
          child: StateView.empty(
            title: t.messages.noResultsFound,
            message: t.search.tryDifferentTerm,
            icon: Symbols.search_off_rounded,
          ),
        ),
      ];
    }

    return [
      SliverList(delegate: SliverChildListDelegate([...sections, ?requestSection])),
    ];
  }

  /// Mockup 05's sections, in hoofdstuk 16.1's order.
  List<Widget> _sections(BuildContext context) {
    final projection = status.projection;
    if (projection == null) return const [];

    final sections = <Widget>[];

    void addGroups(String key, String title, List<UnifiedMediaGroup> groups) {
      if (groups.isEmpty) return;
      sections.add(
        MobileSearchSection(
          instance: key,
          title: title,
          isFirst: sections.isEmpty,
          rows: [
            for (var i = 0; i < groups.length; i++)
              MobileSearchGroupRow(instance: '$key/$i', group: groups[i], onTap: () => onGroupTap(groups[i])),
          ],
        ),
      );
    }

    void addItems(String key, String title, List<MediaItem> items) {
      if (items.isEmpty) return;
      sections.add(
        MobileSearchSection(
          instance: key,
          title: title,
          isFirst: sections.isEmpty,
          rows: [
            for (var i = 0; i < items.length; i++)
              MobileSearchItemRow(
                instance: '$key/$i',
                item: items[i],
                serverName: serverNameFor?.call(items[i]),
                onTap: () => onItemTap(items[i]),
              ),
          ],
        ),
      );
    }

    if (kindFilter == null || kindFilter == MediaKind.movie) {
      addGroups('movies', t.search.filters.movies, projection.movies);
    }
    if (kindFilter == null || kindFilter == MediaKind.show) {
      addGroups('shows', t.search.filters.shows, projection.shows);
    }
    if (kindFilter == null || kindFilter == MediaKind.episode) {
      addGroups('episodes', t.search.filters.episodes, projection.episodes);
    }
    if (kindFilter == null) {
      addItems('collections', t.collections.title, projection.collections);
      addItems('playlists', t.playlists.title, projection.playlists);
      addItems('other', t.search.filters.other, projection.other);
    }
    return sections;
  }

  /// "Niet op je servers", and the tile that fills it.
  ///
  /// Returns null when there is no requests server, which is the honest
  /// answer: without one there is nothing to ask and nothing to draw.
  Widget? _requestSection(BuildContext context, {required bool isFirst}) {
    if (!requests.isConfigured) return null;

    final rows = <Widget>[
      for (var i = 0; i < requests.results.length; i++)
        MobileSearchRequestRow(
          instance: 'requests/$i',
          title: requests.results[i].title,
          meta: requests.results[i].year ?? '',
          year: requests.results[i].year,
          posterUrl: requests.results[i].posterPath == null ? null : requests.results[i].posterUrl,
          requestLabel: t.seerr.request,
          onRequest: () => onRequest(requests.results[i]),
          onTap: () => onOpenRequest(requests.results[i]),
        ),
    ];

    if (rows.isEmpty) {
      rows.add(
        _RequestTrigger(
          isSearching: requests.isSearching,
          hasSearched: requests.hasSearched,
          onSearch: onSearchRequests,
        ),
      );
    }

    return MobileSearchSection(instance: 'requests', title: t.search.notOnYourServers, isFirst: isFirst, rows: rows);
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmit;

  const _Field({required this.controller, required this.focusNode, required this.onClear, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return AutomationNode(
      id: AutomationIds.searchField,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => SizedBox(
            height: 42,
            // FocusableTextField, not a bare TextField: it is the wrapper the
            // whole app inputs through, and `test/no_bare_text_field_test.dart`
            // holds that line.
            child: FocusableTextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmit,
              decoration: pillInputDecoration(
                context,
                hintText: t.search.hint,
                prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(icon: const AppIcon(Symbols.close_rounded, fill: 1), onPressed: onClear),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The four chips, all four of them, always.
///
/// Mockup 05 draws Afleveringen next to a result set that has no episodes in
/// it, so the row is a fixed set of narrowings rather than a summary of what
/// came back. The shared list on TV and desktop keeps its own rule, where a
/// chip with nothing behind it is hidden.
class _Chips extends StatelessWidget {
  final MediaKind? kindFilter;
  final ValueChanged<MediaKind?> onFilterChanged;

  const _Chips({required this.kindFilter, required this.onFilterChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, MediaKind? kind) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FocusableFilterChip(label: label, selected: kindFilter == kind, onPressed: () => onFilterChanged(kind)),
    );

    return AutomationNode(
      id: AutomationIds.searchChips,
      role: 'filter',
      // Scrolls rather than overflows: four labels in a language with long
      // words do not fit 393 points, and a clipped chip is worse than one you
      // reach by swiping.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(
          children: [
            chip(t.search.filters.all, null),
            chip(t.search.filters.movies, MediaKind.movie),
            chip(t.search.filters.shows, MediaKind.show),
            chip(t.search.filters.episodes, MediaKind.episode),
          ],
        ),
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  final List<String> history;
  final ValueChanged<String> onRun;
  final VoidCallback onClear;

  const _RecentSearches({required this.history, required this.onRun, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.search.recentSearches,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: onClear, child: Text(t.search.clearHistory)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in history)
                FocusableFilterChip(icon: Symbols.history_rounded, label: query, onPressed: () => onRun(query)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The row that asks the requests server, once, when the viewer says so.
class _RequestTrigger extends StatelessWidget {
  final bool isSearching;
  final bool hasSearched;
  final VoidCallback onSearch;

  const _RequestTrigger({required this.isSearching, required this.hasSearched, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final done = hasSearched && !isSearching;
    return MobileSearchActionRow(
      instance: 'requests/trigger',
      icon: Symbols.travel_explore_rounded,
      label: done ? t.seerr.noResults : t.seerr.searchOnSeerr,
      trailing: isSearching
          ? const LoadingIndicatorBox(size: 18)
          : (done ? null : const AppIcon(Symbols.chevron_right_rounded, fill: 1)),
      onTap: isSearching || done ? null : onSearch,
    );
  }
}

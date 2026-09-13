/// The iPhone "Bibliotheken" picker, northstar 15
/// (`docs/assets/ios-unified/northstar/15-bibliotheken.png`).
///
/// The shared [LibrariesScreen] auto-selects the first visible library on the
/// phone and drops the user straight into its content — there is no picker
/// page, only the long-press [LibraryQuickPickerSheet] as a secondary switch.
/// That is a different screen than northstar 15 asks for: a dedicated landing
/// with server-filter chips, one card per library and a "recently added" rail
/// for the first catalogable one. Rather than growing the shared,
/// already-2000-line [LibrariesScreen] with a phone-only picker mode, this
/// follows the same split DEC-092 already made for TV's own
/// `TvLibrariesScreen`: a platform-specific screen next to the shared one,
/// which keeps serving desktop and TV unchanged.
///
/// Tapping a card hands off to the existing [LibrariesScreen] machinery
/// (persist the selection, then let it own its own tabs), rather than
/// duplicating library-content rendering here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/library_query.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../media/unified/unified_watch_state.dart';
import '../../media/media_item.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../screens/tv/tv_unified_activation.dart';
import '../../services/unified_catalog/mobile_media_source_picker_route.dart';
import '../../services/storage_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/content_utils.dart';
import '../../utils/library_grouping.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/mobile/mobile_media_rail.dart';
import '../../widgets/settings_section.dart' show settingsOutlineColor;
import '../settings/library_visibility_screen.dart';
import 'libraries_screen.dart';
import 'state_messages.dart';

/// Whether [library] can feed the "recently added" rail — the same
/// catalogable gate `TvLibrariesScreen.tvLibraryActionsFor` applies to
/// "Openen in catalogus", because only movie/show libraries answer a
/// recently-added-sorted content query the same way.
bool _isCatalogable(MediaLibrary library) => library.kind == MediaKind.movie || library.kind == MediaKind.show;

class MobileLibrariesScreen extends StatefulWidget {
  const MobileLibrariesScreen({super.key, required this.onBack});

  /// Returns to My Pleya. The phone's bottom bar has no slot of its own for
  /// this tab (DEC-104) — it always lights My Pleya instead — so an explicit
  /// back affordance is the only way out, the same reasoning `_closeSearch`
  /// documents for Zoeken.
  final VoidCallback onBack;

  @override
  State<MobileLibrariesScreen> createState() => _MobileLibrariesScreenState();
}

class _MobileLibrariesScreenState extends State<MobileLibrariesScreen> {
  /// `globalKey -> totalCount`, populated lazily. Same technique and the same
  /// "failed once, not retried" contract as `TvLibrariesScreen._loadCountFor`:
  /// no client method returns a library's size without paging it.
  final Map<String, int> _counts = {};

  /// Null selects "Alle". Otherwise a `MediaLibrary.serverId`.
  String? _selectedServerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    if (!mounted) return;
    for (final library in context.read<LibrariesProvider>().libraries) {
      if (_counts.containsKey(library.globalKey)) continue;
      unawaited(_loadCountFor(library));
    }
  }

  Future<void> _loadCountFor(MediaLibrary library) async {
    try {
      final client = context.getMediaClientForLibrary(library);
      final page = await client.fetchLibraryPagedContent(
        library.id,
        query: const LibraryQuery(offset: 0, limit: 1),
        libraryKind: library.kind,
      );
      if (!mounted) return;
      setState(() => _counts[library.globalKey] = page.totalCount);
    } catch (e) {
      appLogger.d('MobileLibrariesScreen: count fetch failed for ${library.globalKey}: $e');
    }
  }

  Future<void> _openLibrary(MediaLibrary library) async {
    final storage = await StorageService.getInstance();
    await storage.saveSelectedLibraryKey(library.globalKey);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LibrariesScreen()));
  }

  void _manageLibraries() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryVisibilityScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<HiddenLibrariesProvider>();
    final allLibraries = context.watch<LibrariesProvider>().libraries;
    final visible = allLibraries.where((library) => !hidden.isLibraryHidden(library.globalKey)).toList();
    final grouped = groupLibrariesByFirstAppearance(visible);
    final filtered = _selectedServerId == null ? visible : (grouped.byServer[_selectedServerId] ?? const []);
    final recentLibrary = filtered.where(_isCatalogable).firstOrNull;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // `CustomAppBar.onBackPressed` only shows a leading button when the
          // surrounding route itself can pop (`DesktopTopBar`'s own
          // `canPop` gate) — but this screen is a tab body inside
          // `MainScreen`'s single root route, which never pops. `SearchScreen`
          // hits the exact same problem for the same reason (I4) and solves it
          // by drawing its own unconditional `leading` on `DesktopSliverAppBar`
          // instead; this follows that precedent rather than inventing a
          // second one.
          DesktopSliverAppBar(
            title: Text(t.libraries.title),
            leading: BackButton(onPressed: widget.onBack),
            actions: [TextButton(onPressed: _manageLibraries, child: Text(t.common.edit))],
          ),
          if (grouped.serverOrder.length > 1)
            SliverToBoxAdapter(
              child: _ServerFilterChips(
                groups: grouped,
                selectedServerId: _selectedServerId,
                onSelected: (serverId) => setState(() => _selectedServerId = serverId),
              ),
            ),
          if (allLibraries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateWidget(message: t.libraries.noLibrariesFound, icon: Symbols.video_library_rounded),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateWidget(
                message: t.libraries.allLibrariesHidden,
                icon: Symbols.visibility_off_rounded,
                onAction: _manageLibraries,
                actionLabel: t.libraries.manageLibraries,
                actionIcon: Symbols.edit_rounded,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _LibraryPickerCard(
                    library: filtered[index],
                    itemCount: _counts[filtered[index].globalKey],
                    onTap: () => _openLibrary(filtered[index]),
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),
          if (recentLibrary != null)
            SliverToBoxAdapter(
              child: _RecentlyAddedSection(library: recentLibrary, onOpenLibrary: () => _openLibrary(recentLibrary)),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }
}

/// "Alle" plus one chip per server, in the same first-appearance order
/// [LibraryQuickPickerSheet] already uses for its server headers.
class _ServerFilterChips extends StatelessWidget {
  const _ServerFilterChips({required this.groups, required this.selectedServerId, required this.onSelected});

  final LibraryServerGroups groups;
  final String? selectedServerId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(t.libraries.all),
              selected: selectedServerId == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final serverId in groups.serverOrder)
            if (serverId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(groups.byServer[serverId]!.first.serverName ?? serverId),
                  selected: selectedServerId == serverId,
                  onSelected: (_) => onSelected(serverId),
                ),
              ),
        ],
      ),
    );
  }
}

/// One card: icon tile, title, and a source line with an online/offline dot —
/// northstar 15's own shape, distinct from [MobileMediaCard]'s poster cards.
class _LibraryPickerCard extends StatelessWidget {
  const _LibraryPickerCard({required this.library, required this.itemCount, required this.onTap});

  final MediaLibrary library;
  final int? itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final servers = context.watch<MultiServerProvider?>();
    final serverId = serverIdOrNull(library.serverId);
    final isOnline = serverId == null || (servers?.isServerOnline(serverId) ?? true);
    final countText = itemCount == null
        ? null
        : itemCount == 1
        ? t.libraries.oneItem
        : t.libraries.itemCount(count: '$itemCount');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tokens(context).surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: settingsOutlineColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: tokens(context).surface, borderRadius: BorderRadius.circular(10)),
                child: Center(child: AppIcon(ContentTypeHelper.getLibraryIcon(library.kind.id), size: 32)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              library.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: isOnline ? Colors.green : Colors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [?library.serverName, ?countText].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Recent toegevoegd in `<library>`", fetched on demand for one specific
/// library rather than a cross-server aggregation — the unified catalog's
/// grouping pipeline (with its identity-resolution network calls) exists to
/// dedupe the *same* title across several servers, which cannot happen
/// within a single library. Each item becomes its own single-source
/// [UnifiedMediaGroup] directly, the same shape `_buildSingleSourceGroup`
/// produces internally when `groupUnifiedMediaSources` sees an unpoolable
/// candidate — just without paying for a resolver call that has nothing to
/// resolve here.
class _RecentlyAddedSection extends StatefulWidget {
  const _RecentlyAddedSection({required this.library, required this.onOpenLibrary});

  final MediaLibrary library;
  final VoidCallback onOpenLibrary;

  @override
  State<_RecentlyAddedSection> createState() => _RecentlyAddedSectionState();
}

class _RecentlyAddedSectionState extends State<_RecentlyAddedSection> {
  List<UnifiedMediaGroup>? _groups;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final client = context.getMediaClientForLibrary(widget.library);
      final page = await client.fetchLibraryPagedContent(
        widget.library.id,
        query: const LibraryQuery(
          offset: 0,
          limit: 12,
          sort: LibrarySort(field: 'addedAt', direction: LibrarySortDirection.descending),
        ),
        libraryKind: widget.library.kind,
      );
      if (!mounted) return;
      setState(() {
        _groups = [
          for (final item in page.items)
            if (item.serverId != null && item.serverId!.isNotEmpty) _singleSourceGroup(item),
        ];
      });
    } catch (e) {
      appLogger.d('MobileLibrariesScreen: recently-added fetch failed for ${widget.library.globalKey}: $e');
    }
  }

  UnifiedMediaGroup _singleSourceGroup(MediaItem item) {
    final source = UnifiedMediaSource.fromItem(item);
    return UnifiedMediaGroup(
      groupId: source.sourceKey,
      identity: CanonicalMediaIdentity.opaque(),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: selectRepresentativeWatchState({source.sourceKey: item}),
    );
  }

  Future<void> _openDetails(UnifiedMediaGroup group) async {
    final manager = context.read<MultiServerProvider>().serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );
    await openMobileMediaGroup(
      context,
      group: group,
      intent: UnifiedActivationIntent.details,
      availabilityFor: (source) => unifiedSourceAvailability(source, health),
      coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: MobileMediaRail(
        hub: UnifiedMediaHub(
          hubId: 'library-recent:${widget.library.globalKey}',
          title: t.discover.recentlyAddedIn(library: widget.library.title),
          kind: widget.library.kind == MediaKind.movie ? UnifiedHubKind.movie : UnifiedHubKind.show,
          groups: groups,
        ),
        railIndex: 0,
        onCardTap: _openDetails,
        onViewAll: widget.onOpenLibrary,
      ),
    );
  }
}

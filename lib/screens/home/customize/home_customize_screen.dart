/// "Home aanpassen" on iPhone, iPad and Mac (HOME-R1, mockup set 44).
///
/// One screen for everything the viewer can do to their Home rows: drag to
/// move, an eye to hide, own rows to create, edit and delete. It is the screen
/// behind the "Home aanpassen" line under the last row, the long-press menu of a
/// row header and the Instellingen tile, so there is one place and one
/// implementation. There is no save button: every change is stored as it is
/// made (DEC-100 (4)); Klaar only closes.
///
/// The list is `homeLayoutEntries`, the rows Home itself draws (DEC-103,
/// DEC-145). The writes are `HomeLayoutProvider`'s. tvOS has its own panel and
/// is not touched.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../providers/continue_watching_hidden_provider.dart';
import '../../../providers/discover_provider.dart';
import '../../../providers/home_custom_rows_provider.dart';
import '../../../providers/home_extra_rows_provider.dart';
import '../../../providers/home_layout_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../providers/tv_home_projection_provider.dart';
import '../../../services/unified_catalog/home_custom_row.dart';
import '../../../services/unified_catalog/home_layout_entries.dart';
import '../../../services/unified_catalog/home_row_editing.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/overlay_sheet.dart';
import 'home_customize_row_menu.dart';
import 'home_customize_row_tile.dart';
import 'home_customize_sections.dart';
import 'home_row_actions.dart';
import 'home_row_wizard_page.dart';
import 'home_row_wizard_view.dart';

/// Where the screen is drawn: a page (phone, Instellingen) or inside a dialog
/// (iPad and Mac).
enum HomeCustomizePresentation { page, dialog }

/// Two columns once the room is there (mockup 44 L): the list to drag in, the
/// wizard of the own row being edited beside it.
const double kHomeCustomizeWideBreakpoint = 820;

class HomeCustomizeScreen extends StatelessWidget {
  const HomeCustomizeScreen({super.key, this.presentation = HomeCustomizePresentation.page});

  final HomeCustomizePresentation presentation;

  @override
  Widget build(BuildContext context) {
    // The screen carries its own host, like every pushed screen: the filter
    // sheets of the wizard and the row menus need one above them, and the host
    // of `MainScreen` is not an ancestor of a pushed route or a dialog.
    return Scaffold(
      backgroundColor: tokens(context).bg,
      body: SafeArea(
        child: OverlaySheetHost(
          canPop: presentation == HomeCustomizePresentation.dialog || PlatformDetector.isHandheldIOS(context),
          onSystemBack: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) navigator.pop();
          },
          child: _HomeCustomizeBody(presentation: presentation),
        ),
      ),
    );
  }
}

/// What the wide layout's right-hand column is editing: [initial] null is a
/// new row.
class _WizardTarget {
  const _WizardTarget(this.initial);
  final HomeCustomRow? initial;
}

class _HomeCustomizeBody extends StatefulWidget {
  const _HomeCustomizeBody({required this.presentation});

  final HomeCustomizePresentation presentation;

  @override
  State<_HomeCustomizeBody> createState() => _HomeCustomizeBodyState();
}

class _HomeCustomizeBodyState extends State<_HomeCustomizeBody> {
  _WizardTarget? _wizard;

  MediaServerClient? _clientFor(String? serverId) {
    if (serverId == null) return null;
    return context.read<MultiServerProvider?>()?.getClientForServer(ServerId(serverId));
  }

  HomeRowActions _actions() {
    final projection = context.read<TvHomeProjectionProvider?>();
    return HomeRowActions(
      layout: context.read<HomeLayoutProvider>(),
      customRows: context.read<HomeCustomRowsProvider?>(),
      extraRows: context.read<HomeExtraRowsProvider?>(),
      projection: projection,
      unified: projection != null && PlatformDetector.isPhone(context),
      backendHubsOf: () => context.read<DiscoverProvider?>(),
    );
  }

  Future<void> _startWizard(HomeRowActions actions, {HomeCustomRow? initial, required bool wide}) async {
    if (wide) {
      setState(() => _wizard = _WizardTarget(initial));
      return;
    }
    final row = await showHomeRowWizardPage(
      context,
      editing: HomeRowEditing.of(context, clientFor: (id) => _clientFor(id)),
      initial: initial,
    );
    if (row != null) await actions.save(row);
  }

  Future<void> _openMenu(HomeRowActions actions, HomeLayoutEntry entry, {required bool wide}) async {
    final custom = actions.customRowOf(entry);
    final count = context.read<HomeCustomRowsProvider?>()?.contentFor(entry.customRowId ?? '')?.loadedCount;
    final choice = await showHomeCustomRowMenu(
      context,
      entry: entry,
      hidden: actions.isHidden(entry),
      viewAllCount: PlatformDetector.isPhone(context) ? count : null,
      kind: custom?.kind,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case HomeRowMenuAction.edit:
        await _startWizard(actions, initial: custom, wide: wide);
      case HomeRowMenuAction.toggleHidden:
        await actions.setHidden(entry, !actions.isHidden(entry));
      case HomeRowMenuAction.viewAll:
        if (custom != null) await openHomeCustomRowCatalog(context, custom);
      case HomeRowMenuAction.remove:
        if (await confirmRemoveHomeRow(context, entry.title) && mounted) {
          if (_wizard?.initial?.id == entry.customRowId) setState(() => _wizard = null);
          await actions.remove(entry);
        }
    }
  }

  List<HomeCustomizeFixedRow> _fixedRows() {
    final projection = context.watch<TvHomeProjectionProvider?>();
    final unified = projection != null && PlatformDetector.isPhone(context);
    final List<MediaItem> featured;
    final List<MediaItem>? continueWatching;
    if (unified) {
      featured = [for (final group in projection.heroGroups.take(3)) group.representativeSource.item];
      final cw = projection.continueWatching;
      continueWatching = cw == null ? null : [for (final group in cw.groups.take(3)) group.representativeSource.item];
    } else {
      final discover = context.watch<DiscoverProvider?>();
      featured = discover?.latestMovies.take(3).toList() ?? const [];
      final onDeck = discover?.onDeck ?? const <MediaItem>[];
      continueWatching = onDeck.isEmpty ? null : onDeck.take(3).toList();
    }
    return [
      HomeCustomizeFixedRow(
        title: t.unifiedCatalog.homeRows.featured,
        subtitle: t.unifiedCatalog.homeRows.alwaysFirst,
        posters: featured,
      ),
      if (continueWatching != null)
        HomeCustomizeFixedRow(
          title: t.discover.continueWatching,
          subtitle: t.unifiedCatalog.homeRows.alwaysSecond,
          posters: continueWatching,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Watched, so a move, a hide or a finished preview redraws the list.
    final layout = context.watch<HomeLayoutProvider>();
    final customRows = context.watch<HomeCustomRowsProvider?>();
    context.watch<HomeExtraRowsProvider?>();
    context.watch<TvHomeProjectionProvider?>();
    context.watch<DiscoverProvider?>();
    final hiddenCount = context.watch<ContinueWatchingHiddenProvider?>()?.count ?? 0;

    final actions = _actions();
    final entries = actions.entries();
    final home = t.unifiedCatalog.homeRows;

    return AutomationNode(
      id: AutomationIds.homeCustomizeScreen,
      role: 'screen',
      state: () => {
        'rows': [
          for (final entry in entries)
            {'title': entry.title, 'ids': entry.ids, 'hidden': actions.isHidden(entry), 'own': entry.isOwn},
        ],
        'order': layout.order,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kHomeCustomizeWideBreakpoint;
          final list = _list(context, actions, entries, hiddenCount, wide: wide, customRows: customRows);
          final showWizard = wide && _wizard != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, home.customize),
              Expanded(
                child: showWizard
                    ? Row(
                        children: [
                          Expanded(flex: 5, child: list),
                          VerticalDivider(width: 1, color: tokens(context).outline),
                          Expanded(
                            flex: 6,
                            child: HomeRowWizardView(
                              // A different row is a different draft.
                              key: ValueKey(_wizard!.initial?.id ?? 'new'),
                              editing: HomeRowEditing.of(context, clientFor: (id) => _clientFor(id)),
                              initial: _wizard!.initial,
                              stepsAsTabs: true,
                              onCancel: () => setState(() => _wizard = null),
                              onSave: (row) async {
                                await actions.save(row);
                                if (mounted) setState(() => _wizard = null);
                              },
                            ),
                          ),
                        ],
                      )
                    : list,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Symbols.check_rounded),
          label: Text(t.unifiedCatalog.homeRows.done),
        ),
      ],
    ),
  );

  Widget _list(
    BuildContext context,
    HomeRowActions actions,
    List<HomeLayoutEntry> entries,
    int hiddenCount, {
    required bool wide,
    required HomeCustomRowsProvider? customRows,
  }) {
    final home = t.unifiedCatalog.homeRows;
    final mono = tokens(context);
    final onHome = entries.where((entry) => !actions.isHidden(entry)).length;
    // Several rows can share a title ("Recent toegevoegd" per library), which
    // is when the type and the server have to say which is which.
    bool needsTypeContext(HomeLayoutEntry entry) =>
        entry.serverName != null || entries.any((other) => !identical(other, entry) && other.title == entry.title);
    final intro = !wide
        ? home.dragIntro
        : PlatformDetector.isDesktop(context)
        ? home.dragIntroDesktop
        : home.dragIntroTablet;

    // Twin rows share their ids, so the key counts the occurrence too.
    final seen = <String, int>{};
    final keys = [
      for (final entry in entries)
        ValueKey('${entry.ids.join('|')}#${seen.update(entry.ids.join('|'), (n) => n + 1, ifAbsent: () => 0)}'),
    ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(intro, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mono.textMuted)),
                ),
              ),
              SliverToBoxAdapter(child: HomeCustomizeSectionLabel(home.sectionFixed)),
              SliverToBoxAdapter(
                child: HomeCustomizeFixedRows(rows: _fixedRows(), clientFor: _clientFor),
              ),
              SliverToBoxAdapter(
                child: HomeCustomizeSectionLabel(
                  home.sectionYours,
                  trailing: entries.isEmpty ? null : home.onHomeCount(shown: onHome, total: entries.length),
                ),
              ),
              if (entries.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(12), child: Text(t.settings.homeLayoutEmpty)),
                )
              else
                DecoratedSliver(
                  decoration: BoxDecoration(color: mono.surface, borderRadius: BorderRadius.circular(14)),
                  sliver: SliverReorderableList(
                    itemCount: entries.length,
                    onReorderItem: (from, to) => actions.reorder(entries, from, to),
                    proxyDecorator: (child, index, animation) => Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(14),
                      color: mono.surfaceElevated,
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final hidden = actions.isHidden(entry);
                      final custom = actions.customRowOf(entry);
                      Widget tile = HomeCustomizeRowTile(
                        entry: entry,
                        index: index,
                        total: entries.length,
                        hidden: hidden,
                        subtitle: homeEntrySubtitle(
                          entry,
                          hidden: hidden,
                          needsTypeContext: needsTypeContext(entry),
                          custom: custom,
                          customRows: customRows,
                        ),
                        selected: wide && _wizard != null && _wizard!.initial?.id == entry.customRowId && entry.isOwn,
                        showEditButton: wide && PlatformDetector.isDesktop(context),
                        clientFor: _clientFor,
                        onToggleHidden: () => actions.setHidden(entry, !hidden),
                        onOpenMenu: () => _openMenu(actions, entry, wide: wide),
                        onEdit: () => _startWizard(actions, initial: custom, wide: wide),
                        onMoveUp: actions.neighbourIndex(entries, index, -1) < 0
                            ? null
                            : () => actions.moveStep(entries, index, -1),
                        onMoveDown: actions.neighbourIndex(entries, index, 1) < 0
                            ? null
                            : () => actions.moveStep(entries, index, 1),
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Symbols.drag_indicator_rounded,
                              semanticLabel: home.dragHandle,
                              color: mono.textMuted,
                            ),
                          ),
                        ),
                      );
                      // On a touch screen the whole line can be held too, so
                      // the handle does not have to be hit exactly.
                      if (!PlatformDetector.isDesktop(context)) {
                        tile = ReorderableDelayedDragStartListener(index: index, child: tile);
                      }
                      return KeyedSubtree(key: keys[index], child: tile);
                    },
                  ),
                ),
              SliverToBoxAdapter(
                child: HomeCustomizeNewRowTile(onPressed: () => _startWizard(actions, wide: wide)),
              ),
              if (hiddenCount > 0) ...[
                SliverToBoxAdapter(child: HomeCustomizeSectionLabel(t.discover.continueWatching)),
                SliverToBoxAdapter(child: HomeCustomizeHiddenItemsTile(count: hiddenCount)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

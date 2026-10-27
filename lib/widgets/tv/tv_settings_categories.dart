/// The A-24 settings layout on TV: categories on the left, the chosen
/// category's rows in the middle, and an optional preview on the right.
///
/// Weergave used this shape first (`TvAppearanceCategories`, APP1); the main
/// settings page now uses it as well, so both pages share one implementation
/// of the left/right walk and of the category mark. A-24b (anchor `02`): a
/// tagline under the page title, a glyph per category, the category's own
/// heading over its rows and the remote's key hint at the foot.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/main_screen_scope.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/tv_hig.dart';
import 'tv_page_surface.dart';
import 'tv_settings_studio_style.dart';
import 'tv_studio_category_pill.dart';
import 'tv_unified_layout.dart';

export 'tv_studio_category_pill.dart';

/// VIS-0926-S1 (DEC-139), in HIG points: the gap between pills, the air
/// between the page title and both columns, and under the eyebrow. The gap
/// went from 16 to 12 with A-24's rail fit, see [kTvCategoryPillInsetPt].
const double kTvCategoryGapPt = 12;
const double kTvAppearanceColumnsTopPt = 12;
const double kTvAppearanceLabelGapPt = 6;

/// Width of the category rail and of the preview column, in HIG points.
const double kTvCategoryRailWidthPt = 460;
const double kTvSettingsPreviewWidthPt = 600;

/// One category: its rail label and glyph, the rows it shows, and an optional
/// preview.
class TvSettingsCategory {
  const TvSettingsCategory({
    required this.id,
    required this.title,
    required this.body,
    this.icon,
    this.heading,
    this.preview,
    this.needsAttention = false,
  });

  /// Stable across rebuilds, so the chosen category survives a category
  /// appearing or disappearing before it (an update, iCloud).
  final String id;
  final String title;
  final IconData? icon;

  /// The large line over the rows ("Zo ziet jouw Pleya eruit"), with [title]
  /// as the accent eyebrow above it. Null shows the eyebrow alone.
  final String? heading;

  /// The rows. Built only while this category is the chosen one.
  final Widget body;

  /// Shown to the right of the rows. Null gives that room to the rows; a
  /// preview is only there when it shows something the rows cannot.
  final Widget? preview;

  /// Something in this category waits on the viewer, such as a server whose
  /// session expired (Koppelingen, A-24c): the pill carries the amber dot the
  /// top bar puts on Instellingen, so the dot leads somewhere.
  final bool needsAttention;
}

class TvSettingsCategories extends StatefulWidget {
  const TvSettingsCategories({
    super.key,
    required this.title,
    required this.categories,
    required this.automationInstance,
    required this.categoryAutomationId,
    this.subtitle,
    this.autofocusFirstCategory = true,
    this.maxBodyWidthPt,
  });

  final String title;

  /// The line under the page title (anchor `02`: "Jouw kijkervaring, tot in
  /// detail.").
  final String? subtitle;
  final List<TvSettingsCategory> categories;

  /// The page name on [TvPageSurface] (`my_pleya.section.content[...]`).
  final String automationInstance;

  /// The id every category pill registers under, with its index as instance.
  final String categoryAutomationId;

  /// Weergave opens on its rail. The main settings page does not: it hands
  /// focus over through `FocusableTab`, and an autofocus here would race that.
  final bool autofocusFirstCategory;

  /// Caps the rows column where a category has no preview, so a row's title
  /// and value stay within one glance. Null lets the rows take the width.
  final double? maxBodyWidthPt;

  @override
  State<TvSettingsCategories> createState() => TvSettingsCategoriesState();
}

class TvSettingsCategoriesState extends State<TvSettingsCategories> {
  String? _selectedId;
  final List<FocusNode> _categoryNodes = [];
  final FocusNode _rowsNode = FocusNode(debugLabel: 'settings.categories.rows', skipTraversal: true);

  /// Where the remote last stood on this page: a row of the chosen category,
  /// or the rail. Read by [restoreFocus] when the page gets the remote back.
  FocusNode? _lastRow;
  bool _lastOnRail = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_trackFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_trackFocus);
    for (final node in _categoryNodes) {
      node.dispose();
    }
    _rowsNode.dispose();
    super.dispose();
  }

  void _trackFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    if (_categoryNodes.contains(focus)) {
      _lastOnRail = true;
    } else if (focus.ancestors.contains(_rowsNode)) {
      _lastOnRail = false;
      _lastRow = focus;
    }
  }

  FocusNode _categoryNode(int index) {
    while (_categoryNodes.length <= index) {
      _categoryNodes.add(FocusNode(debugLabel: 'settings.category.${_categoryNodes.length}'));
    }
    return _categoryNodes[index];
  }

  int get _selected {
    final index = widget.categories.indexWhere((c) => c.id == _selectedId);
    return index < 0 ? 0 : index;
  }

  void _select(int index) => setState(() => _selectedId = widget.categories[index].id);

  /// Chooses the category with [id] as SELECT on its pill would, for an entry
  /// from outside the page ("Servers beheren", A-24c). False when there is no
  /// such category.
  bool choose(String id) {
    final index = widget.categories.indexWhere((c) => c.id == id);
    if (index < 0) return false;
    _select(index);
    return true;
  }

  /// Gives the page the remote back (a return from another destination, a
  /// page pushed on top closing): to the chosen category's pill when the
  /// remote last left from the rail, else to the row it last stood on, else
  /// to the chosen category's first row.
  ///
  /// Only the chosen category's rows are mounted, so the remembered row is
  /// one of them or it is detached; a detached node is never asked, because
  /// Flutter keeps such a request and grants it on a later re-attach, which
  /// would pull the remote off the rail on a category SELECT.
  void restoreFocus() {
    if (_lastOnRail) return focusChosenCategory();
    final row = _lastRow;
    if (row != null && row.context != null && row.canRequestFocus) {
      row.requestFocus();
      return;
    }
    _focusFirstRow();
  }

  /// The chosen category's pill.
  void focusChosenCategory() {
    final selected = _selected;
    if (_categoryNodes.length > selected) _categoryNodes[selected].requestFocus();
  }

  /// The top row of the chosen category, once it is laid out.
  void _focusFirstRow() {
    void focus() {
      if (!mounted) return;
      final rows = _rowsNode.traversalDescendants.where((node) => node.canRequestFocus && node.context != null).toList()
        ..sort((a, b) {
          final byTop = a.rect.top.compareTo(b.rect.top);
          return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
        });
      if (rows.isNotEmpty) {
        rows.first.requestFocus();
      } else {
        focusChosenCategory();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => focus());
  }

  // APP1. The columns used to be joined by geometry alone: LEFT only found the
  // categories from a row level with one, and RIGHT landed on whatever row sat
  // beside the category. Both moves are semantic.

  /// RIGHT from a category: that category, on its first row.
  void _enterCategory(int index) {
    _select(index);
    _focusFirstRow();
  }

  /// LEFT from any row a row did not use itself (a slider keeps its LEFT):
  /// the chosen category. UP and DOWN step through the column in the order
  /// the rows are drawn, whichever group or page drew them (A-24b mounts
  /// whole settings pages here), and DOWN holds on the last row instead of
  /// wandering into the preview beside it. UP from the top row goes to the
  /// top bar ([_toTopBar]).
  KeyEventResult _handleRowsKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final selected = _selected;
      if (_categoryNodes.length <= selected) return KeyEventResult.ignored;
      _categoryNodes[selected].requestFocus();
      return KeyEventResult.handled;
    }
    final down = key == LogicalKeyboardKey.arrowDown;
    if (!down && key != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final current = FocusManager.instance.primaryFocus;
    if (current == null || current.context == null) return KeyEventResult.ignored;
    final top = current.rect.top;
    final rows = _rowsNode.traversalDescendants
        .where((node) => node.canRequestFocus && node.context != null && node != current)
        .where((node) => down ? node.rect.top > top + 1 : node.rect.top < top - 1)
        .toList();
    if (rows.isEmpty) {
      if (down) return KeyEventResult.handled;
      return _toTopBar() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    // The nearest row in that direction; level rows (two buttons side by
    // side) by their leading edge.
    rows.sort((a, b) {
      final byTop = down ? a.rect.top.compareTo(b.rect.top) : b.rect.top.compareTo(a.rect.top);
      return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
    });
    rows.first.requestFocus();
    return KeyEventResult.handled;
  }

  /// UP from the top of either column: the top bar. Wired here, as the shell
  /// asks of every screen with a header (`TvRootShell`), rather than left to
  /// traversal, which stops at the content scope. Under the collapsible bar
  /// of A-24 (DEC-166) this press is also what brings the bar back. False
  /// where no shell listens, such as a test that mounts the page on its own.
  bool _toTopBar() {
    final shell = MainScreenFocusScope.of(context, listen: false);
    if (shell == null) return false;
    shell.focusSidebar();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    if (categories.isEmpty) return TvPageSurface(title: widget.title, subtitle: widget.subtitle, children: const []);
    final selected = _selected;
    final category = categories[selected];
    // DENS1: HIG points.
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final preview = category.preview;
    final heading = category.heading;

    final columns = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: kTvCategoryRailWidthPt * pt,
          child: ListView(
            // VIS-0926-S1: air between the page title and both columns.
            padding: EdgeInsets.only(top: kTvAppearanceColumnsTopPt * pt),
            children: [
              for (var index = 0; index < categories.length; index++)
                Padding(
                  padding: EdgeInsets.only(bottom: kTvCategoryGapPt * pt, right: TvHig.itemSpacing * pt),
                  child: FocusableWrapper(
                    automationId: widget.categoryAutomationId,
                    automationInstance: index.toString(),
                    automationState: () => {
                      'selected': selected == index,
                      'title': categories[index].title,
                      'attention': categories[index].needsAttention,
                    },
                    focusNode: _categoryNode(index),
                    autofocus: widget.autofocusFirstCategory && index == 0,
                    disableScale: true,
                    // VIS-0925-A: the ring follows the pill's own corners,
                    // one ring gap out.
                    borderRadius: FocusTheme.ringRadiusAround(tk.radiusMd, gap: TvMyPleyaLayout.tileFocusRingGap * pt),
                    onSelect: () => _select(index),
                    onNavigateUp: index == 0 && MainScreenFocusScope.of(context, listen: false) != null
                        ? _toTopBar
                        : null,
                    onNavigateRight: () => _enterCategory(index),
                    child: GestureDetector(
                      onTap: () => _select(index),
                      child: Padding(
                        // A gap between ring and pill, so the ring never
                        // sits on the pill's own fill.
                        padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * pt),
                        child: Builder(
                          builder: (context) => TvStudioCategoryPill(
                            title: categories[index].title,
                            icon: categories[index].icon,
                            selected: selected == index,
                            focused: Focus.of(context).hasFocus,
                            needsAttention: categories[index].needsAttention,
                            pt: pt,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: kTvAppearanceColumnsTopPt * pt),
          child: SizedBox(
            width: 1,
            height: double.infinity,
            child: ColoredBox(color: tvStudioSeparator(tk)),
          ),
        ),
        SizedBox(width: TvHig.itemSpacing * pt),
        Expanded(
          child: Focus(
            focusNode: _rowsNode,
            onKeyEvent: _handleRowsKey,
            child: _bodyWidth(
              pt,
              preview == null ? widget.maxBodyWidthPt : null,
              ListView(
                key: ValueKey(category.id),
                padding: EdgeInsets.only(top: kTvAppearanceColumnsTopPt * pt),
                children: [
                  TvStudioEyebrow(category.title),
                  if (heading != null) TvStudioHeading(heading) else SizedBox(height: kTvAppearanceLabelGapPt * pt),
                  category.body,
                ],
              ),
            ),
          ),
        ),
        if (preview != null) ...[
          SizedBox(width: TvHig.itemSpacing * pt),
          SizedBox(
            width: kTvSettingsPreviewWidthPt * pt,
            child: Padding(
              padding: EdgeInsets.only(top: kTvAppearanceColumnsTopPt * pt),
              child: preview,
            ),
          ),
        ],
      ],
    );

    return TvPageSurface(
      title: widget.title,
      subtitle: widget.subtitle,
      automationInstance: widget.automationInstance,
      expanded: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: columns),
          // The remote's two keys on this page, as the series' foot line.
          Padding(
            padding: EdgeInsets.only(top: 12 * pt),
            child: Text(
              t.settingsStudio.tvFooterHint,
              style: TextStyle(
                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                fontSize: TvHig.caption2 * pt,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      children: const [],
    );
  }
}

Widget _bodyWidth(double pt, double? maxWidthPt, Widget child) {
  if (maxWidthPt == null) return child;
  return Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidthPt * pt),
      child: child,
    ),
  );
}

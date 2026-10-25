/// The A-24 settings layout on TV: categories on the left, the chosen
/// category's rows in the middle, and an optional preview on the right.
///
/// Weergave used this shape first (`TvAppearanceCategories`, APP1); the main
/// settings page now uses it as well, so both pages share one implementation
/// of the left/right walk and of the category mark.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/tv_hig.dart';
import 'tv_page_surface.dart';
import 'tv_settings_studio_style.dart';
import 'tv_unified_layout.dart';

/// VIS-0926-S1 (DEC-139), in HIG points. VIS-0925-G packed the rail to a
/// 12 pt pill inset with 8 pt between pills, which read as one stack on the
/// 77 inch set; 18 and 16 make it a list. The page title and the section label
/// get back some of the air VIS-0925-G took, not the pre-G amount.
const double kTvCategoryPillInsetPt = 18;
const double kTvCategoryGapPt = 16;
const double kTvAppearanceColumnsTopPt = 12;
const double kTvAppearanceLabelGapPt = 6;

/// Width of the category rail and of the preview column, in HIG points.
const double kTvCategoryRailWidthPt = 400;
const double kTvSettingsPreviewWidthPt = 520;

/// One category: its rail label, the rows it shows, and an optional preview.
class TvSettingsCategory {
  const TvSettingsCategory({
    required this.id,
    required this.title,
    required this.body,
    this.preview,
    this.rowKeys = const [],
  });

  /// Stable across rebuilds, so the chosen category survives a category
  /// appearing or disappearing before it (an update, iCloud).
  final String id;
  final String title;

  /// The rows. Built only while this category is the chosen one.
  final Widget body;

  /// Shown to the right of the rows. Null gives that room to the rows; a
  /// preview is only there when it shows something the rows cannot.
  final Widget? preview;

  /// The focus-memory keys of the rows in [body], so a focus restore can
  /// choose this category before it focuses one of them.
  final List<String> rowKeys;
}

class TvSettingsCategories extends StatefulWidget {
  const TvSettingsCategories({
    super.key,
    required this.title,
    required this.categories,
    required this.automationInstance,
    required this.categoryAutomationId,
    this.autofocusFirstCategory = true,
    this.maxBodyWidthPt,
  });

  final String title;
  final List<TvSettingsCategory> categories;

  /// The page name on [TvPageSurface] (`my_pleya.section.content[...]`).
  final String automationInstance;

  /// The id every category pill registers under, with its index as instance.
  final String categoryAutomationId;

  /// Weergave opens on its rail. The main settings page does not: it hands
  /// focus to its remembered row through `FocusableTab`, and an autofocus
  /// here would race that.
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

  @override
  void dispose() {
    for (final node in _categoryNodes) {
      node.dispose();
    }
    _rowsNode.dispose();
    super.dispose();
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

  /// Focus restore for a remembered row ([key], [node]). Only the chosen
  /// category's rows are mounted, so this chooses the category that holds
  /// [key] first and focuses [node] once it is attached.
  ///
  /// [node] is never asked while detached: Flutter keeps such a request and
  /// grants it whenever the node is attached again, which would pull the
  /// remote off the rail on a later category SELECT. Returns false when no
  /// category holds [key].
  bool focusRow(String key, FocusNode node) {
    final index = widget.categories.indexWhere((c) => c.rowKeys.contains(key));
    if (index < 0) return false;
    if (node.context != null && index == _selected) {
      node.requestFocus();
      return true;
    }
    _select(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
    return true;
  }

  /// The chosen category's pill, for a restore with no row to return to.
  void focusChosenCategory() {
    final selected = _selected;
    if (_categoryNodes.length > selected) _categoryNodes[selected].requestFocus();
  }

  // APP1. The columns used to be joined by geometry alone: LEFT only found the
  // categories from a row level with one, and RIGHT landed on whatever row sat
  // beside the category. Both moves are semantic.

  /// RIGHT from a category: that category, on its first row.
  void _enterCategory(int index) {
    _select(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rows = _rowsNode.traversalDescendants.where((node) => node.canRequestFocus && node.context != null).toList()
        ..sort((a, b) {
          final byTop = a.rect.top.compareTo(b.rect.top);
          return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
        });
      if (rows.isNotEmpty) rows.first.requestFocus();
    });
  }

  /// LEFT from any row a row did not use itself (a slider keeps its LEFT):
  /// the chosen category.
  KeyEventResult _handleRowsKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final selected = _selected;
    if (_categoryNodes.length <= selected) return KeyEventResult.ignored;
    _categoryNodes[selected].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    if (categories.isEmpty) return TvPageSurface(title: widget.title, children: const []);
    final selected = _selected;
    final category = categories[selected];
    // DENS1: HIG points.
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final preview = category.preview;

    return TvPageSurface(
      title: widget.title,
      automationInstance: widget.automationInstance,
      expanded: Row(
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
                      automationState: () => {'selected': selected == index, 'title': categories[index].title},
                      focusNode: _categoryNode(index),
                      autofocus: widget.autofocusFirstCategory && index == 0,
                      disableScale: true,
                      // VIS-0925-A: the ring follows the pill's own corners,
                      // one ring gap out.
                      borderRadius: FocusTheme.ringRadiusAround(
                        tk.radiusMd,
                        gap: TvMyPleyaLayout.tileFocusRingGap * pt,
                      ),
                      onSelect: () => _select(index),
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
                              selected: selected == index,
                              focused: Focus.of(context).hasFocus,
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
                    SizedBox(height: kTvAppearanceLabelGapPt * pt),
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

/// The category name over the rows, in the Studio accent ink.
class TvStudioEyebrow extends StatelessWidget {
  const TvStudioEyebrow(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: TvMyPleyaLayout.groupLabelGap * scale),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: tvStudioEyebrow(tokens(context)),
          fontSize: TvMyPleyaLayout.groupLabelFontSize * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// A-24: one rule for chosen versus focused on the category rail.
///
/// Chosen is a secondary mark, never a focus: a brand-red bar on the leading
/// edge over the warm Studio fill, with the label in full ink and bold. Focus
/// is the ring from [FocusableWrapper] and nothing else, so with the remote in
/// the rows the rail shows the chosen category and no ring at all.
class TvStudioCategoryPill extends StatelessWidget {
  const TvStudioCategoryPill({
    super.key,
    required this.title,
    required this.selected,
    required this.focused,
    required this.pt,
  });

  /// Finds the bar in a test.
  static const Key markerKey = Key('tv-studio-category-marker');

  final String title;
  final bool selected;
  final bool focused;
  final double pt;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tvStudioCategoryFill(tk, selected: selected, focused: focused),
        borderRadius: BorderRadius.circular(tk.radiusMd),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * pt, vertical: kTvCategoryPillInsetPt * pt),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tvStudioCategoryLabel(tk, selected: selected, focused: focused),
                fontSize: TvHig.body * pt,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (selected)
            PositionedDirectional(
              key: markerKey,
              start: 0,
              top: 0,
              bottom: 0,
              width: kTvStudioMarkerWidthPt * pt,
              child: ColoredBox(color: tvStudioMarkerColor(tk)),
            ),
        ],
      ),
    );
  }
}

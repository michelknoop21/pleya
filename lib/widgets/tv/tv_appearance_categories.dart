import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/tv_hig.dart';
import '../settings_section.dart';
import 'tv_unified_layout.dart';
import 'tv_page_surface.dart';

/// VIS-0926-S1 (DEC-139), in HIG points. VIS-0925-G packed the rail to a
/// 12 pt pill inset with 8 pt between pills, which read as one stack on the
/// 77 inch set; 18 and 16 make it a list. The page title and the section label
/// get back some of the air VIS-0925-G took, not the pre-G amount.
const double kTvCategoryPillInsetPt = 18;
const double kTvCategoryGapPt = 16;
const double kTvAppearanceColumnsTopPt = 12;
const double kTvAppearanceLabelGapPt = 6;

/// TV presentation for the existing Appearance rows. The original widgets
/// remain the sole owners of their preferences, callbacks and platform gates.
class TvAppearanceCategories extends StatefulWidget {
  const TvAppearanceCategories({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<TvAppearanceCategories> createState() => _TvAppearanceCategoriesState();
}

class _TvAppearanceCategoriesState extends State<TvAppearanceCategories> {
  int _selected = 0;
  final List<FocusNode> _categoryNodes = [];
  final FocusNode _rowsNode = FocusNode(debugLabel: 'appearance.rows', skipTraversal: true);

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
      _categoryNodes.add(FocusNode(debugLabel: 'appearance.category.${_categoryNodes.length}'));
    }
    return _categoryNodes[index];
  }

  // APP1. The two columns used to be joined by geometry alone: LEFT only found
  // the categories from a row level with one, and RIGHT landed on whatever row
  // sat beside the category. Both moves are now semantic.

  /// RIGHT from a category: that category, on its first row.
  void _enterCategory(int index) {
    setState(() => _selected = index);
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
  /// the active category.
  KeyEventResult _handleRowsKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    if (_categoryNodes.length <= _selected) return KeyEventResult.ignored;
    _categoryNodes[_selected].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final sections = <({String title, List<Widget> rows})>[];
    String? currentTitle;
    var currentRows = <Widget>[];
    for (final child in widget.children) {
      if (child is SettingsSectionHeader) {
        if (currentTitle != null) sections.add((title: currentTitle, rows: currentRows));
        currentTitle = child.title;
        currentRows = [];
      } else {
        currentRows.add(child);
      }
    }
    if (currentTitle != null) sections.add((title: currentTitle, rows: currentRows));
    if (sections.isEmpty) return TvPageSurface(title: widget.title, children: const []);
    final selected = _selected.clamp(0, sections.length - 1);
    // DENS1: HIG points. Body (29 pt) labels in a 68 pt card, the height of a
    // tvOS tab bar, where `scaleOf` drew 35 pt labels in 110 pt cards.
    final pt = TvHig.of(context);
    final tk = tokens(context);

    return TvPageSurface(
      title: widget.title,
      automationInstance: 'appearance',
      expanded: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 400 * pt,
            child: ListView(
              // VIS-0926-S1: air between the page title and both columns.
              padding: EdgeInsets.only(top: kTvAppearanceColumnsTopPt * pt),
              children: [
                for (var index = 0; index < sections.length; index++)
                  Padding(
                    padding: EdgeInsets.only(bottom: kTvCategoryGapPt * pt, right: TvHig.itemSpacing * pt),
                    child: FocusableWrapper(
                      automationId: AutomationIds.settingsAppearanceCategory,
                      automationInstance: index.toString(),
                      automationState: () => {'selected': selected == index},
                      focusNode: _categoryNode(index),
                      autofocus: index == 0,
                      disableScale: true,
                      // VIS-0925-A: the ring follows the pill's own corners,
                      // one ring gap out.
                      borderRadius: FocusTheme.ringRadiusAround(
                        tk.radiusMd,
                        gap: TvMyPleyaLayout.tileFocusRingGap * pt,
                      ),
                      onSelect: () => setState(() => _selected = index),
                      onNavigateRight: () => _enterCategory(index),
                      child: GestureDetector(
                        onTap: () => setState(() => _selected = index),
                        child: Padding(
                          // A gap between ring and pill, so a focused selected
                          // (white) pill in Dark still shows its white ring.
                          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * pt),
                          child: Builder(
                            builder: (context) => _CategoryPill(
                              title: sections[index].title,
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
          Expanded(
            child: Focus(
              focusNode: _rowsNode,
              onKeyEvent: _handleRowsKey,
              child: ListView(
                key: ValueKey(selected),
                padding: EdgeInsets.only(top: kTvAppearanceColumnsTopPt * pt),
                children: [
                  TvPageGroupLabel(sections[selected].title),
                  SizedBox(height: kTvAppearanceLabelGapPt * pt),
                  SettingsGroup(children: sections[selected].rows),
                ],
              ),
            ),
          ),
        ],
      ),
      children: const [],
    );
  }
}

/// VIS-0925-B: one rule for selected versus focused on the category rail.
///
/// Selected is a filled pill in the theme's ink with a [MonoTokens.bg] label,
/// the same as the active top-navigation pill, and carries no ring. Focused is
/// the white ring from [FocusableWrapper] plus the lighter tile fill. The
/// idle pill has the quiet tile fill and no border: the old 1px outlines on
/// every pill made selected (#EDEDED with a rim) and idle (#FFF with a rim)
/// indistinguishable in Light.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.title, required this.selected, required this.focused, required this.pt});

  final String title;
  final bool selected;
  final bool focused;
  final double pt;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24 * pt, vertical: kTvCategoryPillInsetPt * pt),
      decoration: BoxDecoration(
        color: tvCategoryPillFill(tk, selected: selected, focused: focused),
        borderRadius: BorderRadius.circular(tk.radiusMd),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: selected ? tk.bg : tk.text,
          fontSize: TvHig.body * pt,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// Fill of a category pill; public so the contrast test measures the same
/// colors the rail paints.
@visibleForTesting
Color tvCategoryPillFill(MonoTokens tk, {required bool selected, required bool focused}) {
  if (selected) return tk.text;
  return tk.text.withValues(alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha);
}

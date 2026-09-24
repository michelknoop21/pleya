import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../settings_section.dart';
import 'tv_page_surface.dart';

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
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);

    return TvPageSurface(
      title: widget.title,
      automationInstance: 'appearance',
      expanded: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 300 * scale,
            child: ListView(
              children: [
                for (var index = 0; index < sections.length; index++)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10 * scale, right: 14 * scale),
                    child: FocusableWrapper(
                      automationId: AutomationIds.settingsAppearanceCategory,
                      automationInstance: index.toString(),
                      automationState: () => {'selected': selected == index},
                      focusNode: _categoryNode(index),
                      autofocus: index == 0,
                      disableScale: true,
                      onSelect: () => setState(() => _selected = index),
                      onNavigateRight: () => _enterCategory(index),
                      child: GestureDetector(
                        onTap: () => setState(() => _selected = index),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 22 * scale, vertical: 18 * scale),
                          decoration: BoxDecoration(
                            color: selected == index ? tk.surfaceElevated : tk.surface,
                            borderRadius: BorderRadius.circular(tk.radiusMd),
                            border: Border.all(color: selected == index ? tk.textMuted : tk.outline),
                          ),
                          child: Text(
                            sections[index].title,
                            style: TextStyle(
                              color: tk.text,
                              fontSize: 22 * scale,
                              fontWeight: selected == index ? FontWeight.w700 : FontWeight.w500,
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
                children: [
                  TvPageGroupLabel(sections[selected].title),
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

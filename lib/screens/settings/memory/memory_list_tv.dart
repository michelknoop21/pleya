import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../focus/focus_memory_tracker.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart' show assistantMemoryCategoryLabel;
import '../../../widgets/tv/tv_page_chip_bar.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import 'memory_labels.dart';
import 'memory_list_screen.dart';
import 'memory_tv_text.dart';
import 'memory_tv_widgets.dart';

/// "Herinneringen" on TV: 43 D in the TV style of 43 M. A row "Zoeken" opens
/// the system keyboard (the plan's decision 4), the categories are the chip
/// bar of the other Mijn Pleya pages, and every memory is a tile that opens
/// its sheet.
class MemoryListTv extends StatefulWidget {
  const MemoryListTv({super.key, required this.list});

  final MemoryListScreenState list;

  @override
  State<MemoryListTv> createState() => _MemoryListTvState();
}

class _MemoryListTvState extends State<MemoryListTv> {
  final _nodes = FocusMemoryTracker();
  bool _landed = false;

  MemoryListScreenState get _list => widget.list;

  @override
  void dispose() {
    _nodes.dispose();
    super.dispose();
  }

  void _focus(String key) {
    final node = _nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }

  void _focusLater(String key) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _focus(key);
  });

  String _chipKey(MemoryCategory? category) => 'chip_${category?.id ?? 'all'}';

  Future<void> _search() async {
    final l = t.assistant.memory.screen.list;
    final text = await memoryTvCaptureText(
      context,
      _list.speech,
      prompt: l.search,
      initial: _list.query,
      action: 'search',
    );
    if (!mounted) return;
    _focusLater('search');
    if (text != null) _list.setQuery(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final l = t.assistant.memory.screen.list;
    final s = t.assistant.memory.screen;
    final model = _list.model;
    final facts = _list.shown;
    final readable = model.facts != null;
    final searching = _list.query.isNotEmpty;

    // The rows under the chip bar, top to bottom.
    final rows = <String>[
      if (!readable) 'retry',
      for (var i = 0; i < facts.length; i++) 'fact$i',
      if (model.kidsAges.isNotEmpty) 'kidsAges',
      if (!model.kids && readable) 'add',
    ];
    final above = searching ? 'searchClear' : 'search';
    void up(String key) {
      final at = rows.indexOf(key);
      _focus(at <= 0 ? _chipKey(_list.category) : rows[at - 1]);
    }

    void down(String key) {
      final at = rows.indexOf(key);
      if (at >= 0 && at < rows.length - 1) _focus(rows[at + 1]);
    }

    final held = _nodes.lastFocusedKey;
    if (!_landed) {
      _landed = true;
      _focusLater('search');
    } else if (held != null && _nodes.isFocused(held) && held.startsWith('fact') && !rows.contains(held)) {
      // The memory under the remote was removed or filtered away.
      _focusLater(rows.isEmpty ? _chipKey(_list.category) : rows.last);
    } else if (held == 'searchClear' && _nodes.isFocused('searchClear') && !searching) {
      _focusLater('search');
    }

    MemoryTvTile row(
      String key, {
      required String title,
      String? subtitle,
      String? value,
      IconData? icon,
      VoidCallback? onSelect,
      String automationId = AutomationIds.settingsMemoryAction,
      String? instance,
      Map<String, Object?> Function()? state,
    }) => MemoryTvTile(
      title: title,
      subtitle: subtitle,
      value: value,
      icon: icon,
      titleLines: 2,
      node: _nodes.get(key, debugLabel: 'memory.list.$key'),
      instance: instance ?? key,
      automationId: automationId,
      automationRole: automationId == AutomationIds.settingsMemoryFact ? 'list.item' : 'button',
      state: state,
      onSelect: onSelect,
      onNavigateUp: () => up(key),
      onNavigateDown: () => down(key),
      onNavigateLeft: () {},
      onNavigateRight: () {},
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => handleBackKeyAction(event, _list.back),
      child: Material(
        type: MaterialType.transparency,
        child: TvPageSurface(
          title: l.title,
          automationInstance: 'assistant_memory_list',
          children: [
            MemoryTvTile(
              title: l.searchTv,
              subtitle: searching ? _list.query : l.search,
              icon: Symbols.search_rounded,
              node: _nodes.get('search', debugLabel: 'memory.list.search'),
              instance: 'search',
              state: () => {'query': searching},
              onSelect: () => unawaited(_search()),
              onNavigateDown: () => _focus(searching ? 'searchClear' : _chipKey(_list.category)),
              onNavigateLeft: () {},
              onNavigateRight: () {},
            ),
            if (searching) ...[
              SizedBox(height: 4 * pt),
              MemoryTvTile(
                title: l.searchClear,
                icon: Symbols.close_rounded,
                compact: true,
                node: _nodes.get('searchClear', debugLabel: 'memory.list.searchClear'),
                instance: 'searchClear',
                onSelect: () => _list.setQuery(''),
                onNavigateUp: () => _focus('search'),
                onNavigateDown: () => _focus(_chipKey(_list.category)),
                onNavigateLeft: () {},
                onNavigateRight: () {},
              ),
            ],
            SizedBox(height: 14 * pt),
            TvPageChipBar(
              nodes: _nodes,
              automationInstance: 'assistant_memory',
              onExitUp: () => _focus(above),
              onExitDown: rows.isEmpty ? () {} : () => _focus(rows.first),
              chips: [
                for (final category in <MemoryCategory?>[null, ...MemoryCategory.values])
                  TvPageChip(
                    key: _chipKey(category),
                    label: category == null ? l.all : assistantMemoryCategoryLabel(category),
                    selected: category == _list.category,
                    onSelect: () => _list.setCategory(category),
                  ),
              ],
            ),
            SizedBox(height: 8 * pt),
            if (!readable) ...[
              // Unreadable facts are an error, never "no memories".
              MemoryTvLabel(s.error.title),
              Padding(
                padding: EdgeInsets.only(bottom: 14 * pt, left: 4 * pt),
                child: Text(s.error.body, style: memoryTvBody(context)),
              ),
              row(
                'retry',
                title: t.common.retry,
                icon: Symbols.refresh_rounded,
                onSelect: () => unawaited(model.load()),
              ),
            ] else ...[
              MemoryTvLabel(l.header, trailing: memoryCountLabel(facts.length, model.count)),
              if (facts.isEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: 14 * pt, left: 4 * pt),
                  child: Text(l.none, style: memoryTvBody(context)),
                ),
              for (final (i, fact) in facts.indexed) ...[
                if (i > 0) SizedBox(height: 4 * pt),
                row(
                  'fact$i',
                  title: fact.value,
                  subtitle: '${assistantMemoryCategoryLabel(fact.category)} · ${memorySourceLabel(fact.source)}',
                  automationId: AutomationIds.settingsMemoryFact,
                  instance: '$i',
                  state: () => {'category': fact.category.id},
                  onSelect: () => _list.openFact(fact),
                ),
              ],
            ],
            if (model.kidsAges.isNotEmpty) ...[
              MemoryTvLabel(l.kidsHeader),
              row(
                'kidsAges',
                title: l.kidsAges,
                subtitle: l.kidsAgesNote,
                value: memoryAgesLabel(model.kidsAges),
                icon: Symbols.child_care_rounded,
                onSelect: _list.openKidsProfile,
              ),
            ],
            // A children's profile looks and wipes; it adds nothing.
            if (!model.kids && readable) ...[
              SizedBox(height: 22 * pt),
              row('add', title: l.add, icon: Symbols.add_rounded, onSelect: _list.addFact),
            ],
          ],
        ),
      ),
    );
  }
}

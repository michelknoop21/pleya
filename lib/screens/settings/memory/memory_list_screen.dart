import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../i18n/strings.g.dart';
import '../../../navigation/tv/tv_content_route_registry.dart';
import '../../../navigation/tv/tv_nested_surface.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../services/speech_search_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart' show assistantMemoryCategoryLabel;
import '../assistant_settings_screen.dart';
import 'memory_fact_sheet.dart';
import 'memory_labels.dart';
import 'memory_layouts.dart';
import 'memory_list_tv.dart';
import 'memory_screen.dart';
import 'memory_screen_model.dart';
import 'memory_state_card.dart';
import 'memory_widgets.dart';
import '../../../widgets/settings/settings_studio_theme.dart';

/// "Herinneringen" (43 D): the facts themselves, to search, filter, open,
/// add and remove. The children's ages are a reference row to Kinderprofiel
/// under the list, never a memory. On TV the same list in TV style, with a
/// row that opens the system keyboard to search.
class MemoryListScreen extends StatefulWidget {
  const MemoryListScreen({super.key, required this.model, this.speech});

  /// The model of the memory screen this list was opened from.
  final MemoryScreenModel model;
  final SpeechSearchService? speech;

  @override
  State<MemoryListScreen> createState() => MemoryListScreenState();
}

class MemoryListScreenState extends State<MemoryListScreen> {
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'memory.list.search');
  MemoryCategory? _category;

  MemoryScreenModel get model => widget.model;
  SpeechSearchService get speech => widget.speech ?? SpeechSearchService.instance;
  MemoryCategory? get category => _category;
  String get query => _query.text;

  /// The facts the filter and the search leave, newest change first.
  List<MemoryFact> get shown => model.filtered(category: _category, query: _query.text);

  @override
  void initState() {
    super.initState();
    _query.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void setCategory(MemoryCategory? category) => setState(() => _category = category);

  void setQuery(String text) => _query.text = text;

  void back() {
    if (TvNestedRouteScope.readOf(context) case final nested?) {
      nested.dismiss();
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  void openFact(MemoryFact fact) => unawaited(showMemoryFactSheet(context, model, fact: fact, speech: speech));

  void addFact() => unawaited(showMemoryFactSheet(context, model, speech: speech));

  /// The ages live with Kinderprofiel, in Big P's settings.
  void openKidsProfile() {
    final builder = settingsStudioBuilder(context, (_) => const AssistantSettingsScreen());
    final topNav = tvSettingsTopNavFor(context);
    if (openTvContentRoute(id: 'tvSettings_assistant', builder: builder, topNav: topNav) != null) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => AutomationScreen(
      id: AutomationIds.screenMemoryList,
      readiness: () => const AutomationReadiness.ready(),
      child: AutomationNode(
        id: AutomationIds.screenMemoryList,
        role: 'screen',
        state: () => {'count': shown.length, 'total': model.count, 'readable': model.facts != null},
        child: PlatformDetector.isTV() ? MemoryListTv(list: this) : _buildList(context),
      ),
    ),
  );

  Widget _buildList(BuildContext context) {
    final l = t.assistant.memory.screen.list;
    final s = t.assistant.memory.screen;
    final tk = tokens(context);
    final facts = shown;
    final name = context.watch<ActiveProfileProvider?>()?.active?.displayName;
    final tablet = MediaQuery.sizeOf(context).width >= AssistantMemoryScreen.tabletWidth;
    return MemoryPage(
      onBack: back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // The bar of the memory screen behind it, so the title does not
            // jump between the two on a tablet.
            padding: EdgeInsets.symmetric(horizontal: tablet ? 12 : 0),
            child: MemoryHeader(
              title: l.title,
              // Whose memories these are: under the title, so a long profile
              // name never squeezes it.
              subtitle: name == null || name.isEmpty ? '' : l.profile(name: name),
              onBack: back,
              backInstance: 'listBack',
              titleSize: tablet ? 26 : 22,
              trailing: name == null || name.isEmpty ? null : _ProfileMark(name: name),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _searchField(context),
                    const SizedBox(height: 7),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (i, category) in <MemoryCategory?>[null, ...MemoryCategory.values].indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            MemoryChoiceChip(
                              label: category == null ? l.all : assistantMemoryCategoryLabel(category),
                              selected: category == _category,
                              automationId: AutomationIds.settingsMemoryChip,
                              automationInstance: category?.id ?? 'all',
                              onPressed: () => setCategory(category),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Unreadable facts are an error, never "no memories".
                    if (model.facts == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: MemoryStateCard(
                          title: s.error.title,
                          body: s.error.body,
                          icon: Symbols.error_rounded,
                          action: t.common.retry,
                          onAction: () => unawaited(model.load()),
                          automationId: AutomationIds.settingsMemoryAction,
                          automationInstance: 'retry',
                        ),
                      )
                    else ...[
                      MemoryGroupLabel(l.header, trailing: memoryCountLabel(facts.length, model.count)),
                      if (facts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          // Nothing stored is not the same as nothing found.
                          child: Text(
                            model.count == 0 ? s.empty.title : l.none,
                            style: memoryText(context, 15, color: tk.textMuted),
                          ),
                        )
                      else
                        MemoryCard(
                          children: [
                            for (final (i, fact) in facts.indexed)
                              MemoryRow(
                                title: fact.value,
                                subtitle:
                                    '${assistantMemoryCategoryLabel(fact.category)} · ${memorySourceLabel(fact.source)}',
                                automationId: AutomationIds.settingsMemoryFact,
                                automationInstance: '$i',
                                automationRole: 'list.item',
                                automationState: () => {'category': fact.category.id},
                                onPressed: () => openFact(fact),
                              ),
                          ],
                        ),
                    ],
                    if (model.kidsAges.isNotEmpty) ...[
                      MemoryGroupLabel(l.kidsHeader),
                      MemoryCard(
                        children: [
                          MemoryRow(
                            title: l.kidsAges,
                            subtitle: l.kidsAgesNote,
                            value: memoryAgesLabel(model.kidsAges),
                            automationId: AutomationIds.settingsMemoryAction,
                            automationInstance: 'kidsAges',
                            onPressed: openKidsProfile,
                          ),
                        ],
                      ),
                    ],
                    // A children's profile looks and wipes; it adds nothing.
                    if (!model.kids && model.facts != null) ...[
                      const SizedBox(height: 20),
                      MemoryPillButton(
                        label: l.add,
                        icon: Symbols.add_rounded,
                        kind: MemoryPillKind.primary,
                        automationId: AutomationIds.settingsMemoryAction,
                        automationInstance: 'add',
                        onPressed: addFact,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final l = t.assistant.memory.screen.list;
    final tk = tokens(context);
    final style = memoryText(context, 16, height: 1.3);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          AppIcon(Symbols.search_rounded, size: 19, color: memoryFaint(context)),
          const SizedBox(width: 10),
          Expanded(
            child: AutomationNode(
              id: AutomationIds.settingsMemoryAction,
              instance: 'search',
              role: 'field',
              focusNode: _searchFocus,
              child: FocusableTextField(
                controller: _query,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                style: style,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  hintText: l.search,
                  hintMaxLines: 2,
                  hintStyle: style.copyWith(color: memoryFaint(context)),
                ),
                onSubmitted: (_) => _searchFocus.unfocus(),
              ),
            ),
          ),
          if (_query.text.isNotEmpty)
            MemoryPressable(
              shape: const CircleBorder(),
              semanticLabel: l.searchClear,
              onPressed: _query.clear,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: AppIcon(Symbols.close_rounded, size: 18, color: tk.textMuted)),
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// The profile's initial at the right of the bar: the list is of this
/// profile and of no other.
class _ProfileMark extends StatelessWidget {
  const _ProfileMark({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(shape: BoxShape.circle, color: tokens(context).accent),
    child: Center(
      child: Text(
        name.characters.first.toUpperCase(),
        textScaler: TextScaler.noScaling,
        style: memoryText(context, 12, weight: FontWeight.w700, color: Colors.white),
      ),
    ),
  );
}

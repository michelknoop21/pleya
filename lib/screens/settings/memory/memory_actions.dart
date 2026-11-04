import 'dart:async';

import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../widgets/overlay_sheet.dart';
import 'memory_screen_model.dart';
import 'memory_widgets.dart';

/// What the management controls of the memory screen do. The screen owns
/// them, so the menu sheet, the tablet column and the TV tiles all run the
/// same four actions.
class MemoryActionCallbacks {
  const MemoryActionCallbacks({
    required this.openList,
    required this.toggle,
    required this.rewrite,
    required this.clear,
    this.sync,
  });

  /// Opens the list "Herinneringen".
  final VoidCallback openList;

  /// Turns the memory of this profile on or off.
  final VoidCallback toggle;

  /// The user's "Overzicht opnieuw schrijven".
  final VoidCallback rewrite;

  /// Asks, and after a yes wipes every memory of the profile.
  final VoidCallback clear;
  final VoidCallback? sync;
}

/// The four management controls of 43 C: the list with its count, the switch
/// with what it means, writing the overview again, and wiping everything.
/// In the menu sheet on a phone, as the right column on a tablet (43 L).
class MemoryActions extends StatelessWidget {
  const MemoryActions({super.key, required this.model, required this.actions, this.inSheet = false});

  final MemoryScreenModel model;
  final MemoryActionCallbacks actions;

  /// In the menu sheet the cards take the page colour.
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final s = t.assistant.memory.screen.menu;
    final tk = tokens(context);
    final card = inSheet ? tk.bg : tk.surface;
    final facts = model.facts;
    // An overview exists only for an adult profile with the memory on.
    final canRewrite = model.canAsk && model.count > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MemoryCard(
          color: card,
          children: [
            MemoryRow(
              title: s.manage,
              value: facts == null ? null : '${facts.length}',
              automationId: AutomationIds.settingsMemoryAction,
              automationInstance: 'manage',
              onPressed: actions.openList,
            ),
          ],
        ),
        // Not on a children's profile: Big P uses no memory there, whatever
        // the switch says.
        if (!model.kids) ...[
          const SizedBox(height: 12),
          Material(
            color: card,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                MemoryRow(
                  title: s.use,
                  trailing: MemorySwitchMark(on: model.enabled),
                  automationId: AutomationIds.settingsMemoryAction,
                  automationInstance: 'use',
                  automationState: () => {'selected': model.enabled},
                  onPressed: actions.toggle,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Text(s.useNote, style: memoryText(context, 13.5, color: tk.textMuted, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
        if (!model.kids && actions.sync != null) ...[
          const SizedBox(height: 12),
          MemoryCard(
            color: card,
            children: [
              MemoryRow(
                title: t.assistant.memory.sync.title,
                automationId: AutomationIds.settingsMemoryAction,
                automationInstance: 'sync',
                onPressed: actions.sync,
              ),
            ],
          ),
        ],
        if (canRewrite) ...[
          const SizedBox(height: 12),
          MemoryCard(
            color: card,
            children: [
              MemoryRow(
                title: s.rewrite,
                automationId: AutomationIds.settingsMemoryAction,
                automationInstance: 'rewrite',
                onPressed: actions.rewrite,
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        // Wiping stays possible with the memory off, on a children's profile
        // and when the facts could not be read.
        MemoryPillButton(
          label: s.clear,
          kind: MemoryPillKind.danger,
          automationId: AutomationIds.settingsMemoryAction,
          automationInstance: 'clear',
          onPressed: facts != null && facts.isEmpty ? null : actions.clear,
        ),
      ],
    );
  }
}

/// The menu behind the three dots (43 C). An action that leaves the screen or
/// asks something closes the sheet first; the switch flips in place.
Future<void> showMemoryMenu(BuildContext context, MemoryScreenModel model, MemoryActionCallbacks actions) {
  final tk = tokens(context);
  return OverlaySheetController.showAdaptive<void>(
    context,
    backgroundColor: tk.surface,
    isScrollControlled: true,
    restoreLauncherFocus: true,
    builder: (sheetContext) {
      VoidCallback closing(VoidCallback action) => () {
        OverlaySheetController.closeAdaptive(sheetContext);
        action();
      };
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: ListenableBuilder(
            listenable: model,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MemorySheetGrab(),
                Text(t.assistant.memory.screen.menu.title, style: memoryText(context, 20, weight: FontWeight.w700)),
                const SizedBox(height: 16),
                MemoryActions(
                  model: model,
                  inSheet: true,
                  actions: MemoryActionCallbacks(
                    openList: closing(actions.openList),
                    toggle: actions.toggle,
                    rewrite: closing(actions.rewrite),
                    clear: closing(actions.clear),
                    sync: actions.sync == null ? null : closing(actions.sync!),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Flips the switch of the profile's memory.
void toggleMemory(MemoryScreenModel model) => unawaited(model.setEnabled(!model.enabled));

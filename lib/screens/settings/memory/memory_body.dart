import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import 'memory_overview_view.dart';
import 'memory_screen_model.dart';
import 'memory_state_card.dart';
import 'memory_widgets.dart';

/// The reading part of the memory screen for the state it is in: the written
/// overview, the facts as a list, the loading field or one of the state
/// cards. Shared by the phone (43 A) and the left column of the tablet (43 L).
class MemoryBody extends StatelessWidget {
  const MemoryBody({
    super.key,
    required this.model,
    required this.viaMenu,
    this.followUps = true,
    this.bodySize = 16,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 28),
  });

  final MemoryScreenModel model;

  /// The management controls sit behind the menu button (a phone).
  final bool viaMenu;

  /// "Duik dieper" under the text; a tablet shows it in its right column.
  final bool followUps;
  final double bodySize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final s = t.assistant.memory.screen;
    final view = model.view;
    if (view == MemoryScreenView.loading || view == MemoryScreenView.writing) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: MemoryWritingDots());
    }
    final hasFacts = model.count > 0;
    return ListView(
      padding: padding,
      children: [
        ...switch (view) {
          MemoryScreenView.error => [
            _state(
              MemoryStateCard(
                title: s.error.title,
                body: s.error.body,
                icon: Symbols.error_rounded,
                action: t.common.retry,
                onAction: () => unawaited(model.load()),
                automationId: AutomationIds.settingsMemoryAction,
                automationInstance: 'retry',
              ),
            ),
          ],
          MemoryScreenView.off => [
            _state(
              MemoryStateCard(
                title: s.off.title,
                body: s.off.body,
                action: s.off.turnOn,
                onAction: () => unawaited(model.setEnabled(true)),
                automationId: AutomationIds.settingsMemoryAction,
                automationInstance: 'turnOn',
              ),
            ),
          ],
          MemoryScreenView.empty => [_state(MemoryStateCard(title: s.empty.title, body: s.empty.body))],
          // A children's profile: no written overview, no follow-ups and no
          // field. The facts stay readable, and wipeable from the controls.
          MemoryScreenView.kids => [
            _state(
              MemoryStateCard(title: s.kids.title, body: s.kids.body, icon: Symbols.child_care_rounded),
              top: hasFacts ? 12 : 72,
            ),
            if (hasFacts) MemoryReadColumn(model: model, bodySize: bodySize),
          ],
          _ => [
            MemoryReadColumn(model: model, bodySize: bodySize),
            if (followUps && view == MemoryScreenView.overview && model.overview!.followUps.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(s.deeper, style: memoryText(context, 17, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              MemoryFollowUps(model: model),
            ],
            MemoryFooterLine(model: model, viaMenu: viaMenu),
          ],
        },
      ],
    );
  }

  Widget _state(Widget card, {double top = 72}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 8),
    child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: card),
    ),
  );
}

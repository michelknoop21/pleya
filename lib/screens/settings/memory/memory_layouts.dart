import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../widgets/app_icon.dart';
import 'memory_actions.dart';
import 'memory_body.dart';
import 'memory_composer.dart';
import 'memory_labels.dart';
import 'memory_overview_view.dart';
import 'memory_screen_model.dart';
import 'memory_widgets.dart';

/// The bar of the memory screens (`.bar.tall`): back, the title with a line
/// under it, and room on the right for the menu button or the profile.
class MemoryHeader extends StatelessWidget {
  const MemoryHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.subtitle = '',
    this.trailing,
    this.titleSize = 22,
    this.backInstance = 'back',
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget? trailing;
  final double titleSize;

  /// The automation instance of the back button: the list lies over the
  /// memory screen, and each needs a back button of its own name.
  final String backInstance;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 16, 6),
      child: Row(
        children: [
          MemoryPressable(
            shape: const CircleBorder(),
            semanticLabel: t.common.back,
            automationId: AutomationIds.settingsMemoryAction,
            automationInstance: backInstance,
            onPressed: onBack,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: AppIcon(Symbols.arrow_back_rounded, size: 26, color: tk.text)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // A bar title is large already: it grows less than the text
                  // under it, so one word stays on one line.
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4),
                  style: memoryText(context, titleSize, weight: FontWeight.w700, height: 1.2),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: memoryText(context, 13, color: tk.textMuted, height: 1.25),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// The page of a memory screen off TV: Back on a keyboard leaves it, and
/// the content keeps clear of the status bar.
class MemoryPage extends StatelessWidget {
  const MemoryPage({super.key, required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) => handleBackKeyAction(event, onBack),
    child: Scaffold(
      backgroundColor: tokens(context).bg,
      body: SafeArea(child: child),
    ),
  );
}

/// The field with Big P's answer above it, over a fade to the page colour
/// (`.composer`). Nothing on a children's profile or without readable facts:
/// there the screen is for looking and wiping only.
class _ComposerDock extends StatelessWidget {
  const _ComposerDock({
    required this.model,
    required this.maxHeight,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  final MemoryScreenModel model;
  final double maxHeight;
  final EdgeInsets padding;

  static bool shownFor(MemoryScreenModel model) =>
      model.view != MemoryScreenView.kids &&
      model.view != MemoryScreenView.error &&
      model.view != MemoryScreenView.loading;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: Padding(
      padding: padding,
      child: MemoryComposer(model: model),
    ),
  );
}

/// The text fades into the page colour above the field, as 43 A draws it.
class _FadeOut extends StatelessWidget {
  const _FadeOut({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = tokens(context).bg;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 28,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg.withValues(alpha: 0), bg],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// iPhone (43 A to J): the overview over the whole width, the field fixed
/// at the bottom, the management controls behind the menu button.
class MemoryPhoneLayout extends StatelessWidget {
  const MemoryPhoneLayout({super.key, required this.model, required this.onBack, required this.onMenu});

  final MemoryScreenModel model;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return MemoryPage(
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MemoryHeader(
            title: t.assistant.memory.screen.title,
            subtitle: memoryStatusLabel(model),
            onBack: onBack,
            trailing: MemoryPressable(
              shape: const CircleBorder(),
              semanticLabel: t.assistant.memory.screen.menu.open,
              automationId: AutomationIds.settingsMemoryAction,
              automationInstance: 'menu',
              onPressed: onMenu,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: tk.surface),
                    child: Center(child: AppIcon(Symbols.more_horiz_rounded, size: 22, color: tk.text)),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            // The field takes its share of what the bar leaves, so the two
            // never add up to more than the page (a keyboard, a large text).
            child: LayoutBuilder(
              builder: (context, box) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _FadeOut(child: MemoryBody(model: model, viaMenu: true)),
                  ),
                  // A waiting card may take all of it: what it puts in place
                  // has to be readable before the choice (a large text).
                  if (_ComposerDock.shownFor(model))
                    _ComposerDock(model: model, maxHeight: box.maxHeight * (model.host.proposal == null ? 0.72 : 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// iPad (43 L): the overview and the field on the left, the four management
/// controls and "Duik dieper" on the right. No menu button.
class MemoryTabletLayout extends StatelessWidget {
  const MemoryTabletLayout({super.key, required this.model, required this.actions, required this.onBack});

  final MemoryScreenModel model;
  final MemoryActionCallbacks actions;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = t.assistant.memory.screen;
    final deeper = model.view == MemoryScreenView.overview && model.overview!.followUps.isNotEmpty;
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return MemoryPage(
      onBack: onBack,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: MemoryHeader(title: s.title, subtitle: memoryStatusLabel(model), onBack: onBack, titleSize: 26),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(narrow ? 20 : 28, 8, narrow ? 20 : 28, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      flex: 2,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _FadeOut(
                                child: MemoryBody(
                                  model: model,
                                  viaMenu: false,
                                  followUps: false,
                                  bodySize: 17,
                                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
                                ),
                              ),
                            ),
                            if (_ComposerDock.shownFor(model))
                              _ComposerDock(
                                model: model,
                                maxHeight: box.maxHeight * 0.6,
                                padding: const EdgeInsets.only(bottom: 16),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: narrow ? 32 : 56),
                    SizedBox(
                      // Narrower just above the tablet width (an iPad mini
                      // upright), where the text column needs the room.
                      width: narrow ? 280 : 348,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MemoryActions(model: model, actions: actions),
                            if (deeper) ...[MemoryGroupLabel(s.deeper), MemoryFollowUps(model: model, size: 15)],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

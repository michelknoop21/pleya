import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_button.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/tv/tv_nested_back_owner.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';

/// The search field and the inbox button in the Aanvragen sidebar.
///
/// REQ-SEARCH-ROUTE: this row used to get the desktop callbacks. DOWN asked
/// for the first search result and the first filter tab, neither of which is
/// ever built on TV, and still answered `handled`, so the key went nowhere; UP
/// had no handler at all; and Menu on an empty field moved the focus to the
/// top navigation instead of closing Aanvragen. The route is now the one the
/// main search page has: UP to the top navigation, DOWN to the first thing in
/// the content ([onFocusContent]), the same for the inbox button, and Menu on
/// an empty field left to the nested route that owns Back.
class SeerrTvSearchRow extends StatelessWidget {
  const SeerrTvSearchRow({
    super.key,
    required this.controller,
    required this.fieldFocusNode,
    required this.inboxFocusNode,
    required this.decoration,
    required this.onChanged,
    required this.onClear,
    required this.onFocusContent,
    required this.onExitUp,
    required this.onOpenRequests,
    required this.onFocusFilters,
    this.onLeaveGrid,
  });

  final TextEditingController controller;
  final FocusNode fieldFocusNode;
  final FocusNode inboxFocusNode;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Focuses the first card (or the state panel's action); false when the page
  /// has nothing focusable yet, in which case the focus stays where it is.
  final bool Function() onFocusContent;

  /// UP out of the row, and LEFT off the field: the top navigation.
  final VoidCallback onExitUp;
  final VoidCallback onOpenRequests;
  final VoidCallback onFocusFilters;
  final VoidCallback? onLeaveGrid;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AutomationNode(
            id: AutomationIds.seerrSearchField,
            role: 'field',
            focusNode: fieldFocusNode,
            // Rebuilt per keystroke so Menu knows whether there is text to
            // clear, the one case the field still answers Back itself.
            // The white ring of every other TV control, round the pill, while
            // the field holds the focus (review FIX 3). Without it the only
            // sign of focus was the text cursor.
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, fieldFocusNode]),
              builder: (context, _) => AnimatedContainer(
                key: const ValueKey('seerrSearchField.ring'),
                duration: FocusTheme.getAnimationDuration(context),
                curve: Curves.easeOutCubic,
                foregroundDecoration: FocusTheme.shapeFocusRing(
                  context,
                  isFocused: fieldFocusNode.hasFocus && InputModeTracker.isKeyboardMode(context),
                  shape: const StadiumBorder(),
                ),
                child: FocusableTextField(
                  controller: controller,
                  focusNode: fieldFocusNode,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  // The field is a stop on the route between the top navigation
                  // and the content, so arriving on it must not open the
                  // keyboard over the page; Select opens it.
                  tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.never,
                  // Submitting goes to the results, never a bare unfocus that
                  // strands the D-pad; with nothing to land on it stays put.
                  onEditingComplete: () => onFocusContent(),
                  onNavigateUp: onExitUp,
                  onNavigateLeft: onExitUp,
                  // Text is entered through the system keyboard on TV, so RIGHT
                  // is free to be a move: the inbox button below the field.
                  onNavigateRight: inboxFocusNode.requestFocus,
                  onNavigateDown: () => onFocusContent(),
                  onBack: _backFor(context),
                  decoration: decoration,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AutomationNode(
            id: AutomationIds.seerrSearchInbox,
            role: 'button',
            focusNode: inboxFocusNode,
            child: FocusableButton(
              focusNode: inboxFocusNode,
              onPressed: onOpenRequests,
              onBack: onLeaveGrid,
              onNavigateUp: fieldFocusNode.requestFocus,
              onNavigateDown: onFocusFilters,
              onNavigateRight: () => onFocusContent(),
              onNavigateLeft: fieldFocusNode.requestFocus,
              shape: const StadiumBorder(),
              dimWhenUnfocused: false,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: tk.surface,
                  foregroundColor: tk.text,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const AppIcon(Symbols.inbox_rounded, fill: 1),
                label: Text(t.seerr.myRequests, maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: onOpenRequests,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Menu on the field: clear the text first. On an empty field inside a TV
  /// nested route there is no handler, so the key reaches the shell and closes
  /// Aanvragen; outside one it steps up to the top navigation as before.
  VoidCallback? _backFor(BuildContext context) {
    if (controller.text.isNotEmpty) return onClear;
    if (onLeaveGrid != null) return onLeaveGrid;
    if (TvNestedBackOwner.of(context)) return null;
    return onExitUp;
  }
}

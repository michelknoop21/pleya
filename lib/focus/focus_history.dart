import 'package:flutter/widgets.dart';

/// Drops the directional traversal's history in the scope of [node].
///
/// The traversal keeps a history per scope and answers the opposite direction
/// by popping it. That is only right while the cards stand where the history
/// remembers them: after a move from outside the traversal or a new order, the
/// next LEFT would go back to a card rows away.
void clearFocusHistory(FocusNode node) {
  final context = node.context;
  final scope = node.nearestScope;
  if (context != null && scope != null) FocusTraversalGroup.maybeOf(context)?.invalidateScopeData(scope);
}

/// Moves the focus to [node] from outside the directional traversal, for a
/// surface that steps vertically by hand and leaves LEFT and RIGHT to it.
void requestFocusOutsideTraversal(FocusNode node) {
  clearFocusHistory(node);
  node.requestFocus();
}

/// Whether a list update moved cards the history may remember. Only cards
/// added at the tail, as a new page is, leave every position where it was.
bool focusPositionsChanged(List<String> previous, List<String> next) {
  if (identical(previous, next)) return false;
  if (next.length < previous.length) return true;
  for (var i = 0; i < previous.length; i++) {
    if (previous[i] != next[i]) return true;
  }
  return false;
}

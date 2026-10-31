import 'package:flutter/widgets.dart';

/// Moves the focus to [node] from outside the directional traversal.
///
/// LEFT and RIGHT go through that traversal, which keeps a history and answers
/// the opposite direction by popping it. The history belongs to the row just
/// left: kept, it sends the next LEFT back to a card rows away.
void requestFocusClearingDirectionalHistory(FocusNode node) {
  final context = node.context;
  final scope = node.nearestScope;
  if (context != null && scope != null) FocusTraversalGroup.maybeOf(context)?.invalidateScopeData(scope);
  node.requestFocus();
}

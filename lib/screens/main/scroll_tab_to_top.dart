import 'package:flutter/material.dart';

/// iOS convention: re-tapping the active tab scrolls its page back to the top.
///
/// [stackKey] sits on the destination `IndexedStack`; the [index]-th child is the
/// active tab. Its outermost vertical [Scrollable] is animated to offset 0, so
/// every tab works without exposing a controller.
void scrollTabToTop(GlobalKey stackKey, int index) {
  final stack = stackKey.currentContext as Element?;
  if (stack == null) return;
  Element? tab;
  var i = 0;
  stack.visitChildren((child) {
    if (i++ == index) tab = child;
  });
  if (tab == null) return;

  ScrollableState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is ScrollableState) {
      final state = element.state as ScrollableState;
      if (axisDirectionToAxis(state.widget.axisDirection) == Axis.vertical) {
        found = state;
        return;
      }
    }
    element.visitChildren(visit);
  }

  visit(tab!);
  final position = found?.position;
  if (position == null || !position.hasPixels || position.pixels <= position.minScrollExtent) return;
  position.animateTo(position.minScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
}

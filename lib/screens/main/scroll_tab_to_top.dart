import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// iOS convention: re-tapping the active tab scrolls its page back to the top.
///
/// [stackKey] sits on the destination `IndexedStack`; the [index]-th child is the
/// active tab. Its outermost vertical [Scrollable] is animated to offset 0, so
/// every tab works without exposing a controller.
void scrollTabToTop(GlobalKey stackKey, int index) {
  Element? stack = stackKey.currentContext as Element?;
  // IndexedStack is a StatelessWidget around the element that owns the
  // children, so walk down to the RenderIndexedStack before counting.
  while (stack != null && !(stack is RenderObjectElement && stack.renderObject is RenderIndexedStack)) {
    Element? only;
    stack.visitChildren((child) => only = child);
    stack = only;
  }
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

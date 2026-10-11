import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/focus/focusable_wrapper.dart';

/// The widget registered under automation [id] with [instance]: the same
/// handle Pleya Verify addresses it by.
Finder memoryId(String id, [String? instance]) => find.byWidgetPredicate(
  (widget) =>
      (widget is FocusableWrapper && widget.automationId == id && widget.automationInstance == instance) ||
      (widget is AutomationNode && widget.id == id && widget.instance == instance),
  description: 'automation id $id${instance == null ? '' : '[$instance]'}',
);

/// A control of the memory screens: `settings.memory.action[<instance>]`.
Finder memoryAction(String instance) => memoryId(AutomationIds.settingsMemoryAction, instance);

/// Whether the primary focus sits on, or inside, the control under [finder].
bool holdsFocus(WidgetTester tester, Finder finder) {
  final target = tester.element(finder.first);
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  var found = identical(focused, target);
  focused.visitAncestorElements((ancestor) {
    found = found || identical(ancestor, target);
    return !found;
  });
  return found;
}

/// Brings the control under [finder] into view and taps it. A chip row or a
/// list is wider and longer in the test font than on a device.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // The scroll that brings it into view, and the one a focused field started,
  // have to come to rest before the tap lands.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
}

/// `/v1/ui_tree` reports every id that was registered more than once under
/// `duplicates`, and hands the second and later registrations a positional
/// `#2`, `#3`, … suffix (see `AutomationRegistry.snapshot`). Both assertion
/// families look a node up by walking `declared` then `discovered` and taking
/// the first match, so an assertion on a duplicated id silently resolves
/// whichever node registered first.
///
/// That is not a measurement, it is a coin toss that reports PASS: registration
/// order follows widget-tree order, so adding a row above the subject, or
/// reordering two sections, moves the assertion to a different node without
/// anything failing. `books.search.layout` sat in exactly that state — the book
/// `dune` and the series `dune` shared `books.search.result[dune]` — and the
/// runner had no way to say so, because nothing here read `duplicates` at all.
///
/// Returns the message to fail with, or `null` when [id] is unambiguous. The
/// caller throws its own family's exception so the failure keeps reading like
/// the assertion that caused it.
String? ambiguousIdMessage(String id, Map<String, Object?> uiTree) {
  final duplicates = uiTree['duplicates'];
  if (duplicates is! List || !duplicates.contains(id)) return null;

  final occurrences = duplicates.where((other) => other == id).length + 1;
  return "'$id' is registered $occurrences times, so an assertion on it resolves whichever node happened to "
      'register first — give each one its own automation id (ui_tree lists it under `duplicates`)';
}

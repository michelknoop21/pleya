/// A parsed automation-id reference from a scenario file: either a bare
/// base id (`instance == null`) or an instance-suffixed one
/// (`library.grid.item[3]` -> `base: 'library.grid.item', instance: '3'`).
typedef AutomationIdRef = ({String base, String? instance});

final RegExp _instanceSuffix = RegExp(r'^(.+)\[(.+)\]$');

/// Parses the `id` / `id[instance]` grammar a scenario step's `id:` field
/// uses. This is not a second design: it mirrors the same bracket-suffix
/// form the app side already builds (see `AutomationNode._resolvedId` in
/// `lib/automation/automation_node.dart`, `'${id}[${instance}]'`) —
/// `test/automation_id_grammar_test.dart` round-trips the two to prove they
/// agree.
AutomationIdRef parseAutomationIdRef(String ref) {
  final match = _instanceSuffix.firstMatch(ref);
  if (match == null) return (base: ref, instance: null);
  return (base: match.group(1)!, instance: match.group(2)!);
}

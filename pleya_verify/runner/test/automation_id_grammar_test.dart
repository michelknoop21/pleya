import 'package:pleya_verify_runner/src/scenario/automation_id_grammar.dart';
import 'package:test/test.dart';

/// Builds the same combined string `AutomationNode._resolvedId`
/// (`lib/automation/automation_node.dart`) does:
/// `instance != null ? '$id[$instance]' : id`. This is not a copy of app
/// code (there's no shared package between the Flutter app and this plain-
/// Dart runner) — it is the parity check the Fase 5 plan asks for: round-
/// tripping through both sides of the same grammar must be lossless.
String _appSideResolvedId(String id, String? instance) => instance != null ? '$id[$instance]' : id;

void main() {
  group('parity with the app-side id[instance] grammar', () {
    for (final testCase in [
      ('library.grid.item', '3'),
      ('media-detail.episode-list.item', '0'),
      ('sidebar.library_row', 'library-abc123'),
      ('sidebar.rail', null),
      ('screen.main', null),
    ]) {
      final (base, instance) = testCase;
      test('round-trips ($base, $instance)', () {
        final combined = _appSideResolvedId(base, instance);
        final parsed = parseAutomationIdRef(combined);
        expect(parsed.base, base);
        expect(parsed.instance, instance);
      });
    }
  });

  test('an id containing brackets inside the instance is still parsed greedily to the last bracket pair', () {
    final parsed = parseAutomationIdRef('library.grid.item[a[b]');
    expect(parsed.base, 'library.grid.item[a');
    expect(parsed.instance, 'b');
  });
}

import 'dart:io';

import 'package:pleya_verify_runner/src/impact/resolver.dart';
import 'package:test/test.dart';

void main() {
  // The real, committed map — proves the working mappings the plan names
  // explicitly, not a test double that could drift from them.
  final map = ImpactMap.fromFile(File('../impact-map.yaml'));

  test('discover_screen.dart selects discover scenarios', () {
    final result = resolveImpact(['lib/screens/discover_screen.dart'], map);
    expect(result.tags, contains('discover'));
    expect(result.unmatchedPaths, isEmpty);
  });

  test('lib/focus/* selects tvOS-focus/navigation scenarios', () {
    final result = resolveImpact(['lib/focus/dpad_navigator.dart'], map);
    expect(result.tags, containsAll(['tvos-focus', 'navigation']));
  });

  test('a nested path under lib/focus/** still matches the ** glob', () {
    final result = resolveImpact(['lib/focus/nested/dir/file.dart'], map);
    expect(result.tags, containsAll(['tvos-focus', 'navigation']));
  });

  test('media_detail_screen.dart selects media-detail scenarios', () {
    final result = resolveImpact(['lib/screens/media_detail_screen.dart'], map);
    expect(result.tags, contains('media-detail'));
  });

  test('an unrecognized path never yields an empty selection — it falls back to default_suite', () {
    final result = resolveImpact(['lib/services/some_new_thing.dart'], map);
    expect(result.tags, isNotEmpty);
    expect(result.tags, contains(map.defaultSuite));
    expect(result.unmatchedPaths, contains('lib/services/some_new_thing.dart'));
  });

  test('an ignored path contributes no tags and is reported with its reason', () {
    final result = resolveImpact(['test/screens/discover_screen_test.dart'], map);
    expect(result.tags, isEmpty);
    expect(result.ignoredPaths, contains('test/screens/discover_screen_test.dart'));
    expect(result.ignoredPaths['test/screens/discover_screen_test.dart'], isNotEmpty);
  });

  test('a generated .g.dart file is ignored', () {
    final result = resolveImpact(['lib/models/foo.g.dart'], map);
    expect(result.tags, isEmpty);
    expect(result.ignoredPaths.keys, contains('lib/models/foo.g.dart'));
  });

  test('mixed changed paths union their tags and keep per-path attribution', () {
    final result = resolveImpact(['lib/screens/discover_screen.dart', 'lib/screens/media_detail_screen.dart'], map);
    expect(result.tags, containsAll(['discover', 'media-detail']));
    expect(result.matchedBy['lib/screens/discover_screen.dart'], ['discover']);
    expect(result.matchedBy['lib/screens/media_detail_screen.dart'], ['media-detail']);
  });

  test('an ignored entry without a reason fails to parse', () {
    expect(
      () => ImpactMap.fromYaml('default_suite: smoke\nrules: []\nignored:\n  - pattern: "**/*.g.dart"\n'),
      throwsA(isA<ImpactMapParseException>()),
    );
  });

  test('missing default_suite fails to parse', () {
    expect(() => ImpactMap.fromYaml('rules: []\n'), throwsA(isA<ImpactMapParseException>()));
  });
}

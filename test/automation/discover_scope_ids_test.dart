import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/screens/discover_scope.dart';

/// Home, Series and Films are one screen with a type filter (DEC-094), and the
/// shell's `IndexedStack` builds every child, so on a phone all three are
/// mounted at once. They used to declare the same three ids —
/// `screen.discover`, `discover.hero`, `discover.hero.play` — with two
/// consequences a scenario cannot work around:
///
///  * `/v1/ui_tree` reported them under `duplicates` with `#2`/`#3` suffixes,
///    so every geometry assertion on a Home node resolved an ambiguous id.
///    Observed live in the bundle for `books.all.layout`:
///    `duplicates: ['discover.hero', 'discover.hero.play']`.
///  * `handleAutomationOpen`'s `firstWhereOrNull` answered readiness from
///    whichever instance registered first rather than the visible one.
void main() {
  test('every scope gets its own screen id, hero and play button', () {
    final ids = <String>{};
    for (final scope in DiscoverScope.values) {
      ids.addAll([
        AutomationIds.screenForScope(scope),
        AutomationIds.heroForScope(scope),
        AutomationIds.heroPlayForScope(scope),
      ]);
    }

    expect(
      ids.length,
      DiscoverScope.values.length * 3,
      reason: 'three mountings of one screen need three sets of ids, or ui_tree calls them duplicates',
    );
  });

  test('Home keeps the ids the existing scenarios address', () {
    // `discover.hero.layout.yaml` and `discover.hero.layout.macos.yaml` assert
    // on these by name. Adding ids for the filtered landings must not rename
    // the unfiltered one out from under them.
    expect(AutomationIds.screenForScope(DiscoverScope.all), AutomationIds.screenDiscover);
    expect(AutomationIds.heroForScope(DiscoverScope.all), AutomationIds.discoverHero);
    expect(AutomationIds.heroPlayForScope(DiscoverScope.all), AutomationIds.discoverHeroPlay);
  });

  test('all six live in the catalogue GET /v1/automation_ids serves', () {
    final catalogued = {for (final entry in AutomationIds.catalog()) entry['id'] as String};

    for (final scope in DiscoverScope.values) {
      for (final id in [
        AutomationIds.screenForScope(scope),
        AutomationIds.heroForScope(scope),
        AutomationIds.heroPlayForScope(scope),
      ]) {
        expect(
          catalogued,
          contains(id),
          reason: '$id is declared by a widget but not addressable: `verify validate` would reject a scenario using it',
        );
      }
    }
  });

  /// The three tests above are about the ids; this is about the one screen
  /// that has to use them. Read off the source, because `DiscoverScreen` needs
  /// nine providers to mount and the assertion is one line of wiring — the
  /// same shape as `test/no_bare_text_field_test.dart`.
  test('DiscoverScreen derives all three ids from its scope', () {
    final source = File('lib/screens/discover_screen.dart').readAsStringSync();

    for (final call in ['AutomationIds.screenForScope(widget.scope)', 'AutomationIds.heroForScope(widget.scope)']) {
      expect(source, contains(call), reason: 'a scope-independent id makes all three landings the same node again');
    }
    expect(source, contains('AutomationIds.heroPlayForScope(widget.scope)'));
    for (final constant in ['AutomationIds.screenDiscover', 'AutomationIds.discoverHero']) {
      expect(
        source,
        isNot(contains(constant)),
        reason: '$constant names the Home mounting only; the screen must ask for its own scope',
      );
    }
  });

  test('an id a widget declares stays inside a known domain', () {
    // The catalogue's domains are a closed set. A per-scope id has to extend
    // `discover.`/`screen.`, not open `series.` as a domain of its own.
    for (final scope in DiscoverScope.values) {
      expect(AutomationIds.screenForScope(scope), startsWith('screen.'));
      expect(AutomationIds.heroForScope(scope), startsWith('discover.'));
      expect(AutomationIds.heroPlayForScope(scope), startsWith('discover.'));
    }
  });
}

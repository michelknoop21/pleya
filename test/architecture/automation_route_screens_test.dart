import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `_routeScreens` in `lib/automation/automation_signin.dart` is a closed list,
/// and a second place that has to be edited whenever a screen gains a route
/// opener. Nothing connected the two, so the two ways of adding a route drifted
/// apart in silence: golden 09's screen registered its opener in
/// `BooksHomeScreen.initState` and was left out of the list, and `POST /v1/open`
/// answered
///
/// ```
/// unsupported screen "screen.book_text_search" — no nav-tab mapping and no
/// route opener registered for it
/// ```
///
/// which is a scenario that cannot run, found by running it rather than by
/// anything in the repository. This is the check that would have said so first.
///
/// It reads source rather than calling into the app for the reason
/// `automation_ids_yaml_test.dart` reads a file: `_routeScreens` is private and
/// the registrations live in `initState`, so there is no runtime moment at which
/// both sets exist together. Both directions are asserted — a name in the list
/// with nothing registering it is a screen `/v1/open` waits out its timeout for.
void main() {
  test('_routeScreens holds exactly the screens something registers an opener for', () {
    final ids = _idValues(File('lib/automation/automation_ids.dart').readAsStringSync());

    final registered = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final match in _registration.allMatches(file.readAsStringSync())) {
        final name = match.group(1)!;
        final value = ids[name];
        expect(value, isNotNull, reason: 'registerRouteOpener names AutomationIds.$name, which does not exist');
        registered.add(value!);
      }
    }

    final signin = File('lib/automation/automation_signin.dart').readAsStringSync();
    final block = RegExp(r'const Set<String> _routeScreens = \{(.*?)\};', dotAll: true).firstMatch(signin);
    expect(block, isNotNull, reason: '_routeScreens is no longer a const set literal in automation_signin.dart');
    final listed = {
      for (final match in RegExp(r'AutomationIds\.(\w+)').allMatches(block!.group(1)!)) ids[match.group(1)!]!,
    };

    expect(
      registered.difference(listed),
      isEmpty,
      reason:
          'these screens register a route opener but are not in _routeScreens, so POST /v1/open rejects them: '
          '${registered.difference(listed).toList()..sort()}',
    );
    expect(
      listed.difference(registered),
      isEmpty,
      reason:
          'these screens are in _routeScreens but nothing registers an opener, so POST /v1/open waits out its '
          'timeout on them: ${listed.difference(registered).toList()..sort()}',
    );
  });
}

/// `registerRouteOpener(AutomationIds.screenBooksToc, _openCanonicalToc)`, and
/// the same call wrapped over two lines — which is how `dart format` writes the
/// longer ones.
final RegExp _registration = RegExp(r'registerRouteOpener\(\s*AutomationIds\.(\w+)');

/// `static const String screenBooksToc = 'screen.books_toc';` → name to value.
Map<String, String> _idValues(String source) => {
  for (final match in RegExp(r"static const String (\w+) = '([^']+)';").allMatches(source))
    match.group(1)!: match.group(2)!,
};

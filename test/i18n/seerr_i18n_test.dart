import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Dutch UI showed "Search for a movie or show to request" because the key
/// only ever existed in the base locale, and slang's fallback_strategy is
/// base_locale. Nothing crashes when that happens, so only a check like this
/// catches it.
void main() {
  Map<String, dynamic> seerrSection(String locale) {
    final file = File('lib/i18n/$locale.i18n.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return (json['seerr'] as Map).cast<String, dynamic>();
  }

  test('every English seerr string has a Dutch counterpart', () {
    final en = seerrSection('en');
    final nl = seerrSection('nl');

    expect(en.keys.where((k) => !nl.containsKey(k)), isEmpty, reason: 'these fall back to English in the Dutch UI');
  });

  test('the request search placeholder is actually translated', () {
    final en = seerrSection('en');
    final nl = seerrSection('nl');

    expect(nl['searchPlaceholder'], isNotNull);
    expect(nl['searchPlaceholder'], isNot(en['searchPlaceholder']));
  });

  test('no Dutch seerr string is a verbatim copy of the English one', () {
    final en = seerrSection('en');
    final nl = seerrSection('nl');

    // A handful are the same word in both languages and stay that way.
    const sharedWords = {'fourKBadge', 'percentMatch', 'server', 'cast'};
    final copies = en.keys.where((k) => !sharedWords.contains(k) && nl[k] == en[k]);

    expect(copies, isEmpty);
  });
}

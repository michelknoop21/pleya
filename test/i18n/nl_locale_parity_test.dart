import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ROW1q: het Home-aanpaspaneel stond op een Nederlands toestel volledig in het
/// Engels. Geen enkele string was hardcoded — `unifiedCatalog.homeRows` stond in
/// `en.i18n.json` en ontbrak in `nl.i18n.json`, en `fallback_strategy:
/// base_locale` maakt daar Engelse tekst van zonder dat er iets omvalt.
///
/// Dat is niet met vertalen alleen af. Zonder bewaking komt de volgende lading
/// er even stil weer in, en dat is precies wat er sinds fase 9 is gebeurd:
/// `phase9_shared_keys_test.dart` bewaakt elf met de hand gekozen sleutels over
/// zestien talen, en al het andere kon ongemerkt uit `nl` wegblijven.
///
/// Deze test is de andere kant daarvan: hij vergelijkt `nl` **volledig** met de
/// basislocale, tegen een baseline van wat er op 7 september 2026 al ontbrak.
/// Die baseline mag alleen krimpen. Een nieuwe Engelse sleutel zonder
/// Nederlandse tegenhanger valt er meteen uit, en een vertaalde sleutel die nog
/// in de lijst staat ook — anders zou de lijst stilzwijgend achterlopen op zijn
/// eigen onderwerp.
///
/// Bewust alleen `nl`. De veertien andere talen dragen elk hun eigen
/// historische achterstand, en die in één test bevriezen zou een getal
/// vastleggen in plaats van een gebrek benoemen. `nl` is de taal waarin de app
/// gebruikt wordt en waarin de gaten gemeld worden.
void main() {
  /// What was missing in `nl` after ROW1q closed on 7 September 2026 has since
  /// been translated in full (I18N1-4 and I18N6, the tvOS T1 correction
  /// round). The set stays declared, empty, rather than deleted: the next gap
  /// a new English-only key opens has somewhere to be named the moment it is
  /// found, instead of the test file needing surgery first.
  ///
  /// Every entry here is a string a Dutch user would see in English today.
  /// This is a worklist, not an exceptions register; it belongs empty.
  const knownGaps = <String>{};

  Map<String, dynamic> localeJson(String locale) =>
      jsonDecode(File('lib/i18n/$locale.i18n.json').readAsStringSync()) as Map<String, dynamic>;

  /// Elk blad in [json], als gepunte paden. Objecten dalen af, alles wat geen
  /// object is telt als blad: ook een lijst of een getal is iets dat vertaald
  /// had moeten zijn.
  List<String> leaves(Map<String, dynamic> json, [String prefix = '']) {
    final out = <String>[];
    for (final entry in json.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        out.addAll(leaves(value, path));
      } else {
        out.add(path);
      }
    }
    return out;
  }

  bool hasPath(Map<String, dynamic> json, String path) {
    Object? node = json;
    for (final segment in path.split('.')) {
      if (node is! Map) return false;
      if (!node.containsKey(segment)) return false;
      node = node[segment];
    }
    return true;
  }

  test('nl carries every key the base locale declares, except the known gaps', () {
    final en = localeJson('en');
    final nl = localeJson('nl');

    final missing = [
      for (final path in leaves(en))
        if (!hasPath(nl, path)) path,
    ];
    final unexpected = missing.where((p) => !knownGaps.contains(p)).toList()..sort();

    expect(
      unexpected,
      isEmpty,
      reason:
          'these keys exist in en.i18n.json and not in nl.i18n.json, so a Dutch user sees '
          'English through fallback_strategy: base_locale. Translate them, or add them to '
          'knownGaps with a reason.',
    );
  });

  test('the known-gap list has not gone stale', () {
    final en = localeJson('en');
    final nl = localeJson('nl');

    final stale = [
      for (final path in knownGaps)
        if (!hasPath(en, path) || hasPath(nl, path)) path,
    ]..sort();

    expect(
      stale,
      isEmpty,
      reason:
          'these are listed as gaps but are either translated in nl or gone from en. Remove '
          'them from knownGaps so the list keeps meaning what it says.',
    );
  });
}

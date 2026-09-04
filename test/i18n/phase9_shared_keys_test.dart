import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fase 9 zette elf nieuwe gedeelde strings in `en` en liet ze veertien talen
/// lang op de Engelse fallback staan. Met `fallback_strategy: base_locale` in
/// slang.yaml genereert slang dan nog steeds zestien outputbestanden, draait
/// codegen zonder klacht en toont de app gewoon Engels. Niets valt om, dus dat
/// viel pas op bij het nalopen van de fase, niet bij een test.
///
/// Bewust géén volledige key-parity over alle zestien bestanden: die missen elk
/// nog hele secties aan historische debt, en daar gaat deze test niet over. Dit
/// is een expliciete lijst die meegroeit zodra er een nieuwe gedeelde sleutel
/// bij komt.
void main() {
  const sharedKeys = <String>[
    'notices.playbackFileUnavailableTitle',
    'notices.playbackFileUnavailableBody',
    'sourcePicker.detailLoadFailedTitle',
    'tvNavigation.attentionRequired',
    'tvContextMenu.title',
    'tvContextMenu.menuSemantics',
    'tvContextMenu.noUsableSource',
    'tvContextMenu.doneOnAll',
    'tvContextMenu.doneOnSome',
    'tvContextMenu.doneOnSomeNoRetry',
    'tvContextMenu.failed',
  ];

  const locales = <String>[
    'en',
    'bg',
    'da',
    'de',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'nb',
    'nl',
    'pl',
    'pt',
    'ru',
    'sv',
    'zh',
  ];

  /// Sleutels die in een taal terecht hetzelfde woord zijn als in het Engels.
  /// Staat hier expliciet, zodat een echte kopieerfout niet meelift op een
  /// uitzondering die iemand ooit heeft toegestaan.
  const sameWordAsEnglish = <String, Set<String>>{
    'fr': {'tvContextMenu.title'},
  };

  Map<String, dynamic> localeJson(String locale) {
    final file = File('lib/i18n/$locale.i18n.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Resolvet een gepunt pad en geeft null zodra een tussenliggend niveau
  /// ontbreekt of geen object is. Een ontbrekende sectie telt dus even zwaar
  /// als een ontbrekende sleutel: allebei leveren ze de Engelse fallback op.
  Object? valueAt(Map<String, dynamic> json, String path) {
    Object? node = json;
    for (final segment in path.split('.')) {
      if (node is! Map) return null;
      node = node[segment];
    }
    return node;
  }

  test('every shared Phase-9 key is present in all 16 locale sources', () {
    final missing = <String>[];

    for (final key in sharedKeys) {
      for (final locale in locales) {
        if (valueAt(localeJson(locale), key) is! String) missing.add('$locale: $key');
      }
    }

    expect(missing, isEmpty, reason: 'these render English through fallback_strategy: base_locale');
  });

  test('no shared Phase-9 key is declared empty', () {
    final blank = <String>[];

    for (final key in sharedKeys) {
      for (final locale in locales) {
        final value = valueAt(localeJson(locale), key);
        if (value is String && value.trim().isEmpty) blank.add('$locale: $key');
      }
    }

    // clean_translations.py vult ontbrekende sleutels met "". Aanwezig is dan
    // niet hetzelfde als vertaald.
    expect(blank, isEmpty, reason: 'an empty string is a placeholder, not a translation');
  });

  test('no shared Phase-9 key is an unintended copy of the English one', () {
    final en = localeJson('en');
    final copies = <String>[];

    for (final key in sharedKeys) {
      final english = valueAt(en, key);
      for (final locale in locales.where((l) => l != 'en')) {
        if (sameWordAsEnglish[locale]?.contains(key) ?? false) continue;
        if (valueAt(localeJson(locale), key) == english) copies.add('$locale: $key');
      }
    }

    expect(copies, isEmpty);
  });
}

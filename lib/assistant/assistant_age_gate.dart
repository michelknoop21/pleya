/// Age gate for Big P's picks for children. Deliberately lenient: one rating
/// decides, the device region's first, then the US one, then whatever the own
/// server gave. A title without any rating passes only on a family genre.
library;

import 'package:flutter/widgets.dart';

import 'assistant_title_facts.dart';

/// The device region (`NL`, `US`, ...), US when the locale names none.
String assistantRegion() => WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase() ?? 'US';

/// The rating that decided, as the model sees it: `NL 12`.
typedef AgeRating = ({int age, String reason});

class AgeGate {
  const AgeGate._();

  /// Rating to minimum age per country. Codes are upper case.
  static const _tables = <String, Map<String, int>>{
    'NL': {'AL': 0, '6': 6, '9': 9, '12': 12, '14': 14, '16': 16, '18': 18},
    'BE': {'AL': 0, 'KT': 0, 'KNT': 0, 'ENA': 16, '6': 6, '9': 9, '12': 12, '14': 14, '16': 16, '18': 18},
    'DE': {'0': 0, '6': 6, '12': 12, '16': 16, '18': 18},
    'GB': {'U': 0, 'PG': 8, '12': 12, '12A': 12, '15': 15, '18': 18, 'R18': 18},
    'FR': {'U': 0, 'TP': 0, '10': 10, '12': 12, '16': 16, '18': 18},
    'US': {
      'G': 0,
      'PG': 8,
      'PG-13': 13,
      'R': 17,
      'NC-17': 18,
      'TV-Y': 0,
      'TV-Y7': 7,
      'TV-G': 0,
      'TV-PG': 10,
      'TV-14': 14,
      'TV-MA': 17,
    },
  };

  /// Genre names (TMDB in English and Dutch, server names) and TMDB genre ids
  /// that let an unrated title through.
  static const _familyGenres = {
    'animation',
    'animatie',
    'family',
    'familie',
    'kids',
    'kinderen',
    'children',
    '16',
    '10751',
    '10762',
  };

  static final _number = RegExp(r'\d+');

  /// Age for [code] as rated in [country] (null: country unknown). A
  /// Plex-style `nl/12` names its own country. An unknown code with a number
  /// in it counts as that number; anything else as no rating.
  static int? ageFor(String code, [String? country]) {
    var c = code.trim().toUpperCase();
    var land = country;
    if (c.length > 3 && c[2] == '/') {
      land = c.substring(0, 2);
      c = c.substring(3).trim();
    }
    if (c.startsWith('FSK')) c = c.substring(3).trim();
    final own = _tables[land]?[c];
    if (own != null) return own;
    if (land == null || !_tables.containsKey(land)) {
      for (final table in [_tables['US']!, ..._tables.values]) {
        if (table[c] case final age?) return age;
      }
    }
    final n = _number.firstMatch(c)?.group(0);
    return n == null ? null : int.parse(n);
  }

  /// The deciding rating: [region]'s, else the US one, else the server's.
  static AgeRating? rating(TitleFacts facts, String region) {
    final certs = facts.certifications;
    final serverKeys = [
      TitleFacts.anyCountry,
      for (final c in certs.keys)
        if (c != TitleFacts.anyCountry && facts.origin['cert:$c'] == 'server') c,
    ];
    for (final c in {region, 'US', ...serverKeys}) {
      final code = certs[c];
      if (code == null) continue;
      final age = ageFor(code, c == TitleFacts.anyCountry ? null : c);
      if (age != null) return (age: age, reason: c == TitleFacts.anyCountry ? 'server $code' : '$c $code');
    }
    return null;
  }

  /// Minimum age per [rating], null when no rating says anything.
  static int? minimumAge(TitleFacts facts, String region) => rating(facts, region)?.age;

  static bool _familyGenre(TitleFacts facts) => facts.genres.any((g) => _familyGenres.contains(g.trim().toLowerCase()));

  /// Whether a child of [youngestAge] may see it.
  static bool allows(TitleFacts facts, int youngestAge, String region) {
    final age = minimumAge(facts, region);
    return age == null ? _familyGenre(facts) : youngestAge >= age;
  }

  /// Why [allows] decided as it did, for the model.
  static String reason(TitleFacts facts, String region) =>
      rating(facts, region)?.reason ?? (_familyGenre(facts) ? 'unrated, family genre' : 'unrated');
}

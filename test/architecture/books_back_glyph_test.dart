import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every pushed page in the books set leaves by the same glyph.
///
/// The approved goldens all draw the iOS chevron: `02a` and `04a` as clearly as
/// `05a`, `06a` and `09a`. Boekdetail, de inhoudsopgave and Zoeken in boek were
/// built with it; Alle boeken and Boeken zoeken carried Material's full arrow
/// instead, and nothing said so — a glyph is not geometry, so no layout
/// assertion could see it and the difference only shows up beside the golden.
///
/// Source rather than a pumped screen, the same shape
/// `no_bare_text_field_test.dart` uses: this is a rule about every file in the
/// set, including the one someone adds next month.
void main() {
  test('no books screen leaves by Material\'s full arrow', () {
    final offenders = <String>[];
    for (final file in Directory('lib/screens/books').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      // `arrow_back_ios_new_rounded` contains `arrow_back_`, so the plain arrow
      // has to be matched on its own name and not as a prefix.
      if (RegExp(r'Symbols\.arrow_back_rounded\b').hasMatch(source)) offenders.add(file.path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these screens draw Symbols.arrow_back_rounded where the golden draws a chevron; use '
          'Symbols.arrow_back_ios_new_rounded with size 22, fill 0, weight 500: ${offenders..sort()}',
    );
  });

  test('the five pushed books pages all carry the chevron', () {
    const screens = [
      'lib/screens/books/all_books_screen.dart',
      'lib/screens/books/books_search_screen.dart',
      'lib/screens/books/book_detail_screen.dart',
      'lib/screens/books/books_toc_screen.dart',
      'lib/screens/books/book_text_search_screen.dart',
    ];
    for (final path in screens) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('Symbols.arrow_back_ios_new_rounded, size: 22, fill: 0, weight: 500'),
        isTrue,
        reason: '$path no longer draws the set\'s own back glyph',
      );
    }
  });
}

/// The language picker behind the four global rows of mockup 31 A.
///
/// A dialog rather than a page, for the same reason every other settings value
/// in this product is one: a nested page inside a nested TV route would push on
/// the profile navigator and take the top bar with it (PB-1), while a dialog
/// composes over whatever opened it on every platform alike.
///
/// The list is lazily built. There are roughly 180 languages, and the shared
/// [showSelectionDialog] lays its options out in a `Column` inside a
/// `SingleChildScrollView` — every row built before the first frame. That is
/// fine for the six-option settings it was written for and is not fine here,
/// least of all on an Apple TV.
library;

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/language_codes.dart';
import '../../../widgets/focusable_list_tile.dart';

/// What one row of the picker means.
///
/// Three states, not a nullable string: "no preference", "the original
/// language" and a concrete language are three different intentions, and the
/// audio row can express all three (DEC-096 lid 3).
class LanguageChoiceValue {
  const LanguageChoiceValue._(this.code, this.isOriginal);

  /// A concrete language, or null for "no preference".
  factory LanguageChoiceValue.code(String? code) => LanguageChoiceValue._(code, false);

  static const LanguageChoiceValue original = LanguageChoiceValue._(null, true);
  static const LanguageChoiceValue none = LanguageChoiceValue._(null, false);

  final String? code;
  final bool isOriginal;

  @override
  bool operator ==(Object other) =>
      other is LanguageChoiceValue && other.code == code && other.isOriginal == isOriginal;

  @override
  int get hashCode => Object.hash(code, isOriginal);
}

/// The display name for a stored language code, or null when there is none.
///
/// Null in, null out: the row then reads "Geen voorkeur", which is what an
/// empty preference means. An unknown code comes back as itself rather than as
/// a blank, so a value written by a newer build stays legible.
String? languageDisplayName(String? code) {
  if (code == null || code.isEmpty) return null;
  return LanguageCodes.getLanguageName(code) ?? code;
}

/// Ask for one language. Returns null when the viewer backed out.
Future<LanguageChoiceValue?> showLanguagePickerDialog(
  BuildContext context, {
  required String title,
  required LanguageChoiceValue current,
  bool allowOriginal = false,
}) {
  final languages = LanguageCodes.getAllLanguages();
  final options = <LanguageChoiceValue>[
    LanguageChoiceValue.none,
    if (allowOriginal) LanguageChoiceValue.original,
    for (final language in languages) LanguageChoiceValue.code(language.code),
  ];
  final labels = <LanguageChoiceValue, String>{
    LanguageChoiceValue.none: t.languageSettings.noPreference,
    if (allowOriginal) LanguageChoiceValue.original: t.languageSettings.originalLanguage,
    for (final language in languages) LanguageChoiceValue.code(language.code): language.name,
  };
  // The stored code may be a three-letter or regional variant that is not in
  // the list built above ("eng", "pt-BR"). Showing it as its own row keeps the
  // current value visible and selectable instead of leaving the dialog with no
  // marked row at all.
  if (!options.contains(current)) {
    options.insert(allowOriginal ? 2 : 1, current);
    labels[current] = languageDisplayName(current.code) ?? t.languageSettings.noPreference;
  }

  final selectedIndex = options.indexOf(current);

  return showScopedDialog<LanguageChoiceValue>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 24),
      content: SizedBox(
        width: 420,
        height: 420,
        child: ListView.builder(
          // Starts at the current value rather than at "Aymara": with 180 rows
          // the alternative is scrolling to find out what is set.
          controller: ScrollController(initialScrollOffset: selectedIndex <= 0 ? 0 : (selectedIndex - 2) * 56.0),
          itemCount: options.length,
          itemBuilder: (context, index) {
            final option = options[index];
            final selected = option == current;
            return FocusableListTile(
              key: ValueKey('${option.isOriginal}:${option.code}'),
              leading: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? Theme.of(dialogContext).colorScheme.primary : null,
              ),
              title: Text(labels[option] ?? ''),
              selected: selected,
              autofocus: selected,
              onTap: () => Navigator.pop(dialogContext, option),
            );
          },
        ),
      ),
    ),
  );
}

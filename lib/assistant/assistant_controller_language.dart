part of 'assistant_controller.dart';

/// The app language as the model's system prompt names it.
String assistantLanguageName() => switch (LocaleSettings.currentLocale) {
  AppLocale.nl => 'Dutch',
  AppLocale.de => 'German',
  AppLocale.fr => 'French',
  AppLocale.es => 'Spanish',
  AppLocale.it => 'Italian',
  AppLocale.da => 'Danish',
  AppLocale.nb => 'Norwegian',
  AppLocale.sv => 'Swedish',
  AppLocale.pl => 'Polish',
  AppLocale.pt => 'Portuguese',
  AppLocale.ru => 'Russian',
  AppLocale.bg => 'Bulgarian',
  AppLocale.ja => 'Japanese',
  AppLocale.ko => 'Korean',
  AppLocale.zh => 'Chinese',
  AppLocale.en => 'English',
};

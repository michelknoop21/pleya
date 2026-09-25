import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/setting_tile.dart';
import '../settings_utils.dart';

/// The app-language row on the Appearance page.
///
/// VIS-0925-C: this was a bare `ListTile`, the one row on the page without
/// [SettingRowFocus]. On TV it therefore had no focus treatment of its own and
/// a second focus stop inside the tile. It is now a [SettingNavigationTile],
/// the same row, focus, badge and chevron as every other settings row.
class AppLanguageRow extends StatelessWidget {
  const AppLanguageRow({super.key, required this.onRestart});

  /// Called after a new language is written; the app restarts to apply it.
  final VoidCallback onRestart;

  Future<void> _pick(BuildContext context) async {
    final value = await showSelectionDialog<AppLocale>(
      context: context,
      title: t.settings.language,
      options: AppLocale.values
          .map((locale) => DialogOption(value: locale, title: appLocaleDisplayName(locale)))
          .toList(),
      currentValue: LocaleSettings.currentLocale,
    );
    if (value == null) return;
    await SettingsService.instance.write(SettingsService.appLocale, value);
    unawaited(LocaleSettings.setLocale(value));
    if (context.mounted) {
      context.read<MultiServerProvider>().serverManager.updatePlexLanguage(value.languageCode);
    }
    if (context.mounted) onRestart();
  }

  @override
  Widget build(BuildContext context) => SettingNavigationTile(
    icon: Symbols.language_rounded,
    title: t.settings.language,
    subtitle: appLocaleDisplayName(LocaleSettings.currentLocale),
    onTap: () => _pick(context),
  );
}

/// A locale's own name for itself.
String appLocaleDisplayName(AppLocale locale) => switch (locale) {
  AppLocale.en => 'English',
  AppLocale.sv => 'Svenska',
  AppLocale.fr => 'Français',
  AppLocale.it => 'Italiano',
  AppLocale.nl => 'Nederlands',
  AppLocale.de => 'Deutsch',
  AppLocale.zh => '中文',
  AppLocale.ko => '한국어',
  AppLocale.es => 'Español',
  AppLocale.pt => 'Português',
  AppLocale.ja => '日本語',
  AppLocale.ru => 'Русский',
  AppLocale.pl => 'Polski',
  AppLocale.da => 'Dansk',
  AppLocale.nb => 'Norsk bokmål',
  AppLocale.bg => 'Български',
};

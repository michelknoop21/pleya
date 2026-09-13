/// Instellingen ▸ Downloads (northstar 14): storage location, WiFi-only, and
/// auto-remove watched. Promoted out of the flat settings list into its own
/// screen — this covers that the two preference switches actually read and
/// write [SettingsService], the location dialog no longer being a duplicate
/// of `settings_utils.dart`'s shared implementation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/downloads_settings_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.runAsync(() => SettingsService.getInstance());
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: const DownloadsSettingsScreen(),
        ),
      ),
    );
    // Not `pumpAndSettle`: the location row's `getCurrentDownloadPathDisplay`
    // future resolves against a real platform channel with no test mock
    // registered, so it never settles here — a couple of frames is enough for
    // the switches, which are what this test actually checks.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the WiFi-only and auto-remove switches, off by default', (tester) async {
    await pump(tester);

    expect(find.text(t.settings.downloadOnWifiOnly), findsOneWidget);
    expect(find.text(t.settings.autoRemoveWatchedDownloads), findsOneWidget);
    final wifiSwitch = tester.widget<SwitchListTile>(
      find.ancestor(of: find.text(t.settings.downloadOnWifiOnly), matching: find.byType(SwitchListTile)),
    );
    expect(wifiSwitch.value, isFalse);
  });

  testWidgets('toggling WiFi-only writes the preference', (tester) async {
    await pump(tester);

    await tester.tap(find.text(t.settings.downloadOnWifiOnly));
    await tester.pump();

    expect(SettingsService.instance.read(SettingsService.downloadOnWifiOnly), isTrue);
    final wifiSwitch = tester.widget<SwitchListTile>(
      find.ancestor(of: find.text(t.settings.downloadOnWifiOnly), matching: find.byType(SwitchListTile)),
    );
    expect(wifiSwitch.value, isTrue);
  });

  testWidgets('toggling auto-remove writes the preference', (tester) async {
    await pump(tester);

    await tester.tap(find.text(t.settings.autoRemoveWatchedDownloads));
    await tester.pump();

    expect(SettingsService.instance.read(SettingsService.autoRemoveWatchedDownloads), isTrue);
  });
}

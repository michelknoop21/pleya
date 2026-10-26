import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/screens/settings/library_home_settings_screen.dart';
import 'package:pleya/screens/settings/local_library_settings_screen.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/settings_section.dart';
import '../../services/local_library/local_library_store_test.dart' show library, film;

void main() {
  testWidgets('confirmed clear offers a separate explicit refill choice and stays off when dismissed', (tester) async {
    late Directory root;
    late LocalLibraryProvider provider;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('pleya-library-ui-test-');
      final store = LocalLibraryStore(root);
      await store.load();
      await store.saveLibrary(library, [film('cached')], complete: true);
      provider = LocalLibraryProvider(
        profileId: 'fixture',
        directory: root,
        librariesForSync: () => [library],
        clientFor: (_) => null,
        mayReadServer: (_) => true,
        mayReadLibrary: (_) => true,
        networkConnected: () => false,
        wifiConnected: () => false,
        changes: ChangeNotifier(),
      );
      await provider.ready;
    });
    addTearDown(() async {
      provider.dispose();
      await root.delete(recursive: true);
    });
    LocaleSettings.setLocaleSync(AppLocale.en);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(theme: monoTheme(dark: true), home: const LocalLibrarySettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Store library in advance'), findsOneWidget);
    await tester.ensureVisible(find.text('Clear local library'));
    await tester.tap(find.text('Clear local library'));
    await tester.pumpAndSettle();
    expect(provider.items, isNotEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear local library'));
    for (var i = 0; i < 50 && find.text('Local library cleared').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Turn prefetch off'), findsOneWidget);
    expect(find.text('Fetch library again'), findsOneWidget);
    expect(provider.items, isEmpty);
    expect(provider.enabled, isFalse);
    await tester.tap(find.text('Turn prefetch off'));
    await tester.pumpAndSettle();
    expect(provider.enabled, isFalse);
    await tester.runAsync(() async {
      final reopened = LocalLibraryStore(root);
      await reopened.load();
      expect(reopened.enabled, isFalse);
      expect(reopened.items, isEmpty);
    });
  });

  // A-24b (series `ios/03-bibliotheek-home-01`): Bibliotheek & Home shows the
  // local library's own rows inline, the clear in the destructive ink and
  // behind the same confirmation.
  testWidgets('Bibliotheek & Home draws the local library rows inline and asks before it clears', (tester) async {
    late Directory root;
    late LocalLibraryProvider provider;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('pleya-library-hub-test-');
      final store = LocalLibraryStore(root);
      await store.load();
      await store.saveLibrary(library, [film('cached')], complete: true);
      provider = LocalLibraryProvider(
        profileId: 'fixture',
        directory: root,
        librariesForSync: () => [library],
        clientFor: (_) => null,
        mayReadServer: (_) => true,
        mayReadLibrary: (_) => true,
        networkConnected: () => false,
        wifiConnected: () => false,
        changes: ChangeNotifier(),
      );
      await provider.ready;
    });
    addTearDown(() async {
      provider.dispose();
      await root.delete(recursive: true);
    });
    LocaleSettings.setLocaleSync(AppLocale.en);
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: const SettingsStudioTheme(child: LibraryHomeSettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l = t.localLibrary;
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    final order = [l.enable, l.wifiOnly, l.usage, l.lastSync, l.syncNow, l.clear];
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i - 1]), lessThan(top(order[i])), reason: '${order[i - 1]} before ${order[i]}');
    }
    // Every row's title on the same line as the switches' (no icon slot).
    expect(tester.getTopLeft(find.text(l.clear)).dx, tester.getTopLeft(find.text(l.enable)).dx);
    expect(tester.getTopLeft(find.text(l.syncNow)).dx, tester.getTopLeft(find.text(l.enable)).dx);
    final clearInk = tester.widget<Text>(find.text(l.clear)).style?.color;
    expect(clearInk, settingsDestructiveInk(tester.element(find.text(l.clear))));

    await tester.tap(find.text(l.clear));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, l.clear), findsOneWidget, reason: 'the clear asks first');
    expect(provider.items, isNotEmpty);
  });
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/screens/settings/local_library_settings_screen.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/theme/mono_theme.dart';
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
    // Room for the page under the A-24 Studio header: `ensureVisible` does not
    // know about the pinned bar and would park the row underneath it.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
}

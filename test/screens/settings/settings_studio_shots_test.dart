// A-24b phase 2: Instellingen and its regrouped pages rendered at the five
// standard widths (1920, 1440, 1280, 390, 320), for the review, beside the
// simulator run on the iPhone SE. Skipped unless A24B_SHOT_DIR is set:
//   A24B_SHOT_DIR=/tmp/shots flutter test test/screens/settings/settings_studio_shots_test.dart
// Real fonts, no artwork (the header shows its brand panel): a layout check,
// not pixel truth.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/providers/trackers_provider.dart';
import 'package:pleya/providers/trakt_account_provider.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

final _dir = Platform.environment['A24B_SHOT_DIR'];

ThemeData _withInter(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: 'Inter'),
  inputDecorationTheme: theme.inputDecorationTheme.copyWith(
    hintStyle: theme.inputDecorationTheme.hintStyle?.copyWith(fontFamily: 'Inter'),
  ),
);

class _Profiles extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => null;

  @override
  bool get hasMultipleProfiles => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  setUpAll(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    if (_dir == null) return;
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
  });

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required Size size,
    required bool dark,
    String? open,
    double scroll = 0,
  }) async {
    resetSharedPreferencesForTest();
    await tester.runAsync(() => SettingsService.getInstance());
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    // The iPhone status bar: 20 pt on the SE-sized frames, 47 on 390.
    tester.view.padding = FakeViewPadding(top: (size.width == 390 ? 47 : 20) * 3.0);
    addTearDown(tester.view.reset);
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
              ChangeNotifierProvider<TraktAccountProvider>(
                create: (_) => TraktAccountProvider(kidsProfileCheck: () async => false),
              ),
              ChangeNotifierProvider<TrackersProvider>(create: (_) => TrackersProvider()),
              ChangeNotifierProvider<SeerrProvider>(create: (_) => SeerrProvider()),
              ChangeNotifierProvider<TautulliProvider>(create: (_) => TautulliProvider()),
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
              ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _Profiles()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              // The device draws the system face; the test has Inter only.
              theme: _withInter(monoTheme(dark: dark)).copyWith(platform: TargetPlatform.iOS),
              home: const SettingsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (open != null) {
      await tester.scrollUntilVisible(find.text(open), 120, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(open));
      await tester.pumpAndSettle();
    }
    if (scroll > 0) {
      await tester.drag(find.byType(Scrollable).last, Offset(0, -scroll));
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await (await ro.toImage(pixelRatio: 1)).toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  for (final size in const [Size(1920, 1080), Size(1440, 900), Size(1280, 800), Size(390, 844), Size(320, 568)]) {
    testWidgets('main ${size.width.toInt()}', skip: _dir == null, (tester) async {
      await shot(tester, name: 'w${size.width.toInt()}-main-light', size: size, dark: false);
    });
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final (page, label) in [
      ('weergave', () => t.settings.appearance),
      ('afspelen', () => t.settings.videoPlayback),
      ('bibliotheek-home', () => t.settingsStudio.libraries),
      ('koppelingen', () => t.settingsStudio.integrations),
      ('geavanceerd', () => t.settings.advanced),
      ('backup', () => t.settings.backup),
    ]) {
      testWidgets('320 $page $theme', skip: _dir == null, (tester) async {
        await shot(tester, name: 'w320-$page-$theme', size: const Size(320, 568), dark: dark, open: label());
      });
    }
    testWidgets('320 main scrolled $theme', skip: _dir == null, (tester) async {
      await shot(tester, name: 'w320-main-scrolled-$theme', size: const Size(320, 568), dark: dark, scroll: 400);
    });
  }
}

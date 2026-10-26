// A-24b phase 4: Mijn Pleya on iPhone rendered at 390 and 320 pt, beside the
// simulator run. Skipped unless A24B_SHOT_DIR is set:
//   A24B_SHOT_DIR=/tmp/shots flutter test test/screens/my_pleya_shots_test.dart
// Real fonts, no artwork and an empty kijklijst: a layout check, not pixel
// truth.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/screens/my_pleya_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/tv_my_pleya_conditions.dart';

final _dir = Platform.environment['A24B_SHOT_DIR'];

class _Profiles extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => Profile.local(id: 'michel', displayName: 'Michel', createdAt: DateTime.utc(2026, 10, 25));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    if (_dir == null) return;
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
  });

  Future<void> shot(WidgetTester tester, {required String name, required Size size, required ThemeData theme}) async {
    resetSharedPreferencesForTest();
    await tester.runAsync(() => SettingsService.getInstance());
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = FakeViewPadding(top: (size.width == 390 ? 47 : 20) * 3.0);
    addTearDown(tester.view.reset);
    final watchlist = StockedWatchlistDouble();
    addTearDown(watchlist.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _Profiles()),
              ChangeNotifierProvider<WatchlistProvider>.value(value: watchlist),
              ChangeNotifierProvider<SeerrProvider>(create: (_) => ConfiguredSeerrDouble()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                platform: TargetPlatform.iOS,
                textTheme: theme.textTheme.apply(fontFamily: 'Inter'),
              ),
              home: DefaultTextStyle.merge(
                style: const TextStyle(fontFamily: 'Inter'),
                child: MyPleyaScreen(onOpenTab: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await (await ro.toImage(pixelRatio: 1)).toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  for (final size in const [Size(390, 844), Size(320, 568)]) {
    for (final (mode, theme) in [
      ('oled', monoTheme(dark: true, oled: true)),
      ('dark', monoTheme(dark: true)),
      ('light', monoTheme(dark: false)),
    ]) {
      testWidgets('${size.width.toInt()} $mode', skip: _dir == null, (tester) async {
        await shot(tester, name: 'w${size.width.toInt()}-mypleya-$mode', size: size, theme: theme);
      });
    }
  }
}

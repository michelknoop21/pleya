// Kinderen in huis (BP-11c) as rendered widgets, for the review: the Big P card
// on a phone and at TV size, the list on an iPad and the sheet. Skipped unless
// HOUSEHOLD_SHOT_DIR is set:
//   HOUSEHOLD_SHOT_DIR=/tmp/household flutter test test/screens/settings/household_kids_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/household_kids_store.dart';
import 'package:pleya/screens/settings/household_kids/household_birth_picker.dart';
import 'package:pleya/screens/settings/household_kids/household_kids_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_household_kids_card.dart';

import '../../test_helpers/golden.dart';

final _dir = Platform.environment['HOUSEHOLD_SHOT_DIR'];

class _Store implements HouseholdKidsStore {
  @override
  Future<List<HouseholdKid>> read() async => const [
    HouseholdKid(id: 'a', name: 'Noor', birthMonth: '2020-03'),
    HouseholdKid(id: 'b', name: 'Sam', birthMonth: '2023-05'),
    HouseholdKid(id: 'c', name: 'Luuk', birthMonth: '2026-07'),
  ];

  @override
  Future<bool> save(List<HouseholdKid> kids, {required bool kidsProfile}) async => true;
}

void main() {
  setUpAll(() async {
    if (_dir == null) return;
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
  });

  Future<void> shot(WidgetTester tester, String name, Size size, Widget home) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: monoTheme(dark: true), home: home),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await (await ro.toImage(pixelRatio: 2)).toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  final now = DateTime(2026, 10, 16);

  testWidgets('card on a phone', skip: _dir == null, (tester) async {
    await shot(
      tester,
      'card-iphone',
      const Size(402, 874),
      Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: BigPHouseholdKidsCard(
              embedded: true,
              now: now,
              style: HouseholdPickerStyle.dropdown,
              onSave: (_) {},
            ),
          ),
        ),
      ),
    );
  });

  testWidgets('card at TV size', skip: _dir == null, (tester) async {
    await shot(
      tester,
      'card-tv',
      const Size(1920, 1080),
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 1000,
            child: BigPHouseholdKidsCard(now: now, style: HouseholdPickerStyle.tv, onSave: (_) {}),
          ),
        ),
      ),
    );
  });

  testWidgets('list on an iPad', skip: _dir == null, (tester) async {
    await shot(tester, 'list-ipad', const Size(1180, 820), HouseholdKidsScreen(store: _Store(), now: now));
  });
}

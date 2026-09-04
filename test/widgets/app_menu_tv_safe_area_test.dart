/// FOC1: een contextmenu op TV mag geen enkele rij, en dus geen focusring, in
/// de overscanband leggen.
///
/// `showAppMenu` klemde zijn positie op acht logische pixels van de schermrand,
/// op elk platform. Op een telefoon is dat de bedoeling; op een Apple TV ligt
/// acht pixels ruim binnen de band die een toestel niet toont, en dan is de
/// witte ring van de gefocuste regel het eerste dat je mist. Het is geen
/// clipping: de meting op de oude implementatie liet zien dat geen enkele
/// voorouder iets wegknipte — de rij werd volledig getekend, alleen op een plek
/// die je op het toestel niet ziet.
///
/// De veilige rechthoek komt uit dezelfde bron als [TvDiscoverySafeArea]:
/// [TvDiscoveryLayout.pageInset] opzij, [TvCatalogLayout.topSafeInset] boven en
/// [TvCatalogLayout.bottomSafeInset] onder, maal [TvLayoutConstants.scaleOf].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/app_menu.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

const _entries = <AppMenuEntry<String>>[
  AppMenuItem(value: 'a', label: 'Play'),
  AppMenuItem(value: 'b', label: 'Mark as watched'),
  AppMenuItem(value: 'c', label: 'Add to watchlist'),
  AppMenuItem(value: 'd', label: 'File info'),
];

Widget _shell(void Function(BuildContext) open) {
  return TranslationProvider(
    child: MaterialApp(
      theme: monoTheme(dark: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(onPressed: () => open(context), child: const Text('open')),
          ),
        ),
      ),
    ),
  );
}

Rect _safeRect(BuildContext context, Size screen) {
  final scale = TvLayoutConstants.scaleOf(context);
  return Rect.fromLTRB(
    TvDiscoveryLayout.pageInset * scale,
    TvCatalogLayout.topSafeInset * scale,
    screen.width - TvDiscoveryLayout.pageInset * scale,
    screen.height - TvCatalogLayout.bottomSafeInset * scale,
  );
}

/// De zichtbare rij van elke menu-ingang: de pil die de focusvulling draagt.
List<Rect> _rowRects(WidgetTester tester) {
  return [
    for (final entry in _entries.whereType<AppMenuItem<String>>())
      tester.getRect(find.ancestor(of: find.text(entry.label!), matching: find.byType(AnimatedContainer)).first),
  ];
}

void main() {
  const screen = Size(1920, 1080);

  group('TV', () {
    setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

    for (final (naam, plek) in <(String, Offset)>[
      ('rechtsonder', Offset(1912, 1074)),
      ('linksboven', Offset(8, 6)),
      ('rechtsboven', Offset(1912, 6)),
    ]) {
      testWidgets('menu op $naam blijft binnen de titel-veilige zone', (tester) async {
        await tester.binding.setSurfaceSize(screen);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _shell((context) => showAppMenu<String>(context, position: plek, entries: _entries, focusFirstItem: true)),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final safe = _safeRect(tester.element(find.byType(Scaffold)), screen);
        final rows = _rowRects(tester);
        expect(rows, isNotEmpty, reason: 'het menu moet rijen hebben om iets te meten');
        for (final row in rows) {
          expect(
            safe.contains(row.topLeft) && safe.contains(row.bottomRight),
            isTrue,
            reason: 'rij $row valt buiten de veilige zone $safe',
          );
        }
      });
    }
  });

  group('niet-TV', () {
    testWidgets('houdt de bestaande achtpixelmarge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _shell((context) => showAppMenu<String>(context, position: const Offset(0, 0), entries: _entries)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final rows = _rowRects(tester);
      expect(rows, isNotEmpty);
      // Acht pixels klemming plus de zes horizontale en zes verticale pixels
      // die de rij zelf binnen het oppervlak inspringt.
      expect(rows.first.left, closeTo(14, 0.51), reason: 'mobiel blijft op acht pixels klemmen');
      expect(rows.first.top, closeTo(14, 2), reason: 'mobiel blijft bovenaan op acht pixels klemmen');
    });
  });
}

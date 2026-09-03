/// `logs-a`: the log reader on TV.
///
/// The audit of 2 September 2026 measured a desktop screen here — four round
/// icon buttons in a pinned app bar, body text at 1.22% of the width, inside
/// the overscan band, at a size nobody reads from a sofa. What replaces it
/// trades line count for legibility, so the two things worth guarding are that
/// the trade is honest (the actions still act on the whole buffer, not on the
/// filtered view) and that the filter actually narrows what is drawn.
///
/// The third test is the small half of a naming defect the audit found: the
/// tile said "Logs and diagnostics" and the screen said "Logs", the same shape
/// of mistake as Bibliotheken's three names for one place.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/logs_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_page_chip_bar.dart';
import 'package:pleya/widgets/tv/tv_page_surface.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    MemoryLogOutput.clearLogs();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    MemoryLogOutput.clearLogs();
  });

  /// Through the real logger, so what the reader draws is what the app would
  /// actually have put in the buffer.
  void seed() {
    setLoggerLevel(true);
    appLogger.d('debug line');
    appLogger.i('info line');
    appLogger.w('warning line');
    appLogger.e('error line');
  }

  /// Drives a chip by its model rather than by a tap on a capsule. The gesture
  /// and focus path belongs to [TvPageChipBar] and is covered where that lives;
  /// what this file is about is whether the reader narrows.
  TvPageChip chipNamed(WidgetTester tester, String key) =>
      tester.widget<TvPageChipBar>(find.byType(TvPageChipBar)).chips.firstWhere((c) => c.key == key);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(debugShowCheckedModeBanner: false, theme: monoTheme(dark: true), home: const LogsScreen()),
    );
    await tester.pump();
  }

  testWidgets('the level filter narrows the reader, and Errors keeps only errors', (tester) async {
    seed();
    await pump(tester);

    expect(find.byType(TvPageSurface), findsOneWidget);
    expect(find.text('debug line'), findsOneWidget);
    expect(find.text('error line'), findsOneWidget);

    chipNamed(tester, 'level_errors').onSelect!();
    await tester.pump();

    expect(find.text('debug line'), findsNothing);
    expect(find.text('info line'), findsNothing);
    expect(find.text('warning line'), findsNothing);
    expect(find.text('error line'), findsOneWidget);
  });

  testWidgets('Warnings keeps warnings and above, and the count line says so', (tester) async {
    seed();
    await pump(tester);

    chipNamed(tester, 'level_warnings').onSelect!();
    await tester.pump();

    expect(find.text(t.logs.lineCount(shown: 2, total: 4).toUpperCase()), findsOneWidget);
  });

  testWidgets('the page takes the name the tile that opened it uses', (tester) async {
    seed();
    await pump(tester);

    expect(find.text(t.tvMyPleya.logs), findsOneWidget);
  });

  testWidgets('with an empty buffer the actions are disabled but keep their place', (tester) async {
    await pump(tester);

    final bar = tester.widget<TvPageChipBar>(find.byType(TvPageChipBar));
    final byKey = {for (final c in bar.chips) c.key: c};

    // Refresh always works — there may be lines to pick up.
    expect(byKey['refresh']!.onSelect, isNotNull);
    for (final key in ['upload', 'copy', 'clear']) {
      expect(byKey[key]!.onSelect, isNull, reason: key);
    }
    // The level chips are a choice, not an action, so an empty buffer does not
    // take them away.
    expect(byKey['level_all']!.onSelect, isNotNull);
  });

  testWidgets('arrows on an empty reader do not throw', (tester) async {
    // Codex challenge, finding 1. `_buildTv` renders `TvPageBlock` instead of
    // the `ListView` when there is nothing to show, so `_scrollController` has
    // no attached position, while the page's own key handler still calls
    // `_scroll` on UP and DOWN. The mobile path never hits this: its
    // `CustomScrollView` is always built, empty state included.
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('arrows on a filtered-empty reader do not throw either', (tester) async {
    // The second door to the same defect: there are lines, but none at this
    // level, so the reader is a block again.
    seed();
    await pump(tester);

    chipNamed(tester, 'level_errors').onSelect!();
    await tester.pump();
    MemoryLogOutput.clearLogs();
    chipNamed(tester, 'level_warnings').onSelect!();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

/// LANG1 / DEC-096, negatieve controles O tot en met R: de pagina Taal en
/// ondertitels (31 A) en de serievoorkeur-sheet (31 B).
///
/// Verwijst naar `LanguageSettingsScreen`, die vóór deze bouwronde niet
/// bestaat: dit bestand compileert niet op de code van `eae19cb4`, en dat is de
/// vastgelegde rode uitkomst.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/screens/settings/language_settings_screen.dart';
import 'package:pleya/services/pleya_profile_language_preference_store.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/track_preference_store.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

MediaItem _episode({String show = 'show7', String title = 'Severance'}) => MediaItem(
  id: '$show-ep',
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  grandparentId: show,
  grandparentTitle: title,
  serverId: 'nas',
  parentIndex: 2,
  index: 4,
);

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    InputModeTracker(
      child: MaterialApp(theme: monoTheme(dark: true), home: const LanguageSettingsScreen()),
    ),
  );
  // The page's own load is async (profile scope, stored preferences) and the
  // preference stores go through `SharedPreferencesWithCache`, which testWidgets
  // will not drive on its own.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

/// Focus the row carrying [text] and press SELECT, the way a remote does.
///
/// `FocusableWrapper` is deliberately keyboard and remote only — it has no tap
/// handler of its own — so a row inside a TV panel is reached this way and not
/// with `tester.tap`.
Future<void> _selectByText(WidgetTester tester, String text) async {
  final candidates = tester
      .widgetList<Focus>(find.ancestor(of: find.text(text), matching: find.byType(Focus)))
      .where((focus) => focus.focusNode != null)
      .toList();
  expect(candidates, isNotEmpty, reason: 'no focusable ancestor for "$text"');
  candidates.first.focusNode!.requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    // Both stores serialise writes through a static future chain, and a link
    // created in a torn-down test zone never completes: without this the second
    // test in this file waits on the first one's queue forever, behind a
    // spinner that never settles.
    TrackPreferenceStore.resetForTesting();
    PleyaProfileLanguagePreferenceStore.resetForTesting();
    SettingsService.resetForTesting();
    await (await StorageService.getInstance()).clearActiveProfileId();
    await (await SettingsService.getInstance()).write(
      SettingsService.trackLanguagePreferences,
      const <String, TrackLanguageChoice>{},
    );
    await (await SettingsService.getInstance()).write(
      SettingsService.pleyaProfileLanguagePreferences,
      const <String, PleyaProfileLanguagePreferences>{},
    );
    TrackPreferenceStore.deviceNameProvider = () async => 'Apple TV';
  });

  // A page that is disposed mid-load leaves its store reads in flight, and the
  // stores serialise every write through one static lock. Resetting
  // `SettingsService` underneath a queued action strands that lock, and the
  // *next* test then waits on it forever behind a spinner that never settles.
  // Draining here costs a tick and keeps each test independent.
  tearDown(() => Future<void>.delayed(const Duration(milliseconds: 100)));

  // ────────────────────────────────────────────────────────────────
  // CONTROL O — de pagina toont de globale voorkeur en de twee schakelaars
  // ────────────────────────────────────────────────────────────────
  testWidgets('CONTROL O — de globale rijen en de twee schakelaars staan op deze pagina', (tester) async {
    await tester.runAsync(
      () => PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(
          subtitleLanguage: 'nl',
          subtitleFallbackLanguage: 'en',
          useOriginalAudio: true,
        ),
      ),
    );

    await _pumpPage(tester);

    expect(find.text('Audio'), findsWidgets);
    expect(find.text('Original language'), findsOneWidget);
    expect(find.text('Dutch'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    // The two switches moved here from Instellingen ▸ Afspelen (DEC-096 lid 9).
    expect(find.byType(Switch), findsNWidgets(2));
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL P — een serievoorkeur staat er met keuze en herkomst
  // ────────────────────────────────────────────────────────────────
  testWidgets('CONTROL P — de serierij toont de talen en waar de keuze vandaan komt', (tester) async {
    await tester.runAsync(() async {
      await TrackPreferenceStore.saveSubtitle(_episode(), language: 'en', title: 'English');
      await TrackPreferenceStore.saveAudio(_episode(), language: 'en');
    });

    await _pumpPage(tester);

    expect(find.text('Severance'), findsOneWidget);
    expect(find.text('Audio: English · Subtitles: English'), findsOneWidget);
    expect(find.textContaining('S2E4'), findsOneWidget);
    expect(find.textContaining('Apple TV'), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL Q — de sheet van 31 B opent en leest beide waarden
  // ────────────────────────────────────────────────────────────────
  testWidgets('CONTROL Q — de sheet zet de serievoorkeur naast de globale', (tester) async {
    await tester.runAsync(() async {
      await PleyaProfileLanguagePreferenceStore.write(const PleyaProfileLanguagePreferences(subtitleLanguage: 'nl'));
      await TrackPreferenceStore.saveSubtitle(_episode(), language: 'en');
    });

    await _pumpPage(tester);
    await tester.tap(find.text('Severance'));
    await tester.pumpAndSettle();

    expect(find.text('Use global preference'), findsOneWidget);
    expect(find.text('Pleya profile: Dutch'), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────────
  // CONTROL R — "Gebruik globale voorkeur" wist de regel en de rij verdwijnt
  // ────────────────────────────────────────────────────────────────
  testWidgets('CONTROL R — de actie wist de serievoorkeur en de lijst is daarna leeg', (tester) async {
    await tester.runAsync(() => TrackPreferenceStore.saveSubtitle(_episode(), language: 'en'));

    await _pumpPage(tester);
    // SELECT rather than a tap, for both steps: this is the remote's journey,
    // and a tapped settings row that takes the focus back when the sheet closes
    // paints its ink under the focused row's own surface, which Flutter asserts
    // about in debug. Control Q covers the pointer path.
    await _selectByText(tester, 'Severance');
    // The action row is a `TvCatalogOptionRow`, and `FocusableWrapper` is
    // remote input only: no tap handler, on purpose. So the test activates it
    // the way a viewer does, with SELECT on the focused row.
    await _selectByText(tester, 'Use global preference');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Severance'), findsNothing);
    expect(
      find.text('Series preferences appear by themselves when you pick another language during a series.'),
      findsOneWidget,
    );
    final remaining = await tester.runAsync(TrackPreferenceStore.readAllForActiveScope);
    expect(remaining, isEmpty);
  });
}

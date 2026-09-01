import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';
import 'package:pleya/widgets/tv/tv_action_scope_picker.dart';
import 'package:pleya/widgets/tv/tv_source_row.dart';

/// The visible half of the hoofdstuk 23 write-scope question.
///
/// `tv_unified_context_actions_test.dart` proves every *decision* — which scope
/// an action has, which sources are candidates, that a representative is never
/// silently taken. What is proved here is that a user with a remote sees that
/// question and can answer it, and that the answer that comes back is the one
/// they gave.

MediaItem _item(String serverId, {String id = 'i1', String? libraryTitle}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  year: 2021,
  serverId: serverId,
  serverName: serverId,
  libraryTitle: libraryTitle,
);

UnifiedMediaSource _source(String serverId, {String id = 'i1', String? libraryTitle}) => UnifiedMediaSource.fromItem(
  _item(serverId, id: id, libraryTitle: libraryTitle),
).withAvailability(SourceAvailability.online);

class _Harness {
  final List<UnifiedActionScopeChoice> chosen = [];
  int closes = 0;
}

Future<_Harness> _pumpPicker(
  WidgetTester tester, {
  required List<UnifiedMediaSource> sources,
  required bool allowAllSources,
}) async {
  final harness = _Harness();
  final firstRowKey = allowAllSources ? kAllSourcesRowKey : sources.first.sourceKey;

  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: OverlaySheetHost(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    autofocus: true,
                    onPressed: () => OverlaySheetController.of(context).show(
                      presentation: OverlaySheetPresentation.panel,
                      builder: (_) => TvActionScopePicker(
                        sources: sources,
                        focusedRowKey: firstRowKey,
                        initialFocusRowKey: firstRowKey,
                        actionTitle: t.tvContextMenu.scopeTitleMarkWatched,
                        mediaTitle: 'Dune',
                        allowAllSources: allowAllSources,
                        onChoose: harness.chosen.add,
                        onFocusRow: (_) {},
                        onClose: () => harness.closes++,
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

/// Focuses the row showing [label] and presses Select on it.
///
/// `FocusableWrapper` carries no tap handler, so `tester.tap` on a row silently
/// does nothing — which is also the honest way to drive a 10-foot surface.
/// Same helper the playback picker's tests use, for the same reason.
Future<void> _activateByLabel(WidgetTester tester, String label) async {
  final focus = Focus.maybeOf(tester.element(find.text(label)), scopeOk: true)!;
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue, reason: 'the row under test must actually hold the focus');
  SelectKeyUpSuppressor.clearSuppression();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

void main() {
  // `SelectKeyUpSuppressor` is process-global: a test that activates something
  // leaves it armed, and the next test's first Select press would be eaten.
  setUp(SelectKeyUpSuppressor.clearSuppression);
  tearDown(SelectKeyUpSuppressor.clearSuppression);

  testWidgets('the all-sources row leads the list, and answering it returns every source', (tester) async {
    final sources = [_source('nas'), _source('attic')];
    final harness = await _pumpPicker(tester, sources: sources, allowAllSources: true);

    expect(find.text(t.tvContextMenu.allSources), findsOneWidget);
    expect(find.text(t.tvContextMenu.allSourcesDetail(count: 2)), findsOneWidget);

    // Top of the list: hoofdstuk 13.5's "expliciet" reads as a row the user
    // lands on first, not one they have to scroll past the servers to find.
    final rows = tester.widgetList<TvSourceRow>(find.byType(TvSourceRow)).toList();
    expect(rows.first.descriptor.sourceKey, kAllSourcesRowKey);
    expect(rows.length, 3, reason: 'the pseudo-row plus both servers');

    await _activateByLabel(tester, t.tvContextMenu.allSources);

    expect(harness.chosen.single, isA<ChoseAllSources>());
    expect((harness.chosen.single as ChoseAllSources).sources.map((s) => s.serverId.value), ['nas', 'attic']);
  });

  testWidgets('choosing one server returns that server and nothing else', (tester) async {
    final harness = await _pumpPicker(tester, sources: [_source('nas'), _source('attic')], allowAllSources: true);

    await _activateByLabel(tester, 'attic');

    expect(harness.chosen.single, isA<ChoseOneSource>());
    expect((harness.chosen.single as ChoseOneSource).source.serverId.value, 'attic');
  });

  testWidgets('an action without all-sources semantics offers no such row', (tester) async {
    await _pumpPicker(tester, sources: [_source('nas'), _source('attic')], allowAllSources: false);

    expect(
      find.text(t.tvContextMenu.allSources),
      findsNothing,
      reason: 'offering it for rate would invent semantics 13.5 does not give it',
    );
    expect(tester.widgetList<TvSourceRow>(find.byType(TvSourceRow)).length, 2);
  });

  testWidgets('no row is marked as a remembered or preferred choice', (tester) async {
    // The negative control for the picker half: the playback picker marks
    // "Laatst gebruikt" and "Voorkeursserver", and a write question that
    // inherited either would be nudging the user toward an answer they gave to
    // a different question.
    await _pumpPicker(tester, sources: [_source('nas'), _source('attic')], allowAllSources: true);

    expect(find.text(t.sourcePicker.lastUsed), findsNothing);
    expect(find.text(t.sourcePicker.preferredServer), findsNothing);
    expect(find.text(t.sourcePicker.currentSource), findsNothing);
    expect(
      find.text(t.sourcePicker.setPreferredServer(server: 'nas')),
      findsNothing,
      reason: 'and there is no footer action that would turn a write choice into a playback default',
    );

    for (final row in tester.widgetList<TvSourceRow>(find.byType(TvSourceRow))) {
      expect(row.descriptor.isPreferred, isFalse);
      expect(row.descriptor.isPreferredServer, isFalse);
      expect(row.descriptor.isCurrent, isFalse);
    }
  });

  testWidgets('the library name still tells two servers apart', (tester) async {
    await _pumpPicker(
      tester,
      sources: [
        _source('nas', libraryTitle: 'Films 4K'),
        _source('attic', libraryTitle: 'Films'),
      ],
      allowAllSources: false,
    );

    expect(find.textContaining('Films 4K'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/services/unified_catalog/unified_activation_coordinator.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/screens/tv/tv_media_source_picker_route.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';
import 'package:pleya/widgets/tv/tv_media_source_picker.dart';

/// The visible half of hoofdstuk 14 (docs/tvos-unified-experience.md).
///
/// The coordinator tests already prove every *decision*: the ranking, which row
/// should start focused, where focus should go when a server drops out, where a
/// late arrival belongs. What is proved here is that a user with a remote can
/// see and reach those decisions — which is exactly the half register F was
/// kept open for.
///
/// So these deliberately do not re-assert the rules. They drive the widget with
/// the state a rule produces and check what the screen then does.

MediaItem _item(
  String serverId, {
  String id = 'i1',
  String? serverName,
  String? libraryTitle,
  MediaBackend backend = MediaBackend.plex,
  int? viewOffsetMs,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.movie,
  title: 'Dune',
  year: 2021,
  durationMs: 9000000,
  viewOffsetMs: viewOffsetMs,
  libraryTitle: libraryTitle,
  serverId: serverId,
  serverName: serverName ?? serverId,
);

UnifiedMediaSource _source(
  String serverId, {
  String id = 'i1',
  String? serverName,
  String? libraryTitle,
  MediaBackend backend = MediaBackend.plex,
  int? viewOffsetMs,
  SourceAvailability availability = SourceAvailability.online,
}) => UnifiedMediaSource.fromItem(
  _item(
    serverId,
    id: id,
    serverName: serverName,
    libraryTitle: libraryTitle,
    backend: backend,
    viewOffsetMs: viewOffsetMs,
  ),
  availability: availability,
);

UnifiedMediaGroup _group(List<UnifiedMediaSource> sources) => UnifiedMediaGroup(
  groupId: 'g1',
  identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
  sources: sources,
  representativeSourceKey: sources.first.sourceKey,
  watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
);

/// Everything the harness lets a test observe or drive.
class _Harness {
  /// The control that opened the picker. Hoofdstuk 14.4 requires cancelling to
  /// restore "exact de vorige kaart of CTA", so the test needs a node it can
  /// point at rather than a guess about what the tree focuses next.
  final FocusNode openerFocusNode = FocusNode(debugLabel: 'opener');
  final List<UnifiedMediaSource> selected = [];
  final List<String> focused = [];
  int closes = 0;
  int manageServers = 0;
  final List<UnifiedMediaSource> preferredSet = [];
}

/// Pumps the picker inside the production shell: `InputModeTracker` (so TV
/// defaults to keyboard mode and focus is actually painted) and
/// `OverlaySheetHost` with the panel presentation, told which node to focus —
/// exactly what `showUnifiedSourcePicker` does.
Future<_Harness> _pumpPicker(
  WidgetTester tester, {
  required List<UnifiedMediaSource> sources,
  required String focusedSourceKey,
  String? preferredSourceKey,
  String? currentSourceKey,
  String? preferredServerId,
  SourceCoverageState? coverage,
  UnifiedActivationIntent intent = UnifiedActivationIntent.play,
  bool isResolving = false,
  bool offerPreferredServer = false,
  ValueNotifier<int>? rebuild,
  List<UnifiedMediaSource> Function()? liveSources,
  String Function()? liveFocusedSourceKey,
}) async {
  final harness = _Harness();
  final initialFocusNode = FocusNode(debugLabel: 'initialFocus');
  addTearDown(initialFocusNode.dispose);
  addTearDown(() => harness.openerFocusNode.dispose());
  final repaint = rebuild ?? ValueNotifier<int>(0);
  addTearDown(repaint.dispose);

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
                      initialFocusNode: initialFocusNode,
                      builder: (_) => ValueListenableBuilder<int>(
                        valueListenable: repaint,
                        builder: (_, _, _) => TvMediaSourcePicker(
                          sources: liveSources?.call() ?? sources,
                          focusedSourceKey: liveFocusedSourceKey?.call() ?? focusedSourceKey,
                          initialFocusNode: initialFocusNode,
                          initialFocusSourceKey: focusedSourceKey,
                          preferredSourceKey: preferredSourceKey,
                          currentSourceKey: currentSourceKey,
                          preferredServerId: preferredServerId,
                          title: 'Dune',
                          year: 2021,
                          intent: intent,
                          coverage: coverage ?? SourceCoverageState.complete({'nas', 'attic'}),
                          isResolving: isResolving,
                          onSelectSource: harness.selected.add,
                          onFocusSource: harness.focused.add,
                          onClose: () => harness.closes++,
                          onManageServers: () => harness.manageServers++,
                          onSetPreferredServer: offerPreferredServer ? harness.preferredSet.add : null,
                        ),
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
  if (isResolving) {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } else {
    await tester.pumpAndSettle();
  }
  return harness;
}

/// The row a `FocusableWrapper` reports as focused, by its server name.
String? _focusedRowLabel(WidgetTester tester) {
  for (final element in find.byType(Focus).evaluate()) {
    final focus = element.widget as Focus;
    final node = focus.focusNode;
    if (node == null || !node.hasPrimaryFocus) continue;
    final text = find.descendant(of: find.byWidget(focus), matching: find.byType(Text));
    if (!text.evaluate().isNotEmpty) continue;
    return (text.evaluate().first.widget as Text).data;
  }
  return null;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

/// Focuses the control showing [label] and presses Select on it.
///
/// `FocusableWrapper` is a D-pad widget and carries no tap handler at all, so a
/// `tester.tap` on one of these silently does nothing — which is also the
/// honest way to drive a 10-foot surface in a test.
Future<void> _activateByLabel(WidgetTester tester, String label) async {
  final focus = Focus.maybeOf(tester.element(find.text(label)), scopeOk: true)!;
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue, reason: 'the control under test must actually hold the focus');
  SelectKeyUpSuppressor.clearSuppression();
  await _press(tester, LogicalKeyboardKey.select);
}

void main() {
  // `SelectKeyUpSuppressor` is process-global: a test that activates something
  // leaves it armed, and the next test's first Select press would be eaten.
  setUp(SelectKeyUpSuppressor.clearSuppression);
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('initial focus (F2, F15, F16)', () {
    testWidgets('the row the coordinator named is the one that starts focused', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      await _pumpPicker(tester, sources: [nas, attic], focusedSourceKey: attic.sourceKey);

      expect(_focusedRowLabel(tester), 'Zolder');
    });

    testWidgets('a remembered source keeps the focus and is marked "Last used"', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      // What `selectInitialFocus` returns for a remembered, online source.
      await _pumpPicker(
        tester,
        sources: [attic, nas],
        focusedSourceKey: nas.sourceKey,
        preferredSourceKey: nas.sourceKey,
      );

      expect(_focusedRowLabel(tester), 'NAS');
      expect(find.text(t.sourcePicker.lastUsed), findsOneWidget);
    });

    testWidgets('F16: an offline remembered source is not focused and is not marked', (tester) async {
      final nas = _source('nas', serverName: 'NAS', availability: SourceAvailability.offline);
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      // The coordinator falls back to the best online source; the picker must
      // show that fallback focused rather than parking on the dead row.
      await _pumpPicker(tester, sources: [attic, nas], focusedSourceKey: attic.sourceKey, preferredSourceKey: null);

      expect(_focusedRowLabel(tester), 'Zolder');
      expect(find.text(t.sourcePicker.lastUsed), findsNothing);
      expect(find.text(t.sourcePicker.unavailable), findsOneWidget);
    });

    testWidgets('the profile default is marked differently from the remembered source', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      await _pumpPicker(
        tester,
        sources: [nas, attic],
        focusedSourceKey: nas.sourceKey,
        preferredSourceKey: attic.sourceKey,
        preferredServerId: 'nas',
      );

      expect(find.text(t.sourcePicker.preferredServer), findsOneWidget);
      expect(find.text(t.sourcePicker.lastUsed), findsOneWidget);
    });
  });

  group('activation (F2)', () {
    testWidgets('Select activates exactly the focused source, not its neighbour', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      final harness = await _pumpPicker(tester, sources: [nas, attic], focusedSourceKey: attic.sourceKey);
      await _press(tester, LogicalKeyboardKey.select);

      expect(harness.selected.map((s) => s.sourceKey), [attic.sourceKey]);
    });

    testWidgets('an unusable row cannot take focus, so it can never be activated', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final dead = _source('attic', id: 'i2', serverName: 'Zolder', availability: SourceAvailability.offline);

      final harness = await _pumpPicker(tester, sources: [nas, dead], focusedSourceKey: nas.sourceKey);

      final deadRow = tester.widget<FocusableWrapper>(
        find.ancestor(of: find.text('Zolder'), matching: find.byType(FocusableWrapper)).first,
      );
      expect(deadRow.canRequestFocus, isFalse);
      expect(deadRow.onSelect, isNull, reason: 'nothing to activate, so no activation handler at all');

      // Nothing the remote can do reaches it: Select from the row above stays
      // on the row above.
      await _press(tester, LogicalKeyboardKey.select);
      expect(harness.selected.map((s) => s.sourceKey), [nas.sourceKey]);
    });
  });

  group('unusable rows read differently (F6, F7, F11)', () {
    testWidgets('F7: an auth error says something else than an offline server', (tester) async {
      final auth = _source('remote', serverName: 'Vakantiehuis', availability: SourceAvailability.authError);
      final offline = _source('office', id: 'i2', serverName: 'Kantoor', availability: SourceAvailability.offline);
      final nas = _source('nas', id: 'i3', serverName: 'NAS');

      await _pumpPicker(tester, sources: [nas, auth, offline], focusedSourceKey: nas.sourceKey);

      expect(find.text(t.sourcePicker.signInRequired), findsOneWidget);
      expect(find.text(t.sourcePicker.unavailable), findsOneWidget);
      expect(t.sourcePicker.signInRequired, isNot(t.sourcePicker.unavailable));
    });

    testWidgets('F6: with nothing reachable the two panel actions appear and take the focus', (tester) async {
      final auth = _source('remote', serverName: 'Vakantiehuis', availability: SourceAvailability.authError);
      final offline = _source('office', id: 'i2', serverName: 'Kantoor', availability: SourceAvailability.offline);

      final harness = await _pumpPicker(tester, sources: [auth, offline], focusedSourceKey: auth.sourceKey);

      expect(find.text(t.sourcePicker.manageServers), findsOneWidget);
      expect(find.text(t.common.close), findsOneWidget);
      // Hoofdstuk 14.4: focus goes to the panel's controls, never to a row the
      // remote cannot activate.
      expect(_focusedRowLabel(tester), t.sourcePicker.manageServers);

      await _press(tester, LogicalKeyboardKey.select);
      expect(harness.manageServers, 1);
      expect(harness.closes, 0);
    });

    testWidgets('F6: an auth error headline offers the thing the user can fix', (tester) async {
      final auth = _source('remote', serverName: 'Vakantiehuis', availability: SourceAvailability.authError);
      await _pumpPicker(tester, sources: [auth], focusedSourceKey: auth.sourceKey);

      expect(find.text(t.sourcePicker.reauthRequiredTitle), findsOneWidget);
      expect(find.text(t.sourcePicker.noneReachableTitle), findsNothing);
    });

    testWidgets('F6: an unreachable server headline does not tell the user to sign in', (tester) async {
      final offline = _source('office', serverName: 'Kantoor', availability: SourceAvailability.offline);
      await _pumpPicker(tester, sources: [offline], focusedSourceKey: offline.sourceKey);

      expect(find.text(t.sourcePicker.noneReachableTitle), findsOneWidget);
      expect(find.text(t.sourcePicker.reauthRequiredTitle), findsNothing);
    });

    testWidgets('F11: the focused source going offline moves focus to the nearest usable row', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');
      var sources = [nas, attic];
      var focused = nas.sourceKey;
      final rebuild = ValueNotifier<int>(0);

      await _pumpPicker(
        tester,
        sources: sources,
        focusedSourceKey: nas.sourceKey,
        rebuild: rebuild,
        liveSources: () => sources,
        liveFocusedSourceKey: () => focused,
      );
      expect(_focusedRowLabel(tester), 'NAS');

      // What the route does on an availability change: re-stamp, then ask the
      // coordinator where focus goes.
      sources = [nas.withAvailability(SourceAvailability.offline), attic];
      focused = nextFocusAfterAvailabilityChange(ordered: sources, focusedSourceKey: focused)!;
      rebuild.value++;
      await tester.pumpAndSettle();

      expect(focused, attic.sourceKey);
      expect(_focusedRowLabel(tester), 'Zolder');
      expect(find.text(t.sourcePicker.unavailable), findsOneWidget);
    });
  });

  group('coverage and resolving (F8, F9)', () {
    testWidgets('F9: partial coverage is stated in the header', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      await _pumpPicker(
        tester,
        sources: [nas, attic],
        focusedSourceKey: nas.sourceKey,
        coverage: SourceCoverageState(
          expectedServerIds: {'nas', 'attic', 'shed'},
          checkedServerIds: {'nas', 'attic'},
          uncheckedReasons: {'shed': UncheckedSourceReason.offline},
        ),
      );

      expect(find.text(t.sourcePicker.availableOnManyServers(count: 2)), findsOneWidget);
      expect(find.text(t.sourcePicker.oneServerUnchecked), findsOneWidget);
    });

    testWidgets('complete coverage says nothing about unchecked servers', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      await _pumpPicker(tester, sources: [nas, attic], focusedSourceKey: nas.sourceKey);

      expect(find.text(t.sourcePicker.oneServerUnchecked), findsNothing);
      expect(find.textContaining('could not be checked'), findsNothing);
    });

    testWidgets('F8: the resolving line shows without blocking the list', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      await _pumpPicker(tester, sources: [nas, attic], focusedSourceKey: nas.sourceKey, isResolving: true);

      expect(find.text(t.sourcePicker.checkingMoreSources), findsOneWidget);
      // The whole point of 14.5: the known rows are already choosable.
      expect(find.text('NAS'), findsOneWidget);
      expect(find.text('Zolder'), findsOneWidget);
      expect(_focusedRowLabel(tester), 'NAS');
    });

    testWidgets('F10: a late source lands at the bottom without moving the focus', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');
      final late_ = _source('shed', id: 'i3', serverName: 'Schuur');
      var sources = [nas, attic];
      final rebuild = ValueNotifier<int>(0);

      await _pumpPicker(
        tester,
        sources: sources,
        focusedSourceKey: attic.sourceKey,
        isResolving: true,
        rebuild: rebuild,
        liveSources: () => sources,
      );
      expect(_focusedRowLabel(tester), 'Zolder');

      sources = mergeLateSources(sources, [late_]);
      rebuild.value++;
      // Not pumpAndSettle: the resolving spinner never settles.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Schuur'), findsOneWidget);
      expect(_focusedRowLabel(tester), 'Zolder', reason: 'hoofdstuk 14.4: a late arrival never moves the cursor');
    });
  });

  // Driven through `showUnifiedSourcePicker`, not the widget: what is being
  // proved is the *route's* promise, and cancelling is the one case where the
  // route has to do something the widget cannot see.
  group('cancel (F17, F20)', () {
    testWidgets('Menu closes the picker, activates nothing, and restores the exact CTA', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');
      final opener = FocusNode(debugLabel: 'opener');
      addTearDown(opener.dispose);
      UnifiedMediaSource? chosen;
      var completed = false;

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
                        focusNode: opener,
                        onPressed: () async {
                          chosen = await showUnifiedSourcePicker(
                            context,
                            group: _group([nas, attic]),
                            sources: [nas, attic],
                            initialFocusSourceKey: nas.sourceKey,
                            coverage: SourceCoverageState.complete({'nas', 'attic'}),
                            intent: UnifiedActivationIntent.play,
                            environment: UnifiedActivationEnvironment(availabilityFor: (s) => s.availability),
                          );
                          completed = true;
                        },
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
      expect(_focusedRowLabel(tester), 'NAS');
      expect(opener.hasPrimaryFocus, isFalse);

      await _press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(chosen, isNull, reason: 'cancelling must never activate a source');
      expect(find.text('NAS'), findsNothing, reason: 'the panel is gone');
      expect(opener.hasPrimaryFocus, isTrue, reason: 'hoofdstuk 14.4: the exact CTA gets the focus back');
    });
  });

  group('metadata is shown, absence is not (F12, F13, F14)', () {
    testWidgets('F13: a source with no quality metadata simply has one line fewer', (tester) async {
      final rich = _source('nas', serverName: 'NAS', libraryTitle: 'Films 4K');
      final sparse = _source('shed', id: 'i2', serverName: 'Schuur', backend: MediaBackend.pleyaServer);

      await _pumpPicker(tester, sources: [rich, sparse], focusedSourceKey: rich.sourceKey);

      expect(find.text('Schuur'), findsOneWidget);
      expect(find.textContaining('Unknown'), findsNothing);
      expect(find.textContaining('Onbekend'), findsNothing);
    });

    // A picture test, written as a measurement because the golden could not
    // catch it: what shipped was the *track* colour drawn at the *fill's*
    // width, with the red never painted at all — a `Stack` sizes to its largest
    // non-positioned child, and a `ColoredBox` under loose constraints takes
    // zero height. It looked like a plausible grey bar, which is exactly why it
    // survived a visual pass. Both boxes are measured here, not merely found.
    testWidgets('resume progress paints brand red across the watched share of a full-width track', (tester) async {
      // 25% in: far enough from 0 and 1 that a collapsed or full-width fill
      // cannot be mistaken for a correct one.
      final resumed = _source('nas', serverName: 'NAS', viewOffsetMs: 2250000);

      await _pumpPicker(tester, sources: [resumed], focusedSourceKey: resumed.sourceKey);

      final mono = monoTheme(dark: true).extension<MonoTokens>()!;
      Size sizeOfBox(Color color) {
        final finder = find.byWidgetPredicate((w) => w is ColoredBox && w.color == color);
        expect(finder, findsOneWidget, reason: 'expected exactly one $color box in the row');
        return tester.getSize(finder);
      }

      final fill = sizeOfBox(mono.accent);
      final track = sizeOfBox(mono.text.withValues(alpha: TvSourcePickerLayout.progressTrack));

      expect(track.width, greaterThan(0));
      expect(fill.height, track.height, reason: 'the fill must be as tall as its track, not zero-height');
      expect(
        fill.width / track.width,
        closeTo(0.25, 0.01),
        reason: 'the red covers the watched fraction; the track spans the row',
      );
    });

    testWidgets('F12: two servers with one name stay tellable apart by their library', (tester) async {
      final a = _source('a', serverName: 'Media', libraryTitle: 'Films');
      final b = _source('b', id: 'i2', serverName: 'Media', libraryTitle: 'Archief');

      await _pumpPicker(tester, sources: [a, b], focusedSourceKey: a.sourceKey);

      expect(find.text('Media'), findsNWidgets(2));
      expect(find.text('Films'), findsOneWidget);
      expect(find.text('Archief'), findsOneWidget);
    });

    testWidgets('one backend: the backend name is left off every row', (tester) async {
      final plexOnly = [
        _source('nas', serverName: 'NAS', libraryTitle: 'Films'),
        _source('attic', id: 'i2', serverName: 'Zolder', libraryTitle: 'Movies'),
      ];

      await _pumpPicker(tester, sources: plexOnly, focusedSourceKey: plexOnly.first.sourceKey);

      expect(find.textContaining('Plex'), findsNothing, reason: '14.3: only when the distinction is useful');
      expect(find.text('Films'), findsOneWidget);
    });

    testWidgets('two backends: the backend name earns its place', (tester) async {
      final mixed = [
        _source('nas', serverName: 'NAS', libraryTitle: 'Films'),
        _source('attic', id: 'i2', serverName: 'Zolder', libraryTitle: 'Movies', backend: MediaBackend.jellyfin),
      ];

      await _pumpPicker(tester, sources: mixed, focusedSourceKey: mixed.first.sourceKey);

      expect(find.textContaining('Plex'), findsOneWidget);
      expect(find.textContaining('Jellyfin'), findsOneWidget);
    });
  });

  group('the preferred server can be set from here', () {
    testWidgets('the action names the focused server and reports it once', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      final harness = await _pumpPicker(
        tester,
        sources: [nas, attic],
        focusedSourceKey: attic.sourceKey,
        offerPreferredServer: true,
      );

      expect(find.text(t.sourcePicker.setPreferredServer(server: 'Zolder')), findsOneWidget);
      await _activateByLabel(tester, t.sourcePicker.setPreferredServer(server: 'Zolder'));

      expect(harness.preferredSet.map((s) => s.serverId.value), ['attic']);
      // Setting a default is not choosing a source: the panel stays open.
      expect(harness.selected, isEmpty);
      expect(harness.closes, 0);
    });

    testWidgets('it is not offered for the server that is already the default', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');

      await _pumpPicker(
        tester,
        sources: [nas, attic],
        focusedSourceKey: nas.sourceKey,
        preferredServerId: 'nas',
        offerPreferredServer: true,
      );

      expect(find.text(t.sourcePicker.setPreferredServer(server: 'NAS')), findsNothing);
    });

    testWidgets('it is not offered while the focused row is unusable', (tester) async {
      final dead = _source('office', serverName: 'Kantoor', availability: SourceAvailability.offline);
      final nas = _source('nas', id: 'i2', serverName: 'NAS');

      await _pumpPicker(tester, sources: [nas, dead], focusedSourceKey: dead.sourceKey, offerPreferredServer: true);

      expect(find.text(t.sourcePicker.setPreferredServer(server: 'Kantoor')), findsNothing);
    });
  });

  group('intent copy (hoofdstuk 14.2)', () {
    testWidgets('a play intent asks where to play', (tester) async {
      final sources = [_source('nas', serverName: 'NAS'), _source('attic', id: 'i2', serverName: 'Zolder')];

      await _pumpPicker(tester, sources: sources, focusedSourceKey: sources.first.sourceKey);

      expect(find.text(t.sourcePicker.playTitle), findsOneWidget);
      expect(find.text(t.sourcePicker.detailsTitle), findsNothing);
    });

    testWidgets('a details intent asks for a source, and marks the one already open', (tester) async {
      final sources = [_source('nas', serverName: 'NAS'), _source('attic', id: 'i2', serverName: 'Zolder')];

      await _pumpPicker(
        tester,
        sources: sources,
        focusedSourceKey: sources.first.sourceKey,
        intent: UnifiedActivationIntent.details,
        currentSourceKey: sources.first.sourceKey,
      );

      expect(find.text(t.sourcePicker.detailsTitle), findsOneWidget);
      expect(find.text(t.sourcePicker.playTitle), findsNothing);
      expect(find.text(t.sourcePicker.currentSource), findsOneWidget);
    });
  });

  group('accessibility (J8)', () {
    testWidgets('a row announces its position and everything it actually shows', (tester) async {
      final semantics = tester.ensureSemantics();
      final nas = _source('nas', serverName: 'NAS', libraryTitle: 'Films 4K', viewOffsetMs: 2538000);
      final attic = _source('attic', id: 'i2', serverName: 'Zolder', libraryTitle: 'Movies');

      await _pumpPicker(
        tester,
        sources: [nas, attic],
        focusedSourceKey: nas.sourceKey,
        preferredSourceKey: nas.sourceKey,
      );

      expect(
        find.bySemanticsLabel(RegExp(r'Source 1 of 2: NAS, Films 4K, Resume at 42:18, Last used')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'Source 2 of 2: Zolder, Movies')), findsOneWidget);
      semantics.dispose();
    });
  });

  group('the playback failure alternative (F18)', () {
    testWidgets('offers a choice and a way out, and takes neither by itself', (tester) async {
      var chose = 0;
      var closed = 0;

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
                        onPressed: () => OverlaySheetController.of(context).show(
                          presentation: OverlaySheetPresentation.panel,
                          builder: (_) =>
                              TvPlaybackFailureAlternative(onChooseAnother: () => chose++, onClose: () => closed++),
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

      expect(find.text(t.sourcePicker.playbackFailedTitle), findsOneWidget);
      expect(find.text(t.sourcePicker.chooseAnotherSource), findsOneWidget);
      expect(find.text(t.common.close), findsOneWidget);
      expect(chose, 0, reason: 'hoofdstuk 15: the alternative is offered, never taken');

      await _activateByLabel(tester, t.sourcePicker.chooseAnotherSource);
      expect(chose, 1);
      expect(closed, 0);
    });
  });

  // An explicit source-selection intent — "Wijzigen" on a detail page, or
  // "Andere bron kiezen" after a failed start — goes through
  // `showUnifiedSourcePicker` rather than `activateUnifiedMediaGroup`, so the
  // profile's standing default cannot answer a question the user just asked.
  group('explicit source selection bypasses the global preference', () {
    testWidgets('the picker still opens when the preferred server is right there and online', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');
      final opener = FocusNode(debugLabel: 'opener');
      addTearDown(opener.dispose);
      var settled = false;
      UnifiedMediaSource? chosen;

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
                        focusNode: opener,
                        onPressed: () async {
                          chosen = await showUnifiedSourcePicker(
                            context,
                            group: _group([nas, attic]),
                            sources: [nas, attic],
                            initialFocusSourceKey: nas.sourceKey,
                            // The detail page is on NAS and NAS is also the
                            // profile default: the most tempting case to skip.
                            currentSourceKey: nas.sourceKey,
                            preferredServerId: 'nas',
                            coverage: SourceCoverageState.complete({'nas', 'attic'}),
                            intent: UnifiedActivationIntent.details,
                            environment: UnifiedActivationEnvironment(availabilityFor: (s) => s.availability),
                          );
                          settled = true;
                        },
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

      expect(settled, isFalse, reason: 'nothing was chosen for the user');
      expect(chosen, isNull);
      expect(find.text(t.sourcePicker.detailsTitle), findsOneWidget);
      expect(find.text('Zolder'), findsOneWidget, reason: 'the alternative is offered, not hidden');
      // The default is marked, so the user can see what they are overruling.
      expect(find.text(t.sourcePicker.preferredServer), findsOneWidget);
    });

    testWidgets('choosing the other server returns that source, not the default', (tester) async {
      final nas = _source('nas', serverName: 'NAS');
      final attic = _source('attic', id: 'i2', serverName: 'Zolder');
      UnifiedMediaSource? chosen;

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
                        onPressed: () async {
                          chosen = await showUnifiedSourcePicker(
                            context,
                            group: _group([nas, attic]),
                            sources: [nas, attic],
                            initialFocusSourceKey: attic.sourceKey,
                            currentSourceKey: nas.sourceKey,
                            preferredServerId: 'nas',
                            coverage: SourceCoverageState.complete({'nas', 'attic'}),
                            intent: UnifiedActivationIntent.details,
                            environment: UnifiedActivationEnvironment(availabilityFor: (s) => s.availability),
                          );
                        },
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
      await _press(tester, LogicalKeyboardKey.select);

      expect(chosen?.serverId.value, 'attic');
    });
  });

  group('J13: a panel with many sources', () {
    testWidgets('twenty sources render without overflowing, and every one is reachable by D-pad', (tester) async {
      final sources = [for (var i = 0; i < 20; i++) _source('server$i', id: 'i$i', serverName: 'Server $i')];

      await _pumpPicker(tester, sources: sources, focusedSourceKey: sources.first.sourceKey);

      expect(tester.takeException(), isNull, reason: 'a plain Column here would overflow long before twenty rows');
      expect(_focusedRowLabel(tester), 'Server 0');

      // Walk all the way down with the remote, the way a real viewer would.
      for (var i = 0; i < 19; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }

      expect(tester.takeException(), isNull);
      expect(_focusedRowLabel(tester), 'Server 19', reason: 'the last row must actually be reachable, not clipped');
    });
  });
}

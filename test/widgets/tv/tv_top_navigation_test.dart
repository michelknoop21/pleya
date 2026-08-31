/// The fase-7 root navigation bar (hoofdstuk 6.2, 7.2 and 33's shared shell).
///
/// Against the production [TvTopNavigation], not a stand-in: the bar is where
/// "which page am I on" and "where is the remote" are drawn as two different
/// things ([DEC-053]), and a reconstruction would only prove the
/// reconstruction. Focus assertions read the production node's own
/// `debugLabel`, which is [TvDestinationId.focusKey], so a renamed key surfaces
/// as a failure rather than a silent pass.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

void main() {
  late FocusMemoryTracker nodes;
  late List<TvDestinationId> selected;
  late List<TvDestinationId> ringMoves;
  late int downCalls;
  late int profileCalls;

  setUp(() {
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    selected = [];
    ringMoves = [];
    downCalls = 0;
    profileCalls = 0;
  });

  tearDown(() => nodes.dispose());

  /// Drives the bar's inputs without replacing the tree, so a test can change
  /// the destination list the way the shell does — a rebuild — rather than the
  /// way nothing ever does, by tearing the whole app down and putting a new one
  /// up. Node identity across that change is exactly what one test is about.
  late ValueNotifier<List<TvDestinationId>> destinationsIn;
  late ValueNotifier<TvDestinationId> activeIn;

  Future<void> pump(
    WidgetTester tester, {
    required List<TvDestinationId> destinations,
    required TvDestinationId active,
    Locale? locale,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    destinationsIn = ValueNotifier(destinations);
    activeIn = ValueNotifier(active);
    addTearDown(destinationsIn.dispose);
    addTearDown(activeIn.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: ValueListenableBuilder<List<TvDestinationId>>(
                valueListenable: destinationsIn,
                builder: (context, destinations, _) => ValueListenableBuilder<TvDestinationId>(
                  valueListenable: activeIn,
                  builder: (context, active, _) => TvTopNavigation(
                    destinations: destinations,
                    active: active,
                    nodes: nodes,
                    onSelect: selected.add,
                    onFocusDestination: ringMoves.add,
                    onNavigateDown: () => downCalls++,
                    onOpenProfiles: () => profileCalls++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<TvDestinationId> withoutLiveTv() => buildTvDestinations(const TvNavConditions(hasLiveTv: false));
  List<TvDestinationId> withLiveTv() => buildTvDestinations(const TvNavConditions(hasLiveTv: true));

  String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  void focus(String key) => nodes.get(key).requestFocus();

  // ---------------------------------------------------------------------------
  // Composition (hoofdstuk 33's shared shell)
  // ---------------------------------------------------------------------------

  group('composition', () {
    testWidgets('draws the decided destination order, with Series before Films', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      final labels = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().toList();

      expect(
        labels,
        containsAllInOrder(<String>[t.common.home, t.unifiedCatalog.seriesTitle, t.unifiedCatalog.moviesTitle]),
      );
      // Series before Films is a decided rule (DEC-064), not an accident of the
      // rail's historical order.
      expect(labels.indexOf(t.unifiedCatalog.seriesTitle), lessThan(labels.indexOf(t.unifiedCatalog.moviesTitle)));
    });

    testWidgets('Search is a compact control, so it carries no label of its own', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      expect(find.byIcon(Symbols.search_rounded), findsOneWidget);
      expect(find.text(t.common.search), findsNothing);
    });

    testWidgets('the wordmark stands at the far right and is not a focus stop', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/branding/pleya_wordmark.png');
      // Branding, not a destination. Counted rather than probed: the bar holds
      // exactly one focus stop per destination plus the profile chip, so a
      // focusable wordmark would show up here as an extra — and it would
      // dead-end every rightward walk of the bar.
      expect(find.byType(FocusableWrapper), findsNWidgets(withoutLiveTv().length + 1));
    });

    testWidgets('a conditional Live TV slot sits between Films and Mijn Pleya', (tester) async {
      await pump(tester, destinations: withLiveTv(), active: TvDestinationId.home);

      final labels = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().toList();
      expect(
        labels,
        containsAllInOrder(<String>[t.unifiedCatalog.moviesTitle, t.navigation.liveTv, t.navigation.myPleya]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Active versus focused (DEC-053, hoofdstuk 33)
  // ---------------------------------------------------------------------------

  group('active is not focused', () {
    testWidgets('the active destination is a white capsule with dark text', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.movies);

      final context = tester.element(find.byType(TvTopNavigation));
      final tk = tokens(context);

      final activeText = tester.widget<Text>(find.text(t.unifiedCatalog.moviesTitle));
      expect(activeText.style?.color, tk.bg, reason: 'dark ink on the white capsule');

      final idleText = tester.widget<Text>(find.text(t.common.home));
      expect(idleText.style?.color, isNot(tk.bg));
      expect(idleText.style?.color?.a, lessThan(1.0), reason: 'inactive destinations stay quiet');
    });

    testWidgets('walking the ring onto another destination does not move the capsule', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.movies);

      focus(TvDestinationId.movies.focusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);

      expect(focusedLabel(), TvDestinationId.series.focusKey);
      // The ring moved; nothing was activated, so no page changed behind it.
      expect(ringMoves.last, TvDestinationId.series);
      expect(selected, isEmpty);
    });

    testWidgets('red is nowhere in the bar', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      // Hoofdstuk 33 reserves #E5140F for the progress line. A red active pill
      // or a red focus ring is the exact thing the north star rules out.
      final colours = [
        ...tester.widgetList<Text>(find.byType(Text)).map((text) => text.style?.color),
        ...tester.widgetList<Icon>(find.byType(Icon)).map((icon) => icon.color),
      ].whereType<Color>();
      expect(colours.any((c) => c == kAccent), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Focus traversal (hoofdstuk 7.2)
  // ---------------------------------------------------------------------------

  group('traversal', () {
    testWidgets('Left and Right walk the siblings', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      focus(TvDestinationId.home.focusKey);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), TvDestinationId.series.focusKey);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), TvDestinationId.movies.focusKey);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), TvDestinationId.series.focusKey);
    });

    testWidgets('the last destination does not wrap round to the first', (tester) async {
      final destinations = withoutLiveTv();
      await pump(tester, destinations: destinations, active: TvDestinationId.home);

      focus(destinations.last.focusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);

      // Hoofdstuk 7.2: no wrap. Holding Right on a remote would otherwise walk
      // the bar forever and the viewer loses track of where they are.
      expect(focusedLabel(), destinations.last.focusKey);
    });

    testWidgets('Left from the first destination reaches the profile chip, and stops there', (tester) async {
      final destinations = withoutLiveTv();
      await pump(tester, destinations: destinations, active: TvDestinationId.home);

      focus(destinations.first.focusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), 'tvNav_profile');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), 'tvNav_profile');
    });

    testWidgets('Down from any bar item goes into the content', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      focus(TvDestinationId.series.focusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(downCalls, 1);

      focus('tvNav_profile');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(downCalls, 2);
    });

    testWidgets('Select activates the destination the ring is on', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      focus(TvDestinationId.movies.focusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);

      expect(selected, [TvDestinationId.movies]);
    });

    testWidgets('Select on the profile chip opens the profile picker, not a destination', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      focus('tvNav_profile');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);

      expect(profileCalls, 1);
      expect(selected, isEmpty);
    });

    testWidgets('a Live TV slot appearing does not replace the focus node of an existing item', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);
      final before = nodes.get(TvDestinationId.myPleya.focusKey);
      focus(TvDestinationId.myPleya.focusKey);
      await tester.pump();

      destinationsIn.value = withLiveTv();
      await tester.pumpAndSettle();

      // Hoofdstuk 7.2's last bullet: the new item gets a stable id of its own
      // and must not take an existing item's node with it. So Mijn Pleya keeps
      // the very same node, and the remote does not move.
      expect(identical(nodes.get(TvDestinationId.myPleya.focusKey), before), isTrue);
      expect(focusedLabel(), TvDestinationId.myPleya.focusKey);
      expect(find.text(t.navigation.liveTv), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Accessibility and localisation (hoofdstuk 25, 27)
  // ---------------------------------------------------------------------------

  group('accessibility', () {
    testWidgets('the active destination announces that it is the one you are on', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.movies);

      // Active and focused are drawn differently, so they have to be *said*
      // differently too — otherwise all six items announce the same thing and
      // VoiceOver cannot tell a viewer which page is open.
      expect(
        find.bySemanticsLabel('${t.unifiedCatalog.moviesTitle}, ${t.tvNavigation.activeDestination}'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(t.unifiedCatalog.seriesTitle), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the profile chip says what pressing it does', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);

      expect(find.bySemanticsLabel(t.screens.switchProfile), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a long locale keeps every destination on one line and the bar one row high', (tester) async {
      await pump(tester, destinations: withLiveTv(), active: TvDestinationId.home);
      final baseline = tester.getSize(find.byType(TvTopNavigation));

      await pump(tester, destinations: withLiveTv(), active: TvDestinationId.home, locale: const Locale('de'));

      expect(tester.getSize(find.byType(TvTopNavigation)).height, baseline.height);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.maxLines, 1, reason: 'a wrapped destination would change the height of the whole bar');
      }
      expect(tester.takeException(), isNull);
    });
  });
}

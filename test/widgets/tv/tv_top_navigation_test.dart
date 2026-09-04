/// The fase-7 root navigation bar (hoofdstuk 6.2, 7.2 and 33's shared shell).
///
/// Against the production [TvTopNavigation], not a stand-in: the bar is where
/// "which page am I on" and "where is the remote" are drawn as two different
/// things ([DEC-053]), and a reconstruction would only prove the
/// reconstruction. Focus assertions read the production node's own
/// `debugLabel`, which is [TvDestinationId.focusKey], so a renamed key surfaces
/// as a failure rather than a silent pass.
library;

import 'dart:math' as math;

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
import 'package:pleya/widgets/pleya_wordmark.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

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
    double? textScaleFactor,
    // Every existing test in this file runs the dark palette, which is where
    // the bar has always been rendered. The J18 group below needs the light one.
    bool dark = true,
    bool oled = false,
    bool needsAttention = false,
    bool dimmed = false,
    TextDirection? directionality,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (textScaleFactor != null) {
      // Not a manually-inserted `MediaQuery`/`Builder` override: that combined
      // with this bar's own `ValueListenableBuilder`s produced a genuine
      // infinite rebuild loop (a real Flutter stack overflow, reproduced and
      // isolated separately — nothing to do with this bar's own code). Setting
      // the platform dispatcher's test value is the supported seam and flows
      // through the app's own root MediaQuery exactly like a real OS setting
      // would, with none of that risk.
      tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    destinationsIn = ValueNotifier(destinations);
    activeIn = ValueNotifier(active);
    addTearDown(destinationsIn.dispose);
    addTearDown(activeIn.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          theme: monoTheme(dark: dark, oled: oled),
          home: InputModeTracker(
            child: Scaffold(
              body: ValueListenableBuilder<List<TvDestinationId>>(
                valueListenable: destinationsIn,
                builder: (context, destinations, _) => ValueListenableBuilder<TvDestinationId>(
                  valueListenable: activeIn,
                  builder: (context, active, _) {
                    final bar = TvTopNavigation(
                      destinations: destinations,
                      active: active,
                      nodes: nodes,
                      needsAttention: needsAttention,
                      dimmed: dimmed,
                      onSelect: selected.add,
                      onFocusDestination: ringMoves.add,
                      onNavigateDown: () => downCalls++,
                      onOpenProfiles: () => profileCalls++,
                    );
                    return directionality == null ? bar : Directionality(textDirection: directionality, child: bar);
                  },
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

  group('dimmed under an overlay (audit divergentie 13, DEC-095)', () {
    double barOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.descendant(of: find.byType(TvTopNavigation), matching: find.byType(AnimatedOpacity)).first,
        )
        .opacity;

    testWidgets('the bar is opaque on its own and fades to the token when dimmed', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home);
      expect(barOpacity(tester), 1);
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home, dimmed: true);
      expect(barOpacity(tester), TvTopNavLayout.dimmedOpacity);
    });

    testWidgets('dimming keeps every destination in the tree, so the bar comes back where it was', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home, dimmed: true);
      for (final d in withoutLiveTv().where((d) => !d.isCompact)) {
        expect(find.text(d.label), findsOneWidget, reason: '${d.focusKey} must not be unmounted by the dim');
      }
    });
  });

  group('the attention dot', () {
    Rect dotRect(WidgetTester tester) =>
        tester.getRect(find.descendant(of: find.byType(TvTopNavigation), matching: find.byType(Container)).last);

    testWidgets('sits on the trailing corner of the pill in both directions', (tester) async {
      // `Positioned(right:)` is a physical edge: the bar mirrors under RTL and
      // the dot would stay on the physical right, i.e. the leading corner. The
      // same physical-versus-directional mismatch DEC-072 fixed for the hero
      // CTAs, and the one thing about this bar an RTL sweep would have caught.
      await pump(
        tester,
        destinations: withoutLiveTv(),
        active: TvDestinationId.home,
        needsAttention: true,
        directionality: TextDirection.ltr,
      );
      final pill = tester.getRect(find.byKey(const ValueKey('tvNav_myPleya')));
      final ltrDot = dotRect(tester);
      expect(ltrDot.center.dx, greaterThan(pill.center.dx), reason: 'LTR: trailing is the right corner');

      await pump(
        tester,
        destinations: withoutLiveTv(),
        active: TvDestinationId.home,
        needsAttention: true,
        directionality: TextDirection.rtl,
      );
      final rtlPill = tester.getRect(find.byKey(const ValueKey('tvNav_myPleya')));
      expect(dotRect(tester).center.dx, lessThan(rtlPill.center.dx), reason: 'RTL: trailing is the left corner');
    });
  });

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

      expect(find.byType(PleyaWordmark), findsOneWidget);
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

    testWidgets('the whole chain walks one destination per press, in both directions', (tester) async {
      // The physical Apple TV finding: LEFT on Series jumped straight to
      // Search, and RIGHT on Search straight to Series — Home fell out of the
      // route in both directions. The existing walk test only covered
      // Home → Series → Films and back, which is precisely the stretch that
      // works, so it never saw the boundary the report is about.
      final destinations = withoutLiveTv();
      expect(
        destinations,
        containsAllInOrder([
          TvDestinationId.search,
          TvDestinationId.home,
          TvDestinationId.series,
          TvDestinationId.movies,
          TvDestinationId.myPleya,
        ]),
        reason: 'sanity: the bar is in the order the contract names',
      );

      await pump(tester, destinations: destinations, active: TvDestinationId.home);
      focus(TvDestinationId.search.focusKey);
      await tester.pump();

      for (var i = 1; i < destinations.length; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedLabel(), destinations[i].focusKey, reason: 'RIGHT step $i stops on every destination in turn');
      }

      for (var i = destinations.length - 2; i >= 0; i--) {
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedLabel(), destinations[i].focusKey, reason: 'LEFT step $i stops on every destination in turn');
      }
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

    testWidgets('J6: a large system text scale keeps the bar one row high and does not overflow', (tester) async {
      await pump(tester, destinations: withLiveTv(), active: TvDestinationId.home);
      final baseline = tester.getSize(find.byType(TvTopNavigation));

      await pump(tester, destinations: withLiveTv(), active: TvDestinationId.home, textScaleFactor: 1.5);

      expect(
        tester.getSize(find.byType(TvTopNavigation)).height,
        baseline.height,
        reason: 'hoofdstuk 25: "Topnav mag niet buiten beeld lopen"',
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.maxLines, 1, reason: 'a wrapped destination at 1.5x scale would change the height of the bar');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('J18: the wordmark ink follows the surface it sits on', () {
    Finder layer(String asset) => find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset,
      description: asset,
    );

    Image letteringOf(WidgetTester tester) => tester.widget<Image>(layer(PleyaWordmark.letteringAsset));

    Image markOf(WidgetTester tester) => tester.widget<Image>(layer(PleyaWordmark.markAsset));

    /// WCAG relative luminance, so the assertion is about legibility rather
    /// than about which constant happened to be written down.
    double luminance(Color c) {
      double channel(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
    }

    double contrast(Color a, Color b) {
      final (la, lb) = (luminance(a), luminance(b));
      final (hi, lo) = la > lb ? (la, lb) : (lb, la);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final (name, dark, oled) in const [('light', false, false), ('dark', true, false), ('OLED', true, true)]) {
      testWidgets('on $name the lettering takes the theme ink and the mark never does', (tester) async {
        // One composition path for every palette — the light/dark fork this
        // group used to assert is gone with the brand refresh ([DEC-074]).
        await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home, dark: dark, oled: oled);

        final tk = Theme.of(tester.element(find.byType(TvTopNavigation))).extension<MonoTokens>()!;
        expect(letteringOf(tester).color, tk.text);
        expect(letteringOf(tester).colorBlendMode, BlendMode.srcIn);
        // Hoofdstuk 8.2 keeps Pleya red for brand details, so the mark is the
        // half that must never be retinted — on any palette.
        expect(markOf(tester).color, isNull, reason: 'the brand layer was tinted on $name');
      });
    }

    testWidgets('the ink the lettering gets actually reads on the ground it sits on', (tester) async {
      // The assertion that encodes J18 itself rather than the shape of its fix.
      // An equality check against `tk.text` would still pass if someone later
      // hardcoded a pale constant, or if the token drifted.
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home, dark: false);

      final tk = Theme.of(tester.element(find.byType(TvTopNavigation))).extension<MonoTokens>()!;
      // The same expression `TvRootShell` paints under the bar.
      final ground = Color.alphaBlend(tk.text.withValues(alpha: TvCatalogLayout.pageLift), tk.bg);

      expect(
        contrast(letteringOf(tester).color!, ground),
        greaterThan(4.5),
        reason: 'the wordmark was invisible at 1,12:1 before this fix; it must not go back',
      );
    });

    testWidgets('the lockup is sized by height, never by the canvas width', (tester) async {
      // The canvas grew when the lockup started being composed from the current
      // mark. A caller that pinned a width would have squashed or cropped it.
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home, dark: false);

      for (final asset in PleyaWordmark.assets) {
        final image = tester.widget<Image>(layer(asset));
        expect(image.width, isNull, reason: '$asset is pinned to a width');
        expect(image.height, isNotNull);
        expect(image.fit, BoxFit.contain);
      }
    });

    testWidgets('two layers are still not a focus stop', (tester) async {
      await pump(tester, destinations: withoutLiveTv(), active: TvDestinationId.home, dark: false);

      expect(find.byType(FocusableWrapper), findsNWidgets(withoutLiveTv().length + 1));
    });
  });

  // The tvOS remote contract revised on 2 September 2026: focus on a bar item
  // *is* the navigation. These pin the bar's half of it — that a ring move
  // reports a destination and that Select is not what switches.
  //
  // `onFocusDestination` was always the seam ("Reports the ring moving.
  // Distinct from onSelect on purpose"), so what changed is who listens to it
  // and what they do; the negative control lives at that listener, in
  // `main_screen_tv_nav_test.dart`, because the old behaviour was the shell
  // wiring this callback at `TvNavigationCoordinator.focusDestination`, which
  // moves the ring and stops there.
  group('focus is the destination', () {
    testWidgets('walking RIGHT reports every item the ring lands on, and selects nothing', (tester) async {
      await pump(
        tester,
        destinations: TvDestinationId.values.where((d) => d != TvDestinationId.liveTv).toList(),
        active: TvDestinationId.home,
      );
      focus(TvDestinationId.home.focusKey);
      await tester.pump();
      ringMoves.clear();

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(ringMoves, [TvDestinationId.series, TvDestinationId.movies, TvDestinationId.myPleya]);
      expect(selected, isEmpty, reason: 'Select must not be needed to change destination');
    });

    testWidgets('the last item walked to is the last one reported, however fast the walk', (tester) async {
      await pump(
        tester,
        destinations: TvDestinationId.values.where((d) => d != TvDestinationId.liveTv).toList(),
        active: TvDestinationId.home,
      );
      focus(TvDestinationId.home.focusKey);
      await tester.pump();
      ringMoves.clear();

      // No settle between presses: this is the "faster than pages load" case.
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.pumpAndSettle();

      expect(ringMoves.last, TvDestinationId.myPleya);
      expect(selected, isEmpty);
    });

    testWidgets('Select still reports the focused destination, for "go into this content"', (tester) async {
      await pump(
        tester,
        destinations: TvDestinationId.values.where((d) => d != TvDestinationId.liveTv).toList(),
        active: TvDestinationId.movies,
      );
      focus(TvDestinationId.movies.focusKey);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.select);

      expect(selected, [TvDestinationId.movies]);
    });
  });
}

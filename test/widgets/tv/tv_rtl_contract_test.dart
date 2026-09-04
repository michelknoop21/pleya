/// J7 — the RTL contract of hoofdstuk 25.
///
/// Five clauses, and they do not all mean the same kind of thing:
///
///   1. "Tekstkolom en scrim spiegelen" — both move to the other edge.
///   2. "CTA-volgorde logisch spiegelen" — Afspelen and Meer info swap places.
///   3. "Artworkpixel zelf niet spiegelen" — the image is never flipped.
///   4. "Source metadata alignment aanpassen" — the source rows follow suit.
///   5. "Links/rechts voor de carousel blijft gekoppeld aan de visuele
///      richting" — the slide does *not* flip with the text.
///
/// Clauses 2, 3 and 5 were already satisfied — by `Row` resolving its own
/// order, by nothing ever mirroring an image, and by the carousel dispatching
/// on the physical arrow key rather than a traversal direction. Clause 1 was
/// not: the reading scrim was a hardcoded left-to-right ramp and the title
/// block a hardcoded `bottomLeft`, so under an RTL directionality the wash
/// would have sat opposite the type it exists to make readable. Clause 4 was
/// already written directionally in `tv_source_row.dart`.
///
/// Every test below renders both directionalities and compares them, because
/// an assertion that only reads the RTL frame cannot tell "mirrored" from
/// "identical, and wrong in both".
///
/// J17 sits in the same file because it is the same surface under the same
/// override, and it is where clause 2 stops: mirroring the CTA *order* is not
/// the same question as which physical arrow reaches which pill afterwards.
/// [DEC-072] answers that one — spatial D-pad navigation follows the rendered
/// geometry, never the logical action order — and the second group below pins
/// it. Semantics and focus are two contracts: the reading order may mirror, the
/// direction keys may not.
///
/// Pleya ships no RTL locale today (all sixteen are LTR), so none of this is
/// reachable by a viewer yet. That is exactly why it is pinned: the day a
/// locale is added, the failure would otherwise be found by eye, in the one
/// place hoofdstuk 25 says it must not be.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/widgets/tv/tv_hero_artwork.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:pleya/widgets/tv/tv_source_row.dart';
import 'package:pleya/widgets/tv/tv_source_row_descriptor.dart';

import '../../test_helpers/prefs.dart';

MediaItem _film(String id, String title) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: 2024,
  summary: '$title has a synopsis long enough to fill the hero block.',
  genres: const ['Drama'],
  durationMs: 100 * 60 * 1000,
  serverId: 'nas',
  serverName: 'NAS',
);

UnifiedMediaGroup _group(String id, String title) {
  final source = UnifiedMediaSource.fromItem(_film(id, title));
  return UnifiedMediaGroup(
    groupId: id,
    identity: canonicalIdentityOf(source.item) ?? CanonicalMediaIdentity.opaque(),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: selectRepresentativeWatchState({source.sourceKey: source.item}),
  );
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  const size = Size(760, 308);

  Future<void> pumpCarousel(
    WidgetTester tester,
    TextDirection direction, {
    List<UnifiedMediaGroup>? groups,
    void Function(UnifiedMediaGroup group, {required UnifiedActivationIntent intent, required bool playDirectly})?
    onActivate,
  }) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(1038, 584)),
              child: InputModeTracker(
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: TvHeroBillboardCarousel(
                        groups: groups ?? [_group('g1', 'First'), _group('g2', 'Second')],
                        size: size,
                        autoplayEnabled: false,
                        onActivate: (group, {required intent, required playDirectly}) =>
                            onActivate?.call(group, intent: intent, playDirectly: playDirectly),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FocusNode node(WidgetTester tester, String label) => tester
      .widgetList<Focus>(find.byType(Focus))
      .map((f) => f.focusNode)
      .whereType<FocusNode>()
      .firstWhere((n) => n.debugLabel == label);

  String shownTitle(WidgetTester tester) =>
      heroTitleFor(tester.widget<TvHeroBillboardCard>(find.byType(TvHeroBillboardCard)).group);

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pump();
  }

  const play = 'tvHeroPlay';
  const info = 'tvHeroMoreInfo';

  /// The two CTAs by focus-node label, in the order they are actually painted
  /// from left to right. Read off the geometry, never assumed: it is precisely
  /// the rendered order that the D-pad has to agree with.
  List<String> renderedOrder(WidgetTester tester) {
    final centres = {
      play: tester.getRect(find.text(t.common.play)).center.dx,
      info: tester.getRect(find.text(t.mediaMenu.viewDetails)).center.dx,
    };
    return centres.keys.toList()..sort((a, b) => centres[a]!.compareTo(centres[b]!));
  }

  String? focusedCta(WidgetTester tester) {
    for (final label in const [play, info]) {
      if (node(tester, label).hasFocus) return label;
    }
    return null;
  }

  Future<void> focusCta(WidgetTester tester, String label) async {
    node(tester, label).requestFocus();
    await tester.pump();
  }

  group('J7: the hero under a right-to-left directionality', () {
    testWidgets('clause 1: the title block moves to the other edge', (tester) async {
      await pumpCarousel(tester, TextDirection.ltr);
      final ltrTitle = tester.getRect(find.text('First'));
      final card = tester.getRect(find.byType(TvHeroBillboardCard));

      await pumpCarousel(tester, TextDirection.rtl);
      final rtlTitle = tester.getRect(find.text('First'));

      // A true mirror, not merely "somewhere on the other half": the distance
      // from the leading edge has to be the same on both sides. A title block
      // that mirrored its padding but kept a physical `bottomLeft` inside it
      // would drift by the width of the column and still land in the right
      // half, which is exactly the failure this comparison catches.
      expect(
        card.right - rtlTitle.right,
        closeTo(ltrTitle.left - card.left, 1),
        reason: 'hoofdstuk 25: the text column mirrors, so it sits as far from the right edge as it did from the left',
      );
      expect(rtlTitle.left, isNot(closeTo(ltrTitle.left, 1)), reason: 'and it genuinely moved');
    });

    testWidgets('clause 1: the reading scrim is defined directionally, so it follows the column', (tester) async {
      await pumpCarousel(tester, TextDirection.rtl);

      // The scrim is a gradient, so what is asserted is how it is *specified*:
      // a directional geometry follows the text column, a physical one cannot.
      // This is the exact property the fix changed.
      //
      // Only the horizontal ramps are the subject. The bottom scrim runs
      // vertically and the empty-artwork placeholder diagonally; neither is a
      // reading plate for the text column, and hoofdstuk 25 asks nothing of
      // them.
      bool isHorizontal(LinearGradient gradient) {
        final begin = gradient.begin.resolve(TextDirection.ltr);
        final end = gradient.end.resolve(TextDirection.ltr);
        return begin.y == end.y && begin.x != end.x;
      }

      final horizontalWashes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>()
          .where(isHorizontal)
          .toList();

      expect(horizontalWashes, isNotEmpty, reason: 'the hero has a horizontal reading scrim');
      for (final wash in horizontalWashes) {
        // Both ends: a gradient with a directional start and a physical finish
        // mirrors its origin and not its ramp, which is its own kind of wrong.
        expect(
          wash.begin,
          isA<AlignmentDirectional>(),
          reason: 'a physically-pinned wash would sit opposite the text column it exists for',
        );
        expect(wash.end, isA<AlignmentDirectional>(), reason: 'and it has to run to the other edge, not to "right"');
      }
    });

    testWidgets('clause 2: the CTA order mirrors', (tester) async {
      await pumpCarousel(tester, TextDirection.ltr);
      final ltrPlay = tester.getRect(find.text(t.common.play));
      final ltrInfo = tester.getRect(find.text(t.mediaMenu.viewDetails));
      expect(ltrPlay.left, lessThan(ltrInfo.left));

      await pumpCarousel(tester, TextDirection.rtl);
      final rtlPlay = tester.getRect(find.text(t.common.play));
      final rtlInfo = tester.getRect(find.text(t.mediaMenu.viewDetails));
      expect(rtlInfo.left, lessThan(rtlPlay.left), reason: 'hoofdstuk 25: the CTA order mirrors logically');
    });

    testWidgets('clause 3: the artwork itself is not mirrored', (tester) async {
      await pumpCarousel(tester, TextDirection.ltr);
      final ltrArt = tester.getRect(find.byType(TvHeroArtwork));

      await pumpCarousel(tester, TextDirection.rtl);
      final rtlArt = tester.getRect(find.byType(TvHeroArtwork));

      // Same box, and nothing flipping what is painted into it: hoofdstuk 25
      // mirrors the composition, never the pixels.
      expect(rtlArt, ltrArt);
      expect(
        find.descendant(of: find.byType(TvHeroArtwork), matching: find.byType(Transform)),
        findsNothing,
        reason: 'a Transform under the artwork is how a mirrored image would arrive',
      );
    });

    testWidgets('clause 4: a source row runs from the leading edge in both directions', (tester) async {
      // `tv_source_row.dart` was already written directionally; this pins it,
      // because a resume bar that stayed physically left would read as "almost
      // finished" on an RTL surface where the row's own text starts on the
      // right.
      Future<Rect> fillRect(TextDirection direction) async {
        await tester.pumpWidget(
          TranslationProvider(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: Directionality(
                textDirection: direction,
                child: InputModeTracker(
                  child: Scaffold(
                    body: SizedBox(
                      width: 600,
                      child: TvSourceRow(
                        externalFocusNode: null,
                        scale: 1,
                        descriptor: const TvSourceRowDescriptor(
                          sourceKey: 'nas:1',
                          serverName: 'NAS',
                          contextParts: ['Films'],
                          qualityParts: ['2160p'],
                          availability: SourceAvailability.online,
                          isPreferred: false,
                          isCurrent: false,
                          progressLabel: '42 min',
                          progressFraction: 0.25,
                        ),
                        index: 0,
                        total: 1,
                        shouldTakeFocus: false,
                        idleColor: const Color(0xFF202020),
                        onSelect: () {},
                        onFocused: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.getRect(find.byType(FractionallySizedBox));
      }

      final ltr = await fillRect(TextDirection.ltr);
      final ltrTrack = tester.getRect(find.byType(TvSourceRow));
      final rtl = await fillRect(TextDirection.rtl);
      final rtlTrack = tester.getRect(find.byType(TvSourceRow));

      // Measured from each direction's own leading edge: the inset is the
      // row's padding, and what matters is that it is the same inset on the
      // side the row actually starts from.
      expect(
        rtlTrack.right - rtl.right,
        closeTo(ltr.left - ltrTrack.left, 1),
        reason: 'the resume fill grows from the leading edge, which flips with the directionality',
      );
      expect(rtl.width, closeTo(ltr.width, 1), reason: 'same fraction, only the edge it starts from moves');
      expect(rtl.left, isNot(closeTo(ltr.left, 1)), reason: 'and it genuinely moved');
    });

    testWidgets('clause 5: the slide does not flip with the text', (tester) async {
      // The carousel dispatches on the physical arrow, so Right is always the
      // next slide and Left always the previous one, in both directionalities.
      // This is deliberately *not* symmetric with the mirrored CTA order above
      // — hoofdstuk 25 ties the carousel to the visual direction and only the
      // CTA order to the logical one.
      //
      // The press starts from the CTA at the visual edge, which under RTL is
      // the *other* pill than under LTR. That is not a change to this clause:
      // the edge of the row is where the carousel takes over, and the edge is a
      // position, not a button. Reading it off `renderedOrder` is what keeps
      // this test measuring the carousel instead of accidentally re-measuring
      // the CTA order two clauses up.
      for (final direction in TextDirection.values) {
        await pumpCarousel(tester, direction);

        await focusCta(tester, renderedOrder(tester).last);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(
          shownTitle(tester),
          'Second',
          reason: 'hoofdstuk 25: Right off the right edge is the next slide, in $direction too',
        );

        await focusCta(tester, renderedOrder(tester).first);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(
          shownTitle(tester),
          'First',
          reason: 'and Left off the left edge is the previous one, in $direction too',
        );
      }
    });
  });

  group('J17: D-pad LEFT/RIGHT across the hero CTAs follows the rendered geometry', () {
    // The clause above mirrors the CTA *order*; this one is about which
    // physical arrow reaches which pill afterwards. Under RTL the row renders
    // `Meer info` left of `Afspelen`, and wiring the arrows to the list order
    // would make RIGHT walk the focus leftwards across the screen. Semantics
    // and focus are two different contracts: reading order may mirror, spatial
    // navigation follows the geometry that was actually laid out.

    testWidgets('LTR: the left CTA + Right reaches the CTA on the right', (tester) async {
      await pumpCarousel(tester, TextDirection.ltr);
      final order = renderedOrder(tester);
      expect(order, [play, info], reason: 'the premise: under LTR the row paints Afspelen first');

      await focusCta(tester, order.first);
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(focusedCta(tester), order.last);
      expect(shownTitle(tester), 'First', reason: 'and the slide did not move while crossing the row');
    });

    testWidgets('LTR: the right CTA + Left reaches the CTA on the left', (tester) async {
      await pumpCarousel(tester, TextDirection.ltr);
      final order = renderedOrder(tester);

      await focusCta(tester, order.last);
      await press(tester, LogicalKeyboardKey.arrowLeft);

      expect(focusedCta(tester), order.first);
      expect(shownTitle(tester), 'First');
    });

    testWidgets('RTL: the visually left CTA + Right reaches the CTA on the right', (tester) async {
      await pumpCarousel(tester, TextDirection.rtl);
      final order = renderedOrder(tester);
      // The whole point of the case: the rendered order is genuinely the other
      // way round, so "first" here is Meer info and Right must still travel
      // rightwards on the glass.
      expect(order, [info, play], reason: 'the premise: under RTL the row paints Meer info on the left');

      await focusCta(tester, order.first);
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(
        focusedCta(tester),
        order.last,
        reason: 'Right moves to the control that is physically to the right, not the next one in the list',
      );
      expect(shownTitle(tester), 'First', reason: 'and the slide did not move while crossing the row');
    });

    testWidgets('RTL: the visually right CTA + Left reaches the CTA on the left', (tester) async {
      await pumpCarousel(tester, TextDirection.rtl);
      final order = renderedOrder(tester);

      await focusCta(tester, order.last);
      await press(tester, LogicalKeyboardKey.arrowLeft);

      expect(focusedCta(tester), order.first, reason: 'and Left is its exact inverse');
      expect(shownTitle(tester), 'First');
    });

    testWidgets('the labels stay bound to their own control in both directions', (tester) async {
      // A fix that swapped the focus nodes instead of the wiring would pass the
      // four traversal tests above and quietly leave `Afspelen` announcing
      // itself as `Meer info`.
      for (final direction in TextDirection.values) {
        await pumpCarousel(tester, direction);

        String nodeUnder(String label) => tester
            .widget<FocusableButton>(find.ancestor(of: find.text(label), matching: find.byType(FocusableButton)))
            .focusNode!
            .debugLabel!;

        expect(nodeUnder(t.common.play), play, reason: 'the Afspelen pill is the Afspelen control, in $direction');
        expect(nodeUnder(t.mediaMenu.viewDetails), info, reason: 'and Meer info is Meer info, in $direction');
      }
    });

    testWidgets('the actions are not swapped along with the geometry', (tester) async {
      // Directional traversal must not touch what a press does: `Afspelen`
      // still plays and `Meer info` still opens the details, whichever side of
      // the row each of them ended up on.
      for (final direction in TextDirection.values) {
        final fired = <String, UnifiedActivationIntent>{};
        await pumpCarousel(
          tester,
          direction,
          onActivate: (group, {required intent, required playDirectly}) => fired[focusedCta(tester) ?? 'none'] = intent,
        );

        await focusCta(tester, play);
        await press(tester, LogicalKeyboardKey.select);
        await focusCta(tester, info);
        await press(tester, LogicalKeyboardKey.select);

        expect(fired[play], UnifiedActivationIntent.play, reason: 'Afspelen still plays, in $direction');
        expect(fired[info], UnifiedActivationIntent.details, reason: 'Meer info still opens details, in $direction');
      }
    });

    testWidgets('no dead end and no loop: the row is crossable and hands off at both edges', (tester) async {
      for (final direction in TextDirection.values) {
        await pumpCarousel(tester, direction);
        final order = renderedOrder(tester);

        // There and back, from either end: every press lands on a control, and
        // the pair is its own inverse rather than a one-way street.
        await focusCta(tester, order.first);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedCta(tester), order.last, reason: 'crossable in $direction');
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(focusedCta(tester), order.first, reason: 'and reversible in $direction');

        // Off the right edge the carousel takes over — the focus stays put on
        // the edge control rather than falling into nothing, which is the dead
        // end this asserts against.
        await focusCta(tester, order.last);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(shownTitle(tester), 'Second');
        expect(focusedCta(tester), order.last, reason: 'the edge hands off to the slide and keeps the focus');
      }
    });
  });
}

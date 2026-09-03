/// What VoiceOver reads for one card in the unified Films/Series grid
/// (docs/tvos-unified-experience.md hoofdstuk 25, edge-case register J8).
///
/// [semanticLabelFor] is public and pure so this contract is assertable without
/// a widget tree, and most of this file takes that route. The last group pumps
/// a real card anyway, because a pure function nobody reads is worth nothing:
/// the point of the widget test is that the string proven here is the string
/// the semantics node actually carries, not a second implementation that has
/// drifted away from the one under test.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';

import '../../test_helpers/tv_catalog_artwork.dart';
import '../../test_helpers/tv_catalog_fixtures.dart';

/// One group, dialled to exactly the combination a case is about.
///
/// Built on the shared catalog fixtures rather than on hand-rolled items, so a
/// change to what a Films card is made of reaches these assertions instead of
/// leaving them testing a shape the grid stopped using.
UnifiedMediaGroup _group({
  required String title,
  int? year = 2021,
  int sources = 1,
  bool watched = false,
  bool inProgress = false,
  int? durationMs = 9960000,
}) => tvGoldenGroup(
  'g-$title',
  [
    for (var s = 0; s < sources; s++)
      tvGoldenMovie(
        id: '$title-$s',
        title: title,
        year: year,
        artwork: 0,
        // Only the first source carries the watch facts, which is the shape
        // hoofdstuk 13.2 produces: one representative source speaks for the
        // group.
        viewOffsetMs: s == 0 && inProgress ? 2538000 : null,
        durationMs: durationMs,
        viewCount: s == 0 && watched ? 1 : null,
        serverId: const ['nas', 'attic', 'shed'][s],
        serverName: const ['NAS', 'Zolder', 'Schuur'][s],
      ),
  ],
  watched: watched,
  inProgress: inProgress,
);

void main() {
  group('semanticLabelFor', () {
    test('the title leads, and on a bare group it is the whole label', () {
      // A listener scanning a grid of forty hears the title first on every
      // card or the grid is not scannable at all. Nothing else is true of this
      // group, so nothing else may be said about it.
      expect(semanticLabelFor(_group(title: 'Nosferatu', year: null)), 'Nosferatu');
    });

    test('the year follows the title when the source knows one', () {
      expect(semanticLabelFor(_group(title: 'Dune: Part Two', year: 2024)), 'Dune: Part Two, 2024');
    });

    test('a source with no year says nothing about a year', () {
      // Not "unknown", not an empty slot with its separator still in place:
      // "Casablanca, , 2 sources" is what a naive join produces and it reads
      // as a stutter.
      final label = semanticLabelFor(_group(title: 'Casablanca', year: null, sources: 2));
      expect(label, 'Casablanca, 2 sources');
      expect(label, isNot(contains(', ,')));
    });

    test('a single-source group never announces its source count', () {
      // The one the card's own comments call out: hoofdstuk 10.3 puts the
      // badge on `sources.length > 1` and nowhere else, and the label follows
      // the badge. It matters more here than on screen — a silent capsule is
      // just absent, but "1 sources" is four syllables spoken on every card in
      // a catalog that is mostly single-source. The string is a plain
      // interpolation with no plural form, so a regression here is audibly
      // ungrammatical as well as pointless.
      final label = semanticLabelFor(_group(title: 'Poor Things'));
      expect(label, 'Poor Things, 2021');
      expect(label, isNot(contains('source')));
    });

    test('two or more sources are counted, and the count is the real one', () {
      expect(semanticLabelFor(_group(title: 'Past Lives', sources: 2)), 'Past Lives, 2021, 2 sources');
      expect(semanticLabelFor(_group(title: 'Past Lives', sources: 3)), 'Past Lives, 2021, 3 sources');
    });

    test('an untouched title announces neither watched nor in progress', () {
      // Same reasoning as the source count: "not watched" on every unwatched
      // card is noise, and the absence of a state is itself the information.
      final label = semanticLabelFor(_group(title: 'Princess Mononoke'));
      expect(label, isNot(contains(t.unifiedCatalog.semantics.watched)));
      expect(label, isNot(contains(t.unifiedCatalog.semantics.inProgress)));
    });

    test('a watched title says so', () {
      expect(
        semanticLabelFor(_group(title: 'Lawrence of Arabia', watched: true)),
        endsWith(t.unifiedCatalog.semantics.watched),
      );
    });

    test('a title with active progress is announced as a percentage', () {
      // Hoofdstuk 25's card reads "Dune, 2021, 42 procent bekeken, 3 bronnen":
      // the number, not the word "in progress". It is the same fraction the bar
      // under the artwork draws, which is why both come from
      // `resumeFractionFor` — a second computation is how the picture and the
      // announcement drift apart.
      final group = _group(title: 'The Batman', inProgress: true);
      final percent = (resumeFractionFor(group)! * 100).round();
      expect(semanticLabelFor(group), endsWith(t.accessibility.mediaCardPartiallyWatched(percent: percent)));
    });

    test('progress without a runtime falls back to the wordier phrase', () {
      // The one case the percentage cannot cover: the representative source
      // reports an offset but no duration, so there is nothing to be a
      // percentage *of* — and no bar is drawn either. Saying "0 percent
      // watched" there would be a number the app invented.
      final group = _group(title: 'Casablanca', inProgress: true, durationMs: null);
      expect(resumeFractionFor(group), isNull);
      expect(semanticLabelFor(group), endsWith(t.unifiedCatalog.semantics.inProgress));
    });

    test('watched and in progress are mutually exclusive, and watched wins', () {
      // `UnifiedWatchState` can hold both flags at once — a group whose
      // representative source is finished while another source is halfway
      // through produces exactly that — and a label saying "Watched, In
      // progress" would be a contradiction read aloud. The card resolves it
      // with an else-branch; this is what stops that becoming two ifs.
      final label = semanticLabelFor(_group(title: 'Paddington in Peru', watched: true, inProgress: true));
      expect(label, contains(t.unifiedCatalog.semantics.watched));
      expect(label, isNot(contains(t.unifiedCatalog.semantics.inProgress)));
      expect(label, isNot(contains('percent')));
    });

    test('the parts are joined title, year, state, sources with ", "', () {
      // The whole order in one string, on the only group that carries every
      // part at once. Asserted literally rather than by reassembling the parts
      // from `t` — a test that builds its expectation the same way the code
      // does would follow a reordering straight through and prove nothing.
      // English is the base locale, so this is the label as written in
      // lib/i18n/en.i18n.json.
      //
      // The order is hoofdstuk 25's own: "Dune, 2021, 42 procent bekeken, 3
      // bronnen" — watch state before the source count. The first build had the
      // count before the state and this literal is what makes the two disagree
      // out loud.
      expect(
        semanticLabelFor(_group(title: 'Dune: Part Two', year: 2024, sources: 3, watched: true)),
        'Dune: Part Two, 2024, Watched, 3 sources',
      );
    });

    test('every fixture in the shared catalog produces a label starting with its title', () {
      // Cheap breadth over the twelve-card mix the goldens picture: single and
      // multi source, watched, in-progress and untouched. Catches a reordering
      // that happens to leave the hand-built cases above intact.
      for (final group in tvGoldenCatalog()) {
        final title = group.representativeSource.item.displayTitle;
        expect(semanticLabelFor(group), startsWith(title));
        if (!group.hasMultipleSources) {
          expect(semanticLabelFor(group), isNot(contains('source')), reason: '$title has one source');
        }
      }
    });
  });

  group('the rendered card carries that same label', () {
    // The card only paints its focus ring, and therefore only behaves like the
    // 10-foot surface under test, when the app believes it is on a TV.
    setUpAll(() {
      TvDetectionService.debugSetAppleTVOverride(true);
      TvGoldenArtwork.install();
    });

    tearDownAll(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      TvGoldenArtwork.remove();
    });

    /// One card at the width the grid would give it on the tvOS canvas, rather
    /// than at an invented one: `TvCatalogGrid` resolves the card width from
    /// the viewport, and a card sized by hand would be a card the app never
    /// renders.
    Future<void> pumpCard(WidgetTester tester, UnifiedMediaGroup group) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TvUnifiedMediaCard(
                      group: group,
                      width: TvCatalogGrid.forWidth(
                        MediaQuery.sizeOf(context).width,
                        scale: TvLayoutConstants.scaleOf(context),
                      ).cardWidth,
                      onSelect: () {},
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

    /// The card's one semantics node, found by the label the pure function
    /// produced.
    ///
    /// Matched on the *start* of the node label rather than the whole of it,
    /// which is deliberately more permissive than the card currently needs.
    /// The visible title and context line are under an `ExcludeSemantics`, so
    /// the node label is [semanticLabelFor] and nothing else — hoofdstuk 25's
    /// "uitgesloten van dubbele semantiek", which before this fase really did
    /// read the title and year twice on every card. A prefix match keeps the
    /// helper honest if a future card ever appends something of its own.
    SemanticsNode cardSemantics(WidgetTester tester, UnifiedMediaGroup group) =>
        tester.getSemantics(find.bySemanticsLabel(RegExp('^${RegExp.escape(semanticLabelFor(group))}')));

    testWidgets('the node leads with exactly what semanticLabelFor produced', (tester) async {
      final group = _group(title: 'Dune: Part Two', year: 2024, sources: 3, watched: true);
      final handle = tester.ensureSemantics();
      await pumpCard(tester, group);

      expect(
        cardSemantics(tester, group),
        isSemantics(
          // Hoofdstuk 25 reads a card as something you can act on. Without the
          // button flag VoiceOver announces the text and no way to open it,
          // which on a remote-only surface is the whole card being unusable.
          isButton: true,
          isFocusable: true,
        ),
      );
      expect(cardSemantics(tester, group).label, 'Dune: Part Two, 2024, Watched, 3 sources');
      handle.dispose();
    });

    testWidgets('a single-source untouched card exposes no state and no count', (tester) async {
      // The negative case at the level that actually matters. The pure test
      // above proves the string; this proves nothing downstream of it puts the
      // count or a watch state back — a badge with its own semantics, say.
      final group = _group(title: 'Princess Mononoke', year: 1997);
      final handle = tester.ensureSemantics();
      await pumpCard(tester, group);

      expect(cardSemantics(tester, group).label, startsWith('Princess Mononoke, 1997'));
      expect(find.bySemanticsLabel(RegExp('source')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(t.unifiedCatalog.semantics.watched)), findsNothing);
      expect(find.bySemanticsLabel(RegExp(t.unifiedCatalog.semantics.inProgress)), findsNothing);
      handle.dispose();
    });

    testWidgets('the printed title and the spoken title are the same string', (tester) async {
      // The footer draws `displayTitle` and the label starts from the same
      // getter. If one of the two ever starts reading `item.title` directly, an
      // episode-shaped source would be captioned with its show name and
      // announced with its episode name, or the reverse — and nothing on screen
      // would look wrong.
      final group = _group(title: 'The Zone of Interest', year: 2023, sources: 2);
      final handle = tester.ensureSemantics();
      await pumpCard(tester, group);

      expect(find.text('The Zone of Interest'), findsOneWidget);
      expect(cardSemantics(tester, group).label, startsWith('The Zone of Interest, 2023, 2 sources'));
      handle.dispose();
    });

    // Not proven here, and deliberately not pinned either: hoofdstuk 25 quotes
    // one reading per card ("Dune, 2021, ..., 3 bronnen"), while the node today
    // also carries the merged title and context line after it, so the title and
    // year are spoken twice. Closing that is a change to the card's `Semantics`
    // — a container, or excluded child semantics — and it belongs with whoever
    // owns that widget. Asserting the duplication as if it were the contract
    // would make the fix look like a regression.
  });
}

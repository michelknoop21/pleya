/// Fase 8 (hoofdstuk 9.5/9.6/7.3): the Home featured carousel's own contract —
/// what it activates, how it navigates, and when it rotates.
///
/// A widget test over the carousel alone, with a spy for [onActivate], because
/// every claim here is about the carousel rather than about the coördinator
/// behind it. That the coördinator resolves preferred → direct → picker is
/// fase-4 work with its own tests; what fase 8 has to prove is that both CTAs
/// reach it, with the whole group, and never with the representative source.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../test_helpers/prefs.dart';

MediaItem _film(String id, String title, {String serverId = 'nas'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: 2024,
  summary: '$title has a synopsis long enough to fill the hero block.',
  genres: const ['Drama'],
  durationMs: 100 * 60 * 1000,
  serverId: serverId,
  serverName: serverId,
);

/// A group built by hand rather than through the projection: these tests are
/// about the carousel, and a real projection would make every one of them
/// depend on the identity pipeline as well.
UnifiedMediaGroup _group(String id, String title, {List<String> servers = const ['nas']}) {
  final sources = [
    for (final server in servers) UnifiedMediaSource.fromItem(_film('$id-$server', title, serverId: server)),
  ];
  return UnifiedMediaGroup(
    groupId: id,
    identity: canonicalIdentityOf(sources.first.item) ?? CanonicalMediaIdentity.opaque(),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: selectRepresentativeWatchState({for (final s in sources) s.sourceKey: s.item}),
  );
}

typedef _Activation = ({UnifiedMediaGroup group, UnifiedActivationIntent intent, bool playDirectly});

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  const size = Size(760, 308);

  Future<List<_Activation>> pump(
    WidgetTester tester,
    List<UnifiedMediaGroup> groups, {
    bool autoplayEnabled = true,
    bool reduceMotion = false,
    GlobalKey<TvHeroBillboardCarouselState>? key,
    VoidCallback? onNavigateDown,
    VoidCallback? onNavigateUp,
  }) async {
    final calls = <_Activation>[];
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: MediaQuery(
            data: MediaQueryData(size: const Size(1038, 584), disableAnimations: reduceMotion),
            child: InputModeTracker(
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: TvHeroBillboardCarousel(
                      key: key,
                      groups: groups,
                      size: size,
                      autoplayEnabled: autoplayEnabled,
                      onActivate: (group, {required intent, required playDirectly}) =>
                          calls.add((group: group, intent: intent, playDirectly: playDirectly)),
                      onNavigateDown: onNavigateDown,
                      onNavigateUp: onNavigateUp,
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
    return calls;
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

  group('activation boundary (hoofdstuk 4.4)', () {
    testWidgets('Afspelen hands over the whole group, never the representative source', (tester) async {
      final group = _group('g1', 'Blue Signal', servers: ['nas', 'attic']);
      final calls = await pump(tester, [group]);

      node(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);

      expect(calls, hasLength(1));
      expect(identical(calls.single.group, group), isTrue);
      expect(calls.single.group.sources, hasLength(2), reason: 'both servers reach the coördinator');
      expect(calls.single.intent, UnifiedActivationIntent.play);
      expect(calls.single.playDirectly, isTrue);
    });

    testWidgets('Meer info shares the same resolution boundary, differing only in intent', (tester) async {
      final group = _group('g1', 'Blue Signal', servers: ['nas', 'attic']);
      final calls = await pump(tester, [group]);

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);

      expect(calls, hasLength(1));
      expect(identical(calls.single.group, group), isTrue, reason: 'one boundary, no hero-specific picker');
      expect(calls.single.intent, UnifiedActivationIntent.details);
      expect(calls.single.playDirectly, isFalse);
    });

    testWidgets('a single-source slide still activates as a group', (tester) async {
      // The point is not that one source behaves differently — it must not.
      // It is that the *shape* handed over is the same either way, so the
      // coördinator decides "direct" rather than the carousel assuming it.
      final group = _group('g1', 'Solo Title');
      final calls = await pump(tester, [group]);

      node(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);

      expect(calls.single.group.sources, hasLength(1));
      expect(identical(calls.single.group, group), isTrue);
    });

    testWidgets('activating the second slide activates the second group', (tester) async {
      // Display and activation read one list (DEC-067): after navigating, the
      // group handed over must be the one on screen, not the one the carousel
      // started on.
      final groups = [_group('g1', 'First'), _group('g2', 'Second')];
      final calls = await pump(tester, groups);

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Second');

      await press(tester, LogicalKeyboardKey.enter);
      expect(calls.single.group.groupId, 'g2');
    });
  });

  group('slide navigation (hoofdstuk 7.3)', () {
    testWidgets('Right from Play reaches Meer info, and Right again advances the slide', (tester) async {
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second')]);

      node(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      expect(shownTitle(tester), 'First');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(node(tester, 'tvHeroMoreInfo').hasFocus, isTrue);
      expect(shownTitle(tester), 'First', reason: 'moving between the CTAs is not a slide change');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Second');
    });

    testWidgets('Left from Play steps back a slide, and Left from Meer info returns to Play', (tester) async {
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second')]);

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Second');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(node(tester, 'tvHeroPlay').hasFocus, isTrue);
      expect(shownTitle(tester), 'Second');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(shownTitle(tester), 'First');
    });

    testWidgets('the carousel is finite: neither end wraps', (tester) async {
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second')]);

      node(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(shownTitle(tester), 'First', reason: 'Left on the first slide stays put');

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Second', reason: 'Right on the last slide stays put');
    });

    testWidgets('a one-slide hero does not cycle, and its keys are not dead ends', (tester) async {
      // Fase-8 brief §22: one group must not produce a broken control or a
      // timer loop. LEFT and RIGHT simply do nothing to the slide; RIGHT still
      // moves between the two CTAs, so no key is silently inert.
      await pump(tester, [_group('g1', 'Only One')]);

      node(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(shownTitle(tester), 'Only One');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(node(tester, 'tvHeroMoreInfo').hasFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Only One');

      // And nothing rotates it either, however long it is left alone.
      await tester.pump(TvHomeLayout.heroAutoAdvance * 4);
      expect(shownTitle(tester), 'Only One');
    });

    testWidgets('Down leaves for the content feed and Up for the top navigation', (tester) async {
      var down = 0;
      var up = 0;
      await pump(tester, [_group('g1', 'First')], onNavigateDown: () => down++, onNavigateUp: () => up++);

      node(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(down, 1);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(up, 1);
    });

    testWidgets('focusLastCta returns to the CTA the viewer actually used', (tester) async {
      final key = GlobalKey<TvHeroBillboardCarouselState>();
      await pump(tester, [_group('g1', 'First')], key: key);

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      node(tester, 'tvHeroMoreInfo').unfocus();
      await tester.pump();

      expect(key.currentState!.focusLastCta(), isTrue);
      await tester.pump();
      expect(node(tester, 'tvHeroMoreInfo').hasFocus, isTrue, reason: 'hoofdstuk 7.3: the *last used* CTA, not Play');
    });
  });

  group('autoplay lifecycle (hoofdstuk 9.6)', () {
    testWidgets('the carousel advances on its own after the inactivity window', (tester) async {
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second')]);
      expect(shownTitle(tester), 'First');

      // No interaction has happened, so the rotation is already armed.
      await tester.pump(TvHomeLayout.heroAutoAdvance);
      expect(shownTitle(tester), 'Second');
    });

    testWidgets('an interaction pauses the rotation for the inactivity window', (tester) async {
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second'), _group('g3', 'Third')]);

      node(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();

      // Arriving on a CTA is an interaction: the next tick must not fire.
      await tester.pump(TvHomeLayout.heroAutoAdvance ~/ 2);
      expect(shownTitle(tester), 'First');

      // ...and once the window has passed with no further input, it resumes —
      // the clause that makes 9.6's eight-second rotation reachable at all
      // when the resting focus is a hero CTA (DEC-070).
      await tester.pump(TvHomeLayout.heroAutoAdvance);
      await tester.pump(TvHomeLayout.heroAutoAdvance);
      expect(shownTitle(tester), 'Second');
    });

    testWidgets('autoplayEnabled false stops the rotation, and restoring it resumes deterministically', (tester) async {
      final groups = [_group('g1', 'First'), _group('g2', 'Second')];
      // Leaving Home, an overlay opening, the app backgrounding: the feed
      // reports all of them through this one flag.
      await pump(tester, groups, autoplayEnabled: false);

      await tester.pump(TvHomeLayout.heroAutoAdvance * 3);
      expect(shownTitle(tester), 'First', reason: 'a disabled carousel must not rotate behind whatever is on top');

      await pump(tester, groups);
      await tester.pump(TvHomeLayout.heroAutoAdvance);
      expect(shownTitle(tester), 'Second', reason: 'returning resumes from where it stopped, one slide on');
    });

    testWidgets('reduced motion stops the rotation but not the remote', (tester) async {
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second')], reduceMotion: true);

      await tester.pump(TvHomeLayout.heroAutoAdvance * 3);
      expect(shownTitle(tester), 'First', reason: 'no automatic change of the largest element on screen');

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Second', reason: 'manual navigation still works under reduced motion');
    });

    testWidgets('a disposed carousel leaves no timer behind', (tester) async {
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second')]);
      await tester.pumpWidget(const SizedBox.shrink());
      // A `setState` from a surviving timer on an unmounted state throws, and
      // `testWidgets` fails the test on it — so reaching the end of this pump
      // window silently is the assertion.
      await tester.pump(TvHomeLayout.heroAutoAdvance * 3);
    });
  });

  group('accessibility (hoofdstuk 25, fase-8 brief §25)', () {
    testWidgets('the billboard announces the featured title and its place in the rotation', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, [_group('g1', 'Blue Signal'), _group('g2', 'Under the Canopy')]);

      expect(
        find.bySemanticsLabel(RegExp(r'Featured: Blue Signal, 1 of 2')),
        findsOneWidget,
        reason: 'title plus current slide and count, so a screen reader knows where it is',
      );

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.bySemanticsLabel(RegExp(r'Featured: Under the Canopy, 2 of 2')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a one-slide hero announces no position it does not have', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, [_group('g1', 'Solo Title')]);
      // A RegExp, not an exact string: the container node's label is composed
      // with its children's, so the CTA labels ride along behind it.
      expect(find.bySemanticsLabel(RegExp(r'Featured: Solo Title')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'1 of 1')),
        findsNothing,
        reason: 'a rotation of one is not a rotation, and announcing a position implies there is another',
      );
      handle.dispose();
    });

    testWidgets('both CTAs are announced, and a multi-source title is announced once', (tester) async {
      final handle = tester.ensureSemantics();
      // Two servers, one logical title. A screen reader must hear one
      // billboard, not one per concrete source.
      await pump(tester, [
        _group('g1', 'Blue Signal', servers: ['nas', 'attic']),
      ]);

      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(find.bySemanticsLabel(t.mediaMenu.viewDetails), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Featured: Blue Signal')), findsOneWidget);
      handle.dispose();
    });
  });

  group('re-projection (hoofdstuk 7.6)', () {
    testWidgets('the carousel follows its group, not its index, when the list shortens', (tester) async {
      final key = GlobalKey<TvHeroBillboardCarouselState>();
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second'), _group('g3', 'Third')], key: key);

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Third');

      // A re-projection drops the first film. Index 2 no longer exists; the
      // group the viewer is standing on does.
      await pump(tester, [_group('g2', 'Second'), _group('g3', 'Third')], key: key);
      expect(shownTitle(tester), 'Third');
    });

    testWidgets('a slide that genuinely disappears falls back to the first, not to a neighbour by index', (
      tester,
    ) async {
      final key = GlobalKey<TvHeroBillboardCarouselState>();
      await pump(tester, [_group('g1', 'First'), _group('g2', 'Second')], key: key);

      node(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(shownTitle(tester), 'Second');

      await pump(tester, [_group('g1', 'First'), _group('g3', 'Third')], key: key);
      expect(shownTitle(tester), 'First');
    });

    testWidgets('initialGroupId restores the slide by identity', (tester) async {
      final calls = <_Activation>[];
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: Scaffold(
                body: TvHeroBillboardCarousel(
                  groups: [_group('g1', 'First'), _group('g2', 'Second'), _group('g3', 'Third')],
                  size: size,
                  initialGroupId: 'g3',
                  onActivate: (group, {required intent, required playDirectly}) =>
                      calls.add((group: group, intent: intent, playDirectly: playDirectly)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(shownTitle(tester), 'Third');
    });
  });
}

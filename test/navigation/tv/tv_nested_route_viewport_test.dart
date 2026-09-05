/// INV-1: a nested TV route sees the content box, never the window.
///
/// The invariant, not one screen. `docs/tvos-redesign-implementatiecontract.md`
/// is explicit about why: corrected once for detail, the same bug returns at
/// collection, at person, and at every settings subpage PB-1 moves into the
/// shell. So what is asserted here is the property of the surface every nested
/// route passes through, proved with two unrelated routes rather than with one
/// screen that happens to be right.
///
/// The negative control is the destination root in the same shell. It is *not*
/// wrapped by the correction, so it still reads the window, and the two
/// readings taken in one pump are what makes the difference real rather than a
/// number this test made up.
///
/// The last test is the regression this correction could easily have caused.
/// `TvLayoutConstants.scaleOf` used to read `MediaQuery.sizeOf`, so handing a
/// route a shorter viewport would have shrunk its typography by the height of
/// the top bar — one screen rendering two ways depending on how it was opened.
/// `TvDisplayMetrics` is why it does not, and this pins that down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';

/// What a screen inside the shell can observe about the space it was given.
class _Reading {
  const _Reading({required this.size, required this.topPadding, required this.scale});

  final Size size;
  final double topPadding;
  final double scale;
}

_Reading _read(BuildContext context) => _Reading(
  size: MediaQuery.sizeOf(context),
  topPadding: MediaQuery.paddingOf(context).top,
  scale: TvLayoutConstants.scaleOf(context),
);

/// A probe rather than a real screen: this is an invariant test, and mounting
/// `MediaDetailScreen` here would tie it to that screen's provider graph and
/// prove nothing extra about the surface.
class _Probe extends StatelessWidget {
  const _Probe({required this.label, required this.onBuild});

  final String label;
  final void Function(_Reading) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(_read(context));
    return Center(child: Text(label));
  }
}

void main() {
  const window = Size(1280, 720);

  late TvNavigationCoordinator coordinator;
  late FocusMemoryTracker nodes;
  late FocusScopeNode navScope;
  late FocusScopeNode contentScope;

  setUp(() {
    coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    navScope = FocusScopeNode(debugLabel: 'nav');
    contentScope = FocusScopeNode(debugLabel: 'content');
  });

  tearDown(() {
    coordinator.dispose();
    nodes.dispose();
    navScope.dispose();
    contentScope.dispose();
  });

  /// The production shell, with a probe as the destination root.
  Future<void> pump(WidgetTester tester, {required void Function(_Reading) onRoot}) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: TvRootShell(
              coordinator: coordinator,
              contentFocus: TvContentFocusAuthority(),
              navNodes: nodes,
              navFocusScope: navScope,
              contentFocusScope: contentScope,
              isNavFocused: false,
              profile: null,
              onSelectDestination: (_) {},
              onFocusDestination: (_) {},
              onFocusContent: ({bool restorePreviousFocus = true}) {},
              onFocusNav: () {},
              onOpenProfiles: () {},
              onOverlaySheetOpenChanged: (_) {},
              onKeyEvent: (_) => KeyEventResult.ignored,
              selectLibrary: null,
              openSettings: null,
              dismissNestedRoute: ([_]) {},
              child: _Probe(label: 'destination root', onBuild: onRoot),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens a nested route carrying a probe and returns what it read.
  Future<_Reading> openRoute(WidgetTester tester, String id) async {
    late _Reading reading;
    coordinator.pushNested(
      coordinator.active,
      TvNestedRoute(id: id, builder: (_) => _Probe(label: id, onBuild: (r) => reading = r)),
    );
    await tester.pumpAndSettle();
    expect(find.text(id), findsOneWidget, reason: 'the route has to be on screen for its reading to mean anything');
    return reading;
  }

  group('INV-1, the viewport a nested route is given', () {
    testWidgets('is the content box, and the destination root beside it still reads the window', (tester) async {
      late _Reading root;
      await pump(tester, onRoot: (r) => root = r);

      // The negative control, taken from the live tree rather than asserted as
      // a constant: the root is not wrapped by the correction, so it reads the
      // whole window. If that ever stops being true this test has to be
      // rewritten, not quietly adjusted.
      expect(root.size.height, window.height, reason: 'control: an unwrapped screen sees the window');

      final nested = await openRoute(tester, 'route.detail');

      expect(
        nested.size.height,
        lessThan(root.size.height),
        reason: 'INV-1: the route is under a top bar, so its box is shorter than the window',
      );
      expect(nested.size.width, root.size.width, reason: 'a top bar takes height, not width');
      expect(
        root.size.height - nested.size.height,
        greaterThan(0),
        reason: 'the difference is the bar, and it has to be a real band',
      );
    });

    testWidgets('holds for a second, unrelated route — it is the surface, not the screen', (tester) async {
      late _Reading root;
      await pump(tester, onRoot: (r) => root = r);

      final first = await openRoute(tester, 'route.collection');
      final second = await openRoute(tester, 'route.person');

      for (final reading in [first, second]) {
        expect(reading.size.height, lessThan(root.size.height));
        expect(reading.size, first.size, reason: 'every nested route is handed the same box');
      }
      expect(second.size, first.size);
    });

    testWidgets('carries no top safe inset, because the shell already spent it', (tester) async {
      await pump(tester, onRoot: (_) {});

      final nested = await openRoute(tester, 'route.settings-sub');

      expect(
        nested.topPadding,
        0,
        reason: 'TvShellSurface documents the shell as the owner of the top inset; insetting twice is the defect',
      );
    });

    testWidgets('does not shrink the ten-foot type scale with it', (tester) async {
      late _Reading root;
      await pump(tester, onRoot: (r) => root = r);

      final nested = await openRoute(tester, 'route.detail');

      expect(
        nested.scale,
        root.scale,
        reason:
            'the viewport shrinks and the scale does not: one screen may not set type two different sizes '
            'depending on whether it was opened as a destination or as a route',
      );
    });
  });
}

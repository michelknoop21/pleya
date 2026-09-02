/// P2: one content-focus authority, and its five cases.
///
/// ## What is tested where, and why it is split
///
/// The *rule* — what a press means for the focus — lives on
/// [TvContentFocusAuthority] and is unit-tested here directly. That is not a
/// convenience: three surfaces used to answer "should the remote go into the
/// content now" independently, and putting the answer in one object with one
/// contract is the fix. A test that re-implemented the rule in a harness and
/// then checked the harness would prove nothing about that.
///
/// The two *consumers* are tested against production widgets:
///
/// * DOWN out of the bar → `TvRootShell`'s own `onNavigateDown` wiring;
/// * late-arriving content → `DiscoverScreen`'s guard, read off
///   `MainScreenFocusScope`, which is the path that used to steal the focus on
///   every cold Home.
///
/// The one thing not mounted is `MainScreen` itself, which no test in this repo
/// mounts — its provider graph is the whole app. What that costs is stated
/// rather than papered over: the calls `MainScreen` makes into this object
/// (`onDestinationSelected`, `arm` from `_focusContent`, `cancel` from
/// `_focusSidebar`) are covered here as the object's contract, not as
/// `MainScreen`'s use of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';

void main() {
  group('the rule', () {
    late TvContentFocusAuthority authority;

    setUp(() => authority = TvContentFocusAuthority());

    test('1 — a warm switch to another destination arms nothing', () {
      // The report's first line: choosing Home dropped the remote onto the
      // billboard's Afspelen pill. Select on another destination changes the
      // page; the ring stays in the bar.
      expect(authority.onDestinationSelected(wasActive: false), isNull);
      expect(authority.hasPendingIntent, isFalse);
    });

    test('1b — and it clears an intent an earlier press had armed', () {
      // A DOWN that never landed, followed by the viewer going back up and
      // walking to another destination. Honouring the old intent a second later
      // would pull them out of the bar they deliberately returned to.
      authority.arm(TvContentFocusIntent.primary);
      authority.onDestinationSelected(wasActive: false);
      expect(authority.hasPendingIntent, isFalse);
    });

    test('2 — a cold Home leaves the DOWN armed until there is content', () {
      // Nothing has answered yet: the destination cannot satisfy the intent, so
      // it must not be consumed. This is the case that made a naive
      // "consume on ask" wrong.
      authority.arm(TvContentFocusIntent.primary);
      expect(authority.hasPendingIntent, isTrue);
      expect(authority.pending, TvContentFocusIntent.primary, reason: 'peeking must not disarm');
      expect(authority.hasPendingIntent, isTrue);
    });

    test('3 — re-selecting the destination you are on restores the content', () {
      // Hoofdstuk 7.2's `wasActive` branch, unchanged by this round.
      expect(authority.onDestinationSelected(wasActive: true), TvContentFocusIntent.restore);
      expect(authority.consume(), TvContentFocusIntent.restore);
    });

    test('4 — DOWN before content is ready stays pending, and is consumed once', () {
      authority.arm(TvContentFocusIntent.primary);
      expect(authority.consume(), TvContentFocusIntent.primary);
      expect(
        authority.consume(),
        isNull,
        reason: 'consume-once is the whole guard: content arriving twice must not focus twice',
      );
    });

    test('5 — DOWN after content is ready is satisfied and disarmed on the spot', () {
      authority.arm(TvContentFocusIntent.primary);
      // The destination could place the focus, so it takes the intent...
      expect(authority.consume(), isNotNull);
      // ...and a later projection landing finds nothing to act on.
      expect(authority.consume(), isNull);
      expect(authority.hasPendingIntent, isFalse);
    });

    test('leaving for the bar cancels, whatever was armed', () {
      authority.arm(TvContentFocusIntent.restore);
      authority.cancel();
      expect(authority.hasPendingIntent, isFalse);
    });

    test('a second press replaces the first rather than queueing behind it', () {
      authority.arm(TvContentFocusIntent.restore);
      authority.arm(TvContentFocusIntent.primary);
      expect(authority.consume(), TvContentFocusIntent.primary);
      expect(authority.hasPendingIntent, isFalse);
    });
  });

  group('the consumers', () {
    testWidgets('DOWN out of the bar is what asks for the content', (tester) async {
      final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
      final nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
      final navScope = FocusScopeNode(debugLabel: 'nav');
      final contentScope = FocusScopeNode(debugLabel: 'content');
      final authority = TvContentFocusAuthority();
      addTearDown(() {
        coordinator.dispose();
        nodes.dispose();
        navScope.dispose();
        contentScope.dispose();
      });

      var focusContentCalls = 0;
      final selected = <TvDestinationId>[];

      tester.view.physicalSize = const Size(1280, 720);
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
                contentFocus: authority,
                navNodes: nodes,
                navFocusScope: navScope,
                contentFocusScope: contentScope,
                isNavFocused: true,
                profile: null,
                onSelectDestination: selected.add,
                // Exactly what `MainScreen._focusContent` does with it.
                onFocusContent: ({bool restorePreviousFocus = true}) {
                  focusContentCalls++;
                  authority.arm(restorePreviousFocus ? TvContentFocusIntent.restore : TvContentFocusIntent.primary);
                },
                onFocusNav: () {},
                onOpenProfiles: () {},
                onOverlaySheetOpenChanged: (_) {},
                onKeyEvent: (_) => KeyEventResult.ignored,
                selectLibrary: null,
                openSettings: null,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      nodes.get(coordinator.active.focusKey).requestFocus();
      await tester.pump();
      expect(authority.hasPendingIntent, isFalse, reason: 'standing in the bar arms nothing');

      // Select on the destination the ring is already on: activation reports
      // upward, and on its own moves no focus.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(selected, isNotEmpty, reason: 'the press has to have reached the bar at all');
      expect(focusContentCalls, 0, reason: 'the bar does not decide this; the shell owner does');

      // DOWN does.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusContentCalls, 1);
      expect(authority.pending, TvContentFocusIntent.restore);
    });
  });
}

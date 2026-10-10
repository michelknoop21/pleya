/// The menu behind one request, at the size the Apple TV actually runs it:
/// 1920x1080 logical pixels, opened through the overlay host as the list does.
///
/// A manager looking at their own pending series gets every action at once:
/// open, approve, decline, edit, cancel, plus Sluiten. That is the tallest this
/// menu gets, and the surface it opens in is capped. None of it may be drawn
/// past the edge, and the remote has to be able to reach and select all of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_request_rights.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/seerr_request_actions_sheet.dart';

import '../test_helpers/seerr_fake.dart';

const _screen = Size(1920, 1080);

const _request = SeerrRequest(
  id: 1,
  status: SeerrRequestStatus.pending,
  mediaType: 'tv',
  tmdbId: 201,
  // Long enough to take the two lines the header allows.
  mediaTitle: 'De wonderlijke en buitengewoon lange geschiedenis van de Fjord Line veerdienst naar het hoge noorden',
  seasons: [1, 3, 5, 7, 9],
  requestedById: 7,
  requestedByName: 'een-aanvrager-met-een-heel-lange-gebruikersnaam',
);

Finder _item(String action) => seerrNode(AutomationIds.requestsActionsItem, action);

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<SeerrRequestAction? Function()> openMenu(WidgetTester tester) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SeerrRequestAction? result;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: OverlaySheetHost(
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async => result = await showSeerrRequestActionsSheet(
                      context,
                      request: _request,
                      // Own pending series, manager and admin: everything.
                      rights: SeerrRequestRights.of(_request, ownUserId: 7, canManage: true, isAdmin: true),
                      isOwn: true,
                    ),
                    child: const Text('card'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('card'));
    await tester.pumpAndSettle();
    return () => result;
  }

  Rect menu(WidgetTester tester) => tester.getRect(seerrNode(AutomationIds.requestsActions));

  testWidgets('with all five actions the menu lays out without overflow, inside the screen', (tester) async {
    await openMenu(tester);

    expect(tester.takeException(), isNull, reason: 'no "BOTTOM OVERFLOWED" at 1920x1080');
    final sheet = menu(tester);
    expect(sheet.top, greaterThanOrEqualTo(0));
    expect(sheet.bottom, lessThanOrEqualTo(_screen.height));
    for (final action in ['open', 'approve', 'decline', 'edit', 'cancel', 'close']) {
      expect(_item(action), findsOneWidget, reason: '$action is offered');
    }
    // Sluiten is pinned: it is inside the menu whatever the rows above it need.
    final close = tester.getRect(_item('close'));
    expect(close.bottom, lessThanOrEqualTo(sheet.bottom + 0.5), reason: 'Sluiten is not pushed past the edge');
  });

  testWidgets('it opens on Goedkeuren, the decision a manager came for', (tester) async {
    await openMenu(tester);
    expect(seerrHasFocus(tester, _item('approve')), isTrue);
    expect(tester.getRect(_item('open')).top, lessThan(tester.getRect(_item('approve')).top), reason: 'order kept');
  });

  testWidgets('the remote reaches every action, and each one is fully in view when it has the focus', (tester) async {
    await openMenu(tester);
    final sheet = menu(tester);

    Future<void> expectFocusedInView(String action) async {
      expect(seerrHasFocus(tester, _item(action)), isTrue, reason: 'DOWN reaches $action');
      final rect = tester.getRect(_item(action));
      expect(rect.top, greaterThanOrEqualTo(sheet.top - 0.5), reason: '$action is not above the menu');
      expect(rect.bottom, lessThanOrEqualTo(sheet.bottom + 0.5), reason: '$action is not cut off at the bottom');
      expect(rect.bottom, lessThanOrEqualTo(_screen.height), reason: '$action is on screen');
    }

    await expectFocusedInView('approve');
    for (final action in ['decline', 'edit', 'cancel', 'close']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await expectFocusedInView(action);
    }
    for (final action in ['cancel', 'edit', 'decline', 'approve', 'open']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await expectFocusedInView(action);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last action can be selected, not only seen', (tester) async {
    final result = await openMenu(tester);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(seerrHasFocus(tester, _item('cancel')), isTrue);
    expect(find.text(t.seerr.cancelRequest).hitTestable(), findsOneWidget, reason: 'Aanvraag annuleren is not clipped');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(result(), SeerrRequestAction.cancel);
    expect(seerrNode(AutomationIds.requestsActions), findsNothing);
  });

  group('when the rows need more height than the surface has', () {
    // On the device the six controls came out 62 pixels taller than the room
    // the surface gave them. The test font and dense rows make the menu
    // shorter here, so the shortfall is rebuilt directly: the menu is measured
    // at its natural height and then given exactly 62 pixels less.
    Future<void> pumpIn(WidgetTester tester, {double? height}) async {
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 1000,
                    height: height,
                    child: SeerrRequestActionsSheet(
                      request: _request,
                      rights: SeerrRequestRights.of(_request, ownUserId: 7, canManage: true, isAdmin: true),
                      isOwn: true,
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

    testWidgets('62 pixels short, nothing overflows and Sluiten keeps its place', (tester) async {
      await pumpIn(tester);
      final natural = menu(tester).height;
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpIn(tester, height: natural - 62);

      expect(tester.takeException(), isNull, reason: 'no "BOTTOM OVERFLOWED BY 62 PIXELS"');
      final sheet = menu(tester);
      expect(sheet.height, natural - 62);
      expect(tester.getRect(_item('close')).bottom, lessThanOrEqualTo(sheet.bottom + 0.5));
      expect(find.text(t.common.close).hitTestable(), findsOneWidget);
    });

    testWidgets('62 pixels short, the last action is scrolled into view by the remote and can be selected', (
      tester,
    ) async {
      await pumpIn(tester);
      final natural = menu(tester).height;
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpIn(tester, height: natural - 62);
      final sheet = menu(tester);

      tester
          .widget<Focus>(find.descendant(of: _item('approve'), matching: find.byType(Focus)).first)
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      for (final action in ['decline', 'edit', 'cancel']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(seerrHasFocus(tester, _item(action)), isTrue, reason: 'DOWN reaches $action');
        final rect = tester.getRect(_item(action));
        expect(rect.top, greaterThanOrEqualTo(sheet.top - 0.5), reason: '$action top');
        expect(
          rect.bottom,
          lessThanOrEqualTo(tester.getRect(_item('close')).top + 0.5),
          reason: '$action sits above Sluiten, not under it or past the edge',
        );
      }
      expect(find.text(t.seerr.cancelRequest).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('without an overlay host, the opening control keeps its focus node until the menu has left', (
    tester,
  ) async {
    // A hostless screen shows the menu as a route. Its future completes at the
    // pop, while the closing animation still builds the controls.
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSeerrRequestActionsSheet(
                    context,
                    request: _request,
                    rights: SeerrRequestRights.of(_request, ownUserId: 7, canManage: true, isAdmin: true),
                    isOwn: true,
                  ),
                  child: const Text('card'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('card'));
    await tester.pumpAndSettle();
    final node = tester.widget<SeerrRequestActionsSheet>(find.byType(SeerrRequestActionsSheet)).initialFocusNode!;
    bool disposed() {
      try {
        ChangeNotifier.debugAssertNotDisposed(node);
        return false;
      } on FlutterError {
        return true;
      }
    }

    await tester.tap(find.text(t.common.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SeerrRequestActionsSheet), findsOneWidget, reason: 'the menu is still animating out');
    expect(disposed(), isFalse, reason: 'a control that is still built must not hold a disposed node');

    await tester.pumpAndSettle();
    expect(find.byType(SeerrRequestActionsSheet), findsNothing);
    expect(disposed(), isTrue, reason: 'and it is not left behind once the menu is gone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menu closes it without a choice', (tester) async {
    final result = await openMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(seerrNode(AutomationIds.requestsActions), findsNothing);
    expect(result(), isNull);
  });
}

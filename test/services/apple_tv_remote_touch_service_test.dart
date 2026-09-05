import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/diagnostics/select_trace_recorder.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleTvRemoteTouchService', () {
    // NAV1, tweede oorzaak — replay van log y0w9x (build 251, 5 september).
    // Een ringdruk die op Home landt werd 80-230 ms later gevolgd door een
    // tweede compleet native keydown/keyup-paar van dezelfde toets, zonder
    // eigen `started`. Eén druk, twee stappen. De reeksen hieronder zijn de
    // logregels, met hun tijdsverschillen.
    group('NAV1 replay uit log y0w9x', () {
      test('08:31:40 — een tweede paar zonder nieuwe aanraking wordt geconsumeerd', () async {
        final h = _Harness();
        await h.send('started');
        h.advance(const Duration(milliseconds: 108));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isFalse);
        h.advance(const Duration(milliseconds: 1));
        await h.send('cancelled', x: 28.1, y: 16.1);
        h.advance(const Duration(milliseconds: 2));
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft)), isFalse);
        h.advance(const Duration(milliseconds: 136));
        // The duplicate: no `started` in between.
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isTrue);
        h.advance(const Duration(milliseconds: 1));
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft)), isTrue);
      });

      test('08:31:41 — ook als de eerste aanraking nog niet is losgelaten', () async {
        final h = _Harness();
        await h.send('started');
        h.advance(const Duration(milliseconds: 30));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowRight)), isFalse);
        h.advance(const Duration(milliseconds: 3));
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowRight)), isFalse);
        h.advance(const Duration(milliseconds: 104));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowRight)), isTrue);
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowRight)), isTrue);
        h.advance(const Duration(milliseconds: 59));
        await h.send('cancelled');
      });

      test('een echte tweede tik brengt zijn eigen started mee en gaat door', () async {
        final h = _Harness();
        await h.send('started');
        h.advance(const Duration(milliseconds: 100));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowRight)), isFalse);
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowRight)), isFalse);
        await h.send('cancelled');
        h.advance(const Duration(milliseconds: 120));
        await h.send('started');
        h.advance(const Duration(milliseconds: 100));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowRight)), isFalse);
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowRight)), isFalse);
      });

      test('een ingedrukt gehouden richting heeft geen keyup ertussen en blijft herhalen', () async {
        final h = _Harness();
        await h.send('started');
        h.advance(const Duration(milliseconds: 100));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown)), isFalse);
        h.advance(const Duration(milliseconds: 150));
        expect(h.service.handleNativeKeyEvent(_keyRepeat(LogicalKeyboardKey.arrowDown)), isFalse);
        h.advance(const Duration(milliseconds: 150));
        expect(h.service.handleNativeKeyEvent(_keyRepeat(LogicalKeyboardKey.arrowDown)), isFalse);
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowDown)), isFalse);
      });

      // NAV1, derde oorzaak — log 3zsde (build 252, 5 september). De twee
      // tests hierboven bewijzen dat de dienst het tweede paar herként; deze
      // twee bewijzen waar dat oordeel wel en niet aankomt. In het echte
      // logboek stond `consume native keydown reason=repeated-pair-without-touch
      // age=99ms` één millisecond boven `FocusableWrapper:
      // result=KeyEventResult.handled reason=onNavigateLeft`.
      testWidgets('HardwareKeyboard alleen houdt een geconsumeerd duplicaat niet tegen', (tester) async {
        final h = _Harness();
        final received = <KeyEvent>[];
        HardwareKeyboard.instance.addHandler(h.service.handleNativeKeyEvent);
        addTearDown(() => HardwareKeyboard.instance.removeHandler(h.service.handleNativeKeyEvent));
        await _focusRecorder(tester, received);

        await _pressPair(h, received: received);
        h.advance(const Duration(milliseconds: 99));
        received.clear();
        await _sendPair(LogicalKeyboardKey.arrowLeft);

        // Dit is geen wens, dit is de SDK: `KeyEventManager.handleKeyData`
        // gooit het resultaat van `_hardwareKeyboard.handleKeyEvent` weg en
        // roept `_dispatchKeyMessage` er onvoorwaardelijk achteraan
        // (services/hardware_keyboard.dart:1118). Vandaar de tweede stap.
        expect(received, hasLength(2), reason: 'de SDK levert het duplicaat af ondanks de consume');
      });

      testWidgets('met de early key handler erbij bereikt het duplicaat de focustree niet', (tester) async {
        final h = _Harness();
        final received = <KeyEvent>[];
        HardwareKeyboard.instance.addHandler(h.service.handleNativeKeyEvent);
        FocusManager.instance.addEarlyKeyEventHandler(h.service.blockConsumedKeyEvent);
        addTearDown(() {
          HardwareKeyboard.instance.removeHandler(h.service.handleNativeKeyEvent);
          FocusManager.instance.removeEarlyKeyEventHandler(h.service.blockConsumedKeyEvent);
        });
        await _focusRecorder(tester, received);

        await _pressPair(h, received: received);
        h.advance(const Duration(milliseconds: 99));
        received.clear();
        await _sendPair(LogicalKeyboardKey.arrowLeft);

        expect(received, isEmpty, reason: 'één ringdruk mag één stap zijn');
      });

      testWidgets('een echte tweede druk komt er nog steeds door', (tester) async {
        final h = _Harness();
        final received = <KeyEvent>[];
        HardwareKeyboard.instance.addHandler(h.service.handleNativeKeyEvent);
        FocusManager.instance.addEarlyKeyEventHandler(h.service.blockConsumedKeyEvent);
        addTearDown(() {
          HardwareKeyboard.instance.removeHandler(h.service.handleNativeKeyEvent);
          FocusManager.instance.removeEarlyKeyEventHandler(h.service.blockConsumedKeyEvent);
        });
        await _focusRecorder(tester, received);

        await _pressPair(h, received: received);
        await h.send('cancelled');
        h.advance(const Duration(milliseconds: 120));
        await h.send('started');
        h.advance(const Duration(milliseconds: 100));
        received.clear();
        await _sendPair(LogicalKeyboardKey.arrowLeft);

        expect(received, hasLength(2));
      });

      test('een andere toets na een afgerond paar is geen duplicaat', () async {
        final h = _Harness();
        await h.send('started');
        h.advance(const Duration(milliseconds: 100));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowRight)), isFalse);
        expect(h.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowRight)), isFalse);
        h.advance(const Duration(milliseconds: 100));
        expect(h.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isFalse);
      });
    });

    test('emits repeated horizontal swipes only after the repeat interval', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 490);
      await harness.send('move', x: 260, y: 490);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);

      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 260, y: 490);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft]);
    });

    test('uses the dominant vertical axis for swipes', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 540, y: 380);

      expect(harness.keys, [LogicalKeyboardKey.arrowUp]);
    });

    test('keeps horizontal axis through non-decisive vertical drift', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 380, y: 370);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
    });

    test('continues horizontal swipes when drift is slightly vertical-dominant', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 260, y: 370);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft]);
    });

    test('continues reversed horizontal swipes when drift is only slightly vertical-dominant', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 500, y: 370);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]);
    });

    test('switches axis when the new direction clearly dominates the gesture', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 380, y: 300);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp]);
    });

    test('resets swipe axis hysteresis between touches', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('ended', x: 380, y: 500);
      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 500, y: 380);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp]);
    });

    test('short touch without a click event does not emit select', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('ended', x: 512, y: 504);

      expect(harness.keys, isEmpty);
    });

    test('short touch around a native directional key does not emit select', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft));
      await harness.send('started', x: 500, y: 500);
      await harness.send('ended', x: 500, y: 500);

      expect(harness.keys, isEmpty);
    });

    test('swipe end does not also emit select', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('ended', x: 380, y: 500);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
    });

    test('ended position past threshold opposite of the last move does not fire a reverse swipe', () async {
      final harness = _Harness();

      // User swipes left, then releases the finger. The final lift
      // position registers past the swipe threshold from the post-swipe
      // anchor in the *opposite* direction — natural finger pivot during
      // a lift. The previous implementation called _moveTouch on the
      // ended event and re-fired a stray arrowRight here.
      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('ended', x: 600, y: 500);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
    });

    test('click events emit held select key down and up', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('ended', x: 500, y: 500);
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keyDowns, [LogicalKeyboardKey.enter]);
      expect(harness.keyUps, [LogicalKeyboardKey.enter]);

      harness.advance(const Duration(milliseconds: 121));
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keyDowns, [LogicalKeyboardKey.enter, LogicalKeyboardKey.enter]);
      expect(harness.keyUps, [LogicalKeyboardKey.enter, LogicalKeyboardKey.enter]);
    });

    test('native select suppresses click fallback from physical remote path', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select));
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keyDowns, isEmpty);
      expect(harness.keyUps, isEmpty);

      harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.select));
      harness.advance(const Duration(milliseconds: 121));
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keyDowns, [LogicalKeyboardKey.enter]);
      expect(harness.keyUps, [LogicalKeyboardKey.enter]);
    });

    test('native select during click fallback is consumed and releases synthetic select', () async {
      final harness = _Harness();

      await harness.send('click_s');

      expect(harness.keyDowns, [LogicalKeyboardKey.enter]);
      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.enter)), isTrue);
      expect(harness.keyUps, isEmpty);

      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.enter)), isTrue);

      expect(harness.keyUps, [LogicalKeyboardKey.enter]);

      await harness.send('click_e');

      expect(harness.keyUps, [LogicalKeyboardKey.enter]);
    });

    test('native select burst consumes duplicate native pairs', () async {
      final harness = _Harness();

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select)), isFalse);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.select)), isFalse);

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.select)), isTrue);

      harness.advance(const Duration(milliseconds: 121));

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select)), isFalse);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.select)), isFalse);
    });

    test('raw native enter suppresses click fallback from tvOS engine path', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(_rawEnterKey));
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keyDowns, isEmpty);
      expect(harness.keyUps, isEmpty);
    });

    test('recent directional input suppresses click fallback', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft));
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keyDowns, isEmpty);
      expect(harness.keyUps, isEmpty);

      harness.advance(const Duration(milliseconds: 221));
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keyDowns, [LogicalKeyboardKey.enter]);
      expect(harness.keyUps, [LogicalKeyboardKey.enter]);
    });

    test('synthetic swipe suppresses click fallback', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('click_s');
      await harness.send('click_e');

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
      expect(harness.keyDowns, isEmpty);
      expect(harness.keyUps, isEmpty);
    });

    test('synthetic swipe followed by matching native arrow down and up moves once', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft)), isTrue);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
    });

    test('synthetic swipe also suppresses a native arrow on the other axis', () async {
      // The two paths resolve the swipe axis independently, so one diagonal
      // swipe could produce arrowLeft here and arrowDown natively. Matching
      // only the same key let that through as a second, sideways move.
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowDown)), isTrue);
    });

    test('native-only directional press still passes through', () async {
      final harness = _Harness();

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown)), isFalse);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowDown)), isFalse);
    });

    test('native directional press claims the gesture and mutes the accumulator', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isFalse);
      await harness.send('move', x: 380, y: 500);

      expect(harness.keys, isEmpty);
    });

    test('every native directional event is consumed while the swipe owns the gesture', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyRepeat(LogicalKeyboardKey.arrowLeft)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft)), isTrue);
    });

    test('delayed native directional press during the same gesture is still consumed', () async {
      // The regression: the old 120ms per-key window let tvOS' own recognizer
      // through on a busy frame, so one swipe moved the focus two cells.
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      harness.advance(const Duration(milliseconds: 400));

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyRepeat(LogicalKeyboardKey.arrowLeft)), isTrue);
      expect(harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft)), isTrue);
    });

    test('native arrow trailing the finger lift is consumed within the grace', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('ended', x: 380, y: 500);
      harness.advance(const Duration(milliseconds: 200));

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isTrue);
    });

    test('native arrow after the grace expires passes through again', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('ended', x: 380, y: 500);
      harness.advance(const Duration(milliseconds: 251));

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft)), isFalse);
    });

    test('swipe travel past the threshold carries into the next step', () async {
      // Anchor advances by exactly one threshold, so three thresholds of
      // travel yield three steps regardless of how the moves were sampled.
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 200, y: 500);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);

      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 200, y: 500);
      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 200, y: 500);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft]);

      // ...and stops once the carried remainder is used up.
      harness.advance(const Duration(milliseconds: 191));
      await harness.send('move', x: 200, y: 500);

      expect(harness.keys, hasLength(3));
    });

    test('cancelled touch does not emit select on a later ended message', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('cancelled');
      await harness.send('ended', x: 500, y: 500);
      await harness.send('loc', x: 1, y: 0);

      expect(harness.keys, isEmpty);
    });

    test('isTouchActive and listenable track touch start and end', () async {
      final harness = _Harness();
      final seen = <bool>[];
      harness.service.touchActiveListenable.addListener(() => seen.add(harness.service.isTouchActive));

      expect(harness.service.isTouchActive, isFalse);

      await harness.send('started', x: 500, y: 500);
      expect(harness.service.isTouchActive, isTrue);

      await harness.send('ended', x: 500, y: 500);
      expect(harness.service.isTouchActive, isFalse);

      expect(seen, [true, false]);
    });

    test('synthetic swipe tags the direction as swipe-driven', () async {
      final harness = _Harness();

      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isFalse);

      await harness.send('started', x: 500, y: 300);
      await harness.send('move', x: 500, y: 420);

      expect(harness.keys, [LogicalKeyboardKey.arrowDown]);
      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isTrue);
    });

    test('native directional during a travelling touch is tagged as swipe-driven', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 300);
      await harness.send('move', x: 500, y: 370);

      // No synthetic key yet (below the 100pt test threshold), but the finger
      // has travelled past the 60pt classify distance.
      expect(harness.keys, isEmpty);
      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown)), isFalse);
      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isTrue);
    });

    test('a near-still native press clears an earlier swipe tag', () async {
      // The first gesture is owned by the native path, so its ownership does
      // not carry into the second one and the press below actually reaches the
      // app. A press that the swipe owner consumes never gets to a widget, so
      // its attribution is moot.
      final harness = _Harness();

      await harness.send('started', x: 500, y: 300);
      await harness.send('move', x: 500, y: 370);
      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown)), isFalse);
      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isTrue);

      await harness.send('ended', x: 500, y: 370);
      harness.advance(const Duration(milliseconds: 130));
      await harness.send('started', x: 500, y: 300);
      await harness.send('move', x: 500, y: 302);

      expect(harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown)), isFalse);
      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isFalse);
    });

    test('swipe attribution expires after the attribution window', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 300);
      await harness.send('move', x: 500, y: 420);

      harness.advance(const Duration(milliseconds: 250));
      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isTrue);

      harness.advance(const Duration(milliseconds: 1));
      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isFalse);
    });

    test('native key repeats never tag a direction as swipe-driven', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 300);
      await harness.send('move', x: 500, y: 370);

      expect(harness.service.handleNativeKeyEvent(_keyRepeat(LogicalKeyboardKey.arrowDown)), isFalse);
      expect(harness.service.isSwipeDirectional(LogicalKeyboardKey.arrowDown), isFalse);
    });

    test('cancelled touch clears touch-active state', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      expect(harness.service.isTouchActive, isTrue);

      await harness.send('cancelled');
      expect(harness.service.isTouchActive, isFalse);
    });
  });

  group('AppleTvRemoteTouchService directional ownership across a gesture', () {
    // The physical Apple TV finding, in both places it showed up: LEFT on
    // Series jumped past Home to Search, and DOWN on a landing jumped past the
    // first rail. One press, two moves.
    //
    // A click on the Siri Remote's ring is a touch *and* a press, and tvOS
    // reports the two over separate paths — its own recognizer synthesizes the
    // UIPress arrow, the engine streams the raw coordinates this service turns
    // into arrows itself. The class already resolves that with a per-gesture
    // owner, and the mute is symmetric while the owner stands. What was not
    // symmetric is what survives the start of a touch: `_startTouch` carried a
    // *swipe* claim across and threw a *native* one away, on the reasoning
    // that a ring click starts fresh. It does — except when the ring click's
    // own arrow arrived a few milliseconds before its touch stream did, which
    // is the ordering the device actually produces. The claim was dropped, the
    // travel of the same finger crossed the threshold, and the gesture moved
    // the focus a second time.
    //
    // Invisible everywhere it could have been caught: the simulator has no
    // touch surface (idb injects the key directly, so only one path exists),
    // and a widget test sends the key straight to the focus tree.
    test('a native arrow claims the gesture that its own touch stream then starts', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft));
      harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft));

      // The same physical contact, reported a moment later.
      harness.advance(const Duration(milliseconds: 8));
      await harness.send('started', x: 500, y: 500);

      // The travel crosses the threshold 150 ms in. That is past the 120 ms
      // per-key duplicate window — which is the only thing that was catching
      // this case, and only ever when the second arrow happened to be the same
      // key — and well inside the gesture's own ownership grace.
      harness.advance(const Duration(milliseconds: 150));
      await harness.send('move', x: 380, y: 500);
      await harness.send('move', x: 260, y: 500);

      expect(
        harness.keys,
        isEmpty,
        reason: 'the arrow the engine already delivered is the whole gesture; the travel behind it is not a second one',
      );
    });

    test('and keeps holding it for as long as the finger is down', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown));
      harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowDown));
      await harness.send('started', x: 500, y: 500);

      // Well past the post-lift grace, but the finger never left: a claim held
      // while the touch is live does not expire under it.
      harness.advance(const Duration(milliseconds: 900));
      await harness.send('move', x: 500, y: 360);

      expect(harness.keys, isEmpty);
    });

    test('a touch starting long after an unrelated arrow still swipes', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft));
      harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.arrowLeft));

      // Past the grace, so this is a new gesture by any reading and the
      // accumulator owns it.
      harness.advance(const Duration(milliseconds: 400));
      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
    });
  });

  group('AppleTvRemoteTouchService select trace', () {
    // The correlation id is a separate field from the duplicate-suppression
    // flag on purpose. These tests pin that separation: the flag is cleared by
    // rules that have nothing to do with a press reaching a widget, and an id
    // that died with it would leave the row without a trace to carry.
    test('a clickpad press opens one trace and latches it at the release', () async {
      final harness = _Harness();

      await harness.send('click_s');
      expect(harness.recorder.debugOpenTraceIds, hasLength(1));
      final opened = harness.recorder.debugOpenTraceIds.single;

      await harness.send('click_e');

      expect(harness.recorder.consumeActiveSelectTrace(), opened);
    });

    test('a native press latches its id even though the pressed flag is cleared', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select));
      final opened = harness.recorder.debugOpenTraceIds.single;
      harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.select));

      expect(harness.recorder.consumeActiveSelectTrace(), opened);
    });

    test('a suppressed duplicate key-down does not open a second trace', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select));
      harness.service.handleNativeKeyEvent(_keyDown(_rawEnterKey));

      expect(harness.recorder.debugOpenTraceIds, hasLength(1));
    });

    test('an unclaimed press is dropped when the next one starts', () async {
      // Select on something that is not a row leaves a latch nobody consumes.
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select));
      harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.select));
      final abandoned = harness.recorder.debugOpenTraceIds.single;

      // Far enough out that the next press is a real one and not swallowed as
      // a duplicate of the one before it.
      harness.advance(const Duration(seconds: 1));
      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select));

      expect(harness.recorder.debugOpenTraceIds, hasLength(1));
      expect(harness.recorder.debugOpenTraceIds, isNot(contains(abandoned)));
      expect(harness.traceLines, isEmpty, reason: 'a press that reached nothing is not worth a line');
    });

    test('stopping the service leaves no press open', () async {
      final harness = _Harness();
      harness.service.start();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select));
      harness.service.stop();

      expect(harness.recorder.debugOpenTraceIds, isEmpty);
      expect(harness.recorder.consumeActiveSelectTrace(), isNull);
    });
  });
}

class _Harness {
  DateTime now = DateTime(2026, 5, 5, 12);
  final List<LogicalKeyboardKey> keys = [];
  final List<LogicalKeyboardKey> keyDowns = [];
  final List<LogicalKeyboardKey> keyUps = [];
  final List<String> traceLines = [];

  late final SelectTraceRecorder recorder = SelectTraceRecorder(
    enabled: true,
    now: () => now,
    emitInfo: traceLines.add,
    emitWarning: traceLines.add,
  );

  late final AppleTvRemoteTouchService service = AppleTvRemoteTouchService(
    simulateKeyPress: keys.add,
    simulateKeyDown: keyDowns.add,
    simulateKeyUp: keyUps.add,
    scheduleFrame: () {},
    now: () => now,
    swipeThreshold: 100,
    traceRecorder: recorder,
  );

  Future<void> send(String type, {double x = 0, double y = 0}) {
    return service.handleMessage({'type': type, 'x': x, 'y': y});
  }

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

/// A focused node that records every key event that reaches the focus tree —
/// the layer `FocusableWrapper` lives on, and the one the log showed the
/// duplicate still arriving at.
Future<void> _focusRecorder(WidgetTester tester, List<KeyEvent> received) async {
  final node = FocusNode(debugLabel: 'nav1-recorder');
  addTearDown(node.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Focus(
        focusNode: node,
        onKeyEvent: (_, event) {
          received.add(event);
          return KeyEventResult.handled;
        },
        child: const SizedBox.expand(),
      ),
    ),
  );
  node.requestFocus();
  await tester.pump();
}

Future<void> _sendPair(LogicalKeyboardKey key) async {
  await simulateKeyDownEvent(key);
  await simulateKeyUpEvent(key);
}

/// The honest first press: a touch, then one complete pair.
Future<void> _pressPair(_Harness h, {required List<KeyEvent> received}) async {
  await h.send('started');
  h.advance(const Duration(milliseconds: 30));
  await _sendPair(LogicalKeyboardKey.arrowLeft);
  expect(received, hasLength(2), reason: 'de echte druk hoort gewoon aan te komen');
}

const _rawEnterKey = LogicalKeyboardKey(0x0d);

KeyDownEvent _keyDown(LogicalKeyboardKey logicalKey) {
  return KeyDownEvent(physicalKey: PhysicalKeyboardKey.enter, logicalKey: logicalKey, timeStamp: Duration.zero);
}

KeyUpEvent _keyUp(LogicalKeyboardKey logicalKey) {
  return KeyUpEvent(physicalKey: PhysicalKeyboardKey.enter, logicalKey: logicalKey, timeStamp: Duration.zero);
}

KeyRepeatEvent _keyRepeat(LogicalKeyboardKey logicalKey) {
  return KeyRepeatEvent(physicalKey: PhysicalKeyboardKey.enter, logicalKey: logicalKey, timeStamp: Duration.zero);
}

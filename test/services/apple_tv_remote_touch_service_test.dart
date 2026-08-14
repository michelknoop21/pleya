import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleTvRemoteTouchService', () {
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
}

class _Harness {
  DateTime now = DateTime(2026, 5, 5, 12);
  final List<LogicalKeyboardKey> keys = [];
  final List<LogicalKeyboardKey> keyDowns = [];
  final List<LogicalKeyboardKey> keyUps = [];

  late final AppleTvRemoteTouchService service = AppleTvRemoteTouchService(
    simulateKeyPress: keys.add,
    simulateKeyDown: keyDowns.add,
    simulateKeyUp: keyUps.add,
    scheduleFrame: () {},
    now: () => now,
    swipeThreshold: 100,
  );

  Future<void> send(String type, {double x = 0, double y = 0}) {
    return service.handleMessage({'type': type, 'x': x, 'y': y});
  }

  void advance(Duration duration) {
    now = now.add(duration);
  }
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

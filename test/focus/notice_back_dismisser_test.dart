import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/key_event_utils.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/notice/notice.dart';
import 'package:pleya/widgets/notice/notice_back_dismisser.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';

void _noop() {}

const _retry = NoticeAction(label: 'Retry', onPressed: _noop, recovery: true);
const _details = NoticeAction(label: 'Details', onPressed: _noop);

KeyEvent _down() => const KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.escape,
  logicalKey: LogicalKeyboardKey.goBack,
  timeStamp: Duration.zero,
);

KeyEvent _up() => const KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.escape,
  logicalKey: LogicalKeyboardKey.goBack,
  timeStamp: Duration.zero,
);

KeyEvent _unrelated() => const KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.arrowDown,
  logicalKey: LogicalKeyboardKey.arrowDown,
  timeStamp: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoticeController controller;

  setUp(() {
    controller = NoticeController();
    NoticeBackDismisser.debugController = controller;
    NativeInputSession.debugReset();
    BackKeyUpSuppressor.clearSuppression();
  });

  tearDown(() {
    TvDetectionService.debugSetTvOverride(null);
    TvDetectionService.debugSetAppleTVOverride(null);
    NoticeBackDismisser.debugReset();
    NativeInputSession.debugReset();
    BackKeyUpSuppressor.clearSuppression();
  });

  String showPersistent() =>
      controller.show(const Notice(level: NoticeLevel.error, title: 'Boom', groupKey: 'b', primary: _retry));

  group('scope', () {
    test('does nothing off TV, even with a persistent notice on screen', () {
      showPersistent();
      expect(NoticeBackDismisser.handleKeyEvent(_down()), KeyEventResult.ignored);
      expect(NoticeBackDismisser.handleKeyEvent(_up()), KeyEventResult.ignored);
      expect(controller.visible, hasLength(1));
    });

    test('does nothing on TV with no notices', () {
      TvDetectionService.debugSetTvOverride(true);
      expect(NoticeBackDismisser.handleKeyEvent(_down()), KeyEventResult.ignored);
    });

    test('ignores keys that are not back', () {
      TvDetectionService.debugSetTvOverride(true);
      showPersistent();
      expect(NoticeBackDismisser.handleKeyEvent(_unrelated()), KeyEventResult.ignored);
      expect(controller.visible, hasLength(1));
    });

    // The exact regression: press-back-again-to-exit is itself an info notice
    // with a durationOverride. If back closed any notice, the second press
    // would only clear the prompt and the app would never exit.
    test('leaves the press-back-again-to-exit prompt alone', () {
      TvDetectionService.debugSetTvOverride(true);
      controller.show(
        const Notice(
          level: NoticeLevel.info,
          title: 'Press back again to exit',
          groupKey: 'exit',
          durationOverride: Duration(seconds: 2),
        ),
      );
      expect(NoticeBackDismisser.handleKeyEvent(_down()), KeyEventResult.ignored);
      expect(NoticeBackDismisser.handleKeyEvent(_up()), KeyEventResult.ignored);
      expect(controller.visible, hasLength(1));
    });

    test('leaves an error that clears itself alone', () {
      TvDetectionService.debugSetTvOverride(true);
      controller.show(const Notice(level: NoticeLevel.error, title: 'Boom', groupKey: 'b', primary: _details));
      expect(NoticeBackDismisser.handleKeyEvent(_down()), KeyEventResult.ignored);
      expect(controller.visible, hasLength(1));
    });

    test('stands down while a native input session owns the remote', () {
      TvDetectionService.debugSetTvOverride(true);
      showPersistent();
      NativeInputSession.begin();
      expect(NoticeBackDismisser.handleKeyEvent(_down()), KeyEventResult.ignored);
      expect(controller.visible, hasLength(1));

      NativeInputSession.end();
      NoticeBackDismisser.handleKeyEvent(_down());
      NoticeBackDismisser.handleKeyEvent(_up());
      expect(controller.visible, isEmpty);
    });
  });

  group('key edges', () {
    test('Android TV acts on key-up and consumes the down', () {
      TvDetectionService.debugSetTvOverride(true);
      showPersistent();

      expect(NoticeBackDismisser.handleKeyEvent(_down()), KeyEventResult.handled);
      expect(controller.visible, hasLength(1), reason: 'key-down must not dismiss yet');

      expect(NoticeBackDismisser.handleKeyEvent(_up()), KeyEventResult.handled);
      expect(controller.visible, isEmpty);
      // Absorbs the platform popRoute that Android delivers alongside the key.
      expect(BackKeyCoordinator.consumeIfHandled(), isTrue);
    });

    test('Apple TV acts on key-down and swallows the orphaned key-up', () {
      TvDetectionService.debugSetAppleTVOverride(true);
      showPersistent();

      expect(NoticeBackDismisser.handleKeyEvent(_down()), KeyEventResult.handled);
      expect(controller.visible, isEmpty);

      expect(NoticeBackDismisser.handleKeyEvent(_up()), KeyEventResult.ignored);
    });

    test('a suppressed key-up does not eat a notice', () {
      TvDetectionService.debugSetTvOverride(true);
      showPersistent();
      BackKeyUpSuppressor.suppressBackUntilKeyUp();

      expect(NoticeBackDismisser.handleKeyEvent(_up()), KeyEventResult.handled);
      expect(controller.visible, hasLength(1));
    });
  });

  test('one press removes one notice, newest first', () {
    TvDetectionService.debugSetTvOverride(true);
    controller.show(const Notice(level: NoticeLevel.error, title: 'first', groupKey: 'a', primary: _retry));
    controller.show(const Notice(level: NoticeLevel.error, title: 'second', groupKey: 'b', primary: _retry));

    NoticeBackDismisser.handleKeyEvent(_down());
    NoticeBackDismisser.handleKeyEvent(_up());
    expect(controller.visible.map((e) => e.notice.title), ['first']);

    NoticeBackDismisser.handleKeyEvent(_down());
    NoticeBackDismisser.handleKeyEvent(_up());
    expect(controller.visible, isEmpty);
  });
}

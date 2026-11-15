import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/screens/video_player/widgets/player_prompt_overlays.dart';
import 'package:pleya/services/pip_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/video_controls/player_chrome_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('play next prompt tracks chrome visibility for vertical position', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: -1,
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    expect(_promptPosition(tester).bottom, 100);

    chromeController.hide();
    await tester.pump();
    expect(_promptPosition(tester).bottom, 24);
  });

  testWidgets('play next buttons are pills so the focus ring fits the shape', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: -1,
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    // The buttons no longer carry a local shape override (removed in favor of
    // the app theme's MonoShapes.cta), so read the shape the button actually
    // painted with rather than its raw, now-null local style.
    final confirmMaterial = tester.widget<Material>(
      find.descendant(of: find.byType(FilledButton), matching: find.byType(Material)).first,
    );
    final cancelMaterial = tester.widget<Material>(
      find.descendant(of: find.byType(OutlinedButton), matching: find.byType(Material)).first,
    );

    expect(confirmMaterial.shape, isA<StadiumBorder>());
    expect(cancelMaterial.shape, isA<StadiumBorder>());
  });

  testWidgets('hovering play next prompt holds chrome visible and stable', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    chromeController.hide();

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: -1,
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    expect(_promptPosition(tester).bottom, 24);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Cancel')));
    await tester.pump();

    expect(chromeController.controlsVisible, isTrue);
    expect(chromeController.isHeld(PlayerChromeHold.promptInteraction), isTrue);
    expect(_promptPosition(tester).bottom, 100);
    expect(chromeController.hide(), isFalse);
    expect(_promptPosition(tester).bottom, 100);

    // Tree teardown releases the hold, which deliberately re-arms the
    // auto-hide timer (see the dispose comment in player_prompt_overlays.dart);
    // cancel it before the binding's pending-timer check.
    await tester.pumpWidget(_wrapPrompt(const SizedBox.shrink()));
    chromeController.cancelAutoHide();
  });

  testWidgets('focused play next prompt holds chrome visible', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: -1,
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    confirmFocusNode.requestFocus();
    await tester.pump();

    expect(chromeController.isHeld(PlayerChromeHold.promptInteraction), isTrue);
    expect(chromeController.hide(), isFalse);

    // Same deliberate re-arm as above: drop the tree, then cancel the timer.
    await tester.pumpWidget(_wrapPrompt(const SizedBox.shrink()));
    chromeController.cancelAutoHide();
  });

  testWidgets('removing a held prompt releases hold without notifying during dispose', (tester) async {
    PipService().isPipActive.value = false;
    final chromeController = PlayerChromeController();
    final cancelFocusNode = FocusNode(debugLabel: 'TestCancel');
    final confirmFocusNode = FocusNode(debugLabel: 'TestConfirm');
    addTearDown(chromeController.dispose);
    addTearDown(cancelFocusNode.dispose);
    addTearDown(confirmFocusNode.dispose);

    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: _episode(),
          autoPlayCountdown: -1,
          cancelFocusNode: cancelFocusNode,
          confirmFocusNode: confirmFocusNode,
          chromeController: chromeController,
          onCancel: () {},
          onPlayNext: () {},
        ),
      ),
    );

    chromeController.hold(PlayerChromeHold.promptInteraction);
    var notifications = 0;
    chromeController.addListener(() => notifications++);

    await tester.pumpWidget(_wrapPrompt(const SizedBox.shrink()));

    expect(chromeController.isHeld(PlayerChromeHold.promptInteraction), isFalse);
    expect(notifications, 0);

    // The dispose-release deliberately re-armed auto-hide; clear it so the
    // binding's pending-timer invariant stays green.
    chromeController.cancelAutoHide();
  });

  // DENS1 review I3: with the chrome up on a landscape iPhone the 320 card
  // covered the transport group (SE: card from x 323, play at 299..367).
  for (final (name, size, padding) in [
    ('iPhone SE', const Size(667, 375), EdgeInsets.zero),
    ('iPhone 18 Pro Max', const Size(956, 440), const EdgeInsets.only(left: 62, right: 62, bottom: 21)),
  ]) {
    testWidgets('the next-episode card stays right of the transport group on a landscape $name', (tester) async {
      PipService().isPipActive.value = false;
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = FakeViewPadding(
        left: padding.left * 3,
        right: padding.right * 3,
        bottom: padding.bottom * 3,
      );
      addTearDown(tester.view.reset);
      final chrome = PlayerChromeController()..setBottomChromeFraction(0.3);
      final cancel = FocusNode();
      final confirm = FocusNode();
      addTearDown(chrome.dispose);
      addTearDown(cancel.dispose);
      addTearDown(confirm.dispose);
      await tester.pumpWidget(
        _wrapPrompt(
          VideoPlayerPlayNextOverlay(
            visible: true,
            nextEpisode: _episode(),
            autoPlayCountdown: -1,
            cancelFocusNode: cancel,
            confirmFocusNode: confirm,
            chromeController: chrome,
            onCancel: () {},
            onPlayNext: () {},
          ),
          platform: TargetPlatform.iOS,
        ),
      );
      await tester.pumpAndSettle();
      final card = tester.getRect(find.text('S1 E2 · Episode 2'));
      final cardBox = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == Colors.black.withValues(alpha: 0.9),
        ),
      );
      // Transport group: 52 + 18 + 68 + 18 + 52, centred.
      final groupRight = size.width / 2 + 34 + 18 + 52;
      expect(cardBox.left, greaterThanOrEqualTo(groupRight), reason: 'card from ${cardBox.left}');
      expect(card.right, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
      chrome.cancelAutoHide();
    });
  }

  // Re-review Important 1: the narrowed corner applies to "still watching"
  // too, and "9 Doorgaan" did not fit its half of the card on an SE.
  testWidgets('still watching fits beside the transport group on a landscape iPhone SE', (tester) async {
    PipService().isPipActive.value = false;
    tester.view.physicalSize = const Size(667, 375) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final chrome = PlayerChromeController()..setBottomChromeFraction(0.3);
    final pause = FocusNode();
    final resume = FocusNode();
    addTearDown(chrome.dispose);
    addTearDown(pause.dispose);
    addTearDown(resume.dispose);
    await tester.pumpWidget(
      _wrapPrompt(
        VideoPlayerStillWatchingOverlay(
          visible: true,
          countdown: 29,
          pauseFocusNode: pause,
          continueFocusNode: resume,
          chromeController: chrome,
          onPause: () {},
          onContinue: () {},
        ),
        platform: TargetPlatform.iOS,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    chrome.cancelAutoHide();
  });
}

Widget _wrapPrompt(Widget child, {TargetPlatform? platform}) {
  return ChangeNotifierProvider(
    create: (_) => PlaybackStateProvider(),
    child: MaterialApp(
      theme: monoTheme(dark: true).copyWith(platform: platform),
      home: Scaffold(body: Stack(children: [child])),
    ),
  );
}

AnimatedPositioned _promptPosition(WidgetTester tester) {
  return tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
}

MediaItem _episode() {
  return MediaItem(
    id: 'episode-2',
    backend: MediaBackend.plex,
    kind: MediaKind.episode,
    title: 'Episode 2',
    parentIndex: 1,
    index: 2,
  );
}

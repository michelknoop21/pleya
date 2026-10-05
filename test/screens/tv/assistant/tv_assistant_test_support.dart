import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

export '../../../widgets/big_p/fake_assistant_controller.dart';

/// The app's frame around a TV screen: theme, translations, focus mode,
/// the overlay host the TV shell provides, and reduced motion so Big P's
/// ticker does not keep the test busy.
Future<void> pumpTvFrame(WidgetTester tester, AssistantController controller, Widget child) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TranslationProvider(
      child: ChangeNotifierProvider<AssistantController>.value(
        value: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: InputModeTracker(
                child: OverlaySheetHost(child: Scaffold(body: child)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
}

/// Frames enough for post-frame focus and the overlay's open animation,
/// without pumpAndSettle, which a living avatar never lets finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

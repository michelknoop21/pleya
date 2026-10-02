import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

/// A controller the test drives by hand. Every action the surface can take
/// is recorded; state only changes where the real controller's would on
/// that call, or when the test sets it and calls [emit].
class FakeAssistantController extends AssistantController {
  FakeAssistantController() : super(buildContext: (_) => throw UnimplementedError(), rolloutEnabled: false);

  @override
  AssistantAvailability availability = AssistantAvailability.ready;
  @override
  AssistantSurfaceState state = AssistantSurfaceState.idle;
  @override
  bool resultIsError = false;
  @override
  AssistantRunEnd? lastEnd;
  @override
  String? prompt;
  @override
  String answer = '';
  @override
  List<AssistantStep> steps = [];
  @override
  List<AssistantActionRecord> actions = [];
  @override
  List<AssistantDisplay> displays = [];
  @override
  AssistantPendingAction? pending;
  @override
  bool stillChecking = false;

  final submitted = <String>[];
  final listenContexts = <AssistantScreenContext?>[];
  final confirmedPasswords = <String?>[];
  final picked = <AssistantRequestOption>[];
  var cancelledListening = 0;
  var cancelledPending = 0;
  var resets = 0;
  var refreshes = 0;

  void emit() => notifyListeners();

  @override
  Future<void> refreshAvailability() async => refreshes++;

  @override
  void beginListening({AssistantScreenContext? context}) {
    listenContexts.add(context);
    state = AssistantSurfaceState.listening;
    notifyListeners();
  }

  @override
  void cancelListening() {
    cancelledListening++;
    state = AssistantSurfaceState.idle;
    notifyListeners();
  }

  @override
  Future<void> submit(String prompt) async {
    submitted.add(prompt);
    this.prompt = prompt;
    state = AssistantSurfaceState.working;
    notifyListeners();
  }

  @override
  void confirmPending({String? password}) => confirmedPasswords.add(password);

  @override
  void cancelPending() => cancelledPending++;

  @override
  Future<void> pickRequestOption(AssistantRequestOption option, {bool fourK = false}) async => picked.add(option);

  @override
  void reset() => resets++;
}

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

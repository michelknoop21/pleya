import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_results.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';

void main() {
  setUpAll(() => LocaleSettings.setLocale(AppLocale.nl));
  testWidgets('failure card shows the concrete server reason', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: BigPScale(
              pt: 0.53,
              child: BigPResultCard(
                error: true,
                actions: const [],
                time: '12:15',
                failureText: t.errors.connectionFailed,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text(t.errors.connectionFailed), findsOneWidget);
    expect(find.text(t.assistant.ends.nothingChanged), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a failed tool keeps its server reason even after a closing model reply', () {
    const task = AssistantTask(
      id: 't',
      title: 'Controleer bibliotheek',
      intent: 'command',
      status: AssistantTaskStatus.failed,
      answer: '',
      displays: [],
      steps: [],
      actions: [],
      error: 'server_unavailable',
      lastEnd: AssistantRunEnd.answered,
    );
    expect(assistantTaskStatusLabel(task).detail, t.errors.connectionFailed);
    expect(assistantTaskAnswer(task), contains(t.errors.connectionFailed));
  });

  test('a diagnosis that hit its call limit does not tell the user to retry', () {
    const task = AssistantTask(
      id: 't',
      title: 'Controleer bibliotheek',
      intent: 'command',
      status: AssistantTaskStatus.failed,
      answer: '',
      displays: [],
      steps: [],
      actions: [],
      error: 'diagnosis_call_limit',
      lastEnd: AssistantRunEnd.answered,
    );
    expect(assistantTaskStatusLabel(task).detail, t.assistant.ends.checkLimit);
    expect(assistantTaskStatusLabel(task).detail, isNot(t.errors.somethingWentWrongTryAgain));
  });
}

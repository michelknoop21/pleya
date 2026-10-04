import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_results.dart';

import 'tv_assistant_test_support.dart';

/// The result card follows a started scan: running with a percent, then
/// done or failed, and "gestart" when Pleya cannot follow it.
void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.nl));
  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  AssistantActionRecord scan(AssistantJobProgress? progress) => AssistantActionRecord(
    kind: AssistantActionKind.scanLibrary,
    serverName: 'Zolder',
    subject: 'Films',
    progress: progress,
  );

  Future<void> pump(WidgetTester tester, AssistantActionRecord record) =>
      pumpTvFrame(tester, FakeAssistantController(), BigPResultCard(error: false, actions: [record], time: '21:14'));

  testWidgets('running, done, failed, background and not followed', (tester) async {
    await pump(tester, scan(const AssistantJobProgress(AssistantJobPhase.running, percent: 40)));
    expect(find.text('Scan loopt · 40% · Films · Zolder'), findsOneWidget);
    final node = tester.widget<AutomationNode>(
      find.byWidgetPredicate((w) => w is AutomationNode && w.id == AutomationIds.assistantResult),
    );
    expect((node.state!() as Map)['jobs'], [
      {'phase': 'running', 'percent': 40},
    ]);

    await pump(tester, scan(const AssistantJobProgress(AssistantJobPhase.done)));
    expect(find.text('Scan klaar · Films · Zolder'), findsOneWidget);

    await pump(tester, scan(const AssistantJobProgress(AssistantJobPhase.failed)));
    expect(find.text('Scan mislukt · Films · Zolder'), findsOneWidget);

    await pump(tester, scan(const AssistantJobProgress(AssistantJobPhase.background)));
    expect(find.text('Scan loopt nog op de achtergrond · Films · Zolder'), findsOneWidget);

    await pump(tester, scan(const AssistantJobProgress(AssistantJobPhase.started)));
    expect(find.text('Scan gestart · Films · Zolder'), findsOneWidget);
  });
}

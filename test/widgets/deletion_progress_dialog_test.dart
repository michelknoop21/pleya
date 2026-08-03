import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/download_models.dart';
import 'package:pleya/widgets/deletion_progress_dialog.dart';

/// The deletion dialog used to be `barrierDismissible: false` + a `PopScope`
/// that swallowed BACK, with no button at all — a guaranteed dead end whenever
/// the deletion stalled. It must now always offer a way out.
void main() {
  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('a focusable close button dismisses the dialog', (tester) async {
    var closed = 0;
    await _pump(tester, onClose: () => closed++);

    await tester.tap(find.text(t.common.close));
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('a system back press routes to the same close path', (tester) async {
    var closed = 0;
    await _pump(tester, onClose: () => closed++);

    // Simulate the platform back gesture/button.
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('without progress it still renders a labelled spinner', (tester) async {
    await _pump(tester, onClose: () {}, progress: null);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t.downloads.deleting), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onClose,
  DeletionProgress? progress = const DeletionProgress(
    globalKey: 'server_1:item_1',
    itemTitle: 'Some Movie',
    currentItem: 1,
    totalItems: 3,
  ),
}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: DeletionProgressDialog(progress: progress, onClose: onClose),
      ),
    ),
  );
  // A plain pump: the spinner animates forever, so pumpAndSettle never returns.
  await tester.pump();
}

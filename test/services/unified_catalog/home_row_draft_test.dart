import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/home_row_draft.dart';

import '../../test_helpers/home_rows_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HomeCustomRowContent found() => HomeCustomRowContent(groups: [homeGroup('preview')]);

  test('a valid preview can be consumed once, including a saved callback', () async {
    final draft = HomeRowDraft(preview: (_) async => found());
    addTearDown(draft.dispose);
    draft.step = HomeRowWizardStep.preview;
    await draft.loadPreview();
    final save = draft.takeForSave;
    expect(save(), isNotNull);
    expect(save(), isNull);
    expect(draft.canSave, isFalse);
  });

  test('changing name or kind invalidates both a completed and an in-flight preview', () async {
    var pending = Completer<HomeCustomRowContent>();
    final draft = HomeRowDraft(preview: (_) => pending.future);
    addTearDown(draft.dispose);
    draft.step = HomeRowWizardStep.preview;
    final first = draft.loadPreview();
    pending.complete(found());
    await first;
    expect(draft.canSave, isTrue);
    draft.name.text = 'Changed';
    expect(draft.takeForSave(), isNull);
    pending = Completer<HomeCustomRowContent>();
    final second = draft.loadPreview();
    draft.setKind(MediaKind.show);
    pending.complete(found());
    await second;
    expect(draft.content, isNull);
    expect(draft.takeForSave(), isNull);
  });

  test('an older failed request cannot replace a newer successful preview', () async {
    final old = Completer<HomeCustomRowContent>();
    var calls = 0;
    final draft = HomeRowDraft(preview: (_) => calls++ == 0 ? old.future : Future.value(found()));
    addTearDown(draft.dispose);
    draft.step = HomeRowWizardStep.preview;
    final first = draft.loadPreview();
    await draft.loadPreview();
    old.completeError(StateError('old request failed'));
    await first;
    expect(draft.previewFailed, isFalse);
    expect(draft.canSave, isTrue);
  });
}

/// PB-5: the context menu's four navigation actions (Afspelen of Hervatten,
/// Afspelen vanaf het begin, Meer info, Bron wijzigen). Two things are worth
/// a check on their own: the resume/play label picks the right word, and
/// "Bron wijzigen" only appears with something to switch to.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/screens/tv/tv_unified_context_actions.dart';
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';

UnifiedMediaSource _source(String serverId) => UnifiedMediaSource.fromItem(
  MediaItem(
    id: 'i1',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Dune',
    year: 2021,
    serverId: serverId,
    serverName: serverId,
  ),
);

UnifiedMediaGroup _group(List<UnifiedMediaSource> sources) {
  final representative = sources.first.sourceKey;
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: sources,
    representativeSourceKey: representative,
    watchState: UnifiedWatchState(representativeSourceKey: representative),
  );
}

Future<List<UnifiedNavigationAction>> _openAndCollect(
  WidgetTester tester,
  UnifiedMediaGroup group, {
  required ValueChanged<UnifiedNavigationAction> onNavigate,
}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: OverlaySheetHost(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showTvUnifiedContextMenu(
                      context,
                      group: group,
                      availabilityFor: (_) => SourceAvailability.online,
                      onNavigate: (action) async => onNavigate(action),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester
      .widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow))
      .map((row) => row.label)
      .map(
        (label) => switch (label) {
          _ when label == t.common.play || label == t.common.resume => UnifiedNavigationAction.playOrResume,
          _ when label == t.mediaMenu.playFromBeginning => UnifiedNavigationAction.playFromBeginning,
          _ when label == t.tvContextMenu.moreInfo => UnifiedNavigationAction.moreInfo,
          _ when label == t.tvContextMenu.changeSource => UnifiedNavigationAction.changeSource,
          _ => null,
        },
      )
      .nonNulls
      .toList();
}

/// Focus the row carrying [text] and press SELECT, the way a remote does.
/// `FocusableWrapper` is keyboard/remote only — no tap handler of its own —
/// so a row here is reached this way, the same as
/// `language_settings_screen_test.dart`'s `_selectByText`.
Future<void> _selectByText(WidgetTester tester, String text) async {
  final candidates = tester
      .widgetList<Focus>(find.ancestor(of: find.text(text), matching: find.byType(Focus)))
      .where((focus) => focus.focusNode != null)
      .toList();
  expect(candidates, isNotEmpty, reason: 'no focusable ancestor for "$text"');
  candidates.first.focusNode!.requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  test('the play/resume label follows the group\'s own resume progress', () {
    expect(
      labelForUnifiedNavigationAction(UnifiedNavigationAction.playOrResume, hasResumeProgress: false),
      t.common.play,
    );
    expect(
      labelForUnifiedNavigationAction(UnifiedNavigationAction.playOrResume, hasResumeProgress: true),
      t.common.resume,
    );
    expect(
      labelForUnifiedNavigationAction(UnifiedNavigationAction.playFromBeginning, hasResumeProgress: true),
      t.mediaMenu.playFromBeginning,
    );
    expect(
      labelForUnifiedNavigationAction(UnifiedNavigationAction.moreInfo, hasResumeProgress: true),
      t.tvContextMenu.moreInfo,
    );
    expect(
      labelForUnifiedNavigationAction(UnifiedNavigationAction.changeSource, hasResumeProgress: true),
      t.tvContextMenu.changeSource,
    );
  });

  testWidgets('a single-source group offers no "Bron wijzigen" row — nothing to switch to', (tester) async {
    final found = await _openAndCollect(tester, _group([_source('nas')]), onNavigate: (_) {});

    expect(found, [
      UnifiedNavigationAction.playOrResume,
      UnifiedNavigationAction.playFromBeginning,
      UnifiedNavigationAction.moreInfo,
    ]);
  });

  testWidgets('a multi-source group adds "Bron wijzigen" as its own trailing row', (tester) async {
    final found = await _openAndCollect(tester, _group([_source('nas'), _source('jellyfin')]), onNavigate: (_) {});

    expect(found, [
      UnifiedNavigationAction.playOrResume,
      UnifiedNavigationAction.playFromBeginning,
      UnifiedNavigationAction.moreInfo,
      UnifiedNavigationAction.changeSource,
    ]);
  });

  testWidgets('picking a navigation row calls onNavigate with that action, and closes the menu', (tester) async {
    UnifiedNavigationAction? picked;
    await _openAndCollect(tester, _group([_source('nas')]), onNavigate: (action) => picked = action);

    await _selectByText(tester, t.mediaMenu.playFromBeginning);

    expect(picked, UnifiedNavigationAction.playFromBeginning);
    expect(find.byType(TvCatalogOptionRow), findsNothing, reason: 'the sheet has to have closed');
  });
}

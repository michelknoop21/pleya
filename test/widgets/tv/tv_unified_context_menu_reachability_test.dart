import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/screens/tv/tv_unified_context_actions.dart';
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_expandable_media_tile.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';

/// **The regression this file exists for.** Before fase 9, no fase-6/7/8 TV
/// card had a context menu at all: markeer bekeken, rate, kijklijst and
/// verwijder-uit-verder-kijken were unreachable from Home, the Films and Series
/// landings, the complete catalogus and TV-Search. The legacy rails had them,
/// so the rewrite lost a feature rather than never having had one.
///
/// A decision layer with no caller is what that fix looked like the first time
/// it was attempted, and it was reverted for exactly that reason. So this test
/// is deliberately about *reachability*: both unified tiles must arm the
/// hoofdstuk 23 gesture and hand it up, on the same `FocusableWrapper` contract
/// the legacy surfaces used — a long Select, or the remote's context-menu key.

MediaItem _item(String serverId, {String id = 'i1'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  year: 2021,
  serverId: serverId,
  serverName: serverId,
);

UnifiedMediaGroup _group() {
  final source = UnifiedMediaSource.fromItem(_item('nas'));
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
  );
}

Future<void> _pump(WidgetTester tester, Widget tile) => tester.pumpWidget(
  TranslationProvider(
    child: MaterialApp(
      theme: monoTheme(dark: true),
      home: InputModeTracker(
        child: Scaffold(body: Center(child: tile)),
      ),
    ),
  ),
);

/// Presses [key] on the focused tile.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

/// Holds Select past the long-press threshold.
Future<void> _holdSelect(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

void main() {
  setUp(SelectKeyUpSuppressor.clearSuppression);
  tearDown(SelectKeyUpSuppressor.clearSuppression);

  group('the expandable tile (Home rows, both landings, TV-Search)', () {
    testWidgets('a long Select opens the menu instead of activating', (tester) async {
      var menus = 0;
      var selects = 0;
      await _pump(
        tester,
        TvExpandableMediaTile(
          group: _group(),
          semanticLabel: 'Dune',
          autofocus: true,
          onSelect: () => selects++,
          onContextMenu: () => menus++,
        ),
      );
      await tester.pumpAndSettle();

      await _holdSelect(tester);

      expect(menus, 1);
      expect(selects, 0, reason: 'a long press is the menu, not a slow activation');
    });

    testWidgets('a short Select still activates', (tester) async {
      var menus = 0;
      var selects = 0;
      await _pump(
        tester,
        TvExpandableMediaTile(
          group: _group(),
          semanticLabel: 'Dune',
          autofocus: true,
          onSelect: () => selects++,
          onContextMenu: () => menus++,
        ),
      );
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.select);

      expect(selects, 1, reason: 'arming the menu must not cost the primary gesture');
      expect(menus, 0);
    });

    testWidgets('the context-menu key opens the menu', (tester) async {
      var menus = 0;
      await _pump(
        tester,
        TvExpandableMediaTile(
          group: _group(),
          semanticLabel: 'Dune',
          autofocus: true,
          onSelect: () {},
          onContextMenu: () => menus++,
        ),
      );
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.contextMenu);

      expect(menus, 1);
    });

    testWidgets('without a menu the long-press gesture is not armed at all', (tester) async {
      var selects = 0;
      await _pump(
        tester,
        TvExpandableMediaTile(group: _group(), semanticLabel: 'Dune', autofocus: true, onSelect: () => selects++),
      );
      await tester.pumpAndSettle();

      final wrapper = tester.widget<FocusableWrapper>(find.byType(FocusableWrapper).first);
      expect(
        wrapper.enableLongPress,
        isFalse,
        reason: 'arming it with a null callback leaves the select suppressor armed and eats the next press',
      );

      await _holdSelect(tester);
      expect(selects, 1, reason: 'and a held Select stays a plain Select');
    });
  });

  group('the catalog card (complete catalogus)', () {
    testWidgets('a long Select opens the menu instead of activating', (tester) async {
      var menus = 0;
      var selects = 0;
      await _pump(
        tester,
        TvUnifiedMediaCard(
          group: _group(),
          width: 220,
          autofocus: true,
          onSelect: () => selects++,
          onContextMenu: () => menus++,
        ),
      );
      await tester.pumpAndSettle();

      await _holdSelect(tester);

      expect(menus, 1);
      expect(selects, 0);
    });

    testWidgets('the context-menu key opens the menu', (tester) async {
      var menus = 0;
      await _pump(
        tester,
        TvUnifiedMediaCard(group: _group(), width: 220, autofocus: true, onSelect: () {}, onContextMenu: () => menus++),
      );
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.contextMenu);

      expect(menus, 1);
    });
  });

  group('the menu offers what the surface supports', () {
    test('a Continue Watching row offers the remove action; a library wall does not', () {
      final onCw = availableUnifiedGroupActions(group: _group(), isInContinueWatching: true, isOffline: false);
      final onWall = availableUnifiedGroupActions(group: _group(), isInContinueWatching: false, isOffline: false);

      expect(onCw, contains(UnifiedGroupAction.removeFromContinueWatching));
      expect(
        onWall,
        isNot(contains(UnifiedGroupAction.removeFromContinueWatching)),
        reason: '13.4 is about a card in Verder kijken; elsewhere it has nothing to act on',
      );
    });

    test('watched and unwatched are never offered together', () {
      final unwatchedGroup = _group();
      final actions = availableUnifiedGroupActions(
        group: unwatchedGroup,
        isInContinueWatching: false,
        isOffline: false,
      );

      expect(actions, contains(UnifiedGroupAction.markWatched));
      expect(actions, isNot(contains(UnifiedGroupAction.markUnwatched)));
    });

    test('offline drops the actions that need a server, and keeps the one that does not', () {
      final actions = availableUnifiedGroupActions(
        group: _group(),
        isInContinueWatching: false,
        isOffline: true,
        watchlist: UnifiedWatchlistState.notOnList,
      );

      expect(
        actions,
        isNot(contains(UnifiedGroupAction.addToWatchlist)),
        reason: 'DEC-020 refuses a watchlist mutation offline rather than queueing it',
      );
      expect(actions, isNot(contains(UnifiedGroupAction.rate)));
      expect(
        actions,
        contains(UnifiedGroupAction.markWatched),
        reason: 'WatchActions routes an offline mark to the offline queue, so it still means something',
      );
    });

    test('an unsupported watchlist offers neither add nor remove', () {
      final actions = availableUnifiedGroupActions(
        group: _group(),
        isInContinueWatching: false,
        isOffline: false,
        watchlist: UnifiedWatchlistState.unsupported,
      );

      expect(actions, isNot(contains(UnifiedGroupAction.addToWatchlist)));
      expect(actions, isNot(contains(UnifiedGroupAction.removeFromWatchlist)));
    });

    test('every offered action has a label', () {
      for (final action in UnifiedGroupAction.values) {
        expect(labelForUnifiedGroupAction(action), isNotEmpty, reason: '${action.name} would render as a blank row');
      }
    });
  });
  // G10: the message the fan-out ends on. Hoofdstuk 13.4 point 5 fixes both
  // halves of it — the denominator and the retry clause — and both were wrong
  // before fase 9: the count read only the reachable sources, and the retry
  // clause was shown for actions that queue nothing.
  group('the outcome message tells the truth about what landed', () {
    test('a single write that worked says nothing at all', () {
      expect(unifiedActionOutcomeMessage(done: 1, total: 1, queued: 0), isNull);
    });

    test('everything landing on several sources is a tally', () {
      expect(unifiedActionOutcomeMessage(done: 3, total: 3, queued: 0), t.tvContextMenu.doneOnAll(count: 3));
    });

    test('two of three, with the third queued, promises the retry', () {
      expect(
        unifiedActionOutcomeMessage(done: 2, total: 3, queued: 1),
        t.tvContextMenu.doneOnSome(done: 2, total: 3),
      );
      expect(t.tvContextMenu.doneOnSome(done: 2, total: 3), contains('3'));
    });

    test('two of three with nothing queued drops the retry clause', () {
      // The promise "the rest will be retried" may only appear when a queue
      // entry exists. An action that queues nothing must not borrow it.
      final message = unifiedActionOutcomeMessage(done: 2, total: 3, queued: 0);

      expect(message, t.tvContextMenu.doneOnSomeNoRetry(done: 2, total: 3));
      expect(message, isNot(t.tvContextMenu.doneOnSome(done: 2, total: 3)));
      expect(message, isNot(contains(t.tvContextMenu.doneOnSome(done: 2, total: 3).split('. ').last)));
    });

    test('a removal held on every membership reads as held, not as failed', () {
      // Nothing was written, but the user's intent is safely recorded and the
      // card is gone. Reporting a failure here would be the opposite of what
      // happened.
      expect(
        unifiedActionOutcomeMessage(done: 0, total: 2, queued: 2),
        t.tvContextMenu.doneOnSome(done: 0, total: 2),
      );
    });

    test('nothing landed and nothing held is a plain failure', () {
      expect(unifiedActionOutcomeMessage(done: 0, total: 2, queued: 0), t.tvContextMenu.failed);
    });
  });

}

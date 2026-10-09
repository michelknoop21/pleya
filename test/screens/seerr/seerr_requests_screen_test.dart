/// The requests list against a scripted Seerr (Requests 2.0, families 7 and 8):
/// whose requests it shows, which counts it may show beside them, and what one
/// action does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/seerr_request_row.dart';
import 'package:pleya/widgets/tv/tv_seerr_card.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

Finder _state(String which) => seerrNode(AutomationIds.requestsListState, which);
Finder _tvState(String which) => seerrNode(AutomationIds.tvCatalogState, 'requests.$which');

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    fake = FakeSeerr()
      ..on('GET /request', seerrPage([seerrRequestJson(1), seerrRequestJson(2, requestedBy: 9)]))
      ..on('GET /request/count', {'total': 2, 'pending': 2, 'approved': 0, 'available': 5});
  });

  Future<void> open(
    WidgetTester tester, {
    int? userId = 7,
    int permissions = seerrPermRequest,
    bool mineOnly = false,
    MemorySeerrStore? store,
    int? focusRequestId,
    Size size = const Size(1280, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake, userId: userId, permissions: permissions, store: store);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      SeerrRequestsScreen(mineOnly: mineOnly, focusRequestId: focusRequestId),
      host: false,
    );
    await seerrSettle(tester);
  }

  group('scope', () {
    testWidgets("a requester's list is asked for by their own user id and carries no counts", (tester) async {
      await open(tester);

      expect(fake.sent('GET', '/request').single.query['requestedBy'], '7');
      expect(fake.sent('GET', '/request/count'), isEmpty, reason: 'the count route counts everyone');
      expect(find.text(t.seerr.myRequests), findsOneWidget);
      expect(find.textContaining('${t.seerr.filterPending}  '), findsNothing, reason: 'the chip has no number');
    });

    testWidgets('a manager who opens Mijn aanvragen gets their own list, also without counts', (tester) async {
      await open(tester, permissions: seerrPermManage, mineOnly: true);

      expect(fake.sent('GET', '/request').single.query['requestedBy'], '7');
      expect(fake.sent('GET', '/request/count'), isEmpty);
    });

    testWidgets('without a known user id nothing is asked for at all, and the page says why', (tester) async {
      await open(tester, userId: null);

      expect(fake.sent('GET', '/request'), isEmpty, reason: 'requestedBy=null would be everyone');
      expect(find.text(t.seerr.ownScopeUnknown), findsOneWidget);
      expect(find.byType(SeerrRequestRow), findsNothing);
    });

    testWidgets('a manager sees every request, with the counts that belong to that same set', (tester) async {
      await open(tester, permissions: seerrPermManage);

      expect(fake.sent('GET', '/request').single.query.containsKey('requestedBy'), isFalse);
      expect(find.text('${t.seerr.filterAll}  2'), findsOneWidget);
      expect(find.text('${t.seerr.filterApproved}  0'), findsOneWidget, reason: 'a counted zero is a count');
      expect(
        find.text(t.seerr.filterAvailable),
        findsOneWidget,
        reason: 'the count route and the list route mean different things by available',
      );
    });

    testWidgets('counts that fail to load are a dash, never a zero', (tester) async {
      fake.on('GET /request/count', {'message': 'boom'}, 500);
      await open(tester, permissions: seerrPermManage);

      expect(find.text('${t.seerr.filterAll}  –'), findsOneWidget);
      expect(find.textContaining('  0'), findsNothing);
      expect(find.byType(SeerrRequestRow), findsNWidgets(2), reason: 'the list does not depend on the counts');
    });
  });

  group('states', () {
    testWidgets('an empty list is not an error: the way out is Ontdekken, not trying again', (tester) async {
      fake.on('GET /request', seerrPage(const []));
      await open(tester);

      expect(_state('empty'), findsOneWidget);
      expect(find.text(t.seerr.noOwnRequestsYet), findsOneWidget);
      expect(find.text(t.seerr.discoverAction), findsOneWidget);
      expect(find.text(t.common.retry), findsNothing);
    });

    testWidgets('a filter with nothing in it offers clearing the filter', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.on('GET /request', seerrPage(const []));
      await tester.tap(find.text('${t.seerr.filterApproved}  0'));
      await seerrSettle(tester);

      expect(_state('filtered'), findsOneWidget);
      await tester.tap(find.text(t.unifiedCatalog.states.clearFilters));
      await seerrSettle(tester);
      expect(fake.sent('GET', '/request').last.query['filter'], 'all');
    });

    testWidgets('a failed load keeps Opnieuw proberen', (tester) async {
      fake.on('GET /request', {'message': 'boom'}, 500);
      await open(tester);

      expect(_state('error'), findsOneWidget);
      expect(find.text(t.common.retry), findsOneWidget);
    });

    testWidgets('an answer for the previous filter never lands under the new one', (tester) async {
      await open(tester, permissions: seerrPermManage);
      final slow = fake.hold('GET /request');
      await tester.tap(find.text('${t.seerr.filterPending}  2'));
      await tester.pump();
      fake.on('GET /request', seerrPage([seerrRequestJson(5, status: 2)]));
      await tester.tap(find.text('${t.seerr.filterApproved}  0'));
      await seerrSettle(tester);

      slow.complete(FakeSeerr.json(seerrPage([seerrRequestJson(1), seerrRequestJson(2)])));
      await seerrSettle(tester);

      expect(find.byType(SeerrRequestRow), findsOneWidget);
      expect(tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow)).request.id, 5);
    });

    testWidgets('a profile switch drops the old answer and starts over for the new account', (tester) async {
      final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
      final slow = fake.hold('GET /request');
      await open(tester, store: store);

      fake.on('GET /request', seerrPage([seerrRequestJson(8, requestedBy: 9)]));
      await provider.onActiveProfileChanged('user-2');
      await seerrSettle(tester);
      slow.complete(FakeSeerr.json(seerrPage([seerrRequestJson(1)])));
      await seerrSettle(tester);

      expect(fake.sent('GET', '/request').last.query['requestedBy'], '9');
      expect(tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow)).request.id, 8);
    });
  });

  group('actions', () {
    testWidgets('a requester gets Annuleren on their own pending request and nothing on anyone else\'s', (
      tester,
    ) async {
      await open(tester);
      final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();

      expect(rows[0].onCancel, isNotNull);
      expect(rows[0].onApprove, isNull);
      expect(rows[1].onCancel, isNull);
      expect(rows[1].onEdit, isNull);
    });

    testWidgets('approving is sent once, marks the row busy, and reloads list and counts', (tester) async {
      await open(tester, permissions: seerrPermManage);
      final answer = fake.hold('POST /request/2/approve');

      await tester.tap(find.text(t.seerr.approve).last);
      await tester.pump();
      expect(tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last.busy, isTrue);
      await tester.tap(find.text(t.seerr.approve).last, warnIfMissed: false);
      await tester.pump();
      expect(fake.sent('POST', '/request/2/approve'), hasLength(1));

      final listsBefore = fake.sent('GET', '/request').length;
      final countsBefore = fake.sent('GET', '/request/count').length;
      answer.complete(FakeSeerr.json({'id': 2}));
      await seerrSettle(tester);

      expect(fake.sent('GET', '/request').length, listsBefore + 1);
      expect(fake.sent('GET', '/request/count').length, countsBefore + 1);
      expect(tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last.busy, isFalse);
    });

    testWidgets('two starts of the same action in one frame still send it once', (tester) async {
      // The row disarms its own buttons once it is rebuilt as busy. This is
      // the window before that rebuild, and the path the TV menu takes, where
      // there is no row to disarm.
      await open(tester, permissions: seerrPermManage);
      final answer = fake.hold('POST /request/2/approve');
      final approve = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last.onApprove!;

      approve();
      approve();
      await tester.pump();

      expect(fake.sent('POST', '/request/2/approve'), hasLength(1));
      answer.complete(FakeSeerr.json({'id': 2}));
      await seerrSettle(tester);
    });

    testWidgets('a refused action says so and still re-reads the list', (tester) async {
      fake.on('POST /request/2/decline', {'message': 'Only pending requests can be approved or declined.'}, 409);
      await open(tester, permissions: seerrPermManage);
      final listsBefore = fake.sent('GET', '/request').length;

      await tester.tap(find.text(t.seerr.decline).last);
      await seerrSettle(tester);

      expect(find.text(t.seerr.actionFailed), findsOneWidget);
      expect(fake.sent('GET', '/request').length, listsBefore + 1);
    });

    testWidgets('a lost connection is reported as unknown, not as failed, and the list is read back', (tester) async {
      fake.fail('POST /request/2/approve');
      await open(tester, permissions: seerrPermManage);
      final listsBefore = fake.sent('GET', '/request').length;

      await tester.tap(find.text(t.seerr.approve).last);
      await seerrSettle(tester);

      expect(find.text(t.seerr.actionUncertain), findsOneWidget);
      expect(fake.sent('GET', '/request').length, listsBefore + 1);
    });

    testWidgets('cancelling asks first, with the safe button focused, and only then deletes', (tester) async {
      fake.on('DELETE /request/1', null, 204);
      await open(tester);

      await tester.tap(find.text(t.seerr.cancelRequest));
      await tester.pumpAndSettle();
      expect(find.text(t.seerr.cancelRequestConfirm), findsOneWidget);
      expect(fake.sent('DELETE', '/request/1'), isEmpty);

      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();
      expect(fake.sent('DELETE', '/request/1'), isEmpty);

      await tester.tap(find.text(t.seerr.cancelRequest));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, t.seerr.cancelRequest));
      await seerrSettle(tester);
      expect(fake.sent('DELETE', '/request/1'), hasLength(1));
    });

    testWidgets('an action deep in the list reloads everything that was on screen, not just page one', (tester) async {
      fake.routes['GET /request'] = (request) {
        final take = int.parse(request.url.queryParameters['take']!);
        final skip = int.parse(request.url.queryParameters['skip']!);
        return FakeSeerr.json(
          seerrPage([
            for (var i = skip; i < skip + take && i < 30; i++) seerrRequestJson(i + 1, requestedBy: 9),
          ], pages: (30 / take).ceil()),
        );
      };
      tester.view.physicalSize = const Size(1280, 8000);
      await open(tester, permissions: seerrPermManage);
      tester.view.physicalSize = const Size(1280, 8000);
      await seerrSettle(tester);
      expect(find.byType(SeerrRequestRow), findsNWidgets(30), reason: 'page two loaded by itself');

      fake.on('POST /request/25/approve', {'id': 25});
      await tester.tap(find.text(t.seerr.approve).at(24));
      await seerrSettle(tester);

      final reload = fake.sent('GET', '/request').last.query;
      expect(reload['take'], '40');
      expect(reload['skip'], '0');
      expect(find.byType(SeerrRequestRow), findsNWidgets(30));
    });
  });

  group('filters say no more than the server proved (B06)', () {
    testWidgets('Afgewezen is offered off TV too, and leads to the explanation rather than a list', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.on('GET /request', seerrPage([seerrRequestJson(4, status: 3)]));
      final asked = fake.sent('GET', '/request').length;

      await tester.tap(find.text(t.seerr.filterDeclined));
      await seerrSettle(tester);

      expect(_state('unsupported'), findsOneWidget);
      expect(find.byType(SeerrRequestRow), findsNothing);
      expect(fake.sent('GET', '/request').length, asked);
    });

    testWidgets('approved requests still waiting for their file are not shown as Beschikbaar', (tester) async {
      await open(tester, permissions: seerrPermManage);
      // A server that ignored `available` and sent approved, not yet there.
      fake.on('GET /request', seerrPage([seerrRequestJson(6, status: 2, mediaStatus: 3)]));
      await tester.tap(find.text(t.seerr.filterAvailable));
      await seerrSettle(tester);

      expect(_state('unsupported'), findsOneWidget);
      expect(find.byType(SeerrRequestRow), findsNothing);
    });

    testWidgets('requests whose media is there are', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.on('GET /request', seerrPage([seerrRequestJson(6, status: 5, mediaStatus: 5)]));
      await tester.tap(find.text(t.seerr.filterAvailable));
      await seerrSettle(tester);

      expect(find.byType(SeerrRequestRow), findsOneWidget);
    });

    testWidgets("the viewer's own list says why its chips carry no numbers", (tester) async {
      await open(tester);
      expect(find.text(t.seerr.countsOwnScopeNote), findsOneWidget);
    });
  });

  group('an intent belongs to the account it started under (B01)', () {
    Future<MemorySeerrStore> openAsA(WidgetTester tester, {int permissions = seerrPermRequest}) async {
      // Both accounts have a request with id 1: ids are per server, and two
      // profiles can point at different servers or simply collide.
      final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9, permissions: permissions);
      fake.routes['GET /request'] = (request) => FakeSeerr.json(
        seerrPage([
          seerrRequestJson(1, requestedBy: int.tryParse(request.url.queryParameters['requestedBy'] ?? '') ?? 9),
        ]),
      );
      fake
        ..on('DELETE /request/1', null, 204)
        ..on('POST /request/1/approve', {'id': 1})
        ..on('POST /request/1/decline', {'id': 1});
      await open(tester, permissions: permissions, store: store);
      return store;
    }

    testWidgets('a cancel confirmed after a profile switch deletes nothing', (tester) async {
      await openAsA(tester);
      await tester.tap(find.text(t.seerr.cancelRequest));
      await tester.pumpAndSettle();
      expect(find.text(t.seerr.cancelRequestConfirm), findsOneWidget);

      await provider.onActiveProfileChanged('user-2');
      await seerrSettle(tester);
      // The confirmation that was opened for A's request is still on screen.
      await tester.tap(find.widgetWithText(FilledButton, t.seerr.cancelRequest));
      await seerrSettle(tester);

      expect(fake.sent('DELETE', '/request/1'), isEmpty, reason: "that would be B's request with the same id");
    });

    testWidgets('a choice made in a menu that was opened before a profile switch sends nothing', (tester) async {
      await openAsA(tester, permissions: seerrPermManage);
      await tester.tap(find.byTooltip(t.seerr.moreActions));
      await tester.pumpAndSettle();
      expect(seerrNode(AutomationIds.requestsActions), findsOneWidget);

      await provider.onActiveProfileChanged('user-2');
      await seerrSettle(tester);
      await tester.tap(
        find.descendant(
          of: seerrNode(AutomationIds.requestsActionsItem, 'approve'),
          matching: find.text(t.seerr.approve),
        ),
      );
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(fake.sent('POST', '/request/1/approve'), isEmpty);
    });

    testWidgets('a row callback from before a reload is checked against what the list holds now', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.on('POST /request/2/approve', {'id': 2});
      final stale = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last.onApprove!;

      // Someone else approved it meanwhile, and the list has since learned so.
      fake.on('GET /request', seerrPage([seerrRequestJson(1), seerrRequestJson(2, status: 2, requestedBy: 9)]));
      await tester.tap(find.text('${t.seerr.filterPending}  2'));
      await seerrSettle(tester);
      await tester.tap(find.textContaining(t.seerr.filterAll).first);
      await seerrSettle(tester);

      stale();
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request/2/approve'), isEmpty, reason: 'the request is no longer pending');
    });
  });

  group('an action without an answer stays locked until it is read back (B04)', () {
    testWidgets('no second action is offered while neither the answer nor the list could be read', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.fail('POST /request/2/approve');
      fake.fail('GET /request');

      await tester.tap(find.text(t.seerr.approve).last);
      await seerrSettle(tester);

      final row = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last;
      expect(row.busy, isTrue, reason: 'the outcome is open, so the request stays locked');
      expect(row.statusUnknown, isTrue);
      expect(find.text(t.seerr.statusUnknownBadge), findsOneWidget);

      await tester.tap(find.text(t.seerr.approve).last, warnIfMissed: false);
      await tester.tap(find.text(t.seerr.decline).last, warnIfMissed: false);
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request/2/approve'), hasLength(1));
      expect(fake.sent('POST', '/request/2/decline'), isEmpty);
    });

    testWidgets('reading the list back is the one thing it offers, and that unlocks it', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.fail('POST /request/2/approve');
      fake.fail('GET /request');
      await tester.tap(find.text(t.seerr.approve).last);
      await seerrSettle(tester);

      fake.on('GET /request', seerrPage([seerrRequestJson(1), seerrRequestJson(2, status: 2, requestedBy: 9)]));
      await tester.tap(find.byTooltip(t.seerr.checkStatus));
      await seerrSettle(tester);

      final row = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last;
      expect(row.busy, isFalse);
      expect(row.statusUnknown, isFalse);
      expect(row.request.status.name, 'approved');
      expect(
        seerrNode(AutomationIds.requestsActions),
        findsNothing,
        reason: 'it read the list, it did not open a menu',
      );
    });

    testWidgets('when the list can be read after a lost answer, the request is unlocked by that read', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.fail('POST /request/2/approve');
      await tester.tap(find.text(t.seerr.approve).last);
      await seerrSettle(tester);

      expect(tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last.busy, isFalse);
    });
  });

  group('a manager chooses between all requests and their own (7C, 7D)', () {
    testWidgets('automation scope buttons reflect the permitted selection', (tester) async {
      await open(tester, permissions: seerrPermManage);
      final own = seerrNode(AutomationIds.requestsListScope, 'own');
      final all = seerrNode(AutomationIds.requestsListScope, 'all');
      expect(own, findsOneWidget);
      expect(all, findsOneWidget);
      expect(tester.widget<AutomationNode>(own).state!(), {'selected': false});
      expect(tester.widget<AutomationNode>(all).state!(), {'selected': true});
      await tester.tap(own);
      await seerrSettle(tester);
      expect(_state('scope'), findsOneWidget);
      expect(tester.widget<AutomationNode>(own).state!(), {'selected': true});
      expect(tester.widget<AutomationNode>(all).state!(), {'selected': false});
      expect(fake.sent('GET', '/request').last.query['requestedBy'], '7');
      await tester.tap(all);
      await seerrSettle(tester);
      expect(fake.sent('GET', '/request').last.query.containsKey('requestedBy'), isFalse);
    });

    Finder scopeChip(String label) =>
        find.descendant(of: seerrNode(AutomationIds.requestsListState, 'scope'), matching: find.text(label));

    testWidgets('the list offers both scopes, and choosing Mijn aanvragen asks for the manager\'s own', (tester) async {
      await open(tester, permissions: seerrPermManage);
      expect(scopeChip(t.seerr.allRequests), findsOneWidget);
      expect(scopeChip(t.seerr.myRequests), findsOneWidget);
      final countsBefore = fake.sent('GET', '/request/count').length;

      await tester.tap(scopeChip(t.seerr.myRequests));
      await seerrSettle(tester);

      expect(fake.sent('GET', '/request').last.query['requestedBy'], '7');
      expect(fake.sent('GET', '/request/count').length, countsBefore, reason: 'no global counts beside an own list');
      expect(find.textContaining('${t.seerr.filterAll}  '), findsNothing);
      expect(find.text(t.seerr.countsOwnScopeNote), findsOneWidget);

      await tester.tap(scopeChip(t.seerr.allRequests));
      await seerrSettle(tester);
      expect(fake.sent('GET', '/request').last.query.containsKey('requestedBy'), isFalse);
      expect(find.text('${t.seerr.filterAll}  2'), findsOneWidget);
    });

    testWidgets('a requester has no scope to choose and never reaches the unscoped list', (tester) async {
      await open(tester);

      expect(seerrNode(AutomationIds.requestsListState, 'scope'), findsNothing);
      expect(seerrNode(AutomationIds.requestsListScope, 'own'), findsNothing);
      expect(seerrNode(AutomationIds.requestsListScope, 'all'), findsNothing);
      expect(fake.sent('GET', '/request').every((c) => c.query['requestedBy'] == '7'), isTrue);
    });

    testWidgets('an answer for the scope that was left does not land in the scope that was chosen', (tester) async {
      await open(tester, permissions: seerrPermManage);
      final slow = fake.hold('GET /request');
      await tester.tap(find.text('${t.seerr.filterPending}  2'));
      await tester.pump();

      fake.on('GET /request', seerrPage([seerrRequestJson(7)]));
      await tester.tap(scopeChip(t.seerr.myRequests));
      await seerrSettle(tester);
      slow.complete(FakeSeerr.json(seerrPage([seerrRequestJson(1), seerrRequestJson(2, requestedBy: 9)])));
      await seerrSettle(tester);

      final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();
      expect(rows.map((r) => r.request.id), [
        7,
      ], reason: "everyone's pending requests must not appear under Mijn aanvragen");
    });

    testWidgets('on a 390pt phone the manager list fits, and every action is reachable through the row menu', (
      tester,
    ) async {
      fake
        ..on(
          'GET /request',
          seerrPage([
            seerrRequestJson(1, type: 'tv', seasons: [3, 4, 5]),
          ]),
        )
        ..on('GET /request/count', {'total': 1, 'pending': 1, 'approved': 0});
      await open(tester, permissions: seerrPermAdmin, size: const Size(390, 844));

      expect(tester.takeException(), isNull, reason: 'no overflow at phone width');
      for (final label in [t.seerr.approve, t.seerr.decline, t.seerr.edit, t.seerr.cancelRequest]) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left >= 0 && rect.right <= 390, isTrue, reason: '$label is inside the screen');
      }
      expect(tester.getRect(find.text('Title 1')).width, greaterThan(80));
      // The scope chips scroll sideways like the status chips; the second one
      // starts on screen, so it can be seen and dragged into full view.
      expect(tester.getRect(scopeChip(t.seerr.myRequests)).left, lessThan(330));

      await tester.tap(find.byTooltip(t.seerr.moreActions));
      await tester.pumpAndSettle();
      for (final action in ['open', 'approve', 'decline', 'edit', 'cancel']) {
        final item = seerrNode(AutomationIds.requestsActionsItem, action);
        expect(item, findsOneWidget, reason: action);
        final rect = tester.getRect(item);
        expect(rect.left >= 0 && rect.right <= 390 && rect.bottom <= 844, isTrue, reason: '$action is on screen');
      }
      await tester.tap(
        find.descendant(of: seerrNode(AutomationIds.requestsActions), matching: find.text(t.common.close)),
      );
      await tester.pumpAndSettle();
      expect(seerrNode(AutomationIds.requestsActions), findsNothing);
      expect(find.byType(SeerrRequestRow), findsOneWidget, reason: 'back on the same request');
    });
  });

  group('Mijn aanvraag lands on the request it was opened for (3B)', () {
    Map<String, dynamic> pageOfOthers() => seerrPage([for (var i = 1; i <= 20; i++) seerrRequestJson(i)], pages: 3);

    SeerrRequestRow focusedRow() {
      final focused = FocusManager.instance.primaryFocus!.context!;
      final row = focused.findAncestorWidgetOfExactType<SeerrRequestRow>();
      expect(row, isNotNull, reason: 'the focus is on a request row');
      return row!;
    }

    testWidgets('a request further down the loaded page is brought to the top and focused', (tester) async {
      fake.on('GET /request', pageOfOthers());
      await open(tester, mineOnly: true, focusRequestId: 14, size: const Size(1280, 900));
      await tester.pumpAndSettle();

      expect(fake.sent('GET', '/request/14'), isEmpty, reason: 'it is already on the page');
      final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();
      expect(rows.first.request.id, 14, reason: 'not the generic first row of the list');
      expect(rows.where((r) => r.request.id == 14), hasLength(1));
      expect(focusedRow().request.id, 14);
    });

    testWidgets('the chosen row is still the focused row after the list reloads under it (UF1)', (tester) async {
      fake
        ..on('GET /request', pageOfOthers())
        ..on('DELETE /request/14', null, 204);
      await open(tester, mineOnly: true, focusRequestId: 14, size: const Size(1280, 900));
      await tester.pumpAndSettle();
      expect(focusedRow().request.id, 14);
      final node = FocusManager.instance.primaryFocus;

      // An action on it ends in an in-place reload, which rebuilds every row.
      await tester.tap(find.text(t.seerr.cancelRequest).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, t.seerr.cancelRequest));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(fake.sent('DELETE', '/request/14'), hasLength(1));
      expect(fake.sent('GET', '/request').length, greaterThan(1), reason: 'the list was read again');
      expect(focusedRow().request.id, 14, reason: 'the reload must not take the focus off the chosen request');
      expect(identical(FocusManager.instance.primaryFocus, node), isTrue, reason: 'the same row, not a new one');
      final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();
      expect(rows.first.request.id, 14, reason: 'and it is still where the page opened on it');
    });

    testWidgets('a request beyond the loaded page is read by id and shown first, when it is the viewer\'s own', (
      tester,
    ) async {
      fake
        ..on('GET /request', pageOfOthers())
        ..on('GET /request/55', seerrRequestJson(55));
      await open(tester, mineOnly: true, focusRequestId: 55, size: const Size(1280, 900));
      await tester.pumpAndSettle();

      final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();
      expect(rows.first.request.id, 55);
      expect(fake.sent('GET', '/request/55'), hasLength(1), reason: 'one bounded read, no walk through the history');
      expect(fake.sent('GET', '/request'), hasLength(1));
      expect(focusedRow().request.id, 55);
    });

    testWidgets("a request that turns out to be someone else's is not put in the own list, and that is said", (
      tester,
    ) async {
      fake
        ..on('GET /request', pageOfOthers())
        ..on('GET /request/55', seerrRequestJson(55, requestedBy: 9));
      await open(tester, mineOnly: true, focusRequestId: 55, size: const Size(1280, 900));
      await tester.pumpAndSettle();

      final ids = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).map((r) => r.request.id);
      expect(ids.contains(55), isFalse);
      expect(find.text(t.seerr.requestNotInOwnList), findsOneWidget);
    });

    testWidgets('a request that is gone is said, and the list stays what the server sent', (tester) async {
      fake.on('GET /request', pageOfOthers());
      await open(tester, mineOnly: true, focusRequestId: 55, size: const Size(1280, 900));
      await tester.pumpAndSettle();

      expect(find.text(t.seerr.requestNotInOwnList), findsOneWidget);
      expect(tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).first.request.id, 1);
    });

    testWidgets('after a profile switch the id is not looked up on the new account', (tester) async {
      final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
      final slow = fake.hold('GET /request');
      fake.on('GET /request/55', seerrRequestJson(55, requestedBy: 9));
      await open(tester, mineOnly: true, focusRequestId: 55, store: store, size: const Size(1280, 900));

      fake.on('GET /request', seerrPage([seerrRequestJson(8, requestedBy: 9)]));
      await provider.onActiveProfileChanged('user-2');
      await seerrSettle(tester);
      slow.complete(FakeSeerr.json(pageOfOthers()));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(fake.sent('GET', '/request/55'), isEmpty, reason: "request 55 on B's server is B's, not the one A opened");
      expect(tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).map((r) => r.request.id), [8]);
    });
  });

  group('a lock belongs to the account and the request, not to the view (F-B1)', () {
    Finder scopeChip(String label) =>
        find.descendant(of: seerrNode(AutomationIds.requestsListState, 'scope'), matching: find.text(label));

    testWidgets('an approve still on the wire is not offered again after switching All to My', (tester) async {
      // The manager's own pending request: it is in both scopes.
      fake.on('GET /request', seerrPage([seerrRequestJson(1)]));
      await open(tester, permissions: seerrPermManage);
      final answer = fake.hold('POST /request/1/approve');
      await tester.tap(find.text(t.seerr.approve));
      await tester.pump();
      expect(fake.sent('POST', '/request/1/approve'), hasLength(1));

      await tester.tap(scopeChip(t.seerr.myRequests));
      await seerrSettle(tester);
      final row = tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow));
      expect(row.request.id, 1, reason: 'the same request, seen through the other scope');
      expect(row.busy, isTrue, reason: 'its approve has not been answered yet');

      await tester.tap(find.text(t.seerr.approve), warnIfMissed: false);
      row.onApprove?.call();
      await tester.pump();
      expect(
        fake.sent('POST', '/request/1/approve'),
        hasLength(1),
        reason: 'no second approve while the first is open',
      );

      answer.complete(FakeSeerr.json({'id': 1}));
      await seerrSettle(tester);
      expect(tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow)).busy, isFalse);
    });

    testWidgets('a request whose outcome is open stays locked through a scope switch', (tester) async {
      fake.on('GET /request', seerrPage([seerrRequestJson(1)]));
      await open(tester, permissions: seerrPermManage);
      fake.fail('POST /request/1/approve');
      fake.fail('GET /request');
      await tester.tap(find.text(t.seerr.approve));
      await seerrSettle(tester);
      expect(tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow)).statusUnknown, isTrue);

      // The other scope loads, but its row says nothing about the status.
      fake.on('GET /request', seerrPage([seerrRequestJson(1)..remove('status')]));
      await tester.tap(scopeChip(t.seerr.myRequests));
      await seerrSettle(tester);

      final row = tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow));
      expect(row.statusUnknown, isTrue);
      expect(row.onApprove, isNull, reason: 'a row without a status is not shown to be pending');
    });
  });

  group('a partial row is not proof (F-B2)', () {
    testWidgets('a list row without a status does not release a request whose outcome is open', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.fail('POST /request/2/approve');
      fake.fail('GET /request');
      await tester.tap(find.text(t.seerr.approve).last);
      await seerrSettle(tester);

      fake.on('GET /request', seerrPage([seerrRequestJson(1), seerrRequestJson(2, requestedBy: 9)..remove('status')]));
      await tester.tap(find.byTooltip(t.seerr.checkStatus));
      await seerrSettle(tester);

      var row = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last;
      expect(row.statusUnknown, isTrue, reason: 'the read did not say where the request stands');
      expect(row.busy, isTrue);
      expect(find.text(t.seerr.pending), findsOneWidget, reason: 'only request 1 says it is pending');

      fake.on('GET /request', seerrPage([seerrRequestJson(1), seerrRequestJson(2, status: 2, requestedBy: 9)]));
      await tester.tap(find.byTooltip(t.seerr.checkStatus));
      await seerrSettle(tester);
      row = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last;
      expect(row.statusUnknown, isFalse);
      expect(row.busy, isFalse);
    });

    testWidgets('a row without a status offers no action, whatever the parser filled in', (tester) async {
      fake.on('GET /request', seerrPage([seerrRequestJson(2, requestedBy: 9)..remove('status')]));
      await open(tester, permissions: seerrPermManage);

      final row = tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow));
      expect(row.onApprove, isNull);
      expect(row.onDecline, isNull);
      expect(find.text(t.seerr.statusUnknownBadge), findsOneWidget);
    });
  });

  group('R4 scope and page proof', () {
    Finder scopeChip(String label) =>
        find.descendant(of: seerrNode(AutomationIds.requestsListState, 'scope'), matching: find.text(label));
    testWidgets('R4 initial paginated absence leaves the unknown action locked', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.fail('POST /request/2/approve');
      fake.on('GET /request', seerrPage([seerrRequestJson(1)], pages: 2));
      await tester.tap(find.text(t.seerr.approve).last);
      await seerrSettle(tester);
      fake.on('GET /request', seerrPage(const [], pages: 2));
      await tester.tap(scopeChip(t.seerr.myRequests));
      await seerrSettle(tester);
      fake.on('GET /request', seerrPage([seerrRequestJson(2, requestedBy: 9)..remove('status')]));
      await tester.tap(scopeChip(t.seerr.allRequests));
      await seerrSettle(tester);
      final row = tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow));
      expect(row.busy, isTrue);
      expect(row.statusUnknown, isTrue);
    });
    for (final own in [true, false]) {
      testWidgets('R4 complete own scope settles absence only for ${own ? 'own' : 'other'} request', (tester) async {
        final id = own ? 1 : 2;
        await open(tester, permissions: seerrPermManage);
        fake.fail('POST /request/$id/approve');
        fake.fail('GET /request');
        await tester.tap(own ? find.text(t.seerr.approve).first : find.text(t.seerr.approve).last);
        await seerrSettle(tester);
        fake.on('GET /request', seerrPage(const []));
        await tester.tap(scopeChip(t.seerr.myRequests));
        await seerrSettle(tester);
        fake.on('GET /request', seerrPage([seerrRequestJson(id, requestedBy: own ? 7 : 9)..remove('status')]));
        await tester.tap(scopeChip(t.seerr.allRequests));
        await seerrSettle(tester);
        final row = tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow));
        expect(row.busy, !own, reason: 'the own-only projection proves nothing about another requester');
      });
    }
  });

  group('R4 proof boundary', () {
    testWidgets('R4 immediate partial recovery keeps the unknown action locked', (tester) async {
      await open(tester, permissions: seerrPermManage);
      fake.fail('POST /request/2/approve');
      fake.on('GET /request', seerrPage([seerrRequestJson(1), seerrRequestJson(2, requestedBy: 9)..remove('status')]));
      await tester.tap(find.text(t.seerr.approve).last);
      await seerrSettle(tester);
      final row = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last;
      expect(row.busy, isTrue);
      expect(row.statusUnknown, isTrue);
      expect(fake.sent('POST', '/request/2/approve'), hasLength(1));
    });

    for (final (name, answer) in <(String, Object)>[
      (
        'dropped row',
        {
          'results': ['unreadable'],
          'pageInfo': {'pages': 1},
        },
      ),
      ('missing pagination', {'results': <Object>[]}),
      (
        'malformed pagination',
        {
          'results': <Object>[],
          'pageInfo': {'pages': 'unreadable'},
        },
      ),
      ('unreadable envelope', <Object>[]),
    ]) {
      testWidgets('R4 $name cannot prove unresolved request absence', (tester) async {
        await open(tester, permissions: seerrPermManage);
        fake.fail('POST /request/2/approve');
        fake.fail('GET /request');
        await tester.tap(find.text(t.seerr.approve).last);
        await seerrSettle(tester);
        fake.on('GET /request', answer);
        await tester.tap(find.byTooltip(t.seerr.checkStatus));
        await seerrSettle(tester);
        expect(find.byType(SeerrRequestRow), findsNWidgets(2), reason: 'an unreadable read retains prior rows');
        final row = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).last;
        expect(row.request.id, 2);
        expect(row.busy, isTrue);
        expect(row.statusUnknown, isTrue);
        expect(fake.sent('POST', '/request/2/approve'), hasLength(1));
      });
    }
  });

  group('on TV', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    Future<void> select(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await seerrSettle(tester);
    }

    Future<void> openTv(WidgetTester tester, {int permissions = seerrPermManage}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      provider = await seerrProvider(fake, permissions: permissions);
      addTearDown(provider.dispose);
      await pumpSeerr(tester, provider, const SeerrRequestsScreen(), host: false);
      await seerrSettle(tester);
      await tester.pumpAndSettle();
    }

    TvSeerrRequestCard card(WidgetTester tester, int index) =>
        tester.widgetList<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).elementAt(index);

    testWidgets('the page opens with the first card focused', (tester) async {
      await openTv(tester);
      expect(card(tester, 0).focusNode!.hasFocus, isTrue);
    });

    testWidgets('the card menu approves, and the focus is back on that card afterwards', (tester) async {
      fake.on('POST /request/2/approve', {'id': 2});
      await openTv(tester);
      card(tester, 1).focusNode!.requestFocus();
      await tester.pumpAndSettle();

      card(tester, 1).onContextMenu!();
      await tester.pumpAndSettle();
      expect(seerrNode(AutomationIds.requestsActions), findsOneWidget);
      expect(
        seerrHasFocus(tester, seerrNode(AutomationIds.requestsActionsItem, 'approve')),
        isTrue,
        reason: 'the menu opens on the decision a manager came for',
      );

      await select(tester);
      await tester.pumpAndSettle();

      expect(fake.sent('POST', '/request/2/approve'), hasLength(1));
      expect(seerrNode(AutomationIds.requestsActions), findsNothing);
      expect(card(tester, 1).focusNode!.hasFocus, isTrue);
    });

    testWidgets('a requester\'s menu on someone else\'s request explains why there is nothing to do', (tester) async {
      await openTv(tester, permissions: seerrPermRequest);
      fake.on('GET /request', seerrPage([seerrRequestJson(2, requestedBy: 7, status: 2)]));
      await provider.onActiveProfileChanged('user-1');
      await tester.pumpAndSettle();

      card(tester, 0).onContextMenu!();
      await tester.pumpAndSettle();

      expect(find.text(t.seerr.actionsNotPending), findsOneWidget);
      expect(seerrNode(AutomationIds.requestsActionsItem, 'approve'), findsNothing);
      expect(seerrNode(AutomationIds.requestsActionsItem, 'cancel'), findsNothing);
    });

    testWidgets('while an action runs the card says so and offers no second menu, and keeps the focus', (tester) async {
      final answer = fake.hold('POST /request/1/decline');
      await openTv(tester);
      card(tester, 0).onContextMenu!();
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.seerr.decline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(card(tester, 0).busy, isTrue);
      expect(card(tester, 0).onContextMenu, isNull);
      expect(find.text(t.seerr.actionBusy), findsOneWidget);
      expect(card(tester, 0).focusNode!.hasFocus, isTrue);

      answer.complete(FakeSeerr.json({'id': 1}));
      await tester.pumpAndSettle();
      expect(card(tester, 0).busy, isFalse);
      expect(card(tester, 0).focusNode!.hasFocus, isTrue);
    });

    testWidgets('the focused card keeps the focus through a reload', (tester) async {
      await openTv(tester);
      card(tester, 1).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      final slow = fake.hold('GET /request');

      // The status row of the rail triggers nothing here; a reload is what an
      // action ends with, so drive that path.
      fake.on('POST /request/2/approve', {'id': 2});
      card(tester, 1).onContextMenu!();
      await tester.pumpAndSettle();
      await select(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(card(tester, 1).focusNode!.hasFocus, isTrue, reason: 'loading must not take the grid away');
      slow.complete(FakeSeerr.json(seerrPage([seerrRequestJson(1), seerrRequestJson(2, status: 2, requestedBy: 9)])));
      await tester.pumpAndSettle();
      expect(card(tester, 1).focusNode!.hasFocus, isTrue);
    });

    Future<void> pickDeclined(WidgetTester tester) async {
      card(tester, 0).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await select(tester);
      await tester.pumpAndSettle();
      // The subview opens on Alle; Afgewezen is the fifth answer.
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      await select(tester);
      await tester.pumpAndSettle();
    }

    for (final (name, rows) in [
      ('an empty page', <Map<String, dynamic>>[]),
      ('a page of only declined requests', [seerrRequestJson(4, status: 3), seerrRequestJson(5, status: 3)]),
      ('a mixed page', [seerrRequestJson(1), seerrRequestJson(4, status: 3)]),
    ]) {
      testWidgets('Afgewezen is never shown as a list, whatever $name would look like (B06)', (tester) async {
        await openTv(tester);
        // Seerr has no `declined` case and answers with every status. This is
        // what it would send if it were asked; no shape of it proves a filter.
        fake.on('GET /request', seerrPage(rows));
        final asked = fake.sent('GET', '/request').length;
        await pickDeclined(tester);

        expect(_tvState('unsupported'), findsOneWidget);
        expect(find.byType(TvSeerrRequestCard), findsNothing);
        expect(
          _tvState('filtered'),
          findsNothing,
          reason: 'an empty result would claim there are no declined requests',
        );
        expect(find.text(t.seerr.filterUnsupportedBySource), findsOneWidget);
        expect(
          fake.sent('GET', '/request').length,
          asked,
          reason: 'nothing is asked for under a filter that is not one',
        );
        expect(
          FocusManager.instance.primaryFocus?.context,
          isNotNull,
          reason: 'the page is never left without a focus',
        );
      });
    }

    testWidgets('a manager finds Bereik in the rail, picks Mijn aanvragen, and stays on that row', (tester) async {
      await openTv(tester);
      card(tester, 0).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(seerrNode(AutomationIds.tvCatalogRailRow, 'requests.scope'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrRailScope');
      await select(tester);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await select(tester);
      await tester.pumpAndSettle();

      expect(fake.sent('GET', '/request').last.query['requestedBy'], '7');
      expect(find.text(t.seerr.myRequests), findsWidgets);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TvSeerrRailScope',
        reason: 'the choice returns to its row',
      );
    });

    testWidgets('a requester\'s rail has no Bereik row', (tester) async {
      await openTv(tester, permissions: seerrPermRequest);
      card(tester, 0).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(seerrNode(AutomationIds.tvCatalogRailRow, 'requests.status'), findsOneWidget);
      expect(seerrNode(AutomationIds.tvCatalogRailRow, 'requests.scope'), findsNothing);
    });

    testWidgets('opened for one request, the grid lands on that card rather than the first', (tester) async {
      fake.on('GET /request', seerrPage([for (var i = 1; i <= 6; i++) seerrRequestJson(i)]));
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      provider = await seerrProvider(fake);
      addTearDown(provider.dispose);
      await pumpSeerr(tester, provider, const SeerrRequestsScreen(mineOnly: true, focusRequestId: 5), host: false);
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(card(tester, 0).request.id, 5, reason: 'the request it was opened for comes first');
      expect(card(tester, 0).focusNode!.hasFocus, isTrue);
    });

    testWidgets('an empty account is sent to Ontdekken, with the action focused', (tester) async {
      fake.on('GET /request', seerrPage(const []));
      await openTv(tester);

      expect(_tvState('empty'), findsOneWidget);
      expect(find.text(t.seerr.discoverAction), findsOneWidget);
      expect(find.text(t.common.retry), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrStateAction');
    });
  });
}

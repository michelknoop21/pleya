// Regiekamer (DEC-XXX, mockups C1 and C2): count tiles, sections in decision
// order, ticking several requests for one Goedkeuren, swipes, and the facts in
// the menu behind a row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/widgets/seerr_cockpit_tiles.dart';
import 'package:pleya/widgets/seerr_request_row.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

Map<String, dynamic> _at(Map<String, dynamic> json, String createdAt) => json..['createdAt'] = createdAt;

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    fake = FakeSeerr()..on('GET /request/count', {'total': 9, 'pending': 3, 'approved': 4, 'available': 2});
  });

  Future<void> open(WidgetTester tester, {int permissions = seerrPermManage, Size size = const Size(430, 1600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake, permissions: permissions);
    addTearDown(provider.dispose);
    await pumpSeerr(tester, provider, const SeerrRequestsScreen(), host: false);
    await seerrSettle(tester);
  }

  List<int> rowIds(WidgetTester tester) => [
    for (final r in tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow))) r.request.id,
  ];

  SeerrCockpitTile tile(WidgetTester tester, String instance) =>
      tester.widget<SeerrCockpitTile>(find.byWidgetPredicate((w) => w is SeerrCockpitTile && w.instance == instance));

  group('tiles', () {
    testWidgets('a manager sees what waits on them and what is on its way, from the count route', (tester) async {
      fake.on('GET /request', seerrPage([seerrRequestJson(1)]));
      await open(tester);

      expect(tile(tester, 'pending').count, 3);
      expect(tile(tester, 'approved').count, 4);
      // Off an iPhone there is no Meldingen page to open, so no Meldingen tile.
      expect(find.byWidgetPredicate((w) => w is SeerrCockpitTile && w.instance == 'issues'), findsNothing);
      expect(tile(tester, 'all').count, 9);
    });

    testWidgets('a count that did not load is a dash, never a zero', (tester) async {
      fake
        ..on('GET /request', seerrPage([seerrRequestJson(1)]))
        ..on('GET /request/count', {'error': 'down'}, 500);
      await open(tester);

      expect(tile(tester, 'pending').count, isNull);
      expect(
        find.descendant(of: seerrNode(AutomationIds.requestsListTile, 'pending'), matching: find.text('–')),
        findsOneWidget,
      );
    });

    testWidgets('a tile is a shortcut to its filter, and tapping it again goes back to everything', (tester) async {
      fake.on('GET /request', seerrPage([seerrRequestJson(1)]));
      await open(tester);

      await tester.tap(seerrNode(AutomationIds.requestsListTile, 'pending'));
      await seerrSettle(tester);
      expect(fake.sent('GET', '/request').last.query['filter'], 'pending');
      expect(tile(tester, 'pending').selected, isTrue);

      await tester.tap(seerrNode(AutomationIds.requestsListTile, 'pending'));
      await seerrSettle(tester);
      expect(fake.sent('GET', '/request').last.query['filter'], 'all');
    });

    testWidgets("a requester's own list has no tiles: the counts are everyone's", (tester) async {
      fake.on('GET /request', seerrPage([seerrRequestJson(1)]));
      await open(tester, permissions: seerrPermRequest);

      expect(find.byType(SeerrCockpitTile), findsNothing);
    });
  });

  group('sections', () {
    testWidgets('decisions come first, the one that waited longest on top, then what is on its way', (tester) async {
      fake.on(
        'GET /request',
        seerrPage([
          seerrRequestJson(1, status: 2), // approved, media still pending: on its way
          _at(seerrRequestJson(2, requestedBy: 9), '2026-10-08T00:00:00.000Z'),
          _at(seerrRequestJson(3, requestedBy: 9), '2026-10-02T00:00:00.000Z'),
          seerrRequestJson(4, status: 5, mediaStatus: 5), // completed: handled
        ]),
      );
      await open(tester);

      expect(rowIds(tester), [3, 2, 1, 4]);
      expect(find.text(t.seerr.cockpit.waitingOnYou), findsOneWidget);
      expect(find.text(t.seerr.cockpit.inProgress), findsOneWidget);
      expect(find.text(t.seerr.cockpit.handled), findsOneWidget);
    });

    testWidgets('a chosen filter is one list in server order, without headings', (tester) async {
      fake.on(
        'GET /request',
        seerrPage([
          _at(seerrRequestJson(2, requestedBy: 9), '2026-10-08T00:00:00.000Z'),
          _at(seerrRequestJson(3, requestedBy: 9), '2026-10-02T00:00:00.000Z'),
        ]),
      );
      await open(tester);
      await tester.tap(seerrNode(AutomationIds.requestsListTile, 'pending'));
      await seerrSettle(tester);

      expect(rowIds(tester), [2, 3]);
      expect(find.text(t.seerr.cockpit.waitingOnYou), findsNothing);
    });
  });

  group('ticking several for one Goedkeuren', () {
    testWidgets('only the ticked requests are approved, once each, with one reload', (tester) async {
      fake
        ..on(
          'GET /request',
          seerrPage([
            seerrRequestJson(1, requestedBy: 9),
            seerrRequestJson(2, requestedBy: 9),
            seerrRequestJson(3, requestedBy: 9),
          ]),
        )
        ..on('POST /request/1/approve', {'id': 1})
        ..on('POST /request/3/approve', {'id': 3});
      await open(tester);
      expect(seerrNode(AutomationIds.requestsListBulkApprove), findsNothing, reason: 'nothing ticked yet');
      final listReads = fake.sent('GET', '/request').length;

      final rows = tester.widgetList<SeerrRequestRow>(find.byType(SeerrRequestRow)).toList();
      rows.firstWhere((r) => r.request.id == 1).onSelectedChanged!(true);
      rows.firstWhere((r) => r.request.id == 3).onSelectedChanged!(true);
      await tester.pump();
      expect(find.text(t.seerr.cockpit.approveSelected(n: 2)), findsOneWidget);

      await tester.tap(seerrNode(AutomationIds.requestsListBulkApprove));
      await seerrSettle(tester);

      expect(fake.sent('POST', '/request/1/approve'), hasLength(1));
      expect(fake.sent('POST', '/request/3/approve'), hasLength(1));
      expect(fake.sent('POST', '/request/2/approve'), isEmpty, reason: 'not ticked');
      expect(fake.sent('GET', '/request').length, listReads + 1, reason: 'one reload for the batch, not one per row');
      expect(find.text(t.seerr.cockpit.approvedMany(n: 2)), findsOneWidget);
    });

    testWidgets('a row the viewer may not approve has no box to tick', (tester) async {
      fake.on('GET /request', seerrPage([seerrRequestJson(1, requestedBy: 9)]));
      await open(tester, permissions: seerrPermRequest);

      expect(tester.widget<SeerrRequestRow>(find.byType(SeerrRequestRow)).selected, isNull);
    });
  });

  group('swipes', () {
    testWidgets('right approves at once; left asks first and only then declines', (tester) async {
      fake
        ..on('GET /request', seerrPage([seerrRequestJson(1, requestedBy: 9), seerrRequestJson(2, requestedBy: 9)]))
        ..on('POST /request/1/approve', {'id': 1})
        ..on('POST /request/2/decline', {'id': 2});
      await open(tester);

      Finder row(int id) => find.byWidgetPredicate((w) => w is SeerrRequestRow && w.request.id == id);
      await tester.drag(row(1), const Offset(300, 0));
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request/1/approve'), hasLength(1));

      await tester.drag(row(2), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text(t.seerr.cockpit.declineConfirm), findsOneWidget);
      expect(fake.sent('POST', '/request/2/decline'), isEmpty, reason: 'nothing is sent before the answer');

      await tester.tap(find.widgetWithText(FilledButton, t.seerr.decline));
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request/2/decline'), hasLength(1));
    });
  });

  group('the menu behind a row (C2)', () {
    testWidgets('shows the facts a decision needs, and only those the request carries', (tester) async {
      fake.on(
        'GET /request',
        seerrPage([
          seerrRequestJson(1, type: 'tv', seasons: [3, 4, 5], is4k: true, requestedBy: 9, mediaStatus: 4),
        ]),
      );
      await open(tester);

      await tester.tap(find.byType(SeerrRequestRow));
      await tester.pumpAndSettle();
      final menu = seerrNode(AutomationIds.requestsActions);
      expect(find.descendant(of: menu, matching: find.text(t.seerr.cockpit.factSeasons)), findsOneWidget);
      expect(find.descendant(of: menu, matching: find.text('3-5')), findsOneWidget);
      expect(find.descendant(of: menu, matching: find.text(t.seerr.fourKBadge)), findsOneWidget);
      expect(find.descendant(of: menu, matching: find.text(t.seerr.cockpit.inPleyaPartly)), findsOneWidget);
      expect(find.descendant(of: menu, matching: find.text(t.seerr.cockpit.factRequested)), findsOneWidget);
    });
  });

  group('wait time', () {
    test('days, hours, minutes; nothing for a missing or future date', () {
      final now = DateTime.utc(2026, 11, 9, 12);
      expect(seerrRequestAge('2026-11-06T12:00:00.000Z', now: now), t.seerr.cockpit.ageDays(n: 3));
      expect(seerrRequestAge('2026-11-09T07:00:00.000Z', now: now), t.seerr.cockpit.ageHours(n: 5));
      expect(seerrRequestAge('2026-11-09T11:48:00.000Z', now: now), t.seerr.cockpit.ageMinutes(n: 12));
      expect(seerrRequestAge(null, now: now), isNull);
      expect(seerrRequestAge('not a date', now: now), isNull);
      expect(seerrRequestAge('2026-11-10T00:00:00.000Z', now: now), isNull);
    });
  });
}

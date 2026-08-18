import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/seerr_request_row.dart';
import 'package:pleya/widgets/seerr_status_badge.dart';

import '../test_helpers/prefs.dart';

/// Renders one request row the way the requests screen does and checks what the
/// user can actually read off it. The screenshots that started this showed rows
/// whose only heading was the media type, so "does the real title appear" is a
/// behavioural test, not a cosmetic one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  SeerrRequest request({
    String? title = 'The Gray Man',
    String? year = '2022',
    String type = 'movie',
    String? posterPath = '/poster.jpg',
    SeerrRequestStatus status = SeerrRequestStatus.approved,
    SeerrMediaStatus mediaStatus = SeerrMediaStatus.processing,
    List<int> seasons = const [],
    bool is4k = false,
    String? requestedBy = 'rapmadri',
  }) {
    return SeerrRequest(
      id: 1,
      status: status,
      mediaType: type,
      tmdbId: 550,
      mediaTitle: title,
      mediaYear: year,
      posterPath: posterPath,
      mediaStatus: mediaStatus,
      seasons: seasons,
      is4k: is4k,
      requestedById: 7,
      requestedByName: requestedBy,
    );
  }

  Future<void> pumpRow(WidgetTester tester, SeerrRequest req, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: ListView(children: [SeerrRequestRow(request: req)]),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a movie request leads with its real title, not the media type', (tester) async {
    await pumpRow(tester, request());

    expect(find.text('The Gray Man'), findsOneWidget);
    // The media type belongs on the secondary line, together with the year.
    expect(find.text('${t.discover.movie} · 2022'), findsOneWidget);
    expect(find.text(t.seerr.requestedBy(name: 'rapmadri')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a show request reads as a show', (tester) async {
    await pumpRow(tester, request(title: 'Andor', year: '2022', type: 'tv'));

    expect(find.text('Andor'), findsOneWidget);
    expect(find.text('${t.discover.tvShow} · 2022'), findsOneWidget);
  });

  testWidgets('a row without a resolved title shows no stand-in heading', (tester) async {
    await pumpRow(tester, request(title: null, year: null));

    // Neither the old fallback nor an empty heading pretending to be one.
    expect(find.text(t.discover.movie), findsOneWidget, reason: 'only on the secondary line');
    expect(find.text('${t.discover.movie} · 2022'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('status chips', () {
    testWidgets('approved plus partially available keeps both, they say different things', (tester) async {
      await pumpRow(
        tester,
        request(status: SeerrRequestStatus.approved, mediaStatus: SeerrMediaStatus.partiallyAvailable),
      );

      expect(find.text(t.seerr.approved), findsOneWidget);
      expect(find.text(t.seerr.partiallyAvailable), findsOneWidget);
    });

    testWidgets('completed plus available drops the duplicate', (tester) async {
      await pumpRow(tester, request(status: SeerrRequestStatus.completed, mediaStatus: SeerrMediaStatus.available));

      expect(find.text(t.seerr.completed), findsOneWidget);
      expect(find.byType(SeerrStatusBadge), findsNothing, reason: 'available says nothing completed has not');
    });

    testWidgets('available under a still-approved request is worth saying', (tester) async {
      await pumpRow(tester, request(status: SeerrRequestStatus.approved, mediaStatus: SeerrMediaStatus.available));

      expect(find.text(t.seerr.approved), findsOneWidget);
      expect(find.text(t.seerr.available), findsOneWidget);
    });

    testWidgets('4K is its own pill, not glued to the seasons', (tester) async {
      await pumpRow(tester, request(type: 'tv', is4k: true, seasons: const [1]));

      expect(find.text(t.seerr.fourKBadge), findsOneWidget);
      expect(find.text(t.seerr.season(number: 1)), findsOneWidget);
    });
  });

  group('seasons', () {
    testWidgets('one season is named in the singular', (tester) async {
      await pumpRow(tester, request(type: 'tv', seasons: const [3]));
      expect(find.text(t.seerr.season(number: 3)), findsOneWidget);
    });

    testWidgets('a consecutive run collapses instead of taking over the card', (tester) async {
      await pumpRow(tester, request(type: 'tv', seasons: const [18, 19, 20, 21, 22]));

      expect(find.text(t.seerr.seasonsRange(range: '18-22')), findsOneWidget);
      expect(find.text(t.seerr.season(number: 19)), findsNothing);
    });

    testWidgets('a gap is kept, because the range would otherwise be a lie', (tester) async {
      await pumpRow(tester, request(type: 'tv', seasons: const [1, 2, 3, 7]));
      expect(find.text(t.seerr.seasonsRange(range: '1-3, 7')), findsOneWidget);
    });

    testWidgets('too many separate runs fall back to a count', (tester) async {
      await pumpRow(tester, request(type: 'tv', seasons: const [1, 3, 5, 7]));
      expect(find.text(t.seerr.seasonsCount(count: 4)), findsOneWidget);
    });
  });

  group('nothing overflows', () {
    const narrow = Size(320, 700);

    testWidgets('a long title on a narrow phone', (tester) async {
      await pumpRow(
        tester,
        request(title: 'The Lord of the Rings: The Fellowship of the Ring Extended Edition'),
        size: narrow,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long user name on a narrow phone', (tester) async {
      await pumpRow(tester, request(requestedBy: 'een_hele_lange_gebruikersnaam_van_iemand'), size: narrow);
      expect(tester.takeException(), isNull);
    });

    testWidgets('many seasons plus 4K on a narrow phone', (tester) async {
      await pumpRow(
        tester,
        request(type: 'tv', is4k: true, seasons: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        size: narrow,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row never renders wider than the viewport', (tester) async {
      await pumpRow(tester, request(title: 'Een tamelijk lange filmtitel om mee te meten'), size: narrow);

      final row = tester.getRect(find.byType(SeerrRequestRow));
      expect(row.width, lessThanOrEqualTo(narrow.width));
      expect(row.left, greaterThanOrEqualTo(0));
    });
  });
}

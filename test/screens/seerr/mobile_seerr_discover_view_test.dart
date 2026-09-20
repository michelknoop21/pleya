/// The iPhone Aanvragen page (northstar 19). Runs against the presentation widgets:
/// `SeerrDiscoverScreen` itself needs a live `SeerrProvider` session, which has no test
/// seam (see `seerr_discover_tv_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/screens/seerr/mobile_seerr_discover_view.dart';
import 'package:pleya/screens/seerr/seerr_discover_filter_bar.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/theme/mono_theme.dart';

SeerrRequest _request(
  int id, {
  SeerrRequestStatus status = SeerrRequestStatus.pending,
  SeerrMediaStatus media = SeerrMediaStatus.unknown,
  bool is4k = false,
  int? tmdbId,
  List<int> seasons = const [],
}) => SeerrRequest(
  id: id,
  status: status,
  mediaType: 'movie',
  tmdbId: tmdbId ?? 100 + id,
  mediaTitle: 'Request $id',
  mediaStatus: media,
  is4k: is4k,
  seasons: seasons,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('mobileSeerrRequestStatus', () {
    test('available media reads as available', () {
      final status = mobileSeerrRequestStatus(
        _request(1, status: SeerrRequestStatus.approved, media: SeerrMediaStatus.available),
      );
      expect(status.label, t.seerr.available);
      expect(status.tone, MobileSeerrRequestTone.available);
    });

    test('processing media reads as approved and in progress', () {
      final status = mobileSeerrRequestStatus(
        _request(1, status: SeerrRequestStatus.approved, media: SeerrMediaStatus.processing),
      );
      expect(status.label, '${t.seerr.approved} · ${t.seerr.processing}');
      expect(status.tone, MobileSeerrRequestTone.inProgress);
    });

    test('a pending request waits', () {
      final status = mobileSeerrRequestStatus(_request(1));
      expect(status.label, t.seerr.pending);
      expect(status.tone, MobileSeerrRequestTone.waiting);
    });

    test('a declined request says so even when the title is available', () {
      final status = mobileSeerrRequestStatus(
        _request(1, status: SeerrRequestStatus.declined, media: SeerrMediaStatus.available),
      );
      expect(status.label, t.seerr.declined);
      expect(status.tone, MobileSeerrRequestTone.problem);
    });

    test('4K is named after the status', () {
      final status = mobileSeerrRequestStatus(_request(1, media: SeerrMediaStatus.available, is4k: true));
      expect(status.label, '${t.seerr.available} · ${t.seerr.fourKBadge}');
    });
  });

  group('MobileSeerrMyRequestsSection', () {
    String header() => t.seerr.myRequests.toUpperCase();

    testWidgets('lists the requests under a counted header that opens the full list', (tester) async {
      var openedAll = 0;
      SeerrRequest? opened;
      await _pump(
        tester,
        MobileSeerrMyRequestsSection(
          load: () async => (items: [_request(1), _request(2), _request(3)], totalPages: 1),
          onOpenAll: () => openedAll++,
          onOpenRequest: (request) => opened = request,
        ),
      );

      for (final id in [1, 2, 3]) {
        expect(find.text('Request $id'), findsOneWidget);
      }
      await tester.tap(find.text('Request 2'));
      expect(opened?.id, 2);
      await tester.tap(find.text('${header()} · 3'));
      expect(openedAll, 1);
    });

    testWidgets('leaves the count off when there are more requests than shown', (tester) async {
      await _pump(
        tester,
        MobileSeerrMyRequestsSection(
          load: () async => (items: [_request(1), _request(2), _request(3)], totalPages: 2),
          onOpenAll: () {},
          onOpenRequest: (_) {},
        ),
      );
      expect(find.text(header()), findsOneWidget);
    });

    testWidgets('names a single requested season in the title', (tester) async {
      await _pump(
        tester,
        MobileSeerrMyRequestsSection(
          load: () async => (
            items: [
              _request(1, seasons: const [1]),
            ],
            totalPages: 1,
          ),
          onOpenAll: () {},
          onOpenRequest: (_) {},
        ),
      );
      expect(find.text('Request 1 · ${t.seerr.season(number: 1).toLowerCase()}'), findsOneWidget);
    });

    testWidgets('draws nothing without requests', (tester) async {
      await _pump(
        tester,
        MobileSeerrMyRequestsSection(
          load: () async => (items: const <SeerrRequest>[], totalPages: 1),
          onOpenAll: () {},
          onOpenRequest: (_) {},
        ),
      );
      expect(find.textContaining(header()), findsNothing);
    });

    testWidgets('draws nothing when loading fails', (tester) async {
      await _pump(
        tester,
        MobileSeerrMyRequestsSection(
          load: () async => throw Exception('offline'),
          onOpenAll: () {},
          onOpenRequest: (_) {},
        ),
      );
      expect(find.textContaining(header()), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('MobileSeerrTypeChips', () {
    testWidgets('reports the picked type', (tester) async {
      SeerrDiscoverType? picked;
      await _pump(
        tester,
        MobileSeerrTypeChips(
          type: SeerrDiscoverType.all,
          genres: const [],
          genreId: null,
          onTypeSelected: (type) => picked = type,
          onPickGenre: () {},
        ),
      );
      await tester.tap(find.text(t.seerr.filterMovies));
      expect(picked, SeerrDiscoverType.movies);
    });

    testWidgets('has no genre pill under Alles', (tester) async {
      await _pump(
        tester,
        MobileSeerrTypeChips(
          type: SeerrDiscoverType.all,
          genres: const [(id: 1, name: 'Drama')],
          genreId: null,
          onTypeSelected: (_) {},
          onPickGenre: () {},
        ),
      );
      expect(find.text(t.libraries.filterCategories.genre), findsNothing);
    });

    testWidgets('offers the genre pill under a type, named after the picked genre', (tester) async {
      var opened = 0;
      await _pump(
        tester,
        MobileSeerrTypeChips(
          type: SeerrDiscoverType.movies,
          genres: const [(id: 1, name: 'Drama'), (id: 2, name: 'Horror')],
          genreId: 2,
          onTypeSelected: (_) {},
          onPickGenre: () => opened++,
        ),
      );
      await tester.tap(find.text('Horror'));
      expect(opened, 1);
    });
  });

  testWidgets('MobileSeerrSeeAllLink opens the row', (tester) async {
    var opened = 0;
    await _pump(tester, MobileSeerrSeeAllLink(onPressed: () => opened++));
    await tester.tap(find.text(t.watchlist.seeAll));
    expect(opened, 1);
  });
}

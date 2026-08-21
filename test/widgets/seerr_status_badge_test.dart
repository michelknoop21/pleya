import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/seerr_poster_card.dart';
import 'package:pleya/widgets/seerr_status_badge.dart';

import '../test_helpers/prefs.dart';

/// The availability badge sits on top of poster art. With only `left` set on
/// its Positioned it was laid out unconstrained, grew to its intrinsic width
/// and was then cut off by the card's ClipRRect -- which on the screenshots
/// read as a badge wider than its own poster.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<void> pumpCard(WidgetTester tester, SeerrMediaStatus status, {double width = 110}) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SeerrPosterCard(
                media: SeerrMedia(tmdbId: 1, mediaType: 'movie', title: 'Test', year: '2026', status: status),
                onTap: () {},
                width: width,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final status in [SeerrMediaStatus.available, SeerrMediaStatus.partiallyAvailable, SeerrMediaStatus.pending]) {
    testWidgets('the ${status.name} badge stays inside the poster', (tester) async {
      await pumpCard(tester, status);

      final card = tester.getRect(find.byType(SeerrPosterCard));
      final badge = tester.getRect(find.byType(SeerrStatusBadge));

      expect(badge.left, greaterThanOrEqualTo(card.left));
      expect(badge.right, lessThanOrEqualTo(card.right));
      expect(badge.width, lessThanOrEqualTo(card.width));
    });
  }

  testWidgets('a very narrow card shortens the label rather than clipping it', (tester) async {
    await pumpCard(tester, SeerrMediaStatus.partiallyAvailable, width: 80);

    final card = tester.getRect(find.byType(SeerrPosterCard));
    final badge = tester.getRect(find.byType(SeerrStatusBadge));

    expect(badge.right, lessThanOrEqualTo(card.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown status draws no badge at all', (tester) async {
    await pumpCard(tester, SeerrMediaStatus.unknown);
    expect(find.byType(SeerrStatusBadge), findsNothing);
  });
}

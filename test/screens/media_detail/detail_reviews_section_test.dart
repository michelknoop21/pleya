import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_review.dart';
import 'package:pleya/screens/media_detail/mobile/detail_reviews_section.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';

// Taken from test/fixtures/plex_detail/movie_metadata_reviews.json.
const _ebert = MediaReview(
  author: 'Roger Ebert',
  text: "It doesn't have a brain in its head, but it's made with skill and style and, boy, is it fast and furious.",
  imageUri: 'rottentomatoes://image.review.fresh',
  link: 'http://www.rogerebert.com/reviews/2-fast-2-furious-2003',
  source: 'Chicago Sun-Times',
);
const _clark = MediaReview(
  author: 'Mike Clark',
  text: 'Just another retread.',
  imageUri: 'rottentomatoes://image.review.rotten',
  source: 'USA Today',
);

Widget _host(List<MediaReview> reviews) => MaterialApp(
  theme: monoTheme(dark: true),
  home: OverlaySheetHost(
    child: Scaffold(body: DetailReviewsSection(reviews: reviews)),
  ),
);

void main() {
  setUp(() async => LocaleSettings.setLocale(AppLocale.nl));

  testWidgets('an empty list draws nothing', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('two reviews draw two cards with author, source and RT icon', (tester) async {
    await tester.pumpWidget(_host(const [_ebert, _clark]));
    expect(find.text('Roger Ebert'), findsOneWidget);
    expect(find.text('Mike Clark'), findsOneWidget);
    expect(find.text('Chicago Sun-Times'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    final card = tester.getSize(find.byKey(const ValueKey('review-card-0')));
    expect(card, const Size(300, 150));
  });

  testWidgets('tapping a card opens the full text with a source button', (tester) async {
    await tester.pumpWidget(_host(const [_ebert, _clark]));
    await tester.tap(find.text('Roger Ebert'));
    await tester.pumpAndSettle();
    expect(find.text('Lees bij de bron'), findsOneWidget);
    expect(find.text(_ebert.text), findsNWidgets(2)); // card and sheet
  });

  testWidgets('a review without link has no source button', (tester) async {
    await tester.pumpWidget(_host(const [_clark]));
    await tester.tap(find.text('Mike Clark'));
    await tester.pumpAndSettle();
    expect(find.text('Just another retread.'), findsNWidgets(2));
    expect(find.text('Lees bij de bron'), findsNothing);
  });
}

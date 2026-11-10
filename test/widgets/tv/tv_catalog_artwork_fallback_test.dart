import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';

import '../../test_helpers/tv_catalog_fixtures.dart';

void main() {
  testWidgets('TV and desktop catalog draw another proven source poster', (tester) async {
    OptimizedMediaImage.debugImageBuilder = (_, path) => Text(path ?? 'NONE');
    addTearDown(() => OptimizedMediaImage.debugImageBuilder = null);
    final primary = tvGoldenMovie(id: 'one', title: 'Dune');
    final other = tvGoldenMovie(id: 'two', title: 'Dune', serverId: 'other').copyWith(thumbPath: '/other-poster');
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: Center(
                child: TvUnifiedMediaCard(group: tvGoldenGroup('g', [primary, other]), width: 240, onSelect: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('/other-poster'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
  });
}

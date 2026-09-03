import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/media_markers.dart';

MediaItem _item({int? viewOffsetMs, int? durationMs}) => MediaItem(
  id: 'i1',
  backend: .plex,
  kind: MediaKind.movie,
  title: 'Dune',
  viewOffsetMs: viewOffsetMs,
  durationMs: durationMs,
  serverId: 'nas',
  serverName: 'NAS',
);

UnifiedMediaGroup _group({int? viewOffsetMs, int? durationMs, bool hasActiveProgress = false, bool isWatched = false}) {
  final source = UnifiedMediaSource.fromItem(_item(viewOffsetMs: viewOffsetMs, durationMs: durationMs));
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(
      representativeSourceKey: source.sourceKey,
      hasActiveProgress: hasActiveProgress,
      isWatched: isWatched,
    ),
  );
}

Widget _themed(Widget child) => MaterialApp(
  theme: monoTheme(dark: true),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('resumeFractionFor', () {
    test('a group with no active progress draws nothing', () {
      expect(resumeFractionFor(_group(viewOffsetMs: 100, durationMs: 200)), isNull);
    });

    test('an active group with an offset and duration returns the fraction', () {
      final fraction = resumeFractionFor(_group(viewOffsetMs: 2250000, durationMs: 9000000, hasActiveProgress: true));
      expect(fraction, closeTo(0.25, 0.001));
    });

    test('an active group with no duration draws nothing: no denominator', () {
      expect(resumeFractionFor(_group(viewOffsetMs: 100, hasActiveProgress: true)), isNull);
    });
  });

  testWidgets('SourceCountCapsule shows the localized count', (tester) async {
    await tester.pumpWidget(_themed(const SourceCountCapsule(count: 3)));
    expect(find.text('3 sources'), findsOneWidget);
  });

  testWidgets('WatchedTick renders a check glyph', (tester) async {
    await tester.pumpWidget(_themed(const WatchedTick()));
    expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
  });

  testWidgets('ResumeLine clamps its fraction into range', (tester) async {
    await tester.pumpWidget(_themed(const ResumeLine(fraction: 1.4)));
    final box = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
    expect(box.widthFactor, 1.0);
  });

  testWidgets('NewEpisodeDot renders a small solid dot', (tester) async {
    await tester.pumpWidget(_themed(const NewEpisodeDot()));
    expect(find.byType(NewEpisodeDot), findsOneWidget);
  });
}

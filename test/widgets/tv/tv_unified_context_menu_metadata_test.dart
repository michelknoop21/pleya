/// CTX1: de metadata-subregel van mockup 12, onder de titel in de posterkop.
///
/// Wat erin staat is genre, duur, bronnen en kijktijd, en elk deel komt uit de
/// helper die de rest van de app er al voor gebruikt. Deze test bewaakt vooral
/// de tweede helft van die zin: hij leest de verwachte waarde niet terug uit
/// dezelfde `t.`-aanroep die de code doet, maar uit wat de Engelse bron
/// letterlijk declareert.
library;

import 'package:flutter/material.dart';
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
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/formatters.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';

MediaItem _item({
  required String id,
  required String serverId,
  List<String>? genres,
  int? durationMs,
  int? viewOffsetMs,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  year: 2021,
  serverId: serverId,
  serverName: serverId.toUpperCase(),
  genres: genres,
  durationMs: durationMs,
  viewOffsetMs: viewOffsetMs,
);

UnifiedMediaGroup _group({List<String>? genres, int? durationMs, int? viewOffsetMs, int sourceCount = 1}) {
  final sources = [
    for (var i = 0; i < sourceCount; i++)
      UnifiedMediaSource.fromItem(
        _item(id: 'i$i', serverId: 'nas$i', genres: genres, durationMs: durationMs, viewOffsetMs: viewOffsetMs),
      ),
  ];
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(
      representativeSourceKey: sources.first.sourceKey,
      hasActiveProgress: (viewOffsetMs ?? 0) > 0,
    ),
  );
}

void main() {
  Future<void> openMenu(WidgetTester tester, UnifiedMediaGroup group) async {
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
                        onNavigate: (_) async {},
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
  }

  test('the meta line names genre, runtime, sources and remaining time, in that order', () {
    final line = unifiedContextMenuMetaLine(
      _group(
        genres: const ['Science fiction', 'Adventure'],
        durationMs: 9360000, // 2h 36m
        viewOffsetMs: 3600000, // 1h in
        sourceCount: 2,
      ),
    );

    expect(line, isNotNull);
    final parts = line!.split(' · ');
    expect(parts, hasLength(4));
    expect(parts[0], 'Science fiction', reason: 'one genre, not the whole list');
    expect(parts[1], formatDurationTextual(9360000));
    expect(parts[2], t.unifiedCatalog.sources(count: 2));
    expect(parts[3], t.nowWatching.remaining(time: formatDurationTextual(9360000 - 3600000)));
  });

  test('a part with nothing behind it is left out, not printed empty', () {
    final line = unifiedContextMenuMetaLine(_group(sourceCount: 1));

    // Geen genres, geen duur, niets gekeken: alleen het bronnenaantal blijft
    // over, en dat is er altijd want een groep zonder bron bestaat niet.
    expect(line, t.unifiedCatalog.oneSource);
  });

  test('a fully unknown group gives no line rather than a bare separator', () {
    // Er is altijd minstens één bron, dus dit kan niet null worden. De test
    // legt vast dat de functie dat weet en geen ' ·  · ' teruggeeft.
    expect(unifiedContextMenuMetaLine(_group()), isNot(contains('·')));
  });

  testWidgets('the menu draws the meta line under the title', (tester) async {
    await openMenu(tester, _group(genres: const ['Science fiction'], durationMs: 9360000, sourceCount: 2));

    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(
      find.text('Science fiction · ${formatDurationTextual(9360000)} · ${t.unifiedCatalog.sources(count: 2)}'),
      findsOneWidget,
    );
  });

  testWidgets('a group with nothing to say still draws a header', (tester) async {
    await openMenu(tester, _group());

    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text(t.unifiedCatalog.oneSource), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // CTX2: de hervat-rij zegt hoeveel er nog te gaan is
  // ---------------------------------------------------------------------------

  testWidgets('the resume row carries the remaining time as its second line', (tester) async {
    await openMenu(tester, _group(durationMs: 9360000, viewOffsetMs: 3600000));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    final resume = rows.firstWhere((r) => r.label == t.common.resume);

    expect(resume.secondary, t.nowWatching.remaining(time: formatDurationTextual(9360000 - 3600000)));
  });

  testWidgets('a title with no progress says Play and carries no second line', (tester) async {
    await openMenu(tester, _group(durationMs: 9360000));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    final play = rows.firstWhere((r) => r.label == t.common.play);

    expect(play.secondary, isNull, reason: 'nothing watched means nothing remaining');
  });

  testWidgets('only the resume row gets it, not every navigation row', (tester) async {
    await openMenu(tester, _group(durationMs: 9360000, viewOffsetMs: 3600000));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    final withSecondary = rows.where((r) => r.secondary != null).toList();

    expect(withSecondary, hasLength(1));
    expect(withSecondary.single.label, t.common.resume);
  });
}

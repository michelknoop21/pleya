/// The film on [TvDetailPage], through the real screen: what 06-10 draw, and
/// what must not get lost on the way there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_review.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail/now_watching_line.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_backdrop.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_hero_widgets.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_layout.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_page.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/media_context_menu.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size _panel = Size(1038, 584);

MediaItem _movie({int? viewOffsetMs = 1000 * 60 * 41}) => MediaItem.plex(
  id: 'movie_1',
  kind: MediaKind.movie,
  title: 'Puss in Boots',
  summary: 'A cat with one life left goes looking for a wish.',
  year: 2022,
  durationMs: 102 * 60 * 1000,
  viewOffsetMs: viewOffsetMs,
  contentRating: 'nl/6',
  genres: const ['Comedy', 'Fantasy'],
  directors: const ['Joel Crawford'],
  externalRatings: const [ExternalRating(source: ExternalRatingSource.imdb, value: 7.9)],
  reviews: const [MediaReview(author: 'Amy Nicholson', text: 'Very funny and charming.', source: 'FilmWeek')],
  roles: const [
    MediaRole(id: 'p1', tag: 'Antonio Banderas', role: 'Puss (voice)'),
    MediaRole(id: 'p2', tag: 'Salma Hayek', role: 'Kitty (voice)'),
    MediaRole(tag: 'No Id', role: 'Extra'),
  ],
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _other(String id, String title) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: title,
  year: 2011,
  serverId: 'server_1',
  serverName: 'Server',
);

class _Client implements MediaServerClient {
  _Client(this.movie, {this.extras = const [], this.hubs, this.people = const {}, this.fileInfo});

  final MediaItem movie;
  final List<MediaItem> extras;
  final Future<List<MediaHub>>? hubs;
  final Map<String, List<MediaItem>> people;
  final MediaFileInfo? fileInfo;
  final personCalls = <String>[];
  var hubCalls = 0;

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'Server';
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: movie, onDeckEpisode: null);
  @override
  Future<List<MediaItem>> fetchExtras(String id) async => extras;
  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async => fileInfo;
  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) {
    hubCalls++;
    return hubs ?? Future.value(const <MediaHub>[]);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    personCalls.add(personId);
    final items = people[personId] ?? const <MediaItem>[];
    return LibraryPage<MediaItem>(items: items, totalCount: items.length, offset: 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<void> pumpDetail(WidgetTester tester, _Client client, {VoidCallback? onFocusBar}) async {
    tester.view.physicalSize = _panel;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await SettingsService.getInstance();
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: InputModeTracker(
                child: MainScreenFocusScope(
                  focusSidebar: onFocusBar ?? () {},
                  focusContent: () {},
                  isSidebarFocused: false,
                  sideNavigationWidth: 0,
                  child: TvDisplayMetrics(
                    size: _panel,
                    child: TvNestedRouteScope(
                      dismiss: ([_]) {},
                      markResult: (_) {},
                      child: MediaDetailScreen(metadata: client.movie),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a film opens on the page, the ring on the pill, without waiting for its sections', (tester) async {
    // A related-hubs request that never answers would keep the old gate shut.
    final client = _Client(_movie(), hubs: Completer<List<MediaHub>>().future);
    await pumpDetail(tester, client);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TvDetailPage), findsOneWidget);
    expect(find.byType(TvBrowseRail), findsNothing);
    final pill = find.byType(TvDetailPlayPill);
    expect(tester.widget<TvDetailPlayPill>(pill).focused, isTrue);
    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(of: pill, matching: find.byType(AnimatedOpacity)).last).opacity,
      1,
    );
  });

  testWidgets('the pill says what is left and draws how far you are', (tester) async {
    await pumpDetail(tester, _Client(_movie()));

    expect(find.textContaining(RegExp(r'^Resume • .*left$')), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(
      find.descendant(of: find.byType(TvDetailPlayPill), matching: find.byType(CircularProgressIndicator)),
    );
    expect(ring.value, closeTo(41 / 102, 0.001));
  });

  testWidgets('a film not started has a plain Play and no restart', (tester) async {
    await pumpDetail(tester, _Client(_movie(viewOffsetMs: null)));

    expect(find.text('Play'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(TvDetailPlayPill), matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );
  });

  testWidgets('hero reads as 06: rating, score, director, margin', (tester) async {
    await pumpDetail(tester, _Client(_movie()));

    expect(find.text('6'), findsOneWidget, reason: 'the country prefix goes');
    expect(find.text('7.9'), findsOneWidget);
    expect(find.text('Directed by Joel Crawford'), findsOneWidget);
    expect(tester.getTopLeft(find.text('2022')).dx, closeTo(_panel.width * 107 / 1600, 0.5));
  });

  testWidgets('sections arrive in the order of the northstar, and an empty one stays away', (tester) async {
    final client = _Client(
      _movie(),
      extras: [_other('extra_1', 'Teaser')],
      hubs: Future.value([
        MediaHub(id: 'similar', title: 'Similar', type: 'movie', items: [_other('s1', 'Shrek')]),
        MediaHub(
          id: 'c1',
          identifier: 'collection.related',
          title: 'Puss in Boots Collection',
          type: 'movie',
          items: [_other('c1a', 'Puss in Boots 2011')],
        ),
      ]),
      people: {
        'p1': [_other('a1', 'The Expendables 3'), _other('movie_1', 'Puss in Boots')],
        'p2': const [],
      },
    );
    await pumpDetail(tester, client);
    await tester.pump();
    expect(client.personCalls, isEmpty, reason: 'nothing below the second screen loads before you near it');

    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
    }

    final sections = tester.widget<TvDetailPage>(find.byType(TvDetailPage)).sections;
    final titles = [
      for (final section in sections)
        if (section.itemIds.isNotEmpty) section.title,
    ];
    expect(titles, [
      'Cast & Crew',
      'Ratings & Reviews',
      'Trailers & Extras',
      'Puss in Boots Collection',
      'More with Antonio Banderas',
      'Similar',
    ]);
    final actorRow = sections.singleWhere((section) => section.id == 'person:p1');
    expect(actorRow.itemIds, ['a1'], reason: 'the film you are on is not more of that actor');
    expect(client.personCalls, ['p1', 'p2']);
  });

  testWidgets('nothing sits behind a clip in the hero, unlike the old band', (tester) async {
    await pumpDetail(tester, _Client(_movie()));

    Set<Element> clipsAround(Finder finder) =>
        find.ancestor(of: finder, matching: find.byType(ClipRect)).evaluate().toSet();
    // A clip around the whole page is the viewport. One around the rows alone
    // is the band that cut them off.
    expect(clipsAround(find.byType(NowWatchingLine)).difference(clipsAround(find.text('Cast & Crew'))), isEmpty);
  });

  testWidgets('the row keeps every action: what is not on it is in the menu', (tester) async {
    await pumpDetail(tester, _Client(_movie(), extras: [_trailer()]));

    final menu = tester.widget<MediaContextMenu>(find.byType(MediaContextMenu).first);
    expect(menu.onPlayTrailer, isNotNull);
  });

  testWidgets('UP from the row reaches the top bar', (tester) async {
    var bar = 0;
    await pumpDetail(tester, _Client(_movie()), onFocusBar: () => bar++);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(bar, 1);
  });

  testWidgets('DOWN goes into the sections and back up to the row', (tester) async {
    await pumpDetail(tester, _Client(_movie()));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('TvDetailCard_cast'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('TvDetailCard_reviews'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'play_button');
    expect(tester.widget<TvDetailPlayPill>(find.byType(TvDetailPlayPill)).focused, isTrue);
  });

  testWidgets('a popped route gets its card back through the restore host', (tester) async {
    await pumpDetail(tester, _Client(_movie()));

    final host = tester.state(find.byType(MediaDetailScreen)) as TvFocusRestoreHost;
    expect(host.restoreTvFocus(const TvFocusRestoreTarget(itemId: 'p2', containerId: 'cast')), isTrue);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('TvDetailCard_cast(p2)'));

    expect(host.restoreTvFocus(const TvFocusRestoreTarget(itemId: 'nope', containerId: 'cast')), isFalse);
  });

  testWidgets('a person without a photo gets initials', (tester) async {
    await pumpDetail(tester, _Client(_movie()));
    expect(find.text('AB'), findsOneWidget);
  });

  group('the first screen hangs from the top, as 06 does', () {
    const pt = 584 / 1080;
    const threeLines =
        'When a cat discovers that his passion for adventure has taken its toll and he has burned through eight of '
        'his nine lives, he launches an epic journey to restore them by finding the mythical Last Wish that grants '
        'whoever finds it one single and final request.';
    final files = MediaFileInfo(
      videoResolution: '4k',
      videoCodec: 'hevc',
      audioTracks: [MediaAudioTrack(id: 1, language: 'English', codec: 'eac3', channels: 6, selected: true)],
    );

    testWidgets('the rows follow the slot: the pill on 620 and Cast & Crew on 821 of 2000', (tester) async {
      await pumpDetail(tester, _Client(_movie().copyWith(summary: threeLines), fileInfo: files));
      await tester.pumpAndSettle();

      // Wider than a pixel: the test font is taller than the panel's.
      expect(tester.getCenter(find.byType(TvDetailPlayPill)).dy / pt, closeTo(620 * 0.96, 24));
      expect(tester.getCenter(find.text('Cast & Crew')).dy / pt, closeTo(821 * 0.96, 32));
    });

    testWidgets('without the activity row the first section moves up, with no hole above it', (tester) async {
      await pumpDetail(tester, _Client(_movie().copyWith(summary: threeLines, mediaVersions: const [])));
      await tester.pumpAndSettle();

      final pill = tester.getRect(find.byType(TvDetailPlayPill));
      final heading = tester.getRect(find.text('Cast & Crew'));
      expect((heading.top - pill.bottom) / pt, lessThan(TvDetailLayout.sectionGap + 8));
    });

    testWidgets('a text title stands on the metadata line, without the gap of the old slot', (tester) async {
      await pumpDetail(tester, _Client(_movie()));

      final title = tester.getRect(find.text('Puss in Boots'));
      final meta = tester.getRect(find.text('2022'));
      expect((meta.top - title.bottom) / pt, lessThan(TvDetailLayout.metaGap + 8));
      expect(title.bottom, lessThanOrEqualTo(meta.top));
    });

    testWidgets('the metadata line sits at one height whether a title or a logo fills the slot', (tester) async {
      await pumpDetail(tester, _Client(_movie()));
      final withTitle = tester.getTopLeft(find.text('2022')).dy;
      expect(
        withTitle / pt,
        closeTo(TvDetailLayout.headingTop + TvDetailLayout.headingHeight + TvDetailLayout.metaGap, 2),
      );
    });

    testWidgets('running text, metadata and director are set solid', (tester) async {
      await pumpDetail(tester, _Client(_movie()));

      for (final text in ['2022', 'Directed by Joel Crawford', 'A cat with one life left goes looking for a wish.']) {
        final span = tester.widget<RichText>(find.descendant(of: find.text(text), matching: find.byType(RichText)));
        expect(span.text.style?.letterSpacing, 0, reason: text);
      }
    });

    testWidgets('the sharp artwork spans the page, so it brings no left edge of its own', (tester) async {
      OptimizedMediaImage.debugImageBuilder = (_, _) => const SizedBox.expand();
      addTearDown(() => OptimizedMediaImage.debugImageBuilder = null);
      await pumpDetail(tester, _Client(_movie().copyWith(artPath: '/art')));

      expect(tester.getRect(find.byType(TvDetailHeroArt)), const Rect.fromLTWH(0, 0, 1038, 584));
    });

    testWidgets('DOWN scrolls the hero away, UP puts the page back on 0', (tester) async {
      await pumpDetail(tester, _Client(_movie()));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scrollable.position.pixels, greaterThan(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
    });
  });

  test('the page margin is the one Michel set, for the artwork and not the card around it', () {
    expect(TvDetailLayout.leftMargin(1600), 107);
    final grid = TvDetailLayout.rowGrid(width: 1600, cardWidth: 200, pt: 1, artworkInset: 5);
    expect(grid.inset + 5, 107);
    expect(grid.gutter + 10, TvDetailLayout.cardGutter);
  });
}

MediaItem _trailer() => MediaItem(
  id: 'trailer_1',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.clip,
  title: 'Trailer',
  raw: const {'ExtraType': 'Trailer'},
  serverId: 'server_1',
  serverName: 'Server',
);

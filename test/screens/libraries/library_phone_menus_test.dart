/// The menus of a real browse tab in the iPhone library look, reached the way a
/// viewer reaches them: the sheets of `lib/screens/libraries` tested on their own
/// prove nothing about which one a pill opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_filter_result.dart';
import 'package:pleya/media/library_first_character.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_sort.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/libraries/libraries_screen.dart';
import 'package:pleya/screens/libraries/library_phone_filter_pages.dart';
import 'package:pleya/screens/libraries/sort_bottom_sheet.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

final _films = MediaLibrary(
  id: '1',
  backend: MediaBackend.plex,
  title: 'Films',
  kind: MediaKind.movie,
  serverId: 's1',
  serverName: 'Pleya',
);

class _BrowseClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('s1');

  @override
  String? get serverName => 'Pleya';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async => const [
    MediaSort(key: 'random', title: 'Random'),
    MediaSort(key: 'addedAt', title: 'Date Added'),
    MediaSort(key: 'titleSort', title: 'Title'),
  ];

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async => LibraryFilterResult(
    filters: [
      MediaFilter(filter: 'genre', filterType: 'string', key: '/genre', title: 'Genre', type: 'filter'),
      MediaFilter(filter: 'unwatched', filterType: 'boolean', key: '/unwatched', title: 'Unwatched', type: 'filter'),
      MediaFilter(filter: 'hdr', filterType: 'boolean', key: '/hdr', title: 'HDR', type: 'filter'),
    ],
    cachedValues: const {},
  );

  @override
  Future<List<LibraryFirstCharacter>> fetchFirstCharacters(String libraryId, {Map<String, String>? filters}) async =>
      const [];

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async => LibraryPage<MediaItem>(
    items: [
      MediaItem(
        id: 'm1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: '22 Jump Street',
        year: 2014,
        serverId: 's1',
      ),
    ],
    totalCount: 1,
    offset: query.offset,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(false);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        for (var j = 0; j < 4; j++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();
    }
  }

  Future<void> pumpBrowse(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await SettingsService.getInstance();
      final storage = await StorageService.getInstance();
      await storage.saveSelectedLibraryKey(_films.globalKey);
      await storage.saveLibraryTab(_films.globalKey, 'browse');
    });
    final manager = MultiServerManager()..debugRegisterClientForTesting(_BrowseClient());
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);
    final libraries = LibrariesProvider()..debugSetLibraries([_films]);
    final hidden = HiddenLibrariesProvider();
    await tester.runAsync(() => hidden.ensureInitialized());
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: libraries),
            ChangeNotifierProvider.value(value: hidden),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: const OverlaySheetHost(child: LibrariesScreen(phoneLook: true)),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('the filter pill opens the phone menu, floating, in the definition\'s order', (tester) async {
    await pumpBrowse(tester);
    await tester.tap(find.text(t.libraries.all));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.byType(LibraryPhoneFilterMenu), findsOneWidget);
    expect(find.text(t.libraries.filterBy), findsOneWidget);
    double y(String label) => tester.getCenter(find.text(label)).dy;
    final quick = t.unifiedCatalog.filters.quick;
    // The server lists Genre, Unwatched, HDR.
    expect(y(quick.hdr), lessThan(y(quick.unwatched)));
    expect(y(quick.unwatched), lessThan(y(t.unifiedCatalog.filters.genre)));
    expect(tester.getRect(find.byType(LibraryPhoneFilterMenu)).right, 402 - 8);
  });

  testWidgets('the sort pill opens the sheet in the definition\'s order, what it has no row for at the bottom', (
    tester,
  ) async {
    await pumpBrowse(tester);
    await tester.tap(find.text(t.unifiedCatalog.sort.fields.title));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SortBottomSheet), findsOneWidget);
    final inSheet = find.descendant(of: find.byType(SortBottomSheet), matching: find.byType(Text));
    final labels = [
      for (final text in tester.widgetList<Text>(inSheet))
        if (text.data != t.libraries.sortBy && text.data != t.common.clear) text.data,
    ];
    expect(labels, [t.unifiedCatalog.sort.fields.title, t.unifiedCatalog.sort.fields.addedAt, 'Random']);
  });
}

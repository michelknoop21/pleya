import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_memory_host.dart';
import 'package:pleya/assistant/assistant_memory_overview.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/screens/settings/memory/memory_screen_model.dart';
import 'package:pleya/services/memory/memory_enabled_store.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:provider/provider.dart';

import '../../../assistant/assistant_memory_support.dart';
import '../../../services/memory/memory_test_support.dart';

export '../../../assistant/assistant_memory_support.dart' show ScriptedModel, callTool, callTools, say;

/// The switch of a profile's memory without preferences behind it: reading
/// shared preferences inside `testWidgets` hangs.
class FakeEnabledStore extends MemoryEnabledStore {
  FakeEnabledStore(super.profileId, {this.on = true});

  bool on;

  @override
  Future<bool> read() async => on;

  @override
  Future<void> save(bool value) async => on = value;
}

/// A service whose facts cannot be read, as after a database error.
class UnreadableMemoryService extends MemoryService {
  UnreadableMemoryService({required super.database, required super.profileId, super.enabledStore});

  bool broken = true;

  @override
  Future<List<MemoryFact>?> tryList({MemoryCategory? category, String? query}) async =>
      broken ? null : super.tryList(category: category, query: query);
}

/// A model that holds its calls back until [release] completes, as a slow
/// local model does. The first [free] calls answer at once; [started] counts
/// the calls that came in.
class HeldModel extends ScriptedModel {
  HeldModel(super.script, {this.free = 0});

  final int free;
  final release = Completer<void>();
  int started = 0;

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    started++;
    if (started > free) await release.future;
    return super.chat(messages, tools, abort: abort);
  }
}

/// Records how the screen asked: as the user's typed words or as a follow-up.
class RecordingHost extends AssistantMemoryHost {
  RecordingHost({
    required super.buildContext,
    required super.languageName,
    super.entitlement,
    super.loadConfig,
    super.modelFor,
  });

  final List<({String text, bool typed})> asked = [];

  @override
  Future<void> ask(String text) {
    asked.add((text: text, typed: true));
    return super.ask(text);
  }

  @override
  Future<void> askFollowUp(String text) {
    asked.add((text: text, typed: false));
    return super.askFollowUp(text);
  }
}

class FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  FakeActiveProfile(this.active);

  @override
  final Profile? active;

  @override
  String? get activeId => active?.id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The system keyboard of a TV: answers every capture with [next], or with
/// nothing when the viewer backs out.
class FakeSpeech extends SpeechSearchService {
  String? next;
  final List<({String? prompt, String initial, String action})> captures = [];

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<SpeechCaptureResult?> capture({
    String? prompt,
    String initialText = '',
    String action = 'search',
    ValueChanged<String>? onPartial,
  }) async {
    captures.add((prompt: prompt, initial: initialText, action: action));
    final text = next;
    next = null;
    return text == null ? null : (text: text, submitted: true);
  }
}

/// The debug label of the node that holds the focus.
String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

/// The six memories of mockup 43, oldest first.
const mockupFacts = <(String, MemoryCategory, MemorySource)>[
  ('Is fan van Scandinavische misdaadseries', MemoryCategory.preference, MemorySource.userExplicit),
  ('Kijkt graag documentaires in het weekend', MemoryCategory.preference, MemorySource.settingsManual),
  ('Houdt niet van horror', MemoryCategory.dislike, MemorySource.assistantConfirmed),
  ('Heeft een hekel aan musicals', MemoryCategory.dislike, MemorySource.assistantConfirmed),
  ('Kijkt op vrijdagavond met het gezin', MemoryCategory.household, MemorySource.userExplicit),
  ('Kijkt doordeweeks geen films langer dan twee uur', MemoryCategory.habit, MemorySource.userExplicit),
];

/// The overview of mockup 43 A, as the model would answer it.
String mockupOverviewReply({List<String>? followUps, bool other = false}) => jsonEncode({
  'overview': "Je kijkt vooral 's avonds. Het liefst kies je dan een serie. De vrijdagavond is voor het gezin.",
  'preference': 'Je bent fan van Scandinavische misdaadseries. Documentaires kijk je graag in het weekend.',
  'dislike': 'Je houdt niet van horror. Aan musicals heb je een hekel.',
  'household': 'Je kijkt op vrijdagavond met het gezin.',
  'habit': 'Doordeweeks houd je het kort. Films die langer duren dan twee uur kijk je niet op doordeweekse avonden.',
  if (other) 'other': 'Je kijkt het liefst met ondertitels aan.',
  'follow_ups':
      followUps ??
      [
        'Wat past bij een vrijdagavond met het gezin?',
        'Welke misdaadseries heb ik nog niet gezien?',
        'Vat samen wat je over mijn smaak weet.',
      ],
});

/// One profile's memory screen state on an in-memory database, with scripted
/// models behind the overview and behind the field.
class MemoryScreenHarness {
  MemoryScreenHarness({this.profileId = 'profile-a', AppDatabase? database, bool unreadable = false})
    : db = database ?? memoryTestDatabase(),
      _ownsDb = database == null {
    enabledStore = FakeEnabledStore(profileId);
    final clock = TickingClock();
    service = unreadable
        ? UnreadableMemoryService(database: db, profileId: profileId, enabledStore: enabledStore)
        : MemoryService(database: db, profileId: profileId, enabledStore: enabledStore, now: clock.call);
    active = profileId;
  }

  final String profileId;
  final AppDatabase db;
  final bool _ownsDb;
  late final FakeEnabledStore enabledStore;
  late final MemoryService service;
  final servers = MultiServerManager();

  /// What `activeProfileId` answers; another id is a profile switch.
  String? active;
  bool kids = false;
  List<int> kidsAges = const [];
  AssistantProviderConfig? config = memoryConfig;

  /// The replies of the overview writer, and of the run behind the field.
  ScriptedModel overviewModel = ScriptedModel(const []);
  ScriptedModel hostModel = ScriptedModel(const []);

  late final services = AssistantMemoryServices(
    service: service,
    activeProfileId: () => active,
    kidsProfile: () async => kids,
  );

  late final RecordingHost host = RecordingHost(
    buildContext: () => AssistantToolContext(
      servers: servers,
      kidsProfile: () async => kids,
      kidsAges: () async => kidsAges,
      memory: services,
    ),
    languageName: () => 'Dutch',
    entitlement: const Entitled(),
    loadConfig: () async => config,
    modelFor: (_) => hostModel,
  );

  late final writer = AssistantMemoryOverviewWriter(
    memory: services,
    languageName: () => 'Dutch',
    entitlement: const Entitled(),
    loadConfig: () async => config,
    modelFor: (_) => overviewModel,
  );

  late final model = MemoryScreenModel(
    memory: services,
    writer: writer,
    host: host,
    kidsAges: () async => kidsAges,
    locale: () => 'nl',
    now: () => DateTime(2026, 10, 11, 12),
  );

  Future<void> seed([List<(String, MemoryCategory, MemorySource)> facts = mockupFacts]) async {
    for (final (value, category, source) in facts) {
      await service.add(value: value, category: category, source: source);
    }
  }

  Future<List<String>> values() async => [for (final fact in await service.list()) fact.value];

  Future<void> dispose() async {
    model.dispose();
    servers.dispose();
    if (_ownsDb) await db.close();
  }
}

/// Runs real asynchronous work (the in-memory database) and pumps frames
/// until the screen has caught up. Never `pumpAndSettle`: the loading field
/// of 43 B animates for as long as it is shown.
Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

const phoneSize = Size(402, 874);
const phoneSeSize = Size(375, 667);
const tabletSize = Size(1180, 820);

/// The logical canvas of an Apple TV: 1920x1080 over the 1.85 render scale.
const tvSize = Size(1038, 584);
const tvRatio = 1.85;

/// The band the top navigation of the TV shell takes from a nested page: its
/// two insets and its row, as `TvTopNavigation` lays them out.
double tvNavBand(Size display) =>
    (TvTopNavLayout.topInset + TvTopNavLayout.barHeight + TvTopNavLayout.contentGap) *
    TvLayoutConstants.scaleForSize(display);

/// [child] as the TV shell mounts a nested page: under the navigation band,
/// in the box that is left, with the whole display published for the scale.
/// Panels and dialogs lie over the whole display, as in the app.
class TvShellBox extends StatelessWidget {
  const TvShellBox({super.key, required this.display, required this.child});

  final Size display;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final band = tvNavBand(display);
    final media = MediaQuery.of(context);
    return TvDisplayMetrics(
      size: display,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Where the bar stands; drawn as a line so a shot shows the band.
          Container(
            height: band,
            alignment: Alignment.bottomCenter,
            child: Container(height: 1, color: const Color(0x33FFFFFF)),
          ),
          Expanded(
            child: MediaQuery(
              data: media.copyWith(size: Size(display.width, display.height - band)),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pumps [child] as a page of the app, in Dutch, at [size]. On TV the page
/// stands in [TvShellBox], so it has the height the real shell leaves it.
Future<GlobalKey> pumpMemoryApp(
  WidgetTester tester,
  Widget child, {
  Size size = phoneSize,
  bool tv = false,
  bool light = false,
  double textScale = 1,
  String profileName = 'Michel',
  Key? sessionKey,
}) async {
  TvDetectionService.debugSetAppleTVOverride(null);
  if (tv) {
    await tester.runAsync(() => TvDetectionService.getInstance(forceTv: true));
    TvDetectionService.setForceTVSync(true);
  } else {
    TvDetectionService.setForceTVSync(false);
  }
  addTearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
  });
  final ratio = tv ? tvRatio : 2.0;
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final boundary = GlobalKey();
  final profile = Profile.plexHome(id: 'p', displayName: profileName, createdAt: DateTime(2026));
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: ChangeNotifierProvider<ActiveProfileProvider>(
        create: (_) => FakeActiveProfile(profile),
        child: TranslationProvider(
          // As the app: the focus ring shows in remote and keyboard mode only.
          child: InputModeTracker(
            child: MaterialApp(
              key: sessionKey,
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: !light),
              builder: (context, app) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
                child: app!,
              ),
              // The TV shell gives its pages the page surface; here a Scaffold does.
              // The shell hosts the panels of its pages over the whole display.
              home: tv
                  ? Scaffold(
                      body: OverlaySheetHost(
                        child: TvShellBox(display: size, child: child),
                      ),
                    )
                  : child,
            ),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return boundary;
}

/// Writes what [boundary] shows to `<dir>/<name>.png`.
Future<void> writeShot(WidgetTester tester, GlobalKey boundary, String dir, String name, {double ratio = 2}) async {
  await tester.runAsync(() async {
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await (await ro.toImage(pixelRatio: ratio)).toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> useDutch() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await initializeDateFormatting('nl');
  await LocaleSettings.setLocale(AppLocale.nl);
  addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
}

// BP-12 A6: what the user sees for one turn of an eval record, headless, on
// phone, iPad and TV, with deterministic checks on the rendered surface.
// A record turn (see evalRecord) becomes a FakeAssistantController state;
// the real Big P surfaces draw it.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_option_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_results.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_suggestions.dart';
import 'package:pleya/widgets/big_p/big_p_rig.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';
import 'package:provider/provider.dart';

import '../../widgets/big_p/fake_assistant_controller.dart';
import 'big_p_eval_fixtures.dart';

/// The three surfaces: iPhone 17 Pro, an 11-inch iPad in landscape, and an
/// Apple TV (1920x1080, laid out at 1/1.85 as `_AppleTvScale` in main.dart).
enum EvalSurface {
  phone(Size(402, 874), 2, EdgeInsets.only(top: 54, bottom: 34)),
  ipad(Size(1180, 820), 1, EdgeInsets.only(top: 24, bottom: 20)),
  tv(Size(1920, 1080), 1, EdgeInsets.zero);

  const EvalSurface(this.size, this.pixelRatio, this.safe);
  final Size size;
  final double pixelRatio;
  final EdgeInsets safe;
}

typedef EvalCardRef = ({String title, int? year});

List<Map<String, Object?>> _maps(Object? list) => [
  for (final e in list as List? ?? const []) (e as Map).cast<String, Object?>(),
];

/// Every card of [turn], in display order.
List<EvalCardRef> evalTurnCards(Map<String, Object?> turn) => [
  for (final d in _maps(turn['displays']))
    for (final c in _maps(d['cards'])) (title: '${c['title'] ?? ''}', year: c['year'] as int?),
];

String _answerOf(Map<String, Object?> turn) {
  final shown = turn['answer_shown'] as String? ?? '';
  return shown.isNotEmpty ? shown : turn['text'] as String? ?? '';
}

/// Puts [turn] on [c] as a finished run and returns the display types it
/// could not rebuild. Posters are `artwork/<n>` (TvGoldenArtwork).
List<String> evalApplyTurn(FakeAssistantController c, Map<String, Object?> turn) {
  final ctx = AssistantToolContext(servers: MultiServerManager());
  final skipped = <String>[];
  var n = 0;
  MediaItem item(Map<String, Object?> card) {
    final title = '${card['title'] ?? ''}';
    final year = card['year'] as int?;
    final kind = switch (card['kind']) {
      'show' || 'series' || 'tv' => MediaKind.show,
      final String k => MediaKind.values.asNameMap()[k] ?? MediaKind.movie,
      _ => MediaKind.movie,
    };
    final known = evalTitles.where((t) => t.title == title && t.year == year).firstOrNull?.item;
    final base =
        known ??
        MediaItem(
          id: 'render-$n',
          backend: MediaBackend.jellyfin,
          kind: kind,
          title: title,
          year: year,
          serverId: 'zolder',
          serverName: 'zolder',
        );
    return base.copyWith(thumbPath: 'artwork/${n++}');
  }

  AssistantRequestOption option(Map<String, Object?> card) => AssistantRequestOption(
    seerrId: '${card['kind'] == 'movie' ? 'movie' : 'tv'}:${n++}',
    title: '${card['title'] ?? ''}',
    year: card['year'] as int?,
    kind: '${card['kind'] ?? 'movie'}',
    posterUrl: '',
    overview: '',
    status: '${card['status'] ?? 'not_requested'}',
  );

  final displays = <AssistantDisplay>[];
  for (final d in _maps(turn['displays'])) {
    final cards = _maps(d['cards']);
    switch (d['type']) {
      case 'grid':
        displays.add(AssistantMediaGrid([for (final card in cards) (item: item(card), group: null)]));
      case 'matches':
        displays.add(
          AssistantTitleMatches(ctx, [
            for (final (i, card) in cards.indexed)
              AssistantTitleMatch(
                matchId: 'm$i',
                title: '${card['title'] ?? ''}',
                year: card['year'] as int?,
                kind: '${card['kind'] ?? 'movie'}',
                confidence: 'high',
                targets: [
                  if (card['actionable'] == true && card['requestable'] != true)
                    (serverId: ServerId('zolder'), serverName: 'zolder', item: item(card)),
                ],
                request: card['requestable'] == true ? option(card) : null,
              ),
          ]),
        );
      case 'request_options':
        displays.add(AssistantRequestOptions(ctx, [for (final card in cards) option(card)]));
      case 'clarification':
        displays.add(
          AssistantClarification(
            question: '${d['question'] ?? ''}',
            options: [for (final o in d['options'] as List? ?? const []) '$o'],
          ),
        );
      default:
        skipped.add('${d['type']}');
    }
  }
  final end = AssistantRunEnd.values.asNameMap()[turn['end']] ?? AssistantRunEnd.providerError;
  c
    ..prompt = turn['prompt'] as String?
    ..answer = _answerOf(turn)
    ..displays = displays
    ..actions = [
      for (final a in _maps(turn['actions']))
        if (AssistantActionKind.values.asNameMap()[a['kind']] case final kind?)
          AssistantActionRecord(kind: kind, serverName: '${a['server'] ?? ''}', subject: '${a['subject'] ?? ''}'),
    ]
    ..ageFilterNotice = turn['age_filter_notice'] == true
    ..lastEnd = end
    ..resultIsError = end != AssistantRunEnd.answered
    ..state = AssistantSurfaceState.result;
  return skipped;
}

/// What one surface showed for a turn.
class EvalRendered {
  EvalRendered(this.surface);
  final EvalSurface surface;
  final violations = <String>[];

  /// The first sentence of the answer as drawn, or null when no answer text
  /// was found on the surface.
  String? headline;
}

const _tvChannel = MethodChannel('test_big_p_eval_render_entry');

Widget _appleTvScale(Widget child) => LayoutBuilder(
  builder: (context, box) {
    const scale = 1.85;
    final size = Size(box.maxWidth / scale, box.maxHeight / scale);
    final q = MediaQuery.of(context);
    return Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: q.copyWith(size: size, devicePixelRatio: q.devicePixelRatio * scale),
            child: child,
          ),
        ),
      ),
    );
  },
);

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _first(String text) => (RegExp(r'^.*?[.!?](?=\s|$)', dotAll: true).firstMatch(text.trim())?[0] ?? text).trim();
String _key(String title) => title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
String _cut(String s) => s.length > 60 ? '${s.substring(0, 60)}…' : s;

/// Draws [turn] on [surface], runs the per-surface checks and, with [png],
/// saves what was drawn. Leaves the tester with an empty tree.
Future<EvalRendered> evalRenderTurn(
  WidgetTester tester,
  Map<String, Object?> turn,
  EvalSurface surface, {
  File? png,
}) async {
  final out = EvalRendered(surface);
  final tv = surface == EvalSurface.tv;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final c = FakeAssistantController();
  BigPSuggestions.install(c, BigPSuggestions(random: Random(1)));
  final session = BigPMobileSession(c);
  final presses = StreamController<void>.broadcast();
  final boundary = GlobalKey();
  final errors = <String>[];
  final onError = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
  tester.view.physicalSize = surface.size * surface.pixelRatio;
  tester.view.devicePixelRatio = surface.pixelRatio;
  if (tv) {
    TvDetectionService.debugSetAppleTVOverride(true);
    messenger.setMockMethodCallHandler(_tvChannel, (call) async => <String, dynamic>{'text': '', 'submitted': false});
  }
  try {
    final entry = AppleTvNativeTextEntry(channel: _tvChannel);
    final Widget body = tv
        ? _appleTvScale(
            InputModeTracker(
              child: OverlaySheetHost(
                child: Scaffold(
                  backgroundColor: Colors.black,
                  body: TvAssistantSummonHost(
                    longPresses: presses.stream,
                    speech: SpeechSearchService(textEntry: entry),
                    textEntry: entry,
                    screenContext: () => null,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          )
        : const Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.black),
              BigPMobileHost(),
            ],
          );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<AssistantController>.value(value: c),
              ChangeNotifierProvider<BigPMobileSession>.value(value: session),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true, viewPadding: surface.safe, padding: surface.safe),
                  child: body,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (png != null) {
      // Big P's own artwork, or the shot shows him as an empty box.
      await tester.runAsync(() async {
        final ctx = tester.element(find.byKey(boundary));
        for (final a in [
          for (final p in kBigPPoses) bigPPoseAsset(p),
          for (final m in kBigPMouths) bigPAsset('mouth-$m'),
          for (final a in const ['brow-l', 'brow-r', 'aim-arm', 'wave-arm']) bigPAsset(a),
          PleyaWordmark.markAsset,
        ]) {
          await precacheImage(AssetImage(a), ctx);
        }
      });
    }
    await _frames(tester, 2);
    tv ? presses.add(null) : session.summon();
    await _frames(tester, 8);
    final skipped = evalApplyTurn(c, turn);
    c.emit();
    await _frames(tester, 12);
    await tester.pump(const Duration(milliseconds: 1200));

    final cards = evalTurnCards(turn);
    final cardFinder = find.byWidgetPredicate((w) => w is BigPMatchCard || w is BigPOptionCard);
    // Every text line on screen, with whether it stands on a title card.
    final texts = [
      for (final e in find.byType(RichText).evaluate())
        (
          text: (e.widget as RichText).text.toPlainText(),
          paragraph: e.renderObject! as RenderParagraph,
          card: e.findAncestorWidgetOfExactType<BigPMatchCard>() ?? e.findAncestorWidgetOfExactType<BigPOptionCard>(),
        ),
    ];

    out.violations.addAll([for (final d in skipped) 'unrendered: display type $d is not rebuilt']);

    // overflow
    out.violations.addAll([for (final e in errors) 'overflow: ${_cut(e)}']);

    // markup: anything on screen but the user's own question.
    final markup = RegExp(r'\*\*|`|<tool|\{"|function_call|^\s*#', multiLine: true);
    for (final t in texts) {
      if (t.text != c.prompt && markup.hasMatch(t.text)) out.violations.add('markup: "${_cut(t.text)}"');
    }

    // truncated-title: the card's title line did not fit its lines.
    for (final t in texts) {
      final title = switch (t.card) {
        BigPMatchCard(:final match) => match.title,
        BigPOptionCard(:final option) => option.title,
        _ => null,
      };
      if (title != null && title.isNotEmpty && t.text.startsWith(title) && t.paragraph.didExceedMaxLines) {
        out.violations.add('truncated-title: "${_cut(title)}"');
      }
    }

    // The answer as drawn: the lines outside the cards that are a piece of
    // the answer the surface computes (assistantCardsLead above title cards,
    // assistantHeadline otherwise, as both conversations do).
    final shown = c.displays.where((d) => !bigPDisplayIsEmpty(d)).toList();
    final above =
        bigPHasChoices(shown) &&
        shown.any((d) => d is AssistantTitleMatches || d is AssistantMediaGrid || d is AssistantRequestOptions);
    final headline = assistantHeadline(c);
    final answer = above && headline.isNotEmpty ? assistantCardsLead(c) : headline;
    final drawn = [
      for (final t in texts)
        if (t.card == null && t.text.trim().length > 1 && t.text != c.prompt && answer.contains(t.text.trim()))
          t.text.trim(),
    ];
    if (drawn.isNotEmpty) out.headline = _first(drawn.first);

    // text-names-uncarded: a «title» of the answer that is drawn as text
    // while no card carries it.
    if (cards.isNotEmpty) {
      final onCards = {for (final card in cards) _key(card.title)};
      for (final m in RegExp('«([^»\n]+)»').allMatches(_answerOf(turn))) {
        final name = m[1]!.trim();
        if (!onCards.contains(_key(name)) && drawn.any((line) => line.contains(name))) {
          out.violations.add('text-names-uncarded: «$name»');
        }
      }
    }

    // tv-min-cards: with five or more cards, five stand whole inside the
    // list's viewport when the result opens.
    if (tv && cards.length >= 5) {
      // Corners through localToGlobal, so the 1.85 paint scale is in both.
      Rect global(RenderBox box) =>
          Rect.fromPoints(box.localToGlobal(Offset.zero), box.localToGlobal(box.size.bottomRight(Offset.zero)));
      final screen = Offset.zero & surface.size;
      var visible = 0;
      for (final e in cardFinder.evaluate()) {
        final box = e.renderObject! as RenderBox;
        final Object? viewport = RenderAbstractViewport.maybeOf(box);
        final clip = (viewport is RenderBox ? global(viewport).intersect(screen) : screen).inflate(1);
        final rect = global(box);
        if (clip.contains(rect.topLeft) && clip.contains(rect.bottomRight)) visible++;
      }
      if (visible < 5) out.violations.add('tv-min-cards: $visible of ${cards.length} cards in view');
    }

    if (png != null) {
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: surface.pixelRatio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        png.parent.createSync(recursive: true);
        png.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
  } finally {
    FlutterError.onError = onError;
    tester.view.reset();
    if (tv) {
      TvDetectionService.debugSetAppleTVOverride(null);
      messenger.setMockMethodCallHandler(_tvChannel, null);
      NativeInputSession.debugReset();
    }
    session.dispose();
    c.dispose();
    await presses.close();
  }
  return out;
}

/// Draws [turn] on every surface and returns all violations, each prefixed
/// with its check id and, for a per-surface check, followed by `@surface`.
/// [png] names the file per surface, or null for no shots.
Future<List<String>> evalRenderViolations(
  WidgetTester tester,
  Map<String, Object?> turn, {
  File? Function(EvalSurface surface)? png,
}) async {
  final cards = evalTurnCards(turn);
  final seen = <EvalCardRef>{};
  final violations = <String>[
    // duplicate-card: from the record itself, the same on every surface.
    for (final card in cards)
      if (!seen.add((title: _key(card.title), year: card.year))) 'duplicate-card: ${card.title} (${card.year})',
  ];
  final shots = <EvalSurface, EvalRendered>{};
  for (final surface in EvalSurface.values) {
    final r = shots[surface] = await evalRenderTurn(tester, turn, surface, png: png?.call(surface));
    violations.addAll({for (final v in r.violations) '$v @${surface.name}'});
  }
  // headline-differs: the first sentence of the answer text found on the
  // phone against the one found on TV. The text is located as the first line
  // outside the cards that is part of the label functions' answer
  // (big_p_labels.dart), not by a key: the phone's lead has none.
  final phone = shots[EvalSurface.phone]!.headline;
  final tv = shots[EvalSurface.tv]!.headline;
  if (phone != tv) violations.add('headline-differs: phone "${_cut(phone ?? '-')}" tv "${_cut(tv ?? '-')}"');
  return violations;
}

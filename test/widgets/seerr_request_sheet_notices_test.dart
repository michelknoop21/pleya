/// Where the messages of the request form stand, and what they leave for the
/// choices: a reason beside a button that cannot send, and an answer of the
/// server that takes its own height and no more.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/widgets/seerr_request_form_parts.dart';
import 'package:pleya/widgets/seerr_request_sheet.dart';

import '../test_helpers/seerr_fake.dart';

const _movie = SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge');
const _show = SeerrMedia(tmdbId: 1399, mediaType: 'tv', title: 'Wadlopers');
const _fourKTv = SeerrPermission.request | SeerrPermission.request4kTv;

Finder _button(String instance) => seerrNode(AutomationIds.requestsFormButton, instance);
Finder _notice(String kind) => seerrNode(AutomationIds.requestsFormNotice, kind);
Finder _option(String instance) => seerrNode(AutomationIds.requestsFormOption, instance);

Map _form(WidgetTester tester) =>
    tester.widget<AutomationNode>(seerrNode(AutomationIds.requestsForm, 'create')).state!() as Map;

/// Whether a match of [finder] lies whole inside every scroll area it is in.
/// Not `hitTestable`: after a key press the app is in remote mode, and that
/// takes pointer hits away from everything.
bool _inView(WidgetTester tester, Finder finder) {
  for (final element in finder.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    var inside = true;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Scrollable) {
        final port = tester.getRect(find.byElementPredicate((e) => e == ancestor)).inflate(1);
        inside = inside && port.contains(rect.topLeft) && port.contains(rect.bottomRight);
      }
      return true;
    });
    if (inside) return true;
  }
  return false;
}

/// Whether the remote is on the pinned messages.
bool _onMessages() => FocusManager.instance.primaryFocus?.debugLabel == 'requests.form.notices';

/// The scroll view of the pinned messages, not the list of choices.
Finder get _pinned => find.byType(SingleChildScrollView);

/// How far the list of choices can still scroll: zero when it shows all it has.
double _listScrolls(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)))
    .position
    .maxScrollExtent;

void main() {
  late FakeSeerr fake;

  void show(int seasons) => fake.on('GET /tv/1399', {
    'id': 1399,
    'name': 'Wadlopers',
    'seasons': [
      for (var n = 1; n <= seasons; n++) {'seasonNumber': n, 'episodeCount': 8},
    ],
  });

  void instances({bool hdDefault = true, bool fourK = false}) {
    for (final service in ['radarr', 'sonarr']) {
      fake.on('GET /service/$service', [
        {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': hdDefault},
        if (fourK) {'id': 2, 'name': '4K', 'is4k': true, 'isDefault': true},
      ]);
    }
  }

  void quota({required bool reached}) => fake.on('GET /user/7/quota', {
    'movie': {'limit': 5, 'remaining': reached ? 0 : 3},
    'tv': {'limit': 5, 'remaining': reached ? 0 : 3},
  });

  Future<void> open(
    WidgetTester tester,
    SeerrMedia media, {
    required Size size,
    double textScale = 1.0,
    int permissions = seerrPermRequest,
    bool initialIs4k = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = await seerrProvider(fake, permissions: permissions);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: SeerrRequestSheet(media: media, initialIs4k: initialIs4k),
        ),
      ),
    );
    await seerrSettle(tester);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await seerrSettle(tester);
  }

  setUp(() {
    fake = FakeSeerr();
    quota(reached: false);
    instances();
  });

  for (final (name, size) in [('television', const Size(1920, 1080)), ('phone', const Size(375, 667))]) {
    testWidgets('$name: 4K switched off under a long season list leaves the reason in view beside the button', (
      tester,
    ) async {
      show(14);
      instances(hdDefault: false, fourK: true);
      await open(tester, _show, size: size, permissions: _fourKTv, initialIs4k: true);
      expect(_notice('route'), findsNothing, reason: '4K has a default instance');

      // UP lands on a row in view; the switch is the last row of the list.
      await press(tester, LogicalKeyboardKey.arrowUp);
      bool onSwitch() => _option('fourK').evaluate().isNotEmpty && seerrHasFocus(tester, _option('fourK'));
      for (var i = 0; i < 20 && !onSwitch(); i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(onSwitch(), isTrue, reason: 'with the list scrolled to its end');
      await press(tester, LogicalKeyboardKey.select);

      expect(_form(tester), containsPair('is4k', false));
      expect(_form(tester), containsPair('canSubmit', false));
      expect(seerrHasFocus(tester, _option('fourK')), isTrue);
      expect(_inView(tester, find.text(t.seerr.noDefaultServerTitle)), isTrue);
      expect(_inView(tester, _notice('route')), isFalse, reason: 'the notice itself opens the list, out of view');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a refusal under twenty seasons takes its own height and leaves the list the rest', (tester) async {
    show(20);
    fake.on('POST /request', {'message': 'no'}, 409);
    await open(tester, _show, size: const Size(1920, 1080));
    final before = tester.getSize(find.byType(ListView)).height;

    await press(tester, LogicalKeyboardKey.select);
    expect(_notice('refused'), findsOneWidget);
    expect(_inView(tester, find.text(t.seerr.requestRefusedDuplicate)), isTrue);

    final notice = tester.getSize(_pinned).height;
    final after = tester.getSize(find.byType(ListView)).height;
    expect(notice, lessThan(160));
    expect(after, closeTo(before - notice, 1), reason: 'the list gives up what the message needs, not half');
    expect(_onMessages(), isFalse, reason: 'a message that fits is not a stop for the remote');
  });

  testWidgets('messages that outgrow their share are read with the remote, and the remote moves on after them', (
    tester,
  ) async {
    fake
      ..fail('POST /request')
      ..fail('GET /movie/603');
    await open(tester, _movie, size: const Size(320, 568), textScale: 1.3);
    await tester.tap(find.text(t.seerr.requestMovie));
    await seerrSettle(tester);
    await tester.tap(find.text(t.seerr.checkStatus));
    await seerrSettle(tester);
    expect(tester.takeException(), isNull);
    expect(_notice('uncertain'), findsOneWidget);
    expect(_notice('error'), findsOneWidget);

    final position = tester
        .state<ScrollableState>(find.descendant(of: _pinned, matching: find.byType(Scrollable)))
        .position;
    expect(position.maxScrollExtent, greaterThan(0), reason: 'two messages do not fit the share on this screen');
    final room = 568 * 0.72 - tester.getSize(find.byType(SeerrFormButtons)).height;
    expect(tester.getSize(_pinned).height, closeTo(room / 2, 1), reason: 'half of what the buttons leave');
    expect(_inView(tester, find.text(t.seerr.statusCheckFailed)), isFalse);

    // The two buttons stand above each other on a screen this narrow.
    for (var i = 0; i < 2 && !_onMessages(); i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_onMessages(), isTrue);

    var presses = 0;
    while (_onMessages() && presses++ < 20) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(position.pixels, position.maxScrollExtent);
    expect(_inView(tester, find.text(t.seerr.statusCheckFailed)), isTrue);
    expect(seerrHasFocus(tester, _button('close')), isTrue, reason: 'past the end DOWN is a move again');
  });

  group('an answer of the server on a small screen', () {
    tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

    /// The buttons are whole on the screen, and the choices keep at least as
    /// much as the message, unless they show all they have in less.
    void expectRoomForAll(WidgetTester tester, Size size) {
      expect(tester.takeException(), isNull);
      final list = tester.getSize(find.byType(ListView)).height;
      final message = tester.getSize(_pinned).height;
      // 43 on the tightest of these: 568x320 at 1.3 in Dutch, where the two
      // buttons stand above each other.
      expect(list, greaterThan(40));
      if (_listScrolls(tester) > 0) expect(list, greaterThanOrEqualTo(message - 1));
      final buttons = tester.getRect(find.byType(SeerrFormButtons));
      expect(buttons.top, greaterThanOrEqualTo(0));
      expect(buttons.bottom, lessThanOrEqualTo(size.height));
      expect(find.descendant(of: _button('close'), matching: find.byType(TextButton)).hitTestable(), findsOneWidget);
    }

    for (final locale in [AppLocale.nl, AppLocale.en]) {
      for (final portrait in [const Size(320, 568), const Size(375, 667)]) {
        for (final size in [portrait, portrait.flipped]) {
          for (final scale in [1.0, 1.3]) {
            final name = '${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()} at $scale';

            testWidgets('$name: a refused series leaves the seasons and both buttons in reach', (tester) async {
              await tester.runAsync(() => LocaleSettings.setLocale(locale));
              show(6);
              fake.on('POST /request', {'message': 'no'}, 409);
              await open(tester, _show, size: size, textScale: scale);
              await tester.tap(find.byType(FilledButton));
              await seerrSettle(tester);

              expect(_notice('refused'), findsOneWidget);
              expectRoomForAll(tester, size);
              expect(
                find.descendant(of: _button('submit'), matching: find.byType(FilledButton)).hitTestable(),
                findsOneWidget,
              );
            });

            testWidgets('$name: a film with an unknown outcome keeps its buttons, before and after a failed check', (
              tester,
            ) async {
              await tester.runAsync(() => LocaleSettings.setLocale(locale));
              fake
                ..fail('POST /request')
                ..fail('GET /movie/603');
              await open(tester, _movie, size: size, textScale: scale);
              await tester.tap(find.byType(FilledButton));
              await seerrSettle(tester);

              expect(_notice('uncertain'), findsOneWidget);
              expectRoomForAll(tester, size);

              await tester.tap(find.descendant(of: _button('status'), matching: find.byType(FilledButton)));
              await seerrSettle(tester);

              expect(_notice('error'), findsOneWidget);
              expectRoomForAll(tester, size);
            });
          }
        }
      }
    }
  });

  group('a reached limit and no default instance', () {
    tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

    // The line takes two lines and no more. Measured with the font of the
    // widget tests, in which every character is as wide as it is high, the
    // second reason does not begin inside them on these.
    final secondCutOff = {
      (AppLocale.nl, const Size(320, 568), 1.0),
      (AppLocale.nl, const Size(320, 568), 1.3),
      (AppLocale.nl, const Size(375, 667), 1.3),
      (AppLocale.en, const Size(320, 568), 1.3),
    };

    for (final locale in [AppLocale.nl, AppLocale.en]) {
      for (final scale in [1.0, 1.3]) {
        for (final size in [const Size(320, 568), const Size(375, 667), const Size(568, 320), const Size(667, 375)]) {
          final cutOff = secondCutOff.contains((locale, size, scale));
          // 568x320 at 1.3 is too short for the line: the buttons wrap and
          // the choices kept 36 px in Dutch where main kept 86. The reasons
          // stand in the messages of the list there.
          final noLine = size == const Size(568, 320) && scale == 1.3;
          testWidgets(
            noLine
                ? '${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()} at $scale: no line beside '
                      'the button, both reasons stay messages in the list'
                : '${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()} at $scale: the line beside '
                      'the button holds both reasons, and '
                      "${cutOff ? 'is cut before the second' : 'draws the start of the second'}",
            (tester) async {
              await tester.runAsync(() => LocaleSettings.setLocale(locale));
              quota(reached: true);
              instances(hdDefault: false);
              await open(tester, _movie, size: size, textScale: scale);

              expect(tester.takeException(), isNull);
              if (noLine) {
                expect(seerrFormHint('${t.seerr.noDefaultServerTitle} · ${t.seerr.quotaReached}'), findsNothing);
                expect(_notice('quota'), findsOneWidget);
                expect(_notice('route'), findsOneWidget);
                return;
              }
              // The notice with the limit is under the fold on the smallest of these.
              final line = seerrFormHint('${t.seerr.noDefaultServerTitle} · ${t.seerr.quotaReached}');
              expect(line.hitTestable(), findsOneWidget);
              final drawn = tester.renderObject<RenderParagraph>(
                find.descendant(of: line, matching: find.byType(RichText)),
              );
              final second = t.seerr.noDefaultServerTitle.length + 3;
              expect(drawn.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: 1)), isNotEmpty);
              expect(
                drawn.getBoxesForSelection(TextSelection(baseOffset: second, extentOffset: second + 1)),
                cutOff ? isEmpty : isNotEmpty,
              );
              expect(
                find.descendant(of: _button('close'), matching: find.byType(TextButton)).hitTestable(),
                findsOneWidget,
              );
            },
          );
        }
      }
    }
  });
}

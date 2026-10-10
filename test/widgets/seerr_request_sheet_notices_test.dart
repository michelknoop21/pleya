/// Where the messages of the request form stand, and what they leave for the
/// choices: a reason beside a button that cannot send, and an answer of the
/// server that takes its own height and no more.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
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
    expect(tester.getSize(_pinned).height, closeTo(568 * 0.72 * 0.4, 1));
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

  for (final scale in [1.0, 1.3]) {
    for (final size in [const Size(320, 568), const Size(375, 667), const Size(568, 320), const Size(667, 375)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} at $scale: a reached limit and no default instance '
          'are both named beside the button', (tester) async {
        quota(reached: true);
        instances(hdDefault: false);
        await open(tester, _movie, size: size, textScale: scale);

        expect(tester.takeException(), isNull);
        // The notice with the limit is under the fold on the smallest of these.
        final both = find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.startsWith(t.seerr.noDefaultServerTitle) ?? false) &&
              w.data!.contains(t.seerr.quotaReached),
        );
        expect(both.hitTestable(), findsOneWidget);
        expect(find.descendant(of: _button('close'), matching: find.byType(TextButton)).hitTestable(), findsOneWidget);
      });
    }
  }
}

// Every panel of mockup 43 as the app draws it, for the visual review.
// Skipped unless MEMORY_SHOT_DIR is set:
//   MEMORY_SHOT_DIR=/tmp/shots flutter test test/screens/settings/memory/memory_screen_shots_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import '../../../test_helpers/golden.dart';
import 'memory_finders.dart';
import 'memory_screen_support.dart';

final _dir = Platform.environment['MEMORY_SHOT_DIR'];

/// Never answers, so the screen stays in the loading state of 43 B.
class _NeverModel extends ScriptedModel {
  _NeverModel() : super(const []);

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) => Completer<AssistantReply>().future;
}

typedef _Setup = Future<void> Function(WidgetTester tester, MemoryScreenHarness h);

class _Format {
  const _Format(this.tag, this.size, {this.tv = false, this.light = false, this.textScale = 1});

  final String tag;
  final Size size;
  final bool tv;
  final bool light;
  final double textScale;
}

const _phone = _Format('iphone-402', phoneSize);
const _se = _Format('iphone-se', phoneSeSize);
const _pad = _Format('ipad', tabletSize);
const _tv = _Format('tv', tvSize, tv: true);
const _big = _Format('iphone-402-tekst-2x', phoneSize, textScale: 2);
const _light = _Format('iphone-402-licht', phoneSize, light: true);
const _padLight = _Format('ipad-licht', tabletSize, light: true);

Future<void> _withOverview(WidgetTester tester, MemoryScreenHarness h) async {
  await tester.runAsync(h.seed);
  h.kidsAges = const [8, 11];
  h.overviewModel = ScriptedModel([say(mockupOverviewReply()), say(mockupOverviewReply())]);
}

/// The replace proposal of 43 H, from a typed sentence in the field.
Future<void> _replaceScript(WidgetTester tester, MemoryScreenHarness h) async {
  final facts = await tester.runAsync(() => h.service.list());
  final friday = facts!.firstWhere((fact) => fact.value.contains('vrijdagavond'));
  h.hostModel = ScriptedModel([
    callTool('remember_fact', {
      'value': 'Kijkt op zaterdagavond met het gezin',
      'category': 'household',
      'replaces': friday.ref,
    }),
    say('Dat pas ik aan als je het goed vindt.'),
  ]);
}

void main() {
  setUpAll(() async {
    if (_dir == null) return;
    await loadAppFontsForGoldens();
  });

  void shot(
    String name,
    _Format format, {
    required _Setup setup,
    Future<void> Function(WidgetTester tester, MemoryScreenHarness h)? act,
    bool list = false,
  }) {
    testWidgets('${format.tag} $name', skip: _dir == null, (tester) async {
      await tester.runAsync(useDutch);
      final h = MemoryScreenHarness();
      await setup(tester, h);
      final boundary = await pumpMemoryApp(
        tester,
        list ? _ListHost(h) : AssistantMemoryScreen(model: h.model),
        size: format.size,
        tv: format.tv,
        light: format.light,
        textScale: format.textScale,
      );
      if (list) {
        await tester.runAsync(h.model.load);
        await settle(tester);
      }
      if (act != null) {
        await act(tester, h);
        await settle(tester);
      }
      await writeShot(tester, boundary, _dir!, '${format.tag}--$name', ratio: format.tv ? tvRatio : 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.dispose);
    });
  }

  Future<void> openMenu(WidgetTester tester, MemoryScreenHarness h) async {
    await tapOn(tester, memoryAction('menu'));
    await settle(tester);
  }

  Future<void> scrollDown(WidgetTester tester, MemoryScreenHarness h) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await settle(tester);
  }

  Future<void> askReplace(WidgetTester tester, MemoryScreenHarness h) async {
    await _replaceScript(tester, h);
    await tester.enterText(find.byType(EditableText).first, 'We kijken tegenwoordig op zaterdag met het gezin');
    await tester.pump();
    await tapOn(tester, memoryAction('send'));
    await settle(tester, 10);
  }

  Future<void> filterDislike(WidgetTester tester, MemoryScreenHarness h) async {
    await tapOn(tester, memoryId(AutomationIds.settingsMemoryChip, 'dislike'));
    await settle(tester);
  }

  for (final f in [_phone, _se, _big, _light]) {
    shot('43-a-overzicht', f, setup: _withOverview);
    shot('43-a-overzicht-onder', f, setup: _withOverview, act: scrollDown);
    shot('43-c-menu', f, setup: _withOverview, act: openMenu);
    shot('43-d-beheren', f, setup: _withOverview, list: true, act: filterDislike);
    shot(
      '43-e-bewerken',
      f,
      setup: _withOverview,
      list: true,
      act: (tester, h) async {
        await filterDislike(tester, h);
        await tapOn(tester, memoryId(AutomationIds.settingsMemoryFact, '1'));
        await settle(tester);
      },
    );
    shot(
      '43-f-toevoegen',
      f,
      setup: _withOverview,
      list: true,
      act: (tester, h) async {
        await tester.dragUntilVisible(memoryAction('add'), find.byType(ListView).first, const Offset(0, -120));
        await tapOn(tester, memoryAction('add'));
        await settle(tester);
      },
    );
    shot(
      '43-g-wissen',
      f,
      setup: _withOverview,
      act: (tester, h) async {
        await openMenu(tester, h);
        await tapOn(tester, memoryAction('clear'));
        await settle(tester);
      },
    );
    shot('43-h-bijwerken', f, setup: _withOverview, act: askReplace);
  }

  for (final f in [_phone, _se, _pad, _tv, _light]) {
    shot(
      '43-b-genereren',
      f,
      setup: (tester, h) async {
        await tester.runAsync(h.seed);
        h.overviewModel = _NeverModel();
      },
    );
    shot(
      '43-i-uit',
      f,
      setup: (tester, h) async {
        await tester.runAsync(h.seed);
        h.enabledStore.on = false;
      },
    );
    shot('43-j-leeg', f, setup: (tester, h) async {});
    shot(
      'terugval-lijst',
      f,
      setup: (tester, h) async {
        await tester.runAsync(h.seed);
        h.config = null;
      },
    );
    shot(
      'kindstand',
      f,
      setup: (tester, h) async {
        await tester.runAsync(h.seed);
        h.kids = true;
      },
    );
  }

  shot('leesfout', _phone, setup: (tester, h) async {});

  for (final f in [_pad, _padLight]) {
    shot('43-l-ipad', f, setup: _withOverview);
    shot('43-l-ipad-bijwerken', f, setup: _withOverview, act: askReplace);
    shot('43-d-beheren', f, setup: _withOverview, list: true, act: filterDislike);
  }

  // A key first: the white focus ring shows in remote mode only.
  shot('43-m-tvos', _tv, setup: _withOverview, act: (tester, h) => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight));
  shot(
    '43-m-tvos-kaart',
    _tv,
    setup: _withOverview,
    act: (tester, h) async {
      await _replaceScript(tester, h);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.runAsync(() => h.host.ask('We kijken tegenwoordig op zaterdag met het gezin'));
      await settle(tester, 10);
    },
  );
  shot(
    '43-m-tvos-wissen',
    _tv,
    setup: _withOverview,
    act: (tester, h) async {
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await settle(tester);
    },
  );
  shot('43-d-beheren-tv', _tv, setup: _withOverview, list: true);
  shot(
    '43-e-bewerken-tv',
    _tv,
    setup: _withOverview,
    list: true,
    act: (tester, h) async {
      for (final key in [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.select]) {
        await tester.sendKeyEvent(key);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await settle(tester);
    },
  );
}

class _ListHost extends StatelessWidget {
  const _ListHost(this.h);

  final MemoryScreenHarness h;

  @override
  Widget build(BuildContext context) => MemoryListScreen(model: h.model);
}

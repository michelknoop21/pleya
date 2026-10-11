// Every panel of mockup 43 as the app draws it, for the visual review. The
// TV shots stand under a band the height of the shell's top navigation.
// Skipped unless MEMORY_SHOT_DIR is set:
//   MEMORY_SHOT_DIR=/tmp/shots flutter test test/screens/settings/memory/memory_screen_shots_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
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
const _padMini = _Format('ipad-mini-744', Size(744, 1133));
const _seBig = _Format('iphone-se-tekst-2x', phoneSeSize, textScale: 2);

/// The height the system keyboard of an iPhone SE takes, in points.
const _seKeyboard = 260.0;

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
    bool unreadable = false,
    bool english = false,
    String? mustShow,
  }) {
    testWidgets('${format.tag} $name', skip: _dir == null, (tester) async {
      await tester.runAsync(useDutch);
      if (english) await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.en));
      final h = MemoryScreenHarness(unreadable: unreadable);
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
      // A shot that does not show the state it is named after proves nothing.
      if (mustShow != null) expect(find.text(mustShow), findsWidgets, reason: '$name shows "$mustShow"');
      expect(tester.takeException(), isNull);
      await writeShot(tester, boundary, _dir!, '${format.tag}--$name', ratio: format.tv ? tvRatio : 2);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.dispose);
    });
  }

  Future<void> openMenu(WidgetTester tester, MemoryScreenHarness h) async {
    await tapOn(tester, memoryAction('menu'));
    await settle(tester);
  }

  /// To the end of the page: the line under the overview.
  Future<void> scrollDown(WidgetTester tester, MemoryScreenHarness h) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
    await settle(tester);
  }

  Future<void> askReplace(WidgetTester tester, MemoryScreenHarness h) async {
    await _replaceScript(tester, h);
    await tester.enterText(find.byType(EditableText).first, 'We kijken tegenwoordig op zaterdag met het gezin');
    await tester.pump();
    await tapOn(tester, memoryAction('send'));
    await settle(tester, 10);
  }

  /// Chooses the category without moving the chip row or the page where the
  /// chip is in view already, as a tap on a device does.
  Future<void> filterDislike(WidgetTester tester, MemoryScreenHarness h) async {
    final chip = memoryId(AutomationIds.settingsMemoryChip, 'dislike');
    final rect = tester.getRect(chip);
    if (rect.left >= 0 && rect.right <= tester.view.physicalSize.width / tester.view.devicePixelRatio) {
      await tester.tap(chip);
    } else {
      await tapOn(tester, chip);
    }
    await settle(tester);
  }

  Future<void> openAdd(WidgetTester tester, MemoryScreenHarness h) async {
    await tester.dragUntilVisible(memoryAction('add'), find.byType(ListView).first, const Offset(0, -120));
    await tapOn(tester, memoryAction('add'));
    await settle(tester);
  }

  Future<void> openEdit(WidgetTester tester, MemoryScreenHarness h) async {
    await filterDislike(tester, h);
    await tapOn(tester, memoryId(AutomationIds.settingsMemoryFact, '1'));
    await settle(tester);
  }

  /// The system keyboard of an iPhone SE comes up under the open sheet.
  Future<void> keyboardUp(WidgetTester tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: _seKeyboard * 2);
    await settle(tester);
  }

  for (final f in [_phone, _se, _big, _light]) {
    shot('43-a-overzicht', f, setup: _withOverview);
    shot('43-a-overzicht-onder', f, setup: _withOverview, act: scrollDown);
    shot('43-c-menu', f, setup: _withOverview, act: openMenu);
    shot('43-d-beheren', f, setup: _withOverview, list: true, act: filterDislike);
    shot('43-e-bewerken', f, setup: _withOverview, list: true, act: openEdit);
    shot('43-f-toevoegen', f, setup: _withOverview, list: true, act: openAdd);
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

  for (final f in [_phone, _se, _pad, _tv, _light, _big]) {
    // The dots of 43 B have no text to scale.
    if (f != _big) {
      shot(
        '43-b-genereren',
        f,
        setup: (tester, h) async {
          await tester.runAsync(h.seed);
          h.overviewModel = _NeverModel();
        },
      );
    }
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

  // The reading error, raised for real: the service cannot list its facts.
  for (final f in [_phone, _se, _pad, _tv, _big]) {
    shot(
      'leesfout',
      f,
      unreadable: true,
      setup: (tester, h) async {},
      mustShow: 'De herinneringen zijn niet te lezen.',
    );
  }
  for (final f in [_phone, _tv]) {
    shot(
      'leesfout-lijst',
      f,
      unreadable: true,
      list: true,
      setup: (tester, h) async {},
      mustShow: 'De herinneringen zijn niet te lezen.',
    );
  }

  // iPhone SE with the keyboard open: the lower 260 pt of the shot is where
  // the keyboard stands, and the buttons of the sheet stand above it.
  for (final f in [_se, _seBig]) {
    shot(
      '43-f-toevoegen-toetsenbord',
      f,
      setup: _withOverview,
      list: true,
      act: (tester, h) async {
        await openAdd(tester, h);
        await keyboardUp(tester);
      },
    );
  }
  shot(
    '43-e-bewerken-toetsenbord',
    _se,
    setup: _withOverview,
    list: true,
    act: (tester, h) async {
      await openEdit(tester, h);
      await keyboardUp(tester);
    },
  );
  shot('43-e-bewerken', _seBig, setup: _withOverview, list: true, act: openEdit);
  shot(
    '43-g-wissen',
    _seBig,
    setup: _withOverview,
    act: (tester, h) async {
      await openMenu(tester, h);
      await tapOn(tester, memoryAction('clear'));
      await settle(tester);
    },
  );

  // The sheets and the dialog on a tablet, and the narrowest tablet.
  shot('43-e-bewerken', _pad, setup: _withOverview, list: true, act: openEdit);
  shot('43-f-toevoegen', _pad, setup: _withOverview, list: true, act: openAdd);
  shot(
    '43-g-wissen',
    _pad,
    setup: _withOverview,
    act: (tester, h) async {
      await tapOn(tester, memoryAction('clear'));
      await settle(tester);
    },
  );
  shot('43-l-ipad', _padMini, setup: _withOverview);
  shot('43-l-ipad-bijwerken', _padMini, setup: _withOverview, act: askReplace);

  // English: the longest labels of the screens.
  shot('en-43-a-overview', _phone, setup: _withOverview, english: true, mustShow: 'Memory');
  shot('en-43-h-update', _se, setup: _withOverview, english: true, act: askReplace);
  shot('en-43-e-edit', _se, setup: _withOverview, english: true, list: true, act: openEdit);
  shot('en-43-c-menu', _phone, setup: _withOverview, english: true, act: openMenu);
  shot(
    'en-43-m-tvos',
    _tv,
    setup: _withOverview,
    english: true,
    act: (tester, h) => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
  );
  shot(
    'en-43-e-edit-tv',
    _tv,
    setup: _withOverview,
    english: true,
    list: true,
    act: (tester, h) async {
      for (final key in [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.select]) {
        await tester.sendKeyEvent(key);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await settle(tester);
    },
  );

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
  // A long answer above the tiles: bounded, with the tile still in view.
  shot(
    '43-m-tvos-lang-antwoord',
    _tv,
    setup: _withOverview,
    act: (tester, h) async {
      final long = List.filled(14, 'Je kijkt graag naar Scandinavische misdaadseries en documentaires.').join(' ');
      h.hostModel = ScriptedModel([say(long)]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.runAsync(() => h.host.ask('Vat samen wat je over mijn smaak weet'));
      await settle(tester, 10);
    },
  );
  shot(
    '43-f-toevoegen-tv',
    _tv,
    setup: _withOverview,
    list: true,
    act: (tester, h) async {
      for (var i = 0; i < 12; i++) {
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

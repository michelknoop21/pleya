import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/big_p_voice.dart';

/// Drives Big P's states by hand; the voice only reads these getters.
class _Controller extends AssistantController {
  _Controller() : super(buildContext: (_) => throw UnimplementedError());

  AssistantSurfaceState s = AssistantSurfaceState.idle;
  bool error = false;
  AssistantPendingAction? card;

  @override
  AssistantSurfaceState get state => s;
  @override
  bool get resultIsError => error;
  @override
  AssistantPendingAction? get pending => card;

  void go(AssistantSurfaceState next, {bool isError = false}) {
    s = next;
    error = isError;
    notifyListeners();
  }
}

const _clipList = [
  'assets/audio/bigp/en_greet_1.m4a',
  'assets/audio/bigp/en_greet_2.m4a',
  'assets/audio/bigp/en_greet_3.m4a',
  'assets/audio/bigp/en_result_1.m4a',
  'assets/audio/bigp/en_error_1.m4a',
  'assets/audio/bigp/en_working_1.m4a',
  'assets/audio/bigp/nl_greet_1.m4a',
  'assets/audio/bigp/nl_result_1.m4a',
];
final _clips = {for (final a in _clipList) a: 'Line for ${a.split('/').last}.'};

void main() {
  late _Controller c;
  late List<String> played;
  late int stops;
  var on = true, dictating = false, watching = false, lang = 'en';

  BigPVoice voice({Map<String, String>? clips}) => BigPVoice(
    c,
    enabled: () => on,
    dictating: () => dictating,
    playbackActive: () => watching,
    language: () => lang,
    clips: () async => clips ?? _clips,
    play: (asset) async {
      played.add(asset);
      return 0.05;
    },
    stop: () async => stops++,
    random: Random(1),
  );

  setUp(() {
    c = _Controller();
    played = [];
    stops = 0;
    on = true;
    dictating = false;
    watching = false;
    lang = 'en';
  });

  test('picks a clip for the moment in the app language', () async {
    final v = voice();
    expect(await v.say(BigPMoment.result), 'assets/audio/bigp/en_result_1.m4a');
    lang = 'nl';
    expect(await v.say(BigPMoment.result), 'assets/audio/bigp/nl_result_1.m4a');
  });

  test('never the same greeting twice in a row', () async {
    final v = voice();
    String? last;
    for (var i = 0; i < 20; i++) {
      final asset = await v.say(BigPMoment.greet);
      expect(asset, isNot(last));
      last = asset;
    }
  });

  test('result and error follow the controller', () async {
    voice();
    c.go(AssistantSurfaceState.working);
    c.go(AssistantSurfaceState.result);
    await pumpEventQueue();
    c.go(AssistantSurfaceState.working);
    c.go(AssistantSurfaceState.result, isError: true);
    await pumpEventQueue();
    expect(played, ['assets/audio/bigp/en_result_1.m4a', 'assets/audio/bigp/en_error_1.m4a']);
  });

  test('backing out of a follow-up question does not say the old answer again', () async {
    voice();
    c.go(AssistantSurfaceState.working);
    c.go(AssistantSurfaceState.result);
    await pumpEventQueue();
    c.go(AssistantSurfaceState.listening);
    c.go(AssistantSurfaceState.result);
    await pumpEventQueue();
    expect(played, ['assets/audio/bigp/en_result_1.m4a']);
  });

  test('dictation that starts while the clip loads stops it again', () async {
    BigPVoice(
      c,
      enabled: () => on,
      dictating: () => dictating,
      language: () => lang,
      clips: () async => _clips,
      play: (asset) async {
        played.add(asset);
        dictating = true;
        return 1;
      },
      stop: () async => stops++,
    );
    c.go(AssistantSurfaceState.working);
    c.go(AssistantSurfaceState.result);
    await pumpEventQueue();
    expect(played, hasLength(1));
    expect(stops, 1);
  });

  test('the mouth says the clip line for as long as the clip plays', () {
    fakeAsync((async) {
      final v = BigPVoice(
        c,
        enabled: () => on,
        dictating: () => dictating,
        language: () => lang,
        clips: () async => _clips,
        play: (asset) async => 1.5,
        stop: () async => stops++,
      );
      c.go(AssistantSurfaceState.working);
      c.go(AssistantSurfaceState.result);
      async.flushMicrotasks();
      expect(v.speaking.value, 'Line for en_result_1.m4a.');
      async.elapse(const Duration(milliseconds: 1400));
      expect(v.speaking.value, isNotNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(v.speaking.value, isNull, reason: 'the clip ended, so the mouth closes');
    });
  });

  test('listening stops the mouth with the clip', () async {
    final v = voice();
    await v.say(BigPMoment.greet);
    expect(v.speaking.value, isNotNull);
    c.go(AssistantSurfaceState.listening);
    expect(v.speaking.value, isNull);
  });

  test('a dropped clip never moves the mouth', () async {
    final v = voice();
    on = false;
    await v.say(BigPMoment.greet);
    expect(v.speaking.value, isNull);
  });

  test('an older clip that answers late does not take over the mouth', () async {
    final pending = <String, Completer<double?>>{};
    final v = BigPVoice(
      c,
      enabled: () => on,
      dictating: () => dictating,
      language: () => lang,
      clips: () async => _clips,
      play: (asset) => (pending[asset] = Completer<double?>()).future,
      stop: () async => stops++,
    );
    final first = v.say(BigPMoment.greet);
    await pumpEventQueue();
    final second = v.say(BigPMoment.result);
    await pumpEventQueue();
    pending['assets/audio/bigp/en_result_1.m4a']!.complete(1);
    await second;
    pending.values.first.complete(1);
    await first;
    expect(v.speaking.value, 'Line for en_result_1.m4a.');
  });

  test('disposing the controller stops the clip and closes the mouth', () async {
    final v = voice();
    await v.say(BigPMoment.greet);
    expect(v.speaking.value, isNotNull);
    c.dispose();
    expect(v.speaking.value, isNull);
    expect(stops, 1);
  });

  test('a long run gets one "still looking"', () {
    fakeAsync((async) {
      voice();
      c.go(AssistantSurfaceState.working);
      async.elapse(const Duration(seconds: 5));
      expect(played, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(played, ['assets/audio/bigp/en_working_1.m4a']);
    });
  });

  test('dropped while the user dictates, and listening stops a clip', () async {
    final v = voice();
    dictating = true;
    expect(await v.say(BigPMoment.greet), isNull);
    dictating = false;
    c.go(AssistantSurfaceState.listening);
    expect(stops, 1);
    expect(await v.say(BigPMoment.greet), isNull);
    expect(played, isEmpty);
  });

  test('dropped while a video plays, not queued', () async {
    final v = voice();
    watching = true;
    expect(await v.say(BigPMoment.result), isNull);
    watching = false;
    await pumpEventQueue();
    expect(played, isEmpty);
  });

  test('nothing when switched off', () async {
    on = false;
    final v = voice();
    expect(await v.say(BigPMoment.greet), isNull);
    c.go(AssistantSurfaceState.result);
    await pumpEventQueue();
    expect(played, isEmpty);
  });

  test('missing clips mean silence', () async {
    final v = voice(clips: const {});
    expect(await v.say(BigPMoment.greet), isNull);
    expect(played, isEmpty);
  });

  test('of() finds the voice of a controller', () {
    final v = voice();
    expect(BigPVoice.of(c), same(v));
  });
}

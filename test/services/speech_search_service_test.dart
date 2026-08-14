import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test_native_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(channel, null);
    NativeInputSession.debugReset();
  });

  SpeechSearchService buildAppleTvService() {
    TvDetectionService.debugSetAppleTVOverride(true);
    return SpeechSearchService(textEntry: AppleTvNativeTextEntry(channel: channel));
  }

  /// Simulates the native side pushing a `textChanged` call to Dart.
  Future<void> pushTextChanged(String text) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('textChanged', text)),
      (_) {},
    );
  }

  test('Apple TV: edit gets prefill + search action, partials stream, submit flag survives', () async {
    final service = buildAppleTvService();
    final partials = <String>[];
    late Map<Object?, Object?> sentArgs;

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'edit');
      sentArgs = call.arguments as Map<Object?, Object?>;
      await pushTextChanged('batm');
      await pushTextChanged('batman');
      return <String, dynamic>{'text': 'batman', 'submitted': true};
    });

    final result = await service.capture(prompt: 'Search', initialText: 'bat', onPartial: partials.add);

    expect(sentArgs['text'], 'bat');
    expect(sentArgs['action'], 'search');
    expect(partials, ['batm', 'batman']);
    expect(result, isNotNull);
    expect(result!.text, 'batman');
    expect(result.submitted, isTrue);
  });

  test('Apple TV: cancelling with text returns submitted=false', () async {
    final service = buildAppleTvService();
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, dynamic>{'text': 'halfway', 'submitted': false};
    });

    final result = await service.capture();

    expect(result!.text, 'halfway');
    expect(result.submitted, isFalse);
  });

  test('Apple TV: BUSY returns null without flipping support', () async {
    final service = buildAppleTvService();
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: AppleTvNativeTextEntry.busyCode);
    });

    expect(await service.capture(), isNull);
    expect(await service.isSupported(), isTrue);
  });

  test('Apple TV: missing plugin returns null and reports unsupported afterwards', () async {
    final service = buildAppleTvService();
    // No mock handler registered → MissingPluginException.

    expect(await service.capture(), isNull);
    expect(await service.isSupported(), isFalse);
  });

  test('Apple TV: a second session is refused without disarming the live one', () async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    final opened = Completer<void>();
    final release = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) {
      opened.complete();
      return release.future;
    });

    final first = entry.edit(text: 'a');
    await opened.future;
    expect(NativeInputSession.isActive, isTrue);

    await expectLater(
      entry.edit(text: 'b'),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', AppleTvNativeTextEntry.busyCode)),
    );
    // The refused call must not hand the remote back to Flutter while the
    // first keyboard is still on screen.
    expect(NativeInputSession.isActive, isTrue);

    release.complete({'text': 'a', 'submitted': false});
    await first;
    expect(NativeInputSession.isActive, isFalse);
  });

  test('Apple TV: a dead surface is reported to the caller and written off', () async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    TvDetectionService.debugSetAppleTVOverride(true);
    final service = SpeechSearchService(textEntry: entry);
    var edits = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      edits++;
      throw PlatformException(code: AppleTvNativeTextEntry.deadCode);
    });

    // The caller must see the failure — swallowing it is what made the dead
    // dialog look like a hang instead of triggering the fallback keyboard.
    await expectLater(service.capture(), throwsA(isA<PlatformException>()));
    expect(entry.isUnavailable, isTrue);

    // Latched: a second attempt never reaches the platform again.
    await expectLater(entry.edit(text: ''), throwsA(isA<MissingPluginException>()));
    expect(edits, 1);
  });

  test('Apple TV: empty text returns null even when submitted', () async {
    final service = buildAppleTvService();
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, dynamic>{'text': '  ', 'submitted': true};
    });

    expect(await service.capture(), isNull);
  });
}

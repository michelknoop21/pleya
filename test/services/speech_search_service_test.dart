import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/platform_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test_native_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(channel, null);
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

  test('Apple TV: empty text returns null even when submitted', () async {
    final service = buildAppleTvService();
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, dynamic>{'text': '  ', 'submitted': true};
    });

    expect(await service.capture(), isNull);
  });
}

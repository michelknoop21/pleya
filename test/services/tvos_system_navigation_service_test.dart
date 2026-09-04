import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/tvos_system_navigation_service.dart';
import 'package:pleya/utils/platform_detector.dart';

// Fase-0 baseline for Pleya Unified TV 2026 (docs/tvos-unified-experience.md
// hoofdstuk 27): this file locks in the existing tvOS Menu pass-through
// platform-channel call before any unified-catalog code lands. A regression
// here is a regression against the pre-unified baseline, not a new
// requirement.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'flutter/tvos_system_navigation';
  const codec = JSONMessageCodec();
  late List<Object?> sent;

  setUp(() {
    sent = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(channelName, (
      ByteData? message,
    ) async {
      sent.add(codec.decodeMessage(message));
      return codec.encodeMessage(null);
    });
    TvDetectionService.debugSetAppleTVOverride(null);
    TvosSystemNavigationService.debugResetMenuPassthroughCache();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(channelName, null);
  });

  group('TvosSystemNavigationService.setMenuPassthroughEnabled', () {
    test('off Apple TV, no message is ever sent', () async {
      TvDetectionService.debugSetAppleTVOverride(false);

      await TvosSystemNavigationService.setMenuPassthroughEnabled(true);
      await TvosSystemNavigationService.setMenuPassthroughEnabled(false);

      expect(sent, isEmpty);
    });

    test('on Apple TV, enabling sends the channel message with the flag on', () async {
      TvDetectionService.debugSetAppleTVOverride(true);

      await TvosSystemNavigationService.setMenuPassthroughEnabled(true);

      expect(sent, [
        {'menuPassthroughEnabled': true},
      ]);
    });

    test('on Apple TV, disabling sends the channel message with the flag off', () async {
      TvDetectionService.debugSetAppleTVOverride(true);

      await TvosSystemNavigationService.setMenuPassthroughEnabled(false);

      expect(sent, [
        {'menuPassthroughEnabled': false},
      ]);
    });

    test('repeating the same value does not resend', () async {
      TvDetectionService.debugSetAppleTVOverride(true);

      await TvosSystemNavigationService.setMenuPassthroughEnabled(true);
      await TvosSystemNavigationService.setMenuPassthroughEnabled(true);

      expect(sent, [
        {'menuPassthroughEnabled': true},
      ]);
    });

    test('a changed value after a no-op repeat sends again', () async {
      TvDetectionService.debugSetAppleTVOverride(true);

      await TvosSystemNavigationService.setMenuPassthroughEnabled(true);
      await TvosSystemNavigationService.setMenuPassthroughEnabled(true);
      await TvosSystemNavigationService.setMenuPassthroughEnabled(false);

      expect(sent, [
        {'menuPassthroughEnabled': true},
        {'menuPassthroughEnabled': false},
      ]);
    });
  });
}

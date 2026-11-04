import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/platform_detector.dart';

void main() {
  group('isIPad', () {
    tearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      TvDetectionService.debugSetIOSAppOnMacOverride(null);
    });

    Future<bool> isIPad(WidgetTester tester, TargetPlatform platform, Size size, double ratio) async {
      late bool answer;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size, devicePixelRatio: ratio),
          child: Theme(
            data: ThemeData(platform: platform),
            child: Builder(
              builder: (context) {
                answer = PlatformDetector.isIPad(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return answer;
    }

    testWidgets('an iPad is one, in either orientation', (tester) async {
      expect(await isIPad(tester, TargetPlatform.iOS, const Size(834, 1194), 2), isTrue);
      expect(await isIPad(tester, TargetPlatform.iOS, const Size(1194, 834), 2), isTrue);
    });

    testWidgets('a narrow iPad window is still an iPad, not a phone', (tester) async {
      expect(await isIPad(tester, TargetPlatform.iOS, const Size(320, 1100), 2), isTrue);
    });

    testWidgets('an iPhone is not', (tester) async {
      expect(await isIPad(tester, TargetPlatform.iOS, const Size(393, 852), 3), isFalse);
    });

    testWidgets('the iOS app on a Mac is not', (tester) async {
      TvDetectionService.debugSetIOSAppOnMacOverride(true);
      expect(await isIPad(tester, TargetPlatform.iOS, const Size(1194, 834), 2), isFalse);
    });

    testWidgets('Apple TV, an Android tablet and a Mac are not', (tester) async {
      expect(await isIPad(tester, TargetPlatform.android, const Size(1194, 834), 2), isFalse);
      expect(await isIPad(tester, TargetPlatform.macOS, const Size(1194, 834), 2), isFalse);
      TvDetectionService.debugSetAppleTVOverride(true);
      expect(await isIPad(tester, TargetPlatform.iOS, const Size(1920, 1080), 2), isFalse);
    });
  });

  group('detectAndroidTvFromSystemFeatures', () {
    test('detects leanback devices', () {
      final detection = detectAndroidTvFromSystemFeatures([
        'android.software.leanback',
        'android.hardware.touchscreen',
      ]);

      expect(detection.isTv, isTrue);
      expect(detection.reasons, contains('leanback'));
      expect(detection.reasons, isNot(contains('no_touchscreen')));
    });

    test('detects Fire TV even when touchscreen is present', () {
      final detection = detectAndroidTvFromSystemFeatures(['amazon.hardware.fire_tv', 'android.hardware.touchscreen']);

      expect(detection.isTv, isTrue);
      expect(detection.reasons, contains('fire_tv'));
      expect(detection.reasons, isNot(contains('no_touchscreen')));
    });

    test('detects devices without real touchscreen capability', () {
      final detection = detectAndroidTvFromSystemFeatures(['android.hardware.faketouch']);

      expect(detection.isTv, isTrue);
      expect(detection.reasons, contains('no_touchscreen'));
    });

    test('detects television feature', () {
      final detection = detectAndroidTvFromSystemFeatures([
        'android.hardware.type.television',
        'android.hardware.touchscreen',
      ]);

      expect(detection.isTv, isTrue);
      expect(detection.reasons, contains('television_feature'));
    });

    test('does not classify touchscreen-only devices as TV', () {
      final detection = detectAndroidTvFromSystemFeatures(['android.hardware.touchscreen']);

      expect(detection.isTv, isFalse);
      expect(detection.reasons, isEmpty);
    });

    test('does not classify empty feature lists as no-touchscreen TVs', () {
      final detection = detectAndroidTvFromSystemFeatures(const []);

      expect(detection.isTv, isFalse);
      expect(detection.reasons, isEmpty);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `ubiquityIdentityToken` is the iCloud Drive Documents identity (Apple
/// Foundation docs). tvOS has no iCloud Drive, so the token is nil on a
/// signed-in Apple TV, and gating the key-value store on it disabled the sync
/// toggle there and silently held back every reconcile (build 431). The native
/// side has no test target, so this reads the source.
String _tvosBranch(String path) {
  final source = File(path).readAsStringSync();
  final start = source.indexOf('private static var isKvsAvailable: Bool {');
  expect(start, isNot(-1), reason: '$path: availability no longer answered by isKvsAvailable');
  final ifStart = source.indexOf('#if os(tvOS)', start);
  final elseStart = source.indexOf('#else', ifStart);
  expect(ifStart, isNot(-1), reason: '$path: availability is no longer decided per platform');
  expect(source, contains('result(Self.isKvsAvailable)'), reason: '$path: channel bypasses isKvsAvailable');
  return source.substring(ifStart, elseStart);
}

void main() {
  test('tvOS key-value availability does not depend on the iCloud Drive token', () {
    for (final path in [
      'tvos/Runner/ICloudKvsPlugin.swift',
      'ios/Runner/ICloudKvsPlugin.swift',
      'macos/Runner/ICloudKvsPlugin.swift',
    ]) {
      final tvos = _tvosBranch(path);
      expect(tvos, isNot(contains('ubiquityIdentityToken')), reason: path);
      expect(tvos, contains('return true'), reason: path);
    }
  });

  test('the tvOS target carries the key-value store entitlement the answer relies on', () {
    expect(
      File('tvos/Runner/Runner.entitlements').readAsStringSync(),
      contains('com.apple.developer.ubiquity-kvstore-identifier'),
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `FileManager.ubiquityIdentityToken` reports the iCloud **Drive** Documents
/// identity. iCloud Drive does not exist on tvOS, so the token is nil on an
/// Apple TV that is signed in perfectly well. Gating the key-value store on it
/// made every Apple TV say "sign in to iCloud" and disable the sync toggle.
///
/// The store Pleya actually uses is `NSUbiquitousKeyValueStore`, authorised by
/// the `com.apple.developer.ubiquity-kvstore-identifier` entitlement — a
/// different facility with a different gate. These are source-level assertions
/// because the native side has no test target: without them the next person to
/// touch the plugin has nothing telling them the two are not interchangeable.
const _kvsEntitlement = 'com.apple.developer.ubiquity-kvstore-identifier';
const _driveToken = 'ubiquityIdentityToken';

const _tvosPlugin = 'tvos/Runner/ICloudKvsPlugin.swift';
const _iosPlugin = 'ios/Runner/ICloudKvsPlugin.swift';
const _macosPlugin = 'macos/Runner/ICloudKvsPlugin.swift';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path moved; update this test rather than deleting it');
  return file.readAsStringSync();
}

/// The body of the `isKvsAvailable` property, split into its `#if os(tvOS)`
/// branch and its `#else` branch. Parsing beats grepping here: the point is
/// *which* branch names the token, not whether the file mentions it at all.
({String tvos, String other}) _availabilityBranches(String source) {
  final start = source.indexOf('private static var isKvsAvailable: Bool {');
  expect(start, isNot(-1), reason: 'the availability answer moved out of `isKvsAvailable`');
  final ifStart = source.indexOf('#if os(tvOS)', start);
  final elseStart = source.indexOf('#else', ifStart);
  final endifStart = source.indexOf('#endif', elseStart);
  expect(ifStart, isNot(-1), reason: 'availability is no longer decided per platform');
  expect(elseStart, isNot(-1));
  expect(endifStart, isNot(-1));
  return (tvos: source.substring(ifStart, elseStart), other: source.substring(elseStart, endifStart));
}

void main() {
  group('availability is answered per platform, not by the iCloud Drive token', () {
    test('tvOS does not consult ubiquityIdentityToken', () {
      final branches = _availabilityBranches(_read(_tvosPlugin));
      expect(
        branches.tvos,
        isNot(contains(_driveToken)),
        reason:
            'the tvOS branch is back on the iCloud Drive token; it is nil on every Apple TV, '
            'so this reintroduces the false "not signed in to iCloud"',
      );
      expect(branches.tvos, contains('return true'));
    });

    test('iOS and macOS keep the account check — there the token is the right question', () {
      for (final path in [_iosPlugin, _macosPlugin]) {
        final branches = _availabilityBranches(_read(path));
        expect(branches.other, contains(_driveToken), reason: '$path stopped checking for an iCloud account');
      }
    });

    test('the method channel answers from the platform-aware property', () {
      for (final path in [_tvosPlugin, _iosPlugin, _macosPlugin]) {
        final source = _read(path);
        final caseStart = source.indexOf('case "isAvailable":');
        expect(caseStart, isNot(-1), reason: '$path no longer answers isAvailable');
        final caseBody = source.substring(caseStart, source.indexOf('case "getAll":', caseStart));
        expect(caseBody, contains('Self.isKvsAvailable'));
        expect(
          caseBody,
          isNot(contains(_driveToken)),
          reason: '$path went back to deciding availability inline from the iCloud Drive token',
        );
      }
    });
  });

  group('the key-value store stays authorised', () {
    // Losing this entitlement is silent: the store keeps accepting writes and
    // simply never leaves the device, so nothing fails loudly enough to notice.
    const entitlements = [
      'tvos/Runner/Runner.entitlements',
      'ios/Runner/Runner.entitlements',
      'macos/Runner/Release.entitlements',
      'macos/Runner/DebugProfile.entitlements',
    ];

    for (final path in entitlements) {
      test('$path carries the kvstore entitlement', () {
        expect(_read(path), contains(_kvsEntitlement));
      });
    }

    test('the tvOS target signs with the entitlements file that carries it', () {
      // The plist only matters if the target actually signs with it. Without
      // this the key could sit in a file nothing reads, and the store would
      // quietly keep every write on the device.
      expect(
        _read('tvos/Runner.xcodeproj/project.pbxproj'),
        contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements'),
      );
    });

    test('the tvOS target compiles and registers the plugin', () {
      expect(
        _read('tvos/Runner.xcodeproj/project.pbxproj'),
        contains('ICloudKvsPlugin.swift'),
        reason: 'the plugin dropped out of the tvOS build; the channel would answer MissingPluginException',
      );
      expect(_read('tvos/Runner/AppDelegate.swift'), contains('ICloudKvsPlugin.register'));
    });
  });
}

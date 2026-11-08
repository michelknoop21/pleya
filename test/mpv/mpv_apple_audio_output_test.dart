import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Which mpv options `applySharedMpvOptions` sets on each Apple target.
///
/// The choice lives in Swift behind `#if` branches, so this evaluates those
/// branches per platform instead of searching for a string: a line that only
/// survives on tvOS must not count as set on an iPhone.
Map<String, String> _optionsFor({required String os, required bool simulator}) {
  final source = File('shared/apple/MpvPlayer/MpvPlayerCoreBase.swift').readAsStringSync();
  final start = source.indexOf('private func applySharedMpvOptions()');
  expect(start, isNot(-1), reason: 'applySharedMpvOptions moved or was renamed');
  final body = source.substring(start, source.indexOf('\n  }\n', start));

  bool eval(String condition) {
    final osMatch = RegExp(r'^os\((\w+)\)$').firstMatch(condition);
    if (osMatch != null) return osMatch.group(1) == os;
    if (condition == 'targetEnvironment(simulator)') return simulator;
    if (condition.startsWith('!')) return !eval(condition.substring(1));
    throw StateError('unhandled #if condition: $condition');
  }

  // One frame per open #if: whether its enclosing block is active, and whether
  // one of its branches has already been taken.
  final stack = <({bool parentActive, bool taken, bool active})>[];
  bool active() => stack.isEmpty || stack.last.active;
  final options = <String, String>{};
  final setOption = RegExp(r'mpv_set_option_string\(mpv, "([^"]+)", "([^"]*)"\)');

  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('#if ')) {
      final parent = active();
      final on = parent && eval(line.substring(4).trim());
      stack.add((parentActive: parent, taken: on, active: on));
    } else if (line.startsWith('#elseif ')) {
      final frame = stack.removeLast();
      final on = frame.parentActive && !frame.taken && eval(line.substring(8).trim());
      stack.add((parentActive: frame.parentActive, taken: frame.taken || on, active: on));
    } else if (line == '#else') {
      final frame = stack.removeLast();
      final on = frame.parentActive && !frame.taken;
      stack.add((parentActive: frame.parentActive, taken: true, active: on));
    } else if (line == '#endif') {
      stack.removeLast();
    } else if (active()) {
      final match = setOption.firstMatch(line);
      if (match != null) options[match.group(1)!] = match.group(2)!;
    }
  }
  expect(stack, isEmpty, reason: 'unbalanced #if in applySharedMpvOptions');
  return options;
}

void main() {
  group('mpv audio output on Apple devices', () {
    test('an iPhone or iPad prefers the avfoundation output', () {
      // ao_audiounit reads maximumOutputNumberOfChannels once and remixes to
      // it; AirPods report two even with Spatial Audio on, so 5.1 became
      // stereo before the system could place it around the listener.
      expect(_optionsFor(os: 'iOS', simulator: false)['ao'], 'avfoundation,audiounit');
    });

    test('Apple TV keeps the avfoundation output', () {
      expect(_optionsFor(os: 'tvOS', simulator: false)['ao'], 'avfoundation,audiounit');
    });

    test('simulators and the Mac keep their own default', () {
      expect(_optionsFor(os: 'iOS', simulator: true).containsKey('ao'), isFalse);
      expect(_optionsFor(os: 'tvOS', simulator: true).containsKey('ao'), isFalse);
      expect(_optionsFor(os: 'macOS', simulator: false).containsKey('ao'), isFalse);
    });

    test('device video options are unchanged on both platforms', () {
      for (final os in ['iOS', 'tvOS']) {
        final options = _optionsFor(os: os, simulator: false);
        expect(options['vo'], 'avfoundation', reason: os);
        expect(options['hwdec'], 'videotoolbox', reason: os);
        expect(options['avfoundation-composite-osd'], 'no', reason: os);
      }
    });

    test('VideoToolbox decodes on one thread on every Apple device', () {
      // libavcodec serializes the VideoToolbox hwaccel, so mpv's default of 4
      // frame threads only holds 3 extra decoded 4K surfaces per session.
      for (final os in ['iOS', 'tvOS', 'macOS']) {
        expect(_optionsFor(os: os, simulator: false)['hwdec-threads'], '1', reason: os);
      }
    });
  });
}

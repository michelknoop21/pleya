import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/mpv/player/audio_path_arbiter.dart';

void main() {
  group('resolving a request', () {
    test('a running bitstream suspends normalization without discarding it', () {
      const request = AudioPathRequest(passthrough: true, normalization: AudioNormalizationMode.night);
      final effective = resolveAudioPath(request);

      expect(effective.passthrough, isTrue);
      expect(effective.normalization, AudioNormalizationMode.off, reason: 'loudnorm needs decoded audio');
      expect(request.normalization, AudioNormalizationMode.night, reason: 'the user choice is kept as asked');
    });

    test('a rate other than 1.0 drops the bitstream and lets loudnorm back in', () {
      // mpv cannot scaletempo a compressed stream, so the bitstream is the one
      // that gives way here; with PCM in the chain the filter can run again.
      const request = AudioPathRequest(passthrough: true, normalization: AudioNormalizationMode.normalize, rate: 1.5);
      final effective = resolveAudioPath(request);

      expect(effective.passthrough, isFalse);
      expect(effective.normalization, AudioNormalizationMode.normalize);
    });

    test('without a bitstream the request passes through untouched', () {
      final effective = resolveAudioPath(const AudioPathRequest(normalization: AudioNormalizationMode.normalize));
      expect(effective.passthrough, isFalse);
      expect(effective.normalization, AudioNormalizationMode.normalize);
    });
  });

  group('transitions', () {
    test('the first write happens even for off, because the shared core is unknown', () {
      final arbiter = AudioPathArbiter();

      // The mpv core is static and outlives a player, so "off" cannot be
      // assumed to be what it already has: a loudnorm from the previous title
      // would stay in the chain.
      final first = arbiter.request(normalization: AudioNormalizationMode.off);
      expect(first.normalization, AudioNormalizationMode.off);
      arbiter.markNormalizationApplied(AudioNormalizationMode.off);

      expect(arbiter.request(normalization: AudioNormalizationMode.off).normalization, isNull);
    });

    test('nothing is cached until the write returned', () {
      final arbiter = AudioPathArbiter();
      expect(arbiter.request(normalization: AudioNormalizationMode.normalize).normalization, isNotNull);
      // The write failed, so asking again must offer it again rather than skip
      // it as "no change".
      expect(arbiter.request(normalization: AudioNormalizationMode.normalize).normalization, isNotNull);
      expect(arbiter.request(passthrough: true).togglePassthrough, isTrue);
      expect(arbiter.request(passthrough: true).togglePassthrough, isTrue, reason: 'still not applied');
    });

    test('the filter is cleared before the bitstream, and restored after it', () {
      final arbiter = AudioPathArbiter();
      arbiter.request(normalization: AudioNormalizationMode.night);
      arbiter.markNormalizationApplied(AudioNormalizationMode.night);
      arbiter.markPassthroughApplied(false);

      // Order is the whole point: `af` written after `audio-spdif` makes mpv
      // log a passthrough complaint, which the output coordinator reads as a
      // receiver that cannot take the format and remembers for the app run.
      final up = arbiter.request(passthrough: true);
      expect(up.togglePassthrough, isTrue);
      expect(up.normalization, AudioNormalizationMode.off, reason: 'the filter chain has to be emptied');
      expect(up.normalizationFirst, isTrue, reason: 'af must be empty before audio-spdif is set');
      expect(up.suspendsNormalization, isTrue, reason: 'this is the moment worth reporting');
      arbiter.markNormalizationApplied(AudioNormalizationMode.off);
      arbiter.markPassthroughApplied(true);

      final down = arbiter.request(passthrough: false);
      expect(down.normalization, AudioNormalizationMode.night, reason: 'restored, not forgotten');
      expect(down.normalizationFirst, isFalse, reason: 'the bitstream goes down before the filter goes on');
      expect(down.suspendsNormalization, isFalse, reason: 'coming back must not warn again');
    });

    test('a loudness change during a bitstream is remembered, not applied', () {
      final arbiter = AudioPathArbiter();
      arbiter.markPassthroughApplied(true);
      arbiter.markNormalizationApplied(AudioNormalizationMode.off);
      arbiter.request(passthrough: true);

      final held = arbiter.request(normalization: AudioNormalizationMode.normalize);
      expect(held.normalization, isNull, reason: 'nothing to write while the bitstream runs');
      expect(held.togglePassthrough, isFalse);
      expect(arbiter.normalizationSuspended, isTrue);

      // The fallback to PCM is what brings it back, through the same route.
      final fallback = arbiter.request(passthrough: false);
      expect(fallback.normalization, AudioNormalizationMode.normalize);
      expect(fallback.normalizationFirst, isFalse);
    });

    test('the suspension is reported once, not on every reconcile', () {
      final arbiter = AudioPathArbiter();
      arbiter.markPassthroughApplied(false);
      arbiter.markNormalizationApplied(AudioNormalizationMode.off);
      arbiter.request(normalization: AudioNormalizationMode.normalize);
      arbiter.markNormalizationApplied(AudioNormalizationMode.normalize);

      expect(arbiter.request(passthrough: true).suspendsNormalization, isTrue);
      arbiter.markPassthroughApplied(true);
      arbiter.markNormalizationApplied(AudioNormalizationMode.off);

      expect(arbiter.request(passthrough: true).suspendsNormalization, isFalse, reason: 'nothing changed');
      expect(
        arbiter.request(normalization: AudioNormalizationMode.night).suspendsNormalization,
        isFalse,
        reason: 'already suspended',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/audio_output_coordinator.dart';
import 'package:pleya/services/audio_output_decision.dart';
import 'package:pleya/utils/audio_output_labels.dart';

/// The overlay line that answers "did the bitstream really land".
///
/// The device log of build 221 is the reference for every string here: mpv
/// reports `ao=avfoundation` on both routes and only the format tells them
/// apart, so a label that leans on the driver would read the same either way.
void main() {
  group('verifiedAudioOutputLabel', () {
    test('names the codec from the format, since the driver never differs', () {
      const verified = VerifiedAudioOutput(
        intended: AudioOutputDecision.passthrough,
        ao: 'avfoundation',
        format: 'spdif-eac3',
        channels: 'stereo',
      );
      expect(verifiedAudioOutputLabel(verified), 'E-AC3 bitstream · avfoundation');
    });

    test('marks a requested bitstream that ended up decoded as a fallback', () {
      const verified = VerifiedAudioOutput(
        intended: AudioOutputDecision.passthrough,
        ao: 'avfoundation',
        format: 'float',
        channels: '5.1',
      );
      final label = verifiedAudioOutputLabel(verified);
      expect(label, startsWith('PCM 5.1'));
      expect(label, contains('fell back'), reason: 'the gap between asked and got is the point of the line');
    });

    test('leaves a plain PCM decision unmarked', () {
      const verified = VerifiedAudioOutput(
        intended: AudioOutputDecision.pcmMultichannel,
        ao: 'avfoundation',
        format: 'float',
        channels: '5.1',
      );
      expect(verifiedAudioOutputLabel(verified), 'PCM 5.1 · avfoundation');
    });

    test('survives a bitstream format with no codec after the prefix', () {
      // `isBitstream` only checks the `spdif` prefix, so a bare `spdif` reaches
      // here. Slicing at a fixed offset threw a RangeError inside the widget
      // build and took the overlay down mid-playback.
      const bare = VerifiedAudioOutput(intended: AudioOutputDecision.passthrough, format: 'spdif');
      expect(verifiedAudioOutputLabel(bare), 'bitstream');
    });

    test('accepts either separator, since mpv writes both', () {
      // `spdif-eac3` on the output params, `spdif_eac3` on the decoder line.
      const underscore = VerifiedAudioOutput(intended: AudioOutputDecision.passthrough, format: 'spdif_eac3');
      expect(verifiedAudioOutputLabel(underscore), 'E-AC3 bitstream');
    });

    test('survives mpv answering with a format but no channels or driver', () {
      const verified = VerifiedAudioOutput(intended: AudioOutputDecision.pcmStereo, format: 's16');
      expect(verifiedAudioOutputLabel(verified), 'PCM');
    });
  });

  group('audioOutputDecisionLabel', () {
    test('gives each decision its own name', () {
      final labels = AudioOutputDecision.values.map(audioOutputDecisionLabel).toSet();
      expect(labels.length, AudioOutputDecision.values.length);
    });
  });
}

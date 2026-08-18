import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/models.dart';

/// The filter chain is the product decision, so the numbers in it are pinned
/// here rather than left to drift.
///
/// They come from measurement, not preference. On a 120-second dialogue excerpt
/// of an E-AC-3 Atmos title with dialnorm -27, decoded with dialnorm honoured,
/// the levelling chain landed between -22,2 and -23,1 LUFS across AC-3 and
/// E-AC-3 and across dialnorm -27 and -28, true peak always -2,0 dBFS. That is
/// EBU R128, the level broadcast television is held to.
void main() {
  test('no switches means no filter chain', () {
    expect(AudioLoudness.none.mpvFilter, '');
    expect(AudioLoudness.none.isEnabled, isFalse);
  });

  test('levelling targets the broadcast reference', () {
    const loudness = AudioLoudness(levelVolume: true);
    expect(loudness.mpvFilter, 'loudnorm=I=-22:TP=-2:LRA=9');
    expect(loudness.isEnabled, isTrue);
  });

  test('reducing loud sounds puts a compressor ahead of the levelling', () {
    const loudness = AudioLoudness(levelVolume: true, reduceLoudSounds: true);
    // The compressor is what narrows the range: `LRA` alone barely moves
    // single-pass loudnorm (10,2 against 8,5 LU), while this chain measured
    // 6,4 LU at the same -22,5 LUFS.
    expect(loudness.mpvFilter, startsWith('acompressor='));
    expect(loudness.mpvFilter, contains('loudnorm=I=-22:TP=-2:LRA=3'));
  });

  test('reducing loud sounds on its own does nothing', () {
    // Not a simplification: a compressor with makeup gain and no loudness
    // target ran the same excerpt to +5,4 dBFS — clipping — while leaving the
    // loudness range where it started. The UI hides the switch for the same
    // reason; this is the model refusing to be talked into it.
    const loudness = AudioLoudness(reduceLoudSounds: true);
    expect(loudness.mpvFilter, '');
    expect(loudness.isEnabled, isFalse);
  });

  test('equal states compare equal, so the arbiter can skip a rewrite', () {
    expect(const AudioLoudness(levelVolume: true), const AudioLoudness(levelVolume: true));
    expect(
      const AudioLoudness(levelVolume: true),
      isNot(const AudioLoudness(levelVolume: true, reduceLoudSounds: true)),
    );
  });
}

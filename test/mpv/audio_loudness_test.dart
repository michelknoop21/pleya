import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/models.dart';

/// The filter chains are the product decision, so every string is pinned here
/// rather than left to drift. `scripts/loudness/prove.sh` renders each of them
/// through ffmpeg and mpv and measures the result with an independent meter.
void main() {
  const limiter = 'aresample=192000,alimiter=limit=0.7943:level=false:attack=5:release=50:latency=1,aresample=48000';
  const compressor = 'acompressor=threshold=-18dB:ratio=8:attack=5:release=250:makeup=1';

  test('no switches means no filter chain, whatever gain is carried', () {
    expect(AudioLoudness.none.mpvFilter, '');
    expect(AudioLoudness.none.isEnabled, isFalse);
    expect(AudioLoudness.none.mode, LoudnessMode.off);
    expect(const AudioLoudness(programmeGainDb: 8).mpvFilter, '');
  });

  test('levelling without evidence runs the realtime chain', () {
    const loudness = AudioLoudness(levelVolume: true);
    expect(loudness.mpvFilter, 'loudnorm=I=-22:TP=-2:LRA=9');
    expect(loudness.mode, LoudnessMode.realtime);
  });

  test('levelling and reducing without evidence keeps the realtime compressor chain', () {
    const loudness = AudioLoudness(levelVolume: true, reduceLoudSounds: true);
    expect(loudness.mpvFilter, 'acompressor=threshold=-38dB:ratio=8:attack=5:release=250,loudnorm=I=-22:TP=-2:LRA=3');
    expect(loudness.mode, LoudnessMode.realtime);
  });

  test('levelling with a programme gain is a fixed gain into the true-peak limiter', () {
    const loudness = AudioLoudness(levelVolume: true, programmeGainDb: 8);
    expect(loudness.mpvFilter, 'volume=8.00dB:precision=float,$limiter');
    expect(loudness.mode, LoudnessMode.programme);
    expect(const AudioLoudness(levelVolume: true, programmeGainDb: -4).mpvFilter, startsWith('volume=-4.00dB'));
  });

  test('levelling and reducing with a gain puts the compressor between gain and limiter', () {
    const loudness = AudioLoudness(levelVolume: true, reduceLoudSounds: true, programmeGainDb: 6);
    expect(loudness.mpvFilter, 'volume=6.00dB:precision=float,$compressor,$limiter');
  });

  test('reducing loud sounds on its own compresses behind the limiter', () {
    // Used to be '' because a compressor with makeup and no ceiling ran an
    // excerpt to +5,4 dBFS. Neutral makeup plus the limiter makes it safe.
    const loudness = AudioLoudness(reduceLoudSounds: true);
    expect(loudness.mpvFilter, '$compressor,$limiter');
    expect(loudness.isEnabled, isTrue);
    expect(loudness.mode, LoudnessMode.programme);
  });

  test('equal states compare equal, so the arbiter can skip a rewrite', () {
    expect(const AudioLoudness(levelVolume: true), const AudioLoudness(levelVolume: true));
    expect(
      const AudioLoudness(levelVolume: true),
      isNot(const AudioLoudness(levelVolume: true, reduceLoudSounds: true)),
    );
    expect(
      const AudioLoudness(levelVolume: true, programmeGainDb: 8),
      isNot(const AudioLoudness(levelVolume: true, programmeGainDb: 7)),
    );
  });
}

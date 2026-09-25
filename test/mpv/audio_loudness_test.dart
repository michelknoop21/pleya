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

  test('the boost is a linear percentage, not mpv cubic software volume', () {
    // mpv scales its `volume` property cubically and applies it after every
    // filter: 150% was 3,375x, +10,57 dB, past the limiter. Read linearly it
    // is 1,5x.
    expect(const AudioLoudness(boostPercent: 100).boostDb, 0);
    expect(const AudioLoudness(boostPercent: 150).boostDb, closeTo(3.52, 0.01));
    expect(const AudioLoudness(boostPercent: 200).boostDb, closeTo(6.02, 0.01));
    expect(const AudioLoudness(boostPercent: 300).boostDb, closeTo(9.54, 0.01));
  });

  test('a boost on its own is a gain into the true-peak limiter', () {
    const loudness = AudioLoudness(boostPercent: 150);
    expect(loudness.mpvFilter, 'volume=3.52dB:precision=float,$limiter');
    expect(loudness.isEnabled, isTrue, reason: 'the boost needs decoded PCM like the rest of the chain');
    expect(const AudioLoudness(boostPercent: 100).mpvFilter, '');
  });

  test('the boost sits between the compressor and the limiter', () {
    const loudness = AudioLoudness(levelVolume: true, reduceLoudSounds: true, programmeGainDb: 6, boostPercent: 200);
    expect(loudness.mpvFilter, 'volume=6.00dB:precision=float,$compressor,volume=6.02dB:precision=float,$limiter');
  });

  test('the realtime boost raises the loudnorm target, so its own limiter stays last', () {
    // A `volume` stage after single-pass loudnorm would sit behind the only
    // ceiling in that chain. Raising `I` is the same level under the same TP.
    expect(const AudioLoudness(levelVolume: true, boostPercent: 150).mpvFilter, 'loudnorm=I=-18.48:TP=-2:LRA=9');
    expect(
      const AudioLoudness(levelVolume: true, reduceLoudSounds: true, boostPercent: 150).mpvFilter,
      'acompressor=threshold=-38dB:ratio=8:attack=5:release=250,loudnorm=I=-18.48:TP=-2:LRA=3',
    );
  });

  test('a build without acompressor and alimiter keeps the gain and loses the ceiling', () {
    // MPVKit 1.0.26 ships neither, and mpv rejects the whole `af` string over
    // one unknown filter, which silently disabled every audio setting on Apple.
    expect(const AudioLoudness(boostPercent: 150).mpvFilterWithoutDynamics, 'volume=3.52dB:precision=float');
    expect(
      const AudioLoudness(levelVolume: true, programmeGainDb: 6, reduceLoudSounds: true).mpvFilterWithoutDynamics,
      'volume=6.00dB:precision=float',
    );
    expect(
      const AudioLoudness(levelVolume: true, reduceLoudSounds: true).mpvFilterWithoutDynamics,
      'loudnorm=I=-22:TP=-2:LRA=3',
    );
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
    expect(const AudioLoudness(levelVolume: true), isNot(const AudioLoudness(levelVolume: true, boostPercent: 150)));
  });
}

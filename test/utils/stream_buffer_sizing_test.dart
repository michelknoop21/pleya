import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/stream_buffer_sizing.dart';

void main() {
  group('nextPowerOfTwo', () {
    test('rounds up to the next power of two', () {
      expect(nextPowerOfTwo(1), 1);
      expect(nextPowerOfTwo(2), 2);
      expect(nextPowerOfTwo(3), 4);
      expect(nextPowerOfTwo(52 * 1024 * 1024), 64 * 1024 * 1024);
      expect(nextPowerOfTwo(64 * 1024 * 1024), 64 * 1024 * 1024);
      expect(nextPowerOfTwo(64 * 1024 * 1024 + 1), 128 * 1024 * 1024);
    });
  });

  group('networkStreamRingBytes', () {
    test('sizes the iPhone 4K60 HDR10 repro file to 64MiB', () {
      // 69140 kbps total → 8.6 MB/s × 6s ≈ 52MB → pow2 64MiB; the guaranteed
      // seek-back half (32MiB) covers the measured ~24MB interleave gap.
      expect(networkStreamRingBytes(container: 'mov', bitrateKbps: 69140), 64 * 1024 * 1024);
    });

    test('returns null for well-interleaved or unknown containers', () {
      expect(networkStreamRingBytes(container: 'avi', bitrateKbps: 69140), isNull);
      expect(networkStreamRingBytes(container: null, bitrateKbps: 69140), isNull);
      expect(networkStreamRingBytes(container: '', bitrateKbps: 69140), isNull);
    });

    test('sizes high-bitrate Matroska direct play to 64MiB', () {
      expect(networkStreamRingBytes(container: 'mkv', bitrateKbps: 69140), 64 * 1024 * 1024);
      expect(networkStreamRingBytes(container: 'matroska', bitrateKbps: 69140), 64 * 1024 * 1024);
    });

    test('keeps ordinary Matroska direct play on the default stream ring', () {
      expect(networkStreamRingBytes(container: 'mkv', bitrateKbps: 39000), isNull);
      expect(networkStreamRingBytes(container: 'mkv', bitrateKbps: null), isNull);
      expect(networkStreamRingBytes(container: 'mkv', bitrateKbps: 0), isNull);
    });

    test('matches QuickTime-family containers case-insensitively', () {
      expect(networkStreamRingBytes(container: 'MOV', bitrateKbps: 69140), 64 * 1024 * 1024);
      expect(networkStreamRingBytes(container: 'mp4', bitrateKbps: 69140), 64 * 1024 * 1024);
    });

    test('matches ffmpeg demuxer alias lists from Jellyfin', () {
      expect(networkStreamRingBytes(container: 'mov,mp4,m4a,3gp,3g2,mj2', bitrateKbps: 69140), 64 * 1024 * 1024);
      expect(networkStreamRingBytes(container: 'matroska,webm', bitrateKbps: 69140), 64 * 1024 * 1024);
    });

    test('falls back to 64MiB when bitrate is unknown', () {
      expect(networkStreamRingBytes(container: 'mov', bitrateKbps: null), 64 * 1024 * 1024);
      expect(networkStreamRingBytes(container: 'mov', bitrateKbps: 0), 64 * 1024 * 1024);
    });

    test('clamps to the 16MiB floor for low bitrates', () {
      expect(networkStreamRingBytes(container: 'mp4', bitrateKbps: 1000), 16 * 1024 * 1024);
    });

    test('clamps to the 128MiB ceiling for very high bitrates', () {
      expect(networkStreamRingBytes(container: 'mov', bitrateKbps: 400000), 128 * 1024 * 1024);
    });

    test('respects a lower Android heap cap, including the unknown-bitrate path', () {
      expect(
        networkStreamRingBytes(container: 'mov', bitrateKbps: 69140, maxBytes: 32 * 1024 * 1024),
        32 * 1024 * 1024,
      );
      expect(networkStreamRingBytes(container: 'mov', bitrateKbps: null, maxBytes: 32 * 1024 * 1024), 32 * 1024 * 1024);
    });
  });

  group('androidStreamRingCapBytes', () {
    test('tiers by device heap with a conservative unknown fallback', () {
      expect(androidStreamRingCapBytes(0), 64 * 1024 * 1024);
      expect(androidStreamRingCapBytes(256), 32 * 1024 * 1024);
      expect(androidStreamRingCapBytes(512), 64 * 1024 * 1024);
      expect(androidStreamRingCapBytes(1024), 128 * 1024 * 1024);
    });
  });

  group('readForwardCacheBytes', () {
    test('takes what the player reports', () async {
      expect(await readForwardCacheBytes(() async => '33554432'), 32 << 20);
    });

    test('falls back to 64 MiB when the player says nothing usable or throws', () async {
      expect(await readForwardCacheBytes(() async => null), assumedForwardCacheBytes);
      expect(await readForwardCacheBytes(() async => 'auto'), assumedForwardCacheBytes);
      expect(await readForwardCacheBytes(() async => throw StateError('no property')), assumedForwardCacheBytes);
    });
  });

  group('parseMpvByteSize', () {
    test('reads the plain bytes mpv reports, and a suffix in case a build formats one', () {
      expect(parseMpvByteSize('67108864'), 64 * 1024 * 1024);
      expect(parseMpvByteSize(' 33554432 '), 32 * 1024 * 1024);
      expect(parseMpvByteSize('64MiB'), 64 * 1024 * 1024);
      expect(parseMpvByteSize('1.5 GiB'), (1.5 * 1024 * 1024 * 1024).round());
      expect(parseMpvByteSize('512k'), 512 * 1024);
    });

    test('anything unreadable is null, so the opener keeps the default', () {
      for (final raw in [null, '', 'auto', '0', '-1', 'MiB']) {
        expect(parseMpvByteSize(raw), isNull, reason: '$raw');
      }
    });
  });

  group('networkTimeoutSeconds', () {
    // Log vcf49: a stalled connection was only noticed after about 36 s.
    // Code review of 14 November 2026: the timeout used 64 MiB everywhere.
    test('a smaller cache than 64 MiB shortens the wait', () {
      int t(int mib, int kbps) =>
          networkTimeoutSeconds(isNetworkVod: true, isTranscoding: false, bitrateKbps: kbps, cacheBytes: mib << 20);
      expect(t(64, 40000), 6, reason: '64 MiB at 40 Mbit/s holds 13.4 s');
      expect(t(32, 40000), 4, reason: 'Android with 256 MB heap: 6.7 s of cache, half is 3, floored to the minimum');
      expect(t(16, 20000), 4, reason: 'a manual 16 MiB buffer');
      expect(t(512, 40000), 10, reason: 'the disk cache keeps the ceiling');
    });

    test('direct play of a network file gives up a silent connection after ten seconds', () {
      expect(networkTimeoutSeconds(isNetworkVod: true, isTranscoding: false), 10);
      expect(directPlayNetworkTimeoutSeconds, lessThan(mpvDefaultNetworkTimeoutSeconds));
    });

    test('the wait is half of what 64 MiB holds at the bitrate, between four and ten seconds', () {
      int t(int kbps) => networkTimeoutSeconds(isNetworkVod: true, isTranscoding: false, bitrateKbps: kbps);
      expect(t(8000), 10, reason: 'a light file keeps the ten seconds');
      expect(t(26000), 10, reason: 'log vcf49: about 20 s of cache');
      expect(t(40000), 6);
      expect(t(60000), 4);
      expect(t(80000), 4, reason: 'never below four: a seek may wait on a disk');
      expect(networkTimeoutSeconds(isNetworkVod: true, isTranscoding: false, bitrateKbps: 0), 10);
    });

    test('a bitrate changes nothing for a transcode or local media', () {
      expect(networkTimeoutSeconds(isNetworkVod: true, isTranscoding: true, bitrateKbps: 80000), 60);
      expect(networkTimeoutSeconds(isNetworkVod: false, isTranscoding: false, bitrateKbps: 80000), 60);
    });

    test('a transcode, live and local media keep the mpv default', () {
      expect(networkTimeoutSeconds(isNetworkVod: true, isTranscoding: true), 60);
      expect(networkTimeoutSeconds(isNetworkVod: false, isTranscoding: false), 60);
      expect(networkTimeoutSeconds(isNetworkVod: false, isTranscoding: true), 60);
    });
  });

  group('appleTvDiskCacheProperties', () {
    Map<String, String> p({bool enabled = true, bool tv = true, int mb = 0, String? dir = '/tmp/c'}) =>
        appleTvDiskCacheProperties(enabled: enabled, isAppleTV: tv, bufferSizeMB: mb, cacheDir: dir);

    test('on an Apple TV in auto mode with the switch on the cache goes to disk', () {
      expect(p(), {'cache-on-disk': 'yes', 'demuxer-cache-dir': '/tmp/c', 'demuxer-max-bytes': '${512 * 1024 * 1024}'});
    });

    test('off without the switch, off the Apple TV, with a manual buffer or without a directory', () {
      for (final off in [p(enabled: false), p(tv: false), p(mb: 100), p(dir: null), p(dir: '')]) {
        expect(off, {'cache-on-disk': 'no'});
      }
    });
  });
}

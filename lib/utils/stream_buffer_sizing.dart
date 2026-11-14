import 'dart:math';

/// mpv's built-in `stream-buffer-size` default (128 KiB). Written back for
/// opens that don't qualify for an enlarged ring so a reused player instance
/// never carries one item's tuning into the next.
const mpvDefaultStreamBufferBytes = 128 * 1024;

/// QuickTime/MP4 muxer family. Apple capture muxers (iPhone recordings and
/// friends) can store audio packets seconds away from coeval video packets —
/// in bytes, seconds × video byterate — which makes ffmpeg's DTS-ordered
/// reads ping-pong across the file. Over HTTP every ping-pong that escapes
/// mpv's stream ring buffer is a byte seek, and ffmpeg's http layer drops and
/// redials the connection on every seek, collapsing throughput.
const quickTimeFamilyContainers = {'mp4', 'mov', 'm4v', '3gp', '3g2'};

/// Matroska/WebM is normally well-interleaved, but UHD direct-play remuxes can
/// still overrun mpv's tiny 128 KiB default stream ring during normal demuxer
/// read bursts. Only opt in when the server reports a high bitrate so common
/// MKV playback keeps the default memory profile.
const matroskaFamilyContainers = {'mkv', 'matroska', 'webm'};
const _highBitrateMatroskaThresholdKbps = 40 * 1000;

/// mpv's built-in `network-timeout` (seconds): how long a network read may
/// stay silent before it counts as an error.
const mpvDefaultNetworkTimeoutSeconds = 60;

/// The read timeout for direct network playback. A connection that stalls
/// without closing is otherwise only noticed when the peer or the OS ends it:
/// on an Apple TV (log vcf49, 13 November 2026) the stream stood still for
/// about 36 seconds, the 64 MiB cache ran dry after 20 and playback buffered
/// for 16 seconds, although the reconnect then took one second. With ten
/// seconds ffmpeg gives up the dead connection and reconnects at the same
/// byte while the cache still plays.
const directPlayNetworkTimeoutSeconds = 10;

/// The shortest read timeout: below this a slow first byte after a seek (a
/// disk that spins up) would count as a dead connection.
const minDirectPlayNetworkTimeoutSeconds = 4;

/// The forward cache assumed when the player cannot say what it has: the
/// Apple TV ceiling of `appleTvDemuxerLimits`. The opener reads the real
/// `demuxer-max-bytes` first, because a cache can be smaller: 32 MiB on an
/// Android device with 256 MB heap or less, and a manual buffer can go lower.
const assumedForwardCacheBytes = 64 * 1024 * 1024;

/// The forward cache a player really has, from [read] (the player's
/// `demuxer-max-bytes`). A player that cannot say, or says something
/// unreadable, gets [assumedForwardCacheBytes].
Future<int> readForwardCacheBytes(Future<String?> Function() read) async {
  try {
    return parseMpvByteSize(await read()) ?? assumedForwardCacheBytes;
  } catch (_) {
    return assumedForwardCacheBytes;
  }
}

/// A byte size as mpv reports it for an option such as `demuxer-max-bytes`.
/// mpv 0.37 answers with plain bytes (`67108864`), also for a value set as
/// `64MiB`; a suffix is read as well in case a build formats it. Null for
/// anything else, so the caller falls back to [assumedForwardCacheBytes].
int? parseMpvByteSize(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final plain = int.tryParse(text);
  if (plain != null) return plain > 0 ? plain : null;
  final match = RegExp(r'^(\d+(?:\.\d+)?)\s*([KMG])i?B?$', caseSensitive: false).firstMatch(text);
  if (match == null) return null;
  final unit = switch (match.group(2)!.toUpperCase()) {
    'K' => 1024,
    'M' => 1024 * 1024,
    _ => 1024 * 1024 * 1024,
  };
  final bytes = (double.parse(match.group(1)!) * unit).round();
  return bytes > 0 ? bytes : null;
}

/// The `network-timeout` for an open. Only direct play of a network file gets
/// a short one: a transcode can keep a request waiting while the server
/// prepares its first segments, and live and local media keep mpv's default.
///
/// The cache must outlast the wait: at [bitrateKbps] the forward cache holds
/// `cache / bitrate` seconds, and half of that is spent waiting, so the
/// reconnect has the other half to deliver. 64 MiB at 26 Mbit/s is 20 s and
/// keeps the ten seconds; at 80 Mbit/s it is 6.7 s and the wait drops to four.
/// Without a bitrate the ten seconds stand.
int networkTimeoutSeconds({
  required bool isNetworkVod,
  required bool isTranscoding,
  int? bitrateKbps,
  int cacheBytes = assumedForwardCacheBytes,
}) {
  if (!isNetworkVod || isTranscoding) return mpvDefaultNetworkTimeoutSeconds;
  if (bitrateKbps == null || bitrateKbps <= 0) return directPlayNetworkTimeoutSeconds;
  final cacheSeconds = cacheBytes * 8 / (bitrateKbps * 1000);
  return (cacheSeconds / 2).floor().clamp(minDirectPlayNetworkTimeoutSeconds, directPlayNetworkTimeoutSeconds);
}

/// The forward cache when it lives on disk (512 MiB): minutes of a film
/// instead of seconds, without the memory the 64 MiB ceiling protects.
const appleTvDiskCacheBytes = 512 * 1024 * 1024;

/// Demuxer cache on disk for Apple TV in auto buffer mode, off unless the
/// build sets `PLEYA_TV_DISK_CACHE`. mpv writes packets to an unlinked file in
/// [cacheDir] and keeps only an index in memory. Measured with mpv 0.37 on
/// Linux (13 November 2026, 20 Mbit/s file, 30 s outage): 256 MiB on disk
/// played through at 89 MB of process memory, the same in memory took 232 MB,
/// and 16 MiB in memory buffered. Not yet proven on tvOS, hence the switch.
Map<String, String> appleTvDiskCacheProperties({
  required bool enabled,
  required bool isAppleTV,
  required int bufferSizeMB,
  required String? cacheDir,
}) => enabled && isAppleTV && bufferSizeMB == 0 && cacheDir != null && cacheDir.isNotEmpty
    ? {'cache-on-disk': 'yes', 'demuxer-cache-dir': cacheDir, 'demuxer-max-bytes': '$appleTvDiskCacheBytes'}
    : const {'cache-on-disk': 'no'};

const minStreamRingBytes = 16 * 1024 * 1024;
const maxStreamRingBytes = 128 * 1024 * 1024;

/// Ring for QuickTime-family content whose bitrate the backend didn't report.
const unknownBitrateStreamRingBytes = 64 * 1024 * 1024;

/// Seconds of content bytes the ring should hold. mpv guarantees only half
/// the ring as seek-back history, so 6s of bytes ⇒ ≥3s of guaranteed
/// interleave-skew coverage (observed iPhone skew ~2.9s) before the
/// power-of-two round-up adds headroom.
const _streamRingContentSeconds = 6;

int nextPowerOfTwo(int value) {
  var result = 1;
  while (result < value) {
    result <<= 1;
  }
  return result;
}

/// Heap-tier cap for the stream ring on Android, mirroring the demuxer
/// auto-scaling tiers in video_player_screen.dart — mpv is the
/// ExoPlayer-fallback engine there, which is exactly where low-RAM TV boxes
/// land.
int androidStreamRingCapBytes(int heapMB) {
  if (heapMB <= 0) return unknownBitrateStreamRingBytes;
  if (heapMB <= 256) return 32 * 1024 * 1024;
  if (heapMB <= 512) return 64 * 1024 * 1024;
  return maxStreamRingBytes;
}

/// mpv `stream-buffer-size` for a network direct play of [container] at
/// [bitrateKbps] total bitrate, or null when mpv's 128 KiB default suffices.
///
/// The ring absorbs the demuxer's audio↔video byte alternation entirely in
/// RAM so the underlying HTTP reads stay linear. The ring is fully allocated
/// (power-of-two rounded) per stream, hence the container gate and bitrate
/// scaling instead of a flat global value.
int? networkStreamRingBytes({
  required String? container,
  required int? bitrateKbps,
  int maxBytes = maxStreamRingBytes,
}) {
  if (container == null) return null;
  // Jellyfin may report ffmpeg demuxer alias lists ('mov,mp4,m4a,3gp,3g2,mj2').
  final tokens = container.toLowerCase().split(',').map((token) => token.trim());
  final isQuickTimeFamily = tokens.any(quickTimeFamilyContainers.contains);
  final isMatroskaFamily = tokens.any(matroskaFamilyContainers.contains);
  if (!isQuickTimeFamily && !isMatroskaFamily) return null;

  final cap = max(minStreamRingBytes, min(maxBytes, maxStreamRingBytes));
  if (bitrateKbps == null || bitrateKbps <= 0) {
    return isQuickTimeFamily ? min(unknownBitrateStreamRingBytes, cap) : null;
  }
  if (!isQuickTimeFamily && bitrateKbps < _highBitrateMatroskaThresholdKbps) return null;

  final bytesPerSecond = bitrateKbps * 1000 ~/ 8;
  final ring = nextPowerOfTwo(bytesPerSecond * _streamRingContentSeconds);
  return max(minStreamRingBytes, min(ring, cap));
}

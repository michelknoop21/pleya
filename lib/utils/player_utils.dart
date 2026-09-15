import '../mpv/mpv.dart';

/// Live video resolution and codec, read from mpv rather than the
/// server-declared `MediaVersion`: a transcode can change what actually
/// reaches the player, so only the live properties are guaranteed to match
/// what is on screen right now.
Future<({String? resolution, String? videoCodec})> readLiveVideoQuality(Player player) async {
  final height = await player.getProperty('height');
  final codec = await player.getProperty('video-codec');
  final h = int.tryParse(height ?? '');
  return (
    resolution: h != null && h > 0 ? '${h}p' : null,
    videoCodec: (codec != null && codec.trim().isNotEmpty) ? codec.trim().toUpperCase() : null,
  );
}

/// Friendly label for a channel count, shared by the TV info panel and the
/// player's persistent quality line.
String audioChannelLabel(int channels) {
  return switch (channels) {
    1 => 'Mono',
    2 => 'Stereo',
    6 => '5.1',
    8 => '7.1',
    _ => '$channels ch',
  };
}

const restartBeforePreviousItemThreshold = Duration(seconds: 3);
const plexTranscodeSeekRangeStartTolerance = Duration(milliseconds: 500);
const plexTranscodeSeekRangeEndGuard = Duration(milliseconds: 500);
const plexTranscodeSeekNoopTolerance = Duration(seconds: 1);

enum PlexTranscodeSeekAction { nativeSeek, restartTranscode }

bool shouldRestartBeforePreviousItem(Duration position) {
  return position > restartBeforePreviousItemThreshold;
}

Duration clampSeekPosition(Player player, Duration position) {
  final duration = player.state.duration;
  if (position.isNegative) return Duration.zero;
  if (duration > Duration.zero && position > duration) return duration;
  return position;
}

/// Plex MKV-over-HTTP transcodes are only native-seeked inside ranges the
/// player reports as locally seekable. Anything outside those ranges needs a
/// server-offset transcode restart.
PlexTranscodeSeekAction resolvePlexTranscodeSeekAction({
  required Duration currentPosition,
  required Duration target,
  required List<BufferRange> bufferRanges,
  bool allowBufferedNativeSeek = true,
  Duration rangeStartTolerance = plexTranscodeSeekRangeStartTolerance,
  Duration rangeEndGuard = plexTranscodeSeekRangeEndGuard,
  Duration noopTolerance = plexTranscodeSeekNoopTolerance,
}) {
  final validRanges = bufferRanges.where((range) => range.end >= range.start).toList();
  if (allowBufferedNativeSeek &&
      _isInAnyBufferedSeekRange(target, validRanges, startTolerance: rangeStartTolerance, endGuard: rangeEndGuard)) {
    return PlexTranscodeSeekAction.nativeSeek;
  }

  if ((target - currentPosition).abs() <= noopTolerance) {
    return PlexTranscodeSeekAction.nativeSeek;
  }

  return PlexTranscodeSeekAction.restartTranscode;
}

bool _isInAnyBufferedSeekRange(
  Duration target,
  List<BufferRange> ranges, {
  required Duration startTolerance,
  required Duration endGuard,
}) {
  for (final range in ranges) {
    if (target >= range.start - startTolerance && target <= range.end - endGuard) return true;
  }
  return false;
}

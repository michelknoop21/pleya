import 'live_tv_support.dart';
import '../models/livetv_channel.dart';
import '../models/livetv_dvr.dart';
import '../models/livetv_program.dart';

/// No-op [LiveTvSupport] for backends that don't have live TV (local folders).
class NoopLiveTvSupport implements LiveTvSupport {
  const NoopLiveTvSupport();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<LiveTvDvr>> fetchDvrs() async => [];

  @override
  Future<List<LiveTvChannel>> fetchChannels({String? lineup}) async => [];

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) async => [];

  @override
  Future<LiveTvStreamResolution?> resolveStreamUrl(String channelKey, {String? dvrKey}) async => null;

  @override
  Future<LiveTvPlaybackSession?> startPlayback(String channelKey, {String? dvrKey}) async => null;

  @override
  Future<String> buildFavoriteChannelSource({String? lineup}) async => '';

  @override
  LiveTvFavoritesStore? get favorites => null;
}

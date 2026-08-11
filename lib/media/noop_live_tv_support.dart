import 'live_tv_support.dart';
import '../models/livetv_channel.dart';
import '../models/livetv_dvr.dart';
import '../models/livetv_program.dart';
import '../models/media_grab_operation.dart';
import '../models/media_subscription.dart';

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
  String get favoriteStoreKey => 'noop';

  @override
  FavoriteChannelPersistenceMode get favoritePersistenceMode => FavoriteChannelPersistenceMode.none;

  @override
  Future<List<FavoriteChannel>> fetchFavoriteChannels() async => [];

  @override
  Future<void> setFavoriteChannels(List<FavoriteChannel> channels) async {}

  @override
  Future<LiveTvActivityResult<void>> reloadGuide(String dvrId) async => const LiveTvActivityResult(value: null);

  @override
  Future<List<SubscriptionTemplate>> getSubscriptionTemplate(String guid) async => [];

  @override
  Future<List<MediaSubscription>> fetchRecordingRules({bool includeGrabs = true, bool includeStorage = true}) async =>
      [];

  @override
  Future<MediaSubscription?> createRecordingRule(MediaSubscriptionCreateRequest request) async => null;

  @override
  Future<MediaSubscription?> updateRecordingRule(String subscriptionId, Map<String, Object?> prefs) async => null;

  @override
  Future<void> deleteRecordingRule(String subscriptionId) async {}

  @override
  Future<void> processRecordingRules() async {}

  @override
  Future<List<MediaGrabOperation>> fetchScheduledRecordings() async => [];

  @override
  Future<void> cancelGrab(String operationId) async {}

  @override
  Future<List<MediaSubscription>> fetchSubscriptionMapping({
    required String providerId,
    required List<String> ratingKeys,
    bool includeStorage = true,
  }) async => [];
}

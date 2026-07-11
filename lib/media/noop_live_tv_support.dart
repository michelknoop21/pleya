import 'live_tv_support.dart';
import '../models/livetv_channel.dart';
import '../models/livetv_dvr.dart';
import '../models/livetv_lineup.dart';
import '../models/livetv_program.dart';
import '../models/livetv_server_status.dart';
import '../models/livetv_session.dart';
import '../models/media_grab_operation.dart';
import '../models/media_grabber_device.dart';
import '../models/media_provider_info.dart';
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
  Future<LiveTvServerStatus> fetchLiveTvServerStatus() async => const LiveTvServerStatus();

  @override
  Future<LiveTvDvr?> fetchDvr(String dvrId) async => null;

  @override
  Future<LiveTvActivityResult<LiveTvDvr?>> createDvr({
    required List<String> devices,
    required List<String> lineups,
    String? language,
    String? country,
    String? postalCode,
  }) async => LiveTvActivityResult(value: null);

  @override
  Future<void> deleteDvr(String dvrId) async {}

  @override
  Future<void> updateDvrPrefs(String dvrId, Map<String, Object?> prefs) async {}

  @override
  Future<void> attachDeviceToDvr(String dvrId, String deviceId) async {}

  @override
  Future<void> detachDeviceFromDvr(String dvrId, String deviceId) async {}

  @override
  Future<void> addLineupToDvr(String dvrId, String lineupUri) async {}

  @override
  Future<void> removeLineupFromDvr(String dvrId, String lineupUri) async {}

  @override
  Future<LiveTvActivityResult<void>> reloadGuide(String dvrId) async => const LiveTvActivityResult(value: null);

  @override
  Future<void> cancelGuideReload(String dvrId) async {}

  @override
  Future<List<MediaGrabber>> fetchGrabbers({String? protocol}) async => [];

  @override
  Future<List<MediaGrabberDevice>> fetchGrabberDevices() async => [];

  @override
  Future<LiveTvActivityResult<List<MediaGrabberDevice>>> discoverGrabberDevices() async =>
      LiveTvActivityResult(value: []);

  @override
  Future<MediaGrabberDevice?> fetchGrabberDevice(String deviceId) async => null;

  @override
  Future<MediaGrabberDevice?> addGrabberDevice(String uri, {String? grabberId}) async => null;

  @override
  Future<void> updateGrabberDevice(String deviceId, {bool? enabled, String? title}) async {}

  @override
  Future<void> deleteGrabberDevice(String deviceId) async {}

  @override
  Future<List<MediaGrabberDeviceChannel>> fetchGrabberDeviceChannels(String deviceId) async => [];

  @override
  Future<LiveTvActivityResult<MediaGrabberDevice?>> scanGrabberDevice(
    String deviceId, {
    String? source,
    Map<String, Object?> prefs = const {},
    String? network,
    String? country,
  }) async => LiveTvActivityResult(value: null);

  @override
  Future<MediaGrabberDevice?> cancelGrabberDeviceScan(String deviceId) async => null;

  @override
  Future<MediaGrabberDevice?> saveGrabberDeviceChannelMap(String deviceId, MediaGrabberChannelMapRequest request) async =>
      null;

  @override
  Future<void> updateGrabberDevicePrefs(String deviceId, Map<String, Object?> prefs) async {}

  @override
  String buildGrabberDeviceThumbUrl(String deviceId, int version) => '';

  @override
  Future<List<LiveTvCountry>> fetchEpgCountries() async => [];

  @override
  Future<List<LiveTvLanguage>> fetchEpgLanguages() async => [];

  @override
  Future<List<LiveTvRegion>> fetchEpgRegions(String country, String epgId) async => [];

  @override
  Future<LiveTvLineupResult> fetchEpgLineups(String country, String epgId, {String? postalCode, String? region}) async =>
      LiveTvLineupResult(lineups: []);

  @override
  Future<List<LiveTvChannel>> fetchEpgChannelsForLineup(String lineupUri) async => [];

  @override
  Future<List<LiveTvLineup>> fetchEpgChannelsForLineups(List<String> lineupUris) async => [];

  @override
  Future<List<ChannelMapping>> computeEpgChannelMap({required String deviceUri, required String lineupUri}) async =>
      [];

  @override
  Future<LiveTvActivityResult<Map<String, dynamic>?>> findBestLineup({
    required String deviceUri,
    required String lineupGroupUri,
  }) async => LiveTvActivityResult(value: null);

  @override
  Future<List<SubscriptionTemplate>> getSubscriptionTemplate(String guid) async => [];

  @override
  Future<List<MediaSubscription>> fetchRecordingRules({
    bool includeGrabs = true,
    bool includeStorage = true,
  }) async => [];

  @override
  Future<MediaSubscription?> fetchRecordingRule(
    String subscriptionId, {
    bool includeGrabs = true,
    bool includeStorage = true,
  }) async => null;

  @override
  Future<MediaSubscription?> createRecordingRule(MediaSubscriptionCreateRequest request) async => null;

  @override
  Future<MediaSubscription?> updateRecordingRule(String subscriptionId, Map<String, Object?> prefs) async => null;

  @override
  Future<void> deleteRecordingRule(String subscriptionId) async {}

  @override
  Future<MediaSubscription?> moveRecordingRule(String subscriptionId, {String? afterSubscriptionId}) async => null;

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

  @override
  Future<List<MediaProviderInfo>> fetchMediaProviders() async => [];

  @override
  Future<void> registerMediaProvider(String url) async {}

  @override
  Future<void> refreshMediaProviders() async {}

  @override
  Future<void> unregisterMediaProvider(String providerId) async {}

  @override
  Future<List<LiveTvSession>> fetchLiveTvSessionsDetailed() async => [];

  @override
  Future<LiveTvSession?> fetchLiveTvSession(String sessionId) async => null;

  @override
  Uri buildNotificationWebSocketUri({List<String>? filters}) => Uri();

  @override
  Uri buildNotificationEventSourceUri({List<String>? filters}) => Uri();
}
/// WRITES TO THE SERVER. Run it only against a throwaway test server: it
/// signs in as an admin, replaces the first movie's primary image, creates and
/// deletes a playlist and a collection, and toggles watch state, rating and
/// favorite. The overview edit is restored; the uploaded poster is not.
///
/// Live smoke test against a real Emby server (DEC-141). Skipped unless
/// `PLEYA_EMBY_URL`, `PLEYA_EMBY_USER` and `PLEYA_EMBY_PASSWORD` are set; CI
/// never runs it. Expects at least one movie with an external subtitle and one
/// series episode. Every step runs even when an earlier one fails, and every
/// non-2xx response is printed, so one run shows every place Emby differs.
///
///   PLEYA_EMBY_URL=http://localhost:18096 PLEYA_EMBY_USER=pleya \
///   PLEYA_EMBY_PASSWORD=... flutter test test/live/emby_live_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/jellyfin_auth_header.dart';
import 'package:pleya/services/jellyfin_auth_service.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/playback_initialization_types.dart';

class _LoggingClient extends http.BaseClient {
  _LoggingClient(this.headers);
  final Map<String, String> headers;
  final http.Client _inner = http.Client();
  final failures = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    headers.forEach((k, v) => request.headers.putIfAbsent(k, () => v));
    final response = await _inner.send(request);
    // fetchChildren tries `/Shows/{id}/Seasons` first and falls back on 404
    // for a season id; Jellyfin answers the same way.
    final seasonsProbe = response.statusCode == 404 && request.url.path.endsWith('/Seasons');
    if (response.statusCode >= 300 && !seasonsProbe)
      failures.add('${request.method} ${request.url.path}?${request.url.query} -> ${response.statusCode}');
    return response;
  }
}

void main() {
  final env = Platform.environment;
  final url = env['PLEYA_EMBY_URL'];
  final skip = url == null ? 'PLEYA_EMBY_URL not set' : null;
  // PLEYA_LIVE_EXPECT=jellyfin runs the same walk against a Jellyfin server,
  // to prove the Emby branches left Jellyfin alone.
  final expectEmby = env['PLEYA_LIVE_EXPECT'] != 'jellyfin';

  test('the Jellyfin client works end to end against ${expectEmby ? 'Emby' : 'Jellyfin'}', skip: skip, () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    JellyfinApiCache.initialize(db);
    addTearDown(db.close);

    final auth = JellyfinConnectionAuthService(clientName: 'Pleya', clientVersion: '1.0', deviceName: 'Pleya');
    final info = await auth.probe(url!);
    expect(info.isEmby, expectEmby, reason: 'probe must tell Emby and Jellyfin apart');
    final connection = await auth.authenticateByName(
      baseUrl: url,
      username: env['PLEYA_EMBY_USER']!,
      password: env['PLEYA_EMBY_PASSWORD'] ?? '',
      deviceId: 'pleya-live-test',
      serverInfo: info,
    );
    expect(connection.isEmby, expectEmby);
    expect(await auth.validate(connection), isTrue, reason: 'validate uses the current-user route');
    expect(
      await auth.isQuickConnectEnabled(url),
      !expectEmby,
      reason: 'Emby has no QuickConnect; Jellyfin 10.7+ enables it by default',
    );

    final authValue = buildJellyfinAuthHeader(
      clientName: 'Pleya',
      clientVersion: '1.0',
      deviceName: 'Pleya',
      deviceId: connection.deviceId,
      accessToken: connection.accessToken,
    );
    final net = _LoggingClient({
      ...jellyfinAuthHeaders(authValue, isEmby: expectEmby),
      'Content-Type': 'application/json',
    });
    final client = JellyfinClient.forTesting(connection: connection, httpClient: net);
    // MultiServerManager wires this from Policy.IsAdministrator in the app.
    client.canManageServerMetadata = () => connection.isAdministrator;
    expect(connection.isAdministrator, isTrue, reason: 'Emby admin must arrive as isAdministrator');
    addTearDown(client.close);

    final errors = <String>[];
    Future<T?> step<T>(String name, Future<T> Function() body) async {
      final before = net.failures.length;
      try {
        final result = await body();
        final failed = net.failures.sublist(before);
        stdout.writeln('${failed.isEmpty ? 'OK  ' : 'HTTP'} $name ${failed.isEmpty ? '' : failed}');
        if (failed.isNotEmpty) errors.add('$name: $failed');
        return result;
      } catch (e) {
        stdout.writeln('FAIL $name: $e ${net.failures.sublist(before)}');
        errors.add('$name: $e');
        return null;
      }
    }

    void check(String name, bool ok) {
      stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $name');
      if (!ok) errors.add(name);
    }

    check('health', await step('checkHealth', client.isHealthy) == true);
    // A connection saved before Emby support has isEmby false; the health
    // check must detect Emby, migrate and come online, and leave Jellyfin alone.
    final legacy = JellyfinClient.forTesting(
      connection: connection.copyWith(isEmby: false),
      httpClient: _LoggingClient({
        ...jellyfinAuthHeaders(authValue, isEmby: false),
        'Content-Type': 'application/json',
      }),
    );
    addTearDown(legacy.close);
    check('legacy connection healthy', await step('legacy checkHealth', legacy.isHealthy) == true);
    check('legacy connection migrated', legacy.connection.isEmby == expectEmby);
    await step('fetchUserProfile', client.fetchUserProfile);
    final libraries = await step('fetchLibraries', client.fetchLibraries) ?? const [];
    check('two libraries', libraries.length >= 2);
    final movies = libraries.firstWhere((l) => l.kind == MediaKind.movie);
    final shows = libraries.firstWhere((l) => l.kind == MediaKind.show);

    final page = await step('fetchLibraryContent', () => client.fetchLibraryContent(movies.id, const LibraryQuery()));
    final movie = page?.items.firstOrNull;
    check('a movie', movie != null);
    if (movie == null) fail(errors.join('\n'));

    final filters = await step('fetchLibraryFiltersWithValues', () => client.fetchLibraryFiltersWithValues(movies.id));
    check('year filter offered', filters?.filters.any((f) => f.filter == 'year') ?? false);
    await step('fetchFirstCharacters', () => client.fetchFirstCharacters(movies.id));
    final detail = await step('fetchItem', () => client.fetchItem(movie.id));
    check('item detail', detail?.id == movie.id);
    await step('fetchItemWithOnDeck', () => client.fetchItemWithOnDeck(movie.id));
    await step('fetchExtras', () => client.fetchExtras(movie.id));
    await step('fetchRelatedHubs', () => client.fetchRelatedHubs(movie.id));
    await step('fetchExternalIds', () => client.fetchExternalIds(movie.id));
    await step('getFileInfo', () => client.getFileInfo(movie));
    final search = await step('searchItems', () => client.searchItems('Bunny'));
    check('search finds the movie', search?.any((i) => i.id == movie.id) ?? false);
    await step('searchPeople', () => client.searchPeople('a'));
    await step('fetchRecentlyAdded', client.fetchRecentlyAdded);
    await step('fetchGlobalHubs', client.fetchGlobalHubs);
    await step('fetchLibraryHubs', () => client.fetchLibraryHubs(movies.id, libraryName: movies.title));
    await step('fetchSortOptions', () => client.fetchSortOptions(movies.id));

    final showPage = await step(
      'fetchLibraryContent shows',
      () => client.fetchLibraryContent(shows.id, const LibraryQuery()),
    );
    final show = showPage?.items.firstOrNull;
    if (show != null) {
      final seasons = await step('fetchChildren seasons', () => client.fetchChildren(show.id)) ?? const [];
      if (seasons.isNotEmpty) {
        final episodes = await step('fetchChildren episodes', () => client.fetchChildren(seasons.first.id));
        check('an episode', episodes?.isNotEmpty ?? false);
      }
      await step('fetchPlayableDescendants', () => client.fetchPlayableDescendants(show.id));
    }

    // Playback: direct play, then a transcode.
    final direct = await step(
      'getPlaybackInitialization direct',
      () => client.getPlaybackInitialization(
        PlaybackInitializationOptions(metadata: detail ?? movie, selectedMediaIndex: 0),
      ),
    );
    check('direct play url', direct?.videoUrl != null && !direct!.isTranscoding);
    check('external subtitle listed', direct?.externalSubtitles.isNotEmpty ?? false);
    if (direct?.videoUrl != null) {
      final res = await net.send(http.Request('GET', Uri.parse(direct!.videoUrl!))..headers['Range'] = 'bytes=0-1023');
      check('stream url serves bytes (${res.statusCode})', res.statusCode == 200 || res.statusCode == 206);
      await res.stream.drain<void>();
    }
    for (final sub in direct?.externalSubtitles ?? const []) {
      final res = await net.get(Uri.parse(sub.uri));
      check('subtitle url serves (${res.statusCode})', res.statusCode == 200 && res.body.contains('Emby'));
    }
    final transcode = await step(
      'getPlaybackInitialization transcode',
      () => client.getPlaybackInitialization(
        PlaybackInitializationOptions(
          metadata: detail ?? movie,
          selectedMediaIndex: 0,
          qualityPreset: TranscodeQualityPreset.values.firstWhere((p) => p != TranscodeQualityPreset.original),
        ),
      ),
    );
    check('transcode url', transcode?.videoUrl != null && transcode!.isTranscoding);
    if (transcode?.videoUrl != null) {
      final res = await net.get(Uri.parse(transcode!.videoUrl!));
      check('transcode playlist serves (${res.statusCode})', res.statusCode == 200 && res.body.contains('#EXTM3U'));
    }

    // Progress, resume and watch state.
    const pos = Duration(seconds: 120);
    const dur = Duration(seconds: 480);
    await step('reportPlaybackStarted', () => client.reportPlaybackStarted(itemId: movie.id, position: Duration.zero));
    await step(
      'reportPlaybackProgress',
      () => client.reportPlaybackProgress(itemId: movie.id, position: pos, duration: dur),
    );
    await step(
      'reportPlaybackStopped',
      () => client.reportPlaybackStopped(itemId: movie.id, position: pos, duration: dur),
    );
    final resume = await step('fetchContinueWatching', client.fetchContinueWatching);
    check('movie is resumable', resume?.any((i) => i.id == movie.id) ?? false);
    final resumed = await step('fetchItem after progress', () => client.fetchItem(movie.id));
    check('resume offset stored (${resumed?.viewOffsetMs})', (resumed?.viewOffsetMs ?? 0) > 110000);
    check('Continue Watching removal only on Emby', client.capabilities.continueWatchingRemoval == expectEmby);
    if (expectEmby) {
      await step('removeFromContinueWatching', () => client.removeFromContinueWatching(movie));
      final afterHide = await step('fetchContinueWatching after hide', client.fetchContinueWatching);
      check('hidden from Continue Watching', !(afterHide?.any((i) => i.id == movie.id) ?? true));
    }

    await step('markWatched', () => client.markWatched(movie));
    check('watched', ((await client.fetchItem(movie.id))?.viewCount ?? 0) > 0);
    await step('markUnwatched', () => client.markUnwatched(movie));
    await step('rate like', () => client.rate(movie, 8));
    await step('rate clear', () => client.rate(movie, -1));
    await step('setFavorite on', () => client.setFavorite(movie, true));
    final favs = await step('fetchFavorites', client.fetchFavorites);
    check('favorite listed', favs?.items.any((i) => i.id == movie.id) ?? false);
    await step('setFavorite off', () => client.setFavorite(movie, false));

    // Metadata editing (admin): read, write back with a changed overview, images.
    final raw = await step('fetchEditableMetadataItem', () => client.fetchEditableMetadataItem(movie.id));
    if (raw != null) {
      await step(
        'updateMetadataItem',
        () => client.updateMetadataItem(movie.id, {...raw, 'Overview': 'Pleya live edit'}),
      );
      final edited = await client.fetchEditableMetadataItem(movie.id);
      check('overview saved', edited?['Overview'] == 'Pleya live edit');
      await step('restore overview', () => client.updateMetadataItem(movie.id, raw));
    }
    // A 1x1 PNG, uploaded raw the way JellyfinMetadataEditAdapter does.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    await step(
      'uploadItemImage',
      () => client.uploadItemImage(movie.id, imageType: 'Primary', bytes: png, contentType: 'image/png'),
    );
    final images = await step('getItemImageInfos', () => client.getItemImageInfos(movie.id));
    check('uploaded poster present', images?.any((i) => i['ImageType'] == 'Primary') ?? false);
    await step('getRemoteImages', () => client.getRemoteImages(movie.id, imageType: 'Primary'));

    // Playlists and collections.
    final playlist = await step('createPlaylist', () => client.createPlaylist(title: 'Pleya live', items: [movie]));
    if (playlist != null) {
      final items = await step('fetchPlaylistItems', () => client.fetchPlaylistItems(playlist.id));
      check('playlist holds the movie', items?.any((i) => i.id == movie.id) ?? false);
      await step('fetchPlaylists', client.fetchPlaylists);
      await step('deletePlaylist', () => client.deletePlaylist(playlist));
    }
    final collectionId = await step(
      'createCollection',
      () => client.createCollection(
        title: 'Pleya live ${DateTime.now().millisecondsSinceEpoch}',
        items: [movie],
        libraryId: movies.id,
      ),
    );
    if (collectionId != null) {
      await step('fetchCollections', () => client.fetchCollections(movies.id));
      await step('removeFromCollection', () => client.removeFromCollection(collectionId: collectionId, item: movie));
      await step(
        'deleteCollection',
        () => client.deleteCollection(MediaItem(id: collectionId, backend: movie.backend, kind: MediaKind.collection)),
      );
    }

    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/playback_language_intent.dart';
import 'package:pleya/media/playback_language_notice.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/mpv/player/player_stream_controllers.dart';
import 'package:pleya/services/pleya_profile_language_preference_store.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/track_manager.dart';
import 'package:pleya/services/track_preference_store.dart';

import '../test_helpers/prefs.dart';

// NOTE on coverage scope:
// `TrackManager` orchestrates the player + Plex client + SettingsService
// singleton. Most paths require a real (or fake) Player surface plus an
// initialized SettingsService.
//
// Coverage:
//   - Constructor wiring (mutable fields are settable, default values).
//   - `cacheExternalSubtitles` / `lastExternalSubtitles` round-trip.
//   - `addExternalSubtitles` invokes the player's addSubtitleTrack for each
//     entry with a non-null URI, preserves order, and silently swallows errors
//     thrown by the player.
//   - `cycleSubtitleTrack` / `cycleAudioTrack` are no-ops when the player has
//     fewer than 2 real tracks (early-return paths).
//   - `applyTrackSelectionWhenReady` waits for subtitle tracks when server
//     metadata says they exist.
//   - `onPlaybackRestart` is a no-op when not waiting for external subs.
//   - `onSecondarySubtitleTrackChanged` is a documented no-op.
//   - `dispose` is idempotent (timers/subscriptions cleared).
//
// What's NOT covered:
//   - Most `applyTrackSelection` selection permutations — the matching logic
//     itself lives in [TrackSelectionService] and is covered there.
//   - `onAudioTrackChanged` / `onSubtitleTrackChanged` — server-sync paths
//     require a fully-faked PlexClient and MediaSourceInfo with realistic
//     stream IDs. The matching logic itself lives in [TrackSelectionService]
//     and is covered there.
//   - `onBackendSwitched` — wraps applyTrackSelectionWhenReady and is
//     therefore gated on the same SettingsService dependency.
//   - `resumeAfterSubtitleLoad` — schedules a real wall-clock fallback Timer.

MediaItem _meta({String id = 'rk1'}) => MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie);

/// Player that records calls and can be configured per-test.
class _FakePlayer with PlayerStreamControllersMixin implements Player {
  PlayerState _state;
  _FakePlayer({
    Tracks tracks = const Tracks(),
    TrackSelection track = const TrackSelection(),
    this.attachesExternalSubtitlesAtOpen = false,
  }) : _state = PlayerState(tracks: tracks, track: track);

  @override
  PlayerState get state => _state;

  late final PlayerStreams _streams = createStreams();

  @override
  PlayerStreams get streams => _streams;

  @override
  final bool attachesExternalSubtitlesAtOpen;

  @override
  bool get disposed => false;

  set tracks(Tracks t) {
    _state = _state.copyWith(tracks: t);
  }

  void emitTracks(Tracks t) {
    tracks = t;
    tracksController.add(t);
  }

  // ── Recording surface ────────────────────────────────────────────
  final List<({String uri, String? title, String? language, bool select})> addSubtitleCalls = [];
  final List<AudioTrack> selectedAudio = [];
  final List<SubtitleTrack> selectedSubtitle = [];

  /// If non-null and >0, fail this many addSubtitleTrack calls before succeeding.
  int failAddSubtitleTimes = 0;
  Future<void> Function(String uri)? onAddSubtitleTrack;

  @override
  Future<void> addSubtitleTrack({required String uri, String? title, String? language, bool select = false}) async {
    if (failAddSubtitleTimes > 0) {
      failAddSubtitleTimes--;
      throw StateError('simulated addSubtitleTrack failure');
    }
    addSubtitleCalls.add((uri: uri, title: title, language: language, select: select));
    await onAddSubtitleTrack?.call(uri);
  }

  @override
  Future<void> selectAudioTrack(AudioTrack t) async => selectedAudio.add(t);

  @override
  Future<void> selectSubtitleTrack(SubtitleTrack t) async => selectedSubtitle.add(t);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrackManager _make({
  required _FakePlayer player,
  MediaItem? metadata,
  MediaSourceInfo? mediaInfo,
  bool active = true,
  void Function(String, {Duration? duration})? showMessage,
  void Function(PlaybackLanguageNotice)? onLanguageNotice,
}) {
  return TrackManager(
    player: player,
    isActive: () => active,
    persistTrackPreference: _noopPersister,
    getProfileSettings: () => null,
    waitForProfileSettings: () async {},
    metadata: metadata ?? _meta(),
    mediaInfo: mediaInfo,
    showMessage: showMessage,
    onLanguageNotice: onLanguageNotice,
  );
}

MediaSourceInfo _mediaInfoWithSubtitles({bool selected = false}) {
  return MediaSourceInfo(
    videoUrl: 'https://example.com/video.mp4',
    audioTracks: [MediaAudioTrack(id: 1, language: 'English', languageCode: 'eng', selected: true)],
    subtitleTracks: [
      MediaSubtitleTrack(id: 10, language: 'English', languageCode: 'eng', selected: selected, forced: false),
    ],
    chapters: const [],
  );
}

Future<void> _drainAsync() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _noopPersister({required int partId, required String trackType, int? streamID}) async {}

void main() {
  // The constructor doesn't touch prefs, but [dispose] / [applyTrackSelection]
  // could leak across tests — reset to be safe.
  setUp(() {
    resetSharedPreferencesForTest();
    final previousDeviceName = TrackPreferenceStore.deviceNameProvider;
    TrackPreferenceStore.resetForTesting();
    TrackPreferenceStore.deviceNameProvider = () async => 'Fixture';
    addTearDown(() {
      TrackPreferenceStore.deviceNameProvider = previousDeviceName;
      TrackPreferenceStore.resetForTesting();
    });
  });

  // ============================================================
  // Construction
  // ============================================================

  group('server language preference wiring', () {
    final item = MediaItem(
      id: 'ep',
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.episode,
      grandparentId: 'show',
      serverId: 'srv',
    );
    TrackManager manager(
      _FakePlayer player, {
      Future<TrackLanguageChoice?> Function(String)? read,
      Future<void> Function(String, TrackLanguageChoice)? write,
    }) => TrackManager(
      player: player,
      isActive: () => true,
      metadata: item,
      getProfileSettings: () => null,
      waitForProfileSettings: () async {},
      readServerLanguage: read,
      persistServerLanguage: write,
    );
    _FakePlayer player() => _FakePlayer(
      tracks: const Tracks(
        audio: [
          AudioTrack(id: '1', language: 'eng'),
          AudioTrack(id: '2', language: 'nld'),
        ],
        subtitle: [
          SubtitleTrack(id: 's1', language: 'eng'),
          SubtitleTrack(id: 's2', language: 'nld'),
        ],
      ),
    );

    setUp(() async {
      await SettingsService.getInstance();
      PleyaProfileLanguagePreferenceStore.resetForTesting();
      await PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(audioLanguage: 'eng', seeded: true),
      );
    });

    test('server choice precedes global preferences without rewriting fallback', () async {
      var writes = 0;
      final p = player();
      final m = manager(
        p,
        read: (_) async => const TrackLanguageChoice(audioLanguage: 'nld', subtitlesOff: true, updatedAt: 1),
        write: (_, _) async {
          writes++;
        },
      );
      addTearDown(m.dispose);
      await m.applyTrackSelection();
      expect(p.selectedAudio.single.language, 'nld');
      expect(p.selectedSubtitle.last.id, 'no');
      expect(writes, 0);
    });

    test('a subtitle that arrives later stays out of the post-open selection', () async {
      final p = player();
      final m = manager(p, read: (_) async => null, write: (_, _) async {})..subtitleArrivesLater = true;
      addTearDown(m.dispose);
      await m.applyTrackSelection();
      expect(p.selectedAudio, isNotEmpty);
      expect(p.selectedSubtitle, isEmpty);
    });

    test('source preflight uses the same server preference without touching player or writing fallback', () async {
      var writes = 0;
      final p = player();
      final m = manager(
        p,
        read: (_) async => const TrackLanguageChoice(audioLanguage: 'nld', subtitlesOff: true, updatedAt: 1),
        write: (_, _) async {
          writes++;
        },
      );
      addTearDown(m.dispose);
      final choice = await m.selectSourceTracks(
        MediaSourceInfo(
          videoUrl: '',
          chapters: [],
          audioTracks: [
            MediaAudioTrack(id: 1, languageCode: 'eng', selected: true),
            MediaAudioTrack(id: 7, languageCode: 'nld', selected: false),
          ],
          subtitleTracks: [MediaSubtitleTrack(id: 3, languageCode: 'eng', selected: true, forced: false)],
        ),
      );
      expect(choice.audioStreamId, 7);
      expect(choice.subtitleStreamId, 0);
      expect(p.selectedAudio, isEmpty);
      expect(p.selectedSubtitle, isEmpty);
      expect(writes, 0);
    });

    test('a preference read from another device is available in language management', () async {
      final m = manager(player(), read: (_) async => const TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 1));
      addTearDown(m.dispose);
      await m.applyTrackSelection();
      final rows = await TrackPreferenceStore.readAllForActiveScope();
      expect(rows, hasLength(1));
      expect(rows.single.choice.provenance?.serverId, 'srv');
    });

    test('a cached remote choice refreshes instead of becoming an explicit override', () async {
      String? remote = 'nld';
      final p = player();
      final m = manager(
        p,
        read: (_) async => remote == null ? null : TrackLanguageChoice(audioLanguage: remote, updatedAt: 1),
      );
      addTearDown(m.dispose);
      await m.applyTrackSelection();
      expect(p.selectedAudio.last.language, 'nld');
      final cached = (await TrackPreferenceStore.readAllForActiveScope()).single;
      expect(cached.choice.fromServer, isTrue);
      remote = 'eng';
      await m.applyTrackSelection();
      expect(p.selectedAudio.last.language, 'eng');
      remote = null;
      await m.applyTrackSelection();
      expect(await TrackPreferenceStore.readAllForActiveScope(), isEmpty);
    });

    test('local explicit override precedes server choice', () async {
      await TrackPreferenceStore.saveAudio(item, language: 'eng');
      final p = player();
      final m = manager(p, read: (_) async => const TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 1));
      addTearDown(m.dispose);
      await m.applyTrackSelection();
      expect(p.selectedAudio.single.language, 'eng');
    });

    test('manual choices persist language and subtitle-off on the series', () async {
      final writes = <(String, TrackLanguageChoice)>[];
      final m = manager(
        player(),
        write: (id, choice) async {
          writes.add((id, choice));
        },
      );
      addTearDown(m.dispose);
      await m.onAudioTrackChanged(const AudioTrack(id: '17', language: 'nld'));
      await m.onSubtitleTrackChanged(const SubtitleTrack(id: 'no'));
      expect(writes, hasLength(2));
      expect(writes.last.$1, 'show');
      expect(writes.last.$2.audioLanguage, 'nld');
      expect(writes.last.$2.subtitlesOff, isTrue);
      await PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(rememberPerSeries: false, seeded: true),
      );
      await m.onAudioTrackChanged(const AudioTrack(id: '99', language: 'eng'));
      expect(writes, hasLength(2));
    });

    test('a profile switch discards a server response before it reaches the player', () async {
      final storage = await StorageService.getInstance();
      await storage.setActiveProfileId('one');
      final started = Completer<void>();
      final answer = Completer<TrackLanguageChoice?>();
      final p = player();
      final m = manager(
        p,
        read: (_) {
          started.complete();
          return answer.future;
        },
      );
      addTearDown(m.dispose);
      final applying = m.applyTrackSelection();
      await started.future.timeout(const Duration(seconds: 2));
      await storage.setActiveProfileId('two');
      answer.complete(const TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 1));
      await applying;
      expect(p.selectedAudio, isEmpty);
    });
  });

  group('constructor', () {
    test('initialises mutable fields with the provided values', () {
      final player = _FakePlayer();
      final mgr = TrackManager(
        player: player,
        isActive: () => true,
        persistTrackPreference: _noopPersister,
        getProfileSettings: () => null,
        waitForProfileSettings: () async {},
        metadata: _meta(),
        preferredAudioTrack: const AudioTrack(id: 'a-1', language: 'eng'),
        preferredSubtitleTrack: const SubtitleTrack(id: 's-1', language: 'eng'),
        preferredSecondarySubtitleTrack: const SubtitleTrack(id: 's-2', language: 'fre'),
      );
      addTearDown(mgr.dispose);

      expect(mgr.preferredAudioTrack?.id, 'a-1');
      expect(mgr.preferredSubtitleTrack?.id, 's-1');
      expect(mgr.preferredSecondarySubtitleTrack?.id, 's-2');
      expect(mgr.metadata.id, 'rk1');
      expect(mgr.waitingForExternalSubsTrackSelection, isFalse);
      expect(mgr.lastExternalSubtitles, isEmpty);
      expect(mgr.mediaInfo, isNull);
    });

    test('mutable fields can be reassigned (episode-navigation pattern)', () {
      final mgr = _make(player: _FakePlayer());
      addTearDown(mgr.dispose);

      mgr.metadata = _meta(id: 'next');
      mgr.preferredAudioTrack = const AudioTrack(id: 'a2', language: 'fre');
      mgr.waitingForExternalSubsTrackSelection = true;

      expect(mgr.metadata.id, 'next');
      expect(mgr.preferredAudioTrack?.id, 'a2');
      expect(mgr.waitingForExternalSubsTrackSelection, isTrue);
    });
  });

  // ============================================================
  // External subtitle cache
  // ============================================================

  group('cacheExternalSubtitles', () {
    test('round-trips through the lastExternalSubtitles getter', () {
      final mgr = _make(player: _FakePlayer());
      addTearDown(mgr.dispose);

      expect(mgr.lastExternalSubtitles, isEmpty);

      final subs = [
        SubtitleTrack.uri('https://example/a.srt', title: 'EN', language: 'eng'),
        SubtitleTrack.uri('https://example/b.srt', title: 'FR', language: 'fre'),
      ];
      mgr.cacheExternalSubtitles(subs);
      expect(mgr.lastExternalSubtitles, subs);

      // Replacing the cache overwrites it (used during episode navigation).
      mgr.cacheExternalSubtitles(const []);
      expect(mgr.lastExternalSubtitles, isEmpty);
    });
  });

  // ============================================================
  // addExternalSubtitles
  // ============================================================

  group('addExternalSubtitles', () {
    test('returns immediately on empty input', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      await mgr.addExternalSubtitles(const []);
      expect(player.addSubtitleCalls, isEmpty);
    });

    test('forwards each subtitle with a URI to the player in metadata order', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      final subs = [
        SubtitleTrack.uri('https://example/a.srt', title: 'EN', language: 'eng'),
        SubtitleTrack.uri('https://example/b.srt', title: 'FR', language: 'fre'),
      ];
      await mgr.addExternalSubtitles(subs);

      expect(player.addSubtitleCalls, hasLength(2));
      expect(player.addSubtitleCalls.map((c) => c.uri), ['https://example/a.srt', 'https://example/b.srt']);
      // None should be auto-selected — manager picks afterwards.
      expect(player.addSubtitleCalls.every((c) => c.select == false), isTrue);
    });

    test('does not start the next add until the previous subtitle completes', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);
      final firstCompletes = Completer<void>();
      addTearDown(() {
        if (!firstCompletes.isCompleted) firstCompletes.complete();
      });
      player.onAddSubtitleTrack = (uri) async {
        if (uri == 'https://example/a.srt') {
          await firstCompletes.future;
        }
      };

      final addFuture = mgr.addExternalSubtitles([
        SubtitleTrack.uri('https://example/a.srt', title: 'EN'),
        SubtitleTrack.uri('https://example/b.srt', title: 'FR'),
      ]);
      await _drainAsync();

      expect(player.addSubtitleCalls.map((c) => c.uri), ['https://example/a.srt']);

      firstCompletes.complete();
      await addFuture;

      expect(player.addSubtitleCalls.map((c) => c.uri), ['https://example/a.srt', 'https://example/b.srt']);
    });

    test('skips subtitle entries with null URI', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      // SubtitleTrack default constructor allows uri: null even with
      // isExternal: true — exercise the where-filter.
      final subs = const [
        SubtitleTrack(id: 'no-uri', isExternal: true),
        SubtitleTrack(id: 'with-uri', isExternal: true, uri: 'https://example/c.srt'),
      ];
      await mgr.addExternalSubtitles(subs);

      expect(player.addSubtitleCalls, hasLength(1));
      expect(player.addSubtitleCalls.single.uri, 'https://example/c.srt');
    });

    test('selects subtitle sidecars marked as default', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      const subs = [
        SubtitleTrack(id: 'selected', uri: 'https://example/selected.srt', isExternal: true, isDefault: true),
      ];
      await mgr.addExternalSubtitles(subs);

      expect(player.addSubtitleCalls, hasLength(1));
      expect(player.addSubtitleCalls.single.select, isTrue);
    });

    test('a player error on one entry does not prevent others from succeeding', () async {
      final player = _FakePlayer()..failAddSubtitleTimes = 1;
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      final subs = [
        SubtitleTrack.uri('https://example/a.srt', title: 'EN'),
        SubtitleTrack.uri('https://example/b.srt', title: 'FR'),
      ];
      // Should NOT throw — each per-track future has its own try/catch.
      await mgr.addExternalSubtitles(subs);
      // One add failed, one succeeded.
      expect(player.addSubtitleCalls, hasLength(1));
    });

    test('waits for player readiness before adding subtitles', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);
      final ready = Completer<void>();

      final addFuture = mgr.addExternalSubtitles([
        SubtitleTrack.uri('https://example/ready.srt', title: 'EN'),
      ], waitUntilReady: ready.future);
      await Future<void>.delayed(Duration.zero);

      expect(player.addSubtitleCalls, isEmpty);

      ready.complete();
      await addFuture;

      expect(player.addSubtitleCalls, hasLength(1));
      expect(player.addSubtitleCalls.single.uri, 'https://example/ready.srt');
    });
  });

  // ============================================================
  // applyTrackSelectionWhenReady
  // ============================================================

  group('applyTrackSelectionWhenReady', () {
    test('waits for player subtitle tracks when Plex metadata advertises subtitles', () async {
      await SettingsService.getInstance();
      final player = _FakePlayer(
        tracks: const Tracks(
          audio: [AudioTrack(id: '1', language: 'eng')],
        ),
      );
      final mgr = _make(player: player, mediaInfo: _mediaInfoWithSubtitles());
      addTearDown(mgr.dispose);

      mgr.applyTrackSelectionWhenReady();
      await _drainAsync();

      expect(player.selectedSubtitle, isEmpty);

      player.emitTracks(
        const Tracks(
          audio: [AudioTrack(id: '1', language: 'eng')],
          subtitle: [SubtitleTrack(id: '10', language: 'eng')],
        ),
      );
      await _drainAsync();

      expect(player.selectedSubtitle, hasLength(1));
      expect(player.selectedSubtitle.single.id, 'no');
    });
  });

  // ============================================================
  // LANG1 / DEC-109 — the manager actually supplies the layers
  // ============================================================

  group('the global Pleya profile preference reaches the resolver', () {
    // `TrackSelectionService` honouring a global preference is covered in
    // `lang1_controls_management_test.dart`, which builds the service by hand.
    // That leaves the wiring untested, and wiring is exactly what broke here
    // before: the resolver was right and the caller handed it the wrong thing.
    // These tests go through `TrackManager`, so they fail if the manager stops
    // reading the profile.
    test('with no series preference the profile decides the audio', () async {
      await SettingsService.getInstance();
      await PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(audioLanguage: 'nld', seeded: true),
      );

      final player = _FakePlayer(
        tracks: const Tracks(
          audio: [
            AudioTrack(id: '1', language: 'eng'),
            AudioTrack(id: '2', language: 'nld'),
          ],
        ),
      );
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      mgr.applyTrackSelectionWhenReady();
      await _drainAsync();

      expect(player.selectedAudio.single.language, 'nld');
    });

    test('it applies on a Pleya Server item exactly as on a Plex one', () async {
      await SettingsService.getInstance();
      await PleyaProfileLanguagePreferenceStore.write(
        const PleyaProfileLanguagePreferences(audioLanguage: 'nld', seeded: true),
      );

      final player = _FakePlayer(
        tracks: const Tracks(
          audio: [
            AudioTrack(id: '1', language: 'eng'),
            AudioTrack(id: '2', language: 'nld'),
          ],
        ),
      );
      final mgr = _make(
        player: player,
        metadata: MediaItem(id: 'ps1', backend: MediaBackend.pleyaServer, kind: MediaKind.movie),
      );
      addTearDown(mgr.dispose);

      mgr.applyTrackSelectionWhenReady();
      await _drainAsync();

      expect(
        player.selectedAudio.single.language,
        'nld',
        reason: 'the global layer is the Pleya profile, so it cannot depend on which backend is playing',
      );
    });

    test('a deliberate change becomes the session intent, not just a track', () async {
      await SettingsService.getInstance();
      final player = _FakePlayer(
        tracks: const Tracks(
          audio: [
            AudioTrack(id: '1', language: 'eng'),
            AudioTrack(id: '2', language: 'nld'),
          ],
        ),
      );
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      await mgr.onAudioTrackChanged(const AudioTrack(id: '2', language: 'nld'));

      expect(mgr.sessionIntent?.audioLanguage, 'nld');
      expect(mgr.sessionIntent?.origin, PlaybackIntentOrigin.session);
    });

    test('an automatic resolution does not become the session intent', () async {
      await SettingsService.getInstance();
      final player = _FakePlayer(
        tracks: const Tracks(
          audio: [
            AudioTrack(id: '1', language: 'eng'),
            AudioTrack(id: '2', language: 'nld'),
          ],
        ),
      );
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      await mgr.onAudioTrackChanged(const AudioTrack(id: '2', language: 'nld'), userInitiated: false);

      expect(mgr.sessionIntent, isNull, reason: 'DEC-109 lid 1: only a real action by the viewer creates layer 1');
    });
  });

  // ============================================================
  // Track cycling early-return paths
  // ============================================================

  group('cycleSubtitleTrack', () {
    test('no-op when no real subtitle tracks exist', () {
      // Tracks contains only auto/none (filtered out).
      final player = _FakePlayer(
        tracks: const Tracks(subtitle: [SubtitleTrack(id: 'auto')]),
      );
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      mgr.cycleSubtitleTrack();
      expect(player.selectedSubtitle, isEmpty);
    });

    test('no-op when subtitle list is empty', () {
      final player = _FakePlayer(); // empty tracks
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      mgr.cycleSubtitleTrack();
      expect(player.selectedSubtitle, isEmpty);
    });
  });

  group('cycleAudioTrack', () {
    test('no-op when fewer than 2 real audio tracks exist', () {
      final player = _FakePlayer(
        tracks: const Tracks(
          audio: [AudioTrack(id: '1', language: 'eng')],
        ),
      );
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      mgr.cycleAudioTrack();
      expect(player.selectedAudio, isEmpty);
    });

    test('filters out auto/no when computing the cycle length', () {
      // 1 real + 1 auto + 1 no = 1 real → still <2, no cycle.
      final player = _FakePlayer(
        tracks: const Tracks(
          audio: [
            AudioTrack(id: '1', language: 'eng'),
            AudioTrack(id: 'auto'),
            AudioTrack(id: 'no'),
          ],
        ),
      );
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      mgr.cycleAudioTrack();
      expect(player.selectedAudio, isEmpty);
    });
  });

  // ============================================================
  // Misc handlers
  // ============================================================

  group('onPlaybackRestart', () {
    test('no-op when not waiting for external subs', () {
      final mgr = _make(player: _FakePlayer());
      addTearDown(mgr.dispose);

      // Don't set the waiting flag — onPlaybackRestart should be a pure no-op
      // and must not call applyTrackSelection (which would touch the player).
      expect(mgr.waitingForExternalSubsTrackSelection, isFalse);
      mgr.onPlaybackRestart();
      // No exception is the contract.
      expect(mgr.waitingForExternalSubsTrackSelection, isFalse);
    });

    test('waits for the complete native external-track update before resolving a same-language choice', () async {
      const sidecar = SubtitleTrack(
        id: '1',
        title: 'Pleya sidecar',
        language: 'eng',
        isExternal: true,
        uri: 'https://example/sidecar.srt',
      );
      const embedded = SubtitleTrack(
        id: '2',
        title: 'Pleya embedded',
        language: 'eng',
        isExternal: true,
        uri: 'https://example/embedded.srt',
      );
      final p = _FakePlayer(
        tracks: const Tracks(
          audio: [AudioTrack(id: '1', language: 'eng')],
          subtitle: [sidecar],
        ),
      );
      final m = _make(player: p);
      addTearDown(m.dispose);
      m.sessionIntent = const PlaybackLanguageIntent(
        origin: PlaybackIntentOrigin.session,
        subtitleLanguage: 'eng',
        subtitleTitle: 'Pleya embedded',
      );
      m.waitingForExternalSubsTrackSelection = true;
      await m.addExternalSubtitles([
        SubtitleTrack.uri(sidecar.uri!, title: sidecar.title, language: 'eng'),
        SubtitleTrack.uri(embedded.uri!, title: embedded.title, language: 'eng'),
      ]);
      m.onPlaybackRestart();
      await _drainAsync();
      expect(p.selectedSubtitle, isEmpty, reason: 'sub-add completion can precede the track-list event');
      p.emitTracks(
        const Tracks(
          audio: [AudioTrack(id: '1', language: 'eng')],
          subtitle: [sidecar, embedded],
        ),
      );
      await _drainAsync();
      expect(p.selectedSubtitle.last.title, 'Pleya embedded');
    });

    test('keeps selection pending while external subtitle add is in flight', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);
      final ready = Completer<void>();

      mgr.waitingForExternalSubsTrackSelection = true;
      final addFuture = mgr.addExternalSubtitles([
        SubtitleTrack.uri('https://example/pending.srt', title: 'EN'),
      ], waitUntilReady: ready.future);
      await Future<void>.delayed(Duration.zero);

      mgr.onPlaybackRestart();

      expect(mgr.waitingForExternalSubsTrackSelection, isTrue);
      expect(player.addSubtitleCalls, isEmpty);

      ready.complete();
      await addFuture;

      mgr.onPlaybackRestart();

      expect(mgr.waitingForExternalSubsTrackSelection, isFalse);
      expect(player.addSubtitleCalls, hasLength(1));
    });
  });

  test(
    'at-open subtitles wait for every declared native URI before choosing the desired same-language track',
    () async {
      const sidecar = SubtitleTrack(
        id: '1',
        title: 'Pleya sidecar',
        language: 'eng',
        isExternal: true,
        uri: 'https://example/sidecar.srt',
      );
      const embedded = SubtitleTrack(
        id: '2',
        title: 'Pleya embedded',
        language: 'eng',
        isExternal: true,
        uri: 'https://example/embedded.srt',
      );
      final p = _FakePlayer(
        attachesExternalSubtitlesAtOpen: true,
        tracks: const Tracks(
          audio: [AudioTrack(id: '1', language: 'eng')],
          subtitle: [sidecar],
        ),
      );
      final m = _make(player: p);
      addTearDown(m.dispose);
      m.sessionIntent = const PlaybackLanguageIntent(
        origin: PlaybackIntentOrigin.session,
        subtitleLanguage: 'eng',
        subtitleTitle: 'Pleya embedded',
      );
      m.cacheExternalSubtitles([sidecar, embedded]);
      m.applyTrackSelectionWhenReady();
      await _drainAsync();
      expect(p.selectedSubtitle, isEmpty);
      p.emitTracks(
        const Tracks(
          audio: [AudioTrack(id: '1', language: 'eng')],
          subtitle: [sidecar, embedded],
        ),
      );
      await _drainAsync();
      expect(p.selectedSubtitle.last.title, 'Pleya embedded');
    },
  );

  group('onBackendSwitched', () {
    test('re-adds cached external subtitles for post-open fallback backends', () async {
      final player = _FakePlayer();
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      mgr.cacheExternalSubtitles([SubtitleTrack.uri('https://example/fallback.srt', title: 'EN')]);

      await mgr.onBackendSwitched();

      expect(player.addSubtitleCalls.map((c) => c.uri), ['https://example/fallback.srt']);
    });

    test('does not duplicate subtitles when fallback attached them at open', () async {
      final player = _FakePlayer(attachesExternalSubtitlesAtOpen: true);
      final mgr = _make(player: player);
      addTearDown(mgr.dispose);

      mgr.cacheExternalSubtitles([SubtitleTrack.uri('https://example/fallback.srt', title: 'EN')]);

      await mgr.onBackendSwitched();

      expect(player.addSubtitleCalls, isEmpty);
    });
  });

  group('onSecondarySubtitleTrackChanged', () {
    test('is a documented no-op', () {
      final mgr = _make(player: _FakePlayer());
      addTearDown(mgr.dispose);
      // Just verify it returns normally; nothing else to assert.
      expect(() => mgr.onSecondarySubtitleTrackChanged(const SubtitleTrack(id: '1')), returnsNormally);
    });
  });

  // ============================================================
  // Lifecycle
  // ============================================================

  group('dispose', () {
    test('is idempotent', () {
      final mgr = _make(player: _FakePlayer());
      mgr.dispose();
      expect(mgr.dispose, returnsNormally);
    });
  });

  // ============================================================
  // LANG1 / DEC-109 — CONTROL N: de bevestiging van mockup 31 C
  // ============================================================

  group('CONTROL N — een handmatige keuze meldt zich', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      PleyaProfileLanguagePreferenceStore.resetForTesting();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    test('de melding noemt de serie, de bewaarde keuze en de ongewijzigde globale voorkeur', () async {
      await PleyaProfileLanguagePreferenceStore.write(const PleyaProfileLanguagePreferences(subtitleLanguage: 'nl'));
      final notices = <PlaybackLanguageNotice>[];
      final mgr = _make(
        player: _FakePlayer(),
        metadata: MediaItem(
          id: 'ep1',
          backend: MediaBackend.plex,
          kind: MediaKind.episode,
          grandparentId: 'show7',
          grandparentTitle: 'Severance',
        ),
        onLanguageNotice: notices.add,
      );
      addTearDown(mgr.dispose);

      await mgr.onSubtitleTrackChanged(const SubtitleTrack(id: 's-1', language: 'eng', title: 'English'));

      final notice = notices.single as LanguageChoiceRemembered;
      expect(notice.kind, LanguageTrackKind.subtitles);
      expect(notice.language, 'eng');
      expect(notice.seriesTitle, 'Severance');
      expect(notice.storedForSeries, isTrue);
      expect(notice.globalLanguage, 'nl');
    });

    test('met "Onthoud keuzes per serie" uit meldt hij een keuze voor deze sessie', () async {
      await PleyaProfileLanguagePreferenceStore.write(const PleyaProfileLanguagePreferences(rememberPerSeries: false));
      final notices = <PlaybackLanguageNotice>[];
      final mgr = _make(player: _FakePlayer(), onLanguageNotice: notices.add);
      addTearDown(mgr.dispose);

      await mgr.onAudioTrackChanged(const AudioTrack(id: 'a-1', language: 'eng'));

      expect((notices.single as LanguageChoiceRemembered).storedForSeries, isFalse);
    });

    test('automatische resolutie meldt niets', () async {
      final notices = <PlaybackLanguageNotice>[];
      final mgr = _make(player: _FakePlayer(), onLanguageNotice: notices.add);
      addTearDown(mgr.dispose);

      await mgr.onAudioTrackChanged(const AudioTrack(id: 'a-1', language: 'eng'), userInitiated: false);

      expect(notices, isEmpty);
    });
  });
}

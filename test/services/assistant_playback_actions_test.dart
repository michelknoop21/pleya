import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_playback.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/mpv/player/player_stream_controllers.dart';
import 'package:pleya/services/track_manager.dart';
import 'package:pleya/services/track_preference_store.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

class _Player with PlayerStreamControllersMixin implements Player {
  @override
  PlayerState state = const PlayerState();
  @override
  late final PlayerStreams streams = createStreams();
  @override
  bool get disposed => false;
  @override
  bool get supportsSecondarySubtitles => false;
  Future<void> Function(AudioTrack)? audio;
  Future<void> Function(String)? add;
  final audioCalls = <AudioTrack>[];
  final subtitleCalls = <SubtitleTrack>[];
  final added = <String>[];

  void observed(AudioTrack track) {
    state = state.copyWith(track: TrackSelection(audio: track));
    trackController.add(state.track);
  }

  @override
  Future<void> selectAudioTrack(AudioTrack track) async {
    audioCalls.add(track);
    if (audio != null) {
      await audio!(track);
    } else {
      observed(track);
    }
  }

  @override
  Future<void> selectSubtitleTrack(SubtitleTrack track) async => subtitleCalls.add(track);

  @override
  Future<void> addSubtitleTrack({required String uri, String? title, String? language, bool select = false}) async {
    added.add(uri);
    await add?.call(uri);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _item = MediaItem(id: 'episode', backend: MediaBackend.plex, kind: MediaKind.episode, grandparentId: 'show');
const _a = AudioTrack(id: '1', language: 'eng');
const _b = AudioTrack(id: '2', language: 'nld');

TrackManager _manager(_Player player, {Future<void> Function()? wait}) => TrackManager(
  player: player,
  isActive: () => true,
  metadata: _item,
  getProfileSettings: () => null,
  waitForProfileSettings: wait ?? () async {},
);

Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    TrackPreferenceStore.resetForTesting();
    await (await StorageService.getInstance()).clearActiveProfileId();
    await (await SettingsService.getInstance()).write(
      SettingsService.trackLanguagePreferences,
      const <String, TrackLanguageChoice>{},
    );
    final previous = TrackPreferenceStore.deviceNameProvider;
    TrackPreferenceStore.deviceNameProvider = () async => 'Fixture';
    addTearDown(() {
      TrackPreferenceStore.deviceNameProvider = previous;
      TrackPreferenceStore.resetForTesting();
    });
  });

  test('I1 property acknowledgement before observed event still completes native selection and store', () async {
    final player = _Player()..observed(_a);
    addTearDown(player.closeStreamControllers);
    final revision = AssistantPlaybackRevision();
    final release = revision.bind(player, isCurrent: () => true);
    addTearDown(release);
    final manager = _manager(player);
    addTearDown(manager.dispose);
    final acknowledged = Completer<void>();
    player.audio = (_) async => acknowledged.complete();
    final pending = assistantSelectPlaybackTrack(
      player: player,
      revisions: revision,
      select: () => player.selectAudioTrack(_b),
      persist: (live) => manager.onAudioTrackChanged(_b, isCurrent: live),
      isCurrent: () => true,
      selectionMatches: () => player.state.track.audio == _b,
    );
    await acknowledged.future;
    await _drain();
    expect(await TrackPreferenceStore.read(_item), isNull);
    player.observed(_b);
    expect(await pending, isTrue);
    expect((await TrackPreferenceStore.read(_item))?.audioLanguage, 'nld');
  });

  test('I2 manual ABA during actual TrackManager provenance await cannot persist old assistant preference', () async {
    final player = _Player()..observed(_a);
    addTearDown(player.closeStreamControllers);
    final revision = AssistantPlaybackRevision();
    addTearDown(revision.bind(player, isCurrent: () => true));
    final manager = _manager(player);
    addTearDown(manager.dispose);
    final writing = Completer<void>();
    final device = Completer<String>();
    TrackPreferenceStore.deviceNameProvider = () {
      writing.complete();
      return device.future;
    };
    final pending = assistantSelectPlaybackTrack(
      player: player,
      revisions: revision,
      select: () => player.selectAudioTrack(_b),
      persist: (live) => manager.onAudioTrackChanged(_b, isCurrent: live),
      isCurrent: () => true,
      selectionMatches: () => player.state.track.audio == _b,
    );
    await writing.future;
    player.observed(_a);
    player.observed(_b);
    await _drain();
    device.complete('Fixture');
    expect(await pending, isFalse);
    expect(await TrackPreferenceStore.read(_item), isNull);
    // The temporary assistant guard does not disable later ordinary choices.
    await manager.onAudioTrackChanged(_a);
    expect((await TrackPreferenceStore.read(_item))?.audioLanguage, 'eng');
  });

  test('I3 scoped external subtitle add stops subsequent adds without disabling ordinary manager', () async {
    final player = _Player()..state = const PlayerState(tracks: Tracks(audio: [_a]));
    addTearDown(player.closeStreamControllers);
    final manager = _manager(player);
    manager.waitingForExternalSubsTrackSelection = true;
    addTearDown(manager.dispose);
    final adding = Completer<void>();
    final finish = Completer<void>();
    player.add = (_) {
      adding.complete();
      return finish.future;
    };
    var live = true;
    final pending = manager.addExternalSubtitles(const [
      SubtitleTrack(id: 's1', uri: 'fixture-one'),
      SubtitleTrack(id: 's2', uri: 'fixture-two'),
    ], isCurrent: () => live);
    await adding.future;
    live = false;
    finish.complete();
    await pending;
    expect(player.added, ['fixture-one']);
    manager.onPlaybackRestart();
    await _drain();
    expect(player.audioCalls, isEmpty);
    expect(player.subtitleCalls, isEmpty);
    player.add = null;
    await manager.addExternalSubtitles(const [SubtitleTrack(id: 's3', uri: 'fixture-manual')]);
    expect(player.added, ['fixture-one', 'fixture-manual']);
  });

  test('I3 deferred selection captures reload scope through pending profile read', () async {
    final player = _Player();
    addTearDown(player.closeStreamControllers);
    final reading = Completer<void>();
    final settings = Completer<void>();
    final manager = _manager(
      player,
      wait: () {
        if (!reading.isCompleted) reading.complete();
        return settings.future;
      },
    );
    addTearDown(manager.dispose);
    var live = true;
    manager.applyTrackSelectionWhenReady(isCurrent: () => live);
    player.state = player.state.copyWith(tracks: const Tracks(audio: [_a, _b]));
    player.tracksController.add(player.state.tracks);
    await reading.future;
    live = false;
    settings.complete();
    await _drain();
    expect(player.audioCalls, isEmpty);
    expect(player.subtitleCalls, isEmpty);
    await manager.applyTrackSelection();
    expect(player.audioCalls, isNotEmpty);
    expect(player.subtitleCalls, isNotEmpty);
  });

  test('I3 cancellation during native selection prevents nested server callbacks and later subtitle work', () async {
    final player = _Player()..state = const PlayerState(tracks: Tracks(audio: [_a]));
    addTearDown(player.closeStreamControllers);
    final selecting = Completer<void>();
    final acknowledge = Completer<void>();
    player.audio = (_) {
      selecting.complete();
      return acknowledge.future;
    };
    final serverCalls = <String>[];
    final manager = TrackManager(
      player: player,
      isActive: () => true,
      metadata: _item,
      mediaInfo: MediaSourceInfo(
        videoUrl: 'fixture-video',
        partId: 10,
        audioTracks: [MediaAudioTrack(id: 1, languageCode: 'eng', selected: true)],
        subtitleTracks: const [],
        chapters: const [],
      ),
      getProfileSettings: () => null,
      waitForProfileSettings: () async {},
      persistTrackPreference: ({required partId, required trackType, streamID}) async => serverCalls.add(trackType),
    );
    addTearDown(manager.dispose);
    var live = true;
    final pending = manager.applyTrackSelection(isCurrent: () => live);
    await selecting.future;
    live = false;
    acknowledge.complete();
    await pending;
    await _drain();
    expect(serverCalls, isEmpty);
    expect(player.subtitleCalls, isEmpty);
    player.audio = null;
    await manager.applyTrackSelection();
    await _drain();
    expect(serverCalls, isNotEmpty);
    expect(player.subtitleCalls, isNotEmpty);
  });

  test('I4 a single selected burned source subtitle offers the existing source off callback', () async {
    final calls = <int>[];
    final actions = assistantSourceSubtitleActions(
      streamIds: const [7],
      selectedId: 7,
      isCurrent: () => true,
      switchSource: (id, _) async {
        calls.add(id);
        return true;
      },
    );
    expect(actions, hasLength(1));
    expect(actions.single.kind, AssistantPlaybackActionKind.subtitle);
    expect(actions.single.label, 'Source subtitles off');
    expect(await actions.single.execute(() => true), isTrue);
    expect(calls, [0]);
  });
}

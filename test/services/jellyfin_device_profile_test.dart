import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/device_capabilities.dart';
import 'package:pleya/services/jellyfin_client/jellyfin_device_profile.dart';

import '../media/device_capabilities_fixtures.dart';

/// Table tests on the Jellyfin profile, one row per device plus one row per
/// field that has to survive an unknown capability.
///
/// The whole risk of PS-5 is that a wrong profile is silence or a black screen
/// and not a compile error. The rule these rows enforce is the countermeasure:
/// an unknown capability produces exactly the string the app sent before this
/// phase.
void main() {
  Map<String, Object?> directPlay(DeviceCapabilities capabilities) {
    final profile = buildJellyfinDeviceProfile(capabilities);
    return (profile['DirectPlayProfiles']! as List<Map<String, Object?>>).first;
  }

  group('an unknown device sends exactly what the app sent before PS-5', () {
    test('DirectPlayProfiles', () {
      expect(directPlay(nothingKnown), {
        'Type': 'Video',
        'Container': 'mp4,mkv,m4v,webm,mov,ts',
        'VideoCodec': 'hevc,h264,h265,vp8,vp9,av1,mpeg4,mpeg2video',
        'AudioCodec': 'aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts',
      });
    });

    test('TranscodingProfiles', () {
      final profile = buildJellyfinDeviceProfile(nothingKnown);

      expect(profile['TranscodingProfiles'], [
        {
          'Type': 'Video',
          'Container': 'ts',
          'Protocol': 'hls',
          'VideoCodec': 'hevc,h264',
          'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus',
        },
      ]);
    });

    test('SubtitleProfiles, all external', () {
      final profile = buildJellyfinDeviceProfile(nothingKnown);
      final subtitles = profile['SubtitleProfiles']! as List<Map<String, Object?>>;

      expect(subtitles.map((s) => s['Format']), ['srt', 'ass', 'ssa', 'vtt', 'pgssub', 'dvdsub', 'dvbsub']);
      expect(subtitles.every((s) => s['Method'] == 'External'), isTrue);
    });

    test('MaxStreamingBitrate is present only when the caller passes one', () {
      expect(buildJellyfinDeviceProfile(nothingKnown).containsKey('MaxStreamingBitrate'), isFalse);
      expect(buildJellyfinDeviceProfile(nothingKnown, maxStreamingBitrate: 5000000)['MaxStreamingBitrate'], 5000000);
    });

    test('the name never varies', () {
      expect(buildJellyfinDeviceProfile(nothingKnown)['Name'], 'Pleya');
    });
  });

  group('CodecProfiles', () {
    // Conditions on profile, level, bit depth or HDR would each be a claim
    // about the decoder, and nothing asks mpv for `decoder-list` yet.
    test('stays empty for every device PS-5 can detect', () {
      for (final entry in allDeviceFixtures.entries) {
        expect(buildJellyfinDeviceProfile(entry.value)['CodecProfiles'], isEmpty, reason: entry.key);
      }
      expect(buildJellyfinDeviceProfile(nothingKnown)['CodecProfiles'], isEmpty);
    });

    test('carries conditions the moment a real limit is detected', () {
      const withLimits = DeviceCapabilities(
        decoder: DeviceDecoderCapabilities(
          engine: PlayerEngine.mpv,
          videoCodecs: Capability.inferred({'hevc'}),
          audioCodecs: Capability.inferred({'aac'}),
          containers: Capability.inferred({'mp4'}),
          maxVideoLevel: Capability.detected(51),
          maxBitDepth: Capability.detected(8),
        ),
        display: DeviceDisplayCapabilities.unknown,
        audio: DeviceAudioCapabilities.unknown,
        connection: DeviceConnectionCapabilities.unknown,
      );

      final profiles = buildJellyfinDeviceProfile(withLimits)['CodecProfiles']! as List<Map<String, Object?>>;
      final conditions = profiles.single['Conditions']! as List<Map<String, Object?>>;

      expect(profiles.single['Codec'], 'hevc');
      expect(conditions.map((c) => c['Property']), ['VideoLevel', 'VideoBitDepth']);
      expect(conditions.first['Value'], '51');
    });
  });

  group('per device', () {
    test('every mpv device differs from the old constant in exactly one token', () {
      for (final name in ['appleTv4kOnReceiver', 'iPhoneWithAirPods', 'macOsDesktop']) {
        final profile = directPlay(allDeviceFixtures[name]!);
        expect(profile['Container'], directPlay(nothingKnown)['Container'], reason: name);
        expect(profile['VideoCodec'], directPlay(nothingKnown)['VideoCodec'], reason: name);
        expect(profile['AudioCodec'], '${directPlay(nothingKnown)['AudioCodec']},truehd', reason: name);
      }
    });

    // Android is where the old comment above the constant was wrong: it
    // claimed mpv decodes HEVC on every platform we ship, while `use_exoplayer`
    // defaults to true. The list is the same in PS-5 because ExoPlayer's real
    // set comes from MediaCodecList and nobody queries it, but it now comes
    // from a layer that knows which engine is running.
    test('ExoPlayer gets the same list in PS-5, from the engine-aware layer', () {
      expect(androidTvExoPlayer.decoder.engine, PlayerEngine.exoPlayer);
      expect(directPlay(androidTvExoPlayer), directPlay(nothingKnown));
    });

    test('a narrower decoder produces a narrower profile', () {
      expect(directPlay(appleTvHd)['VideoCodec'], isNot(contains('av1')));
      expect(directPlay(appleTv4kOnReceiver)['VideoCodec'], contains('av1'));
    });
  });

  group('TrueHD comes from the decoder, not from passthrough', () {
    // The pre-PS-5 list named `dts` but not `truehd`, so every TrueHD track
    // cost a transcode the player never needed. What credits the player with it
    // is that mpv decodes it, which is a decoder property and holds whether or
    // not the route can carry a bitstream.
    test('a device that cannot bitstream anything still declares it', () {
      expect(iPhoneWithAirPods.audio.passthroughCodecs.value, isEmpty);
      expect(directPlay(iPhoneWithAirPods)['AudioCodec'], contains('truehd'));
    });

    test('ExoPlayer does not get it, because nobody queried MediaCodecList', () {
      expect(directPlay(androidTvExoPlayer)['AudioCodec'], isNot(contains('truehd')));
      expect(directPlay(androidTvExoPlayer)['AudioCodec'], directPlay(nothingKnown)['AudioCodec']);
    });

    test('an unknown device still sends the pre-PS-5 list', () {
      expect(directPlay(nothingKnown)['AudioCodec'], 'aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts');
    });
  });

  group('the resolution ceiling', () {
    List<Map<String, Object?>> conditions(DeviceCapabilities capabilities) {
      final profiles = buildJellyfinDeviceProfile(capabilities)['CodecProfiles']! as List<Map<String, Object?>>;
      if (profiles.isEmpty) return const <Map<String, Object?>>[];
      return profiles.single['Conditions']! as List<Map<String, Object?>>;
    }

    // A panel that measures 1080p is a fact. Asking a server to transcode 4K
    // down to it is a policy decision, and policy is the PS-6 planner's job.
    test('a measured display alone puts nothing on the wire', () {
      expect(appleTvHd.display.hasResolutionCeiling, isTrue);
      expect(buildJellyfinDeviceProfile(appleTvHd)['CodecProfiles'], isEmpty);
    });

    test('a user cap does, because an instruction is not a policy decision', () {
      final capped = appleTv4kOnReceiver.copyWith(
        display: DeviceDisplayCapabilities(
          maxWidth: const Capability<int>.unknown().overriddenWith(1920),
          maxHeight: const Capability<int>.unknown().overriddenWith(1080),
        ),
      );

      expect(conditions(capped), [
        {'Condition': 'LessThanEqual', 'Property': 'Width', 'Value': '1920', 'IsRequired': false},
        {'Condition': 'LessThanEqual', 'Property': 'Height', 'Value': '1080', 'IsRequired': false},
      ]);
    });

    test('HDR stays off the wire entirely in PS-5', () {
      final profile = buildJellyfinDeviceProfile(appleTvHd);

      expect(profile.containsKey('VideoRangeType'), isFalse);
      expect(profile.toString(), isNot(contains('VideoRangeType')));
    });
  });
}

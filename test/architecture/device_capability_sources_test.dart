import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every codec, container and channel list in `lib/` is accounted for.
///
/// Modelled on `test/no_raw_preference_write_test.dart`, and for the same
/// reason. A source scan that forbids `Platform.is…` in two files only guards
/// those two files; an inventory catches a second codec list appearing
/// somewhere nobody was looking. That is how the passthrough list came to exist
/// three times in two spellings, and the container list three times with three
/// different contents.
///
/// The inventory is deliberately not a deduplication order. Lists that look
/// alike are not automatically the same thing: what the local scanner
/// recognises as a video file, what a download may keep, and what a backend may
/// direct-play are three different boundaries that happen to share tokens.
/// Merging them would couple them. What this guard demands is that each one
/// says which boundary it draws.
enum CapabilityListKind {
  /// What the player is believed to handle. The source the profile builders
  /// derive from.
  playerCapability,

  /// A frozen record of what the app put on the wire before PS-5, used when a
  /// capability is unknown. Never widened as a side effect.
  wireFallback,

  /// Which files on disk count as media. A discovery boundary, not a
  /// capability: `.iso` is here because the scanner has to find it, and
  /// libbluray opens it as a device rather than the demuxer reading it as a
  /// stream.
  fileDiscovery,

  /// Which downloaded files may be kept and played back offline.
  downloadWhitelist,

  /// Spelling and display: aliases, human-readable names, normalization.
  naming,

  /// A tuning table keyed by codec or container. Says nothing about what the
  /// device can do.
  tuning,
}

class CapabilityListRecord {
  const CapabilityListRecord(this.kind, this.tokenCount, this.reason);

  final CapabilityListKind kind;

  /// How many distinct media tokens the file is expected to name. Exact, so a
  /// changed list shows up here whether it grew or shrank.
  final int tokenCount;

  final String reason;
}

void main() {
  const inventory = <String, CapabilityListRecord>{
    // -- The source, and the two frozen records it may not be confused with.
    'lib/media/device_capability_baseline.dart': CapabilityListRecord(
      CapabilityListKind.playerCapability,
      23,
      'what the detection layer publishes as inferred: the video codecs, audio '
      'codecs and containers the Flutter player is credited with',
    ),
    'lib/services/jellyfin_client/jellyfin_device_profile.dart': CapabilityListRecord(
      CapabilityListKind.wireFallback,
      23,
      'the DirectPlay and Transcoding lists the app sent before PS-5, used when '
      'the decoder layer says unknown',
    ),
    'lib/services/plex_client/plex_client_profile.dart': CapabilityListRecord(
      CapabilityListKind.wireFallback,
      5,
      'the transcode-target codecs in the X-Plex-Client-Profile-Extra clauses, '
      'frozen for the same reason',
    ),

    // -- Audio passthrough: one set, one translation of it.
    'lib/services/audio_output_decision.dart': CapabilityListRecord(
      CapabilityListKind.playerCapability,
      6,
      'appleBitstreamCodecs and desktopBitstreamCodecs, plus the mpv audio-spdif '
      'spelling map; player_native and player_android read these instead of '
      'keeping their own copy',
    ),

    // -- Discovery and retention. Neither is a capability.
    'lib/services/local_folder_client.dart': CapabilityListRecord(
      CapabilityListKind.fileDiscovery,
      16,
      'extensions the local scanner recognises as a video file, wider than what '
      'we declare to a backend on purpose',
    ),
    'lib/services/pleya_share/pleya_share_protocol.dart': CapabilityListRecord(
      CapabilityListKind.fileDiscovery,
      15,
      'the same boundary for a shared folder over Pleya Share. It is one token '
      'short of the scanner list (no .iso) and that gap is worth closing, but '
      'in a Pleya Share round rather than here',
    ),
    'lib/services/download_manager_service.dart': CapabilityListRecord(
      CapabilityListKind.downloadWhitelist,
      6,
      'which downloaded files count as video for the offline library',
    ),

    // -- Naming and tuning. Neither answers "can this device play this".
    'lib/utils/codec_utils.dart': CapabilityListRecord(
      CapabilityListKind.naming,
      20,
      'codec aliases and display names, the shared normalizer for both backends',
    ),
    'lib/widgets/video_controls/widgets/performance_overlay/performance_stats_service.dart': CapabilityListRecord(
      CapabilityListKind.naming,
      14,
      'human-readable codec labels for the performance overlay',
    ),
    'lib/services/track_selection_service.dart': CapabilityListRecord(
      CapabilityListKind.tuning,
      9,
      'audio codec equivalence groups for remembering a track choice across '
      'servers, a preference rather than a capability',
    ),
    'lib/utils/stream_buffer_sizing.dart': CapabilityListRecord(
      CapabilityListKind.tuning,
      6,
      'the Matroska family and the container tiers that size the mpv stream ring',
    ),
  };

  /// Codec and container tokens. A file naming three or more of them in code is
  /// holding a capability list, whatever it calls it.
  const vocabulary = <String>{
    'hevc',
    'h264',
    'h265',
    'av1',
    'vp9',
    'vp8',
    'mpeg4',
    'mpeg2video',
    'aac',
    'mp3',
    'mp2',
    'ac3',
    'eac3',
    'flac',
    'opus',
    'vorbis',
    'dts',
    'dtshd',
    'dts-hd',
    'truehd',
    'mp4',
    'mkv',
    'm4v',
    'webm',
    'mov',
    'ts',
    'avi',
    'm2ts',
    'wmv',
    'flv',
    'mpg',
    'mpeg',
    'vob',
    '3gp',
    'ogv',
    'iso',
  };

  final literal = RegExp(r"'([^'\n]*)'");

  Map<String, int> scan() {
    final found = <String, int>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') || entity.path.endsWith('.freezed.dart')) continue;
      final tokens = <String>{};
      for (final line in entity.readAsLinesSync()) {
        // Doc comments name codecs as examples; only code counts.
        if (line.trimLeft().startsWith('//')) continue;
        for (final match in literal.allMatches(line)) {
          for (final part in match.group(1)!.split(',')) {
            final token = part.trim().replaceFirst(RegExp(r'^\.'), '').toLowerCase();
            if (vocabulary.contains(token)) tokens.add(token);
          }
        }
      }
      if (tokens.length >= 3) found[entity.path] = tokens.length;
    }
    return found;
  }

  test('every capability list in lib/ is in the inventory', () {
    final unaccounted = scan().keys.where((path) => !inventory.containsKey(path)).toList()..sort();

    expect(
      unaccounted,
      isEmpty,
      reason:
          'These files name three or more codecs or containers and nobody has said which boundary '
          'they draw. Add each one with a kind and a reason, or derive it from an existing source.\n'
          '${unaccounted.join('\n')}',
    );
  });

  test('every inventory entry still exists and still holds a list', () {
    final scanned = scan();
    final vanished = inventory.keys.where((path) => !scanned.containsKey(path)).toList()..sort();

    expect(vanished, isEmpty, reason: 'Inventory entries with no list left in them:\n${vanished.join('\n')}');
  });

  test('the token counts are exact, so a changed list shows up here', () {
    final scanned = scan();
    final drifted = <String>[];
    for (final entry in inventory.entries) {
      final actual = scanned[entry.key];
      if (actual != null && actual != entry.value.tokenCount) {
        drifted.add('${entry.key}: expected ${entry.value.tokenCount}, found $actual');
      }
    }

    expect(
      drifted,
      isEmpty,
      reason:
          'A capability list changed size. That may be correct, but it is a playback change and it '
          'needs saying out loud here.\n${drifted.join('\n')}',
    );
  });

  // Architecture chapter 10.4 in test form. The planner may never branch on
  // client type, platform or app version, and the two builders that feed it are
  // where that rule would break first.
  test('the profile builders never branch on the platform', () {
    const builders = [
      'lib/services/jellyfin_client/jellyfin_device_profile.dart',
      'lib/services/plex_client/plex_client_profile.dart',
    ];

    for (final path in builders) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('Platform.')), reason: '$path decides on a capability, never on a platform');
      expect(source, isNot(contains('dart:io')), reason: path);
    }
  });
}

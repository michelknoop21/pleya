import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_part.dart';
import 'package:pleya/media/media_stream.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/source_row_descriptor.dart';
import 'package:pleya/media/unified/unified_media_source.dart';

/// The picker's one hard rule, field by field: "ontbrekende metadata wordt
/// weggelaten, geen rijen vol 'Onbekend'".

List<MediaVersion> _versions({
  String? resolution,
  int? height,
  String? videoCodec,
  bool hdr = false,
  bool dolbyVision = false,
  String? audioCodec,
  int? channels,
  String? channelLayout,
  String? audioProfile,
  bool audioSelected = true,
}) => [
  MediaVersion(
    id: 'm1',
    videoResolution: resolution,
    height: height,
    videoCodec: videoCodec,
    parts: [
      MediaPart(
        id: 'p1',
        streams: [
          MediaStream(id: 'v', kind: MediaStreamKind.video, hdr: hdr, dolbyVision: dolbyVision),
          if (audioCodec != null)
            MediaStream(
              id: 'a',
              kind: MediaStreamKind.audio,
              codec: audioCodec,
              channels: channels,
              channelLayout: channelLayout,
              profile: audioProfile,
              selected: audioSelected,
            ),
        ],
      ),
    ],
  ),
];

UnifiedMediaSource _source({
  String serverId = 'nas',
  String id = 'i1',
  String? serverName,
  String? libraryTitle,
  MediaBackend backend = MediaBackend.plex,
  List<MediaVersion>? mediaVersions,
  int? durationMs,
  int? viewOffsetMs,
  int? viewCount,
  SourceAvailability availability = SourceAvailability.online,
}) => UnifiedMediaSource.fromItem(
  MediaItem(
    id: id,
    backend: backend,
    kind: MediaKind.movie,
    title: 'Dune',
    libraryTitle: libraryTitle,
    mediaVersions: mediaVersions,
    durationMs: durationMs,
    viewOffsetMs: viewOffsetMs,
    viewCount: viewCount,
    serverId: serverId,
    serverName: serverName ?? serverId,
  ),
  availability: availability,
);

SourceRowDescriptor _describe(UnifiedMediaSource source, {bool showBackend = false}) =>
    describeSource(source, showBackend: showBackend);

void main() {
  group('quality line', () {
    test('a numeric resolution becomes a p-label, a named one is upper-cased', () {
      expect(_describe(_source(mediaVersions: _versions(resolution: '1080'))).qualityParts, contains('1080p'));
      expect(_describe(_source(mediaVersions: _versions(resolution: '4k'))).qualityParts, contains('4K'));
    });

    test('height stands in when the backend reports no resolution label', () {
      expect(_describe(_source(mediaVersions: _versions(height: 2160))).qualityParts, contains('2160p'));
    });

    test('a source with no media versions has no quality line at all', () {
      final descriptor = _describe(_source());

      expect(descriptor.qualityParts, isEmpty);
      expect(descriptor.accessibleDescription, isNot(contains('Unknown')));
    });

    test('Dolby Vision wins over HDR10, because that is the mode you get', () {
      final both = _describe(_source(mediaVersions: _versions(resolution: '2160', hdr: true, dolbyVision: true)));
      expect(both.qualityParts, contains('Dolby Vision'));
      expect(both.qualityParts, isNot(contains('HDR')));
    });

    test('SDR says nothing rather than saying "SDR"', () {
      final sdr = _describe(_source(mediaVersions: _versions(resolution: '1080')));
      expect(sdr.qualityParts, ['1080p']);
    });

    test('Atmos is named from the codec profile, where the servers actually put it', () {
      final atmos = _describe(
        _source(
          mediaVersions: _versions(resolution: '2160', audioCodec: 'eac3', audioProfile: 'dd+atmos'),
        ),
      );
      expect(atmos.qualityParts, contains('E-AC3 Atmos'));
    });

    test('without Atmos the channel layout carries the audio line', () {
      expect(
        _describe(_source(mediaVersions: _versions(audioCodec: 'dts', channels: 6))).qualityParts,
        contains('DTS 5.1'),
      );
      expect(
        _describe(
          _source(
            mediaVersions: _versions(audioCodec: 'truehd', channels: 8, channelLayout: '7.1'),
          ),
        ).qualityParts,
        contains('TrueHD 7.1'),
      );
    });

    test('an audio stream with no codec contributes nothing instead of an empty label', () {
      final descriptor = _describe(
        _source(
          mediaVersions: _versions(resolution: '1080', audioCodec: ''),
        ),
      );
      expect(descriptor.qualityParts, ['1080p']);
    });
  });

  group('context line', () {
    test('the backend is named only when the caller says the distinction is useful', () {
      final source = _source(libraryTitle: 'Films');

      expect(_describe(source).contextParts, ['Films']);
      expect(_describe(source, showBackend: true).contextParts, ['Plex', 'Films']);
    });

    test('a source with neither library nor edition has no context line', () {
      expect(_describe(_source()).contextParts, isEmpty);
    });

    test('a blank library title counts as absent, not as an empty segment', () {
      expect(_describe(_source(libraryTitle: '   ')).contextParts, isEmpty);
    });

    test('every backend Pleya actually has gets a label, and there is no Emby', () {
      for (final backend in MediaBackend.values) {
        expect(backendDisplayLabel(backend), isNotEmpty);
        expect(backendDisplayLabel(backend), isNot('Emby'));
      }
    });
  });

  group('progress', () {
    test('a resume position becomes a label and a fraction', () {
      final descriptor = _describe(_source(durationMs: 9000000, viewOffsetMs: 2250000));

      expect(descriptor.progressFraction, closeTo(0.25, 0.001));
      expect(descriptor.progressLabel, contains('37:30'));
    });

    test('a watched source says so and draws no bar', () {
      final descriptor = _describe(_source(durationMs: 9000000, viewCount: 1));

      expect(descriptor.progressFraction, isNull);
      expect(descriptor.progressLabel, isNotNull);
    });

    test('an offset with no duration draws nothing: there is no denominator', () {
      final descriptor = _describe(_source(viewOffsetMs: 2250000));

      expect(descriptor.progressFraction, isNull);
      expect(descriptor.progressLabel, isNull);
    });

    test('an untouched source has no progress line', () {
      final descriptor = _describe(_source(durationMs: 9000000));

      expect(descriptor.progressFraction, isNull);
      expect(descriptor.progressLabel, isNull);
    });
  });

  group('status label ranking', () {
    UnifiedMediaSource online() => _source(serverName: 'NAS');

    test('an unusable row says why, and outranks every other marking', () {
      final offline = describeSource(
        _source(availability: SourceAvailability.offline),
        showBackend: false,
        isPreferred: true,
        isPreferredServer: true,
      );
      expect(offline.statusLabel, isNotNull);
      expect(offline.isUsable, isFalse);

      final auth = describeSource(
        _source(availability: SourceAvailability.authError),
        showBackend: false,
        isPreferred: true,
      );
      expect(auth.statusLabel, isNot(offline.statusLabel));
    });

    test('the profile default outranks the per-title memory, which outranks "already open"', () {
      final all = describeSource(
        online(),
        showBackend: false,
        isPreferred: true,
        isCurrent: true,
        isPreferredServer: true,
      );
      final remembered = describeSource(online(), showBackend: false, isPreferred: true, isCurrent: true);
      final current = describeSource(online(), showBackend: false, isCurrent: true);

      expect(all.statusLabel, isNot(remembered.statusLabel));
      expect(remembered.statusLabel, isNot(current.statusLabel));
      expect(current.statusLabel, isNotNull);
    });

    test('an ordinary usable row says nothing at all', () {
      expect(_describe(online()).statusLabel, isNull);
    });
  });

  group('accessibility', () {
    test('the spoken description carries exactly what the row shows', () {
      final descriptor = describeSource(
        _source(
          serverName: 'NAS',
          libraryTitle: 'Films 4K',
          durationMs: 9000000,
          viewOffsetMs: 2250000,
          mediaVersions: _versions(resolution: '2160', hdr: true, audioCodec: 'eac3', audioProfile: 'atmos'),
        ),
        showBackend: true,
        isPreferred: true,
      );

      expect(descriptor.accessibleDescription, startsWith('NAS, Plex, Films 4K, 2160p, HDR, E-AC3 Atmos'));
      expect(descriptor.accessibleDescription, contains('37:30'));
      expect(descriptor.accessibleDescription, endsWith(descriptor.statusLabel!));
    });

    test('a sparse row announces only its server, with no empty segments', () {
      expect(_describe(_source(serverName: 'Schuur')).accessibleDescription, 'Schuur');
    });
  });

  group('describeSources decides the backend question once for the whole list', () {
    test('one backend across the group leaves the backend off every row', () {
      final descriptors = describeSources([
        _source(serverId: 'nas', libraryTitle: 'Films'),
        _source(serverId: 'attic', id: 'i2', libraryTitle: 'Movies'),
      ]);

      expect(descriptors.every((d) => !d.contextParts.contains('Plex')), isTrue);
    });

    test('two backends put the backend on both rows, including the Plex one', () {
      final descriptors = describeSources([
        _source(serverId: 'nas', libraryTitle: 'Films'),
        _source(serverId: 'attic', id: 'i2', libraryTitle: 'Movies', backend: MediaBackend.jellyfin),
      ]);

      expect(descriptors[0].contextParts, ['Plex', 'Films']);
      expect(descriptors[1].contextParts, ['Jellyfin', 'Movies']);
    });

    test('the markings are matched by key and by server id, not by position', () {
      final descriptors = describeSources(
        [_source(serverId: 'nas'), _source(serverId: 'attic', id: 'i2')],
        preferredSourceKey: 'attic:i2',
        preferredServerId: 'nas',
      );

      expect(descriptors[0].isPreferredServer, isTrue);
      expect(descriptors[0].isPreferred, isFalse);
      expect(descriptors[1].isPreferred, isTrue);
      expect(descriptors[1].isPreferredServer, isFalse);
    });
  });
}

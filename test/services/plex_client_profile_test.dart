import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/device_capabilities.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/services/plex_client/plex_client_profile.dart';

import '../media/device_capabilities_fixtures.dart';

/// Table tests on the Plex transcode request, one row per device and one row
/// per field that has to survive an unknown capability.
void main() {
  final config = PlexConfig(
    baseUrl: 'https://plex.example.com',
    token: 'token',
    clientIdentifier: 'client-id',
    product: 'Pleya',
    version: '1',
  );

  Map<String, String> params(
    DeviceCapabilities capabilities, {
    TranscodeQualityPreset preset = TranscodeQualityPreset.p720_3mbps,
  }) {
    return buildPlexTranscodeParams(
      config: config,
      capabilities: capabilities,
      ratingKey: '42',
      mediaIndex: 0,
      preset: preset,
      sessionIdentifier: 'session-id',
      transcodeSessionId: 'transcode-id',
    );
  }

  group('an unknown device sends exactly what the app sent before PS-5', () {
    test('the profile-extra clauses, in order', () {
      expect(buildPlexProfileExtraClauses(nothingKnown, TranscodeQualityPreset.p720_3mbps), [
        'add-settings(DirectPlayStreamSelection=true)',
        'add-limitation(scope=videoCodec&scopeName=*&type=upperBound&name=video.bitrate&value=3000&replace=true)',
        'add-transcode-target(type=videoProfile&context=streaming'
            '&protocol=http&container=mkv&videoCodec=h264%2Chevc%2C*'
            '&audioCodec=opus%2Cvorbis%2Cflac%2C*&subtitleCodec=ass%2Cpgs%2Cvobsub%2C*)',
        'add-transcode-target-settings(type=videoProfile&context=streaming'
            '&protocol=http&CopyMatroskaAttachments=true)',
      ]);
    });

    test('the original preset adds no bitrate limitation', () {
      expect(buildPlexProfileExtraClauses(nothingKnown, TranscodeQualityPreset.original), [
        'add-settings(DirectPlayStreamSelection=true)',
        'add-transcode-target(type=videoProfile&context=streaming'
            '&protocol=http&container=mkv&videoCodec=h264%2Chevc%2C*'
            '&audioCodec=opus%2Cvorbis%2Cflac%2C*&subtitleCodec=ass%2Cpgs%2Cvobsub%2C*)',
        'add-transcode-target-settings(type=videoProfile&context=streaming'
            '&protocol=http&CopyMatroskaAttachments=true)',
      ]);
    });

    // Plex treats `location` as hard input, and no source for it is trusted
    // yet: a VPN, split DNS, a relay and plain local routing each break a
    // private-address check, in both directions.
    test('location is lan, because locality is unknown', () {
      expect(params(nothingKnown)['location'], 'lan');
      for (final entry in allDeviceFixtures.entries) {
        expect(params(entry.value)['location'], 'lan', reason: entry.key);
      }
    });

    test('directStreamAudio stays off, because turning it on is a PS-6 decision', () {
      expect(params(nothingKnown)['directStreamAudio'], '0');
      expect(params(macOsDesktop)['directStreamAudio'], '0');
    });

    test('the platform name stays Generic, because the others return HTTP 400', () {
      expect(plexTranscodePlatformName(), 'Generic');
      expect(params(nothingKnown)['X-Plex-Platform'], 'Generic');
    });

    // Only the connection layer reaches the Plex wire in PS-5. The decoder,
    // display and audio layers are carried in the model for the PS-6 planner
    // and change nothing here, which is what makes this step revertible.
    test('the decoder, display and audio layers change nothing on the Plex wire', () {
      for (final entry in allDeviceFixtures.entries) {
        final withoutConnection = entry.value.copyWith(connection: DeviceConnectionCapabilities.unknown);
        expect(params(withoutConnection), params(nothingKnown), reason: entry.key);
      }
    });

    test('the connection layer is the one thing that does reach it', () {
      expect(macOsDesktop.connection.maxBitrateKbps.value, 20000);
      expect(params(macOsDesktop)['maxVideoBitrate'], '20000');
    });
  });

  group('the bitrate ceiling comes from the connection layer', () {
    test('a preset override reaches both the limitation and maxVideoBitrate', () {
      final capped = nothingKnown.copyWith(
        connection: DeviceConnectionCapabilities(maxBitrateKbps: const Capability<int>.unknown().overriddenWith(2000)),
      );

      expect(params(capped)['maxVideoBitrate'], '2000');
      expect(
        buildPlexProfileExtraClauses(capped, TranscodeQualityPreset.p720_3mbps),
        contains(contains('&name=video.bitrate&value=2000&')),
      );
    });

    test('an unknown ceiling falls back to the preset, which is what produced it before', () {
      expect(params(nothingKnown)['maxVideoBitrate'], '3000');
      expect(plexMaxVideoBitrateKbps(nothingKnown, TranscodeQualityPreset.p720_3mbps), 3000);
    });

    test('the original preset carries no ceiling at all', () {
      expect(params(nothingKnown, preset: TranscodeQualityPreset.original).containsKey('maxVideoBitrate'), isFalse);
    });
  });

  group('the encoder', () {
    // Parens and asterisks have to appear as %28, %29 and %2A on the wire, and
    // Uri.encodeComponent leaves them literal.
    test('escapes what Plex Web escapes', () {
      expect(plexEncode('add-settings(a=b*c)'), 'add-settings%28a%3Db%2Ac%29');
      expect(plexEncode("it's!"), 'it%27s%21');
    });
  });
}

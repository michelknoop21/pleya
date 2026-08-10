import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_audio_session_service.dart';
import 'package:pleya/services/audio_output_decision.dart';

/// AirPods once the app has opted into multichannel content: spatial-capable,
/// but the route itself still reports stereo.
const _airPodsStereo = AppleAudioRoute(
  portType: 'BluetoothA2DP',
  spatialAudioEnabled: true,
  supportsMultichannelContent: true,
);

/// The same route if the system does widen it — the case Step 0 measures.
const _airPodsWide = AppleAudioRoute(
  portType: 'BluetoothA2DP',
  spatialAudioEnabled: true,
  supportsMultichannelContent: true,
  maximumOutputNumberOfChannels: 8,
  outputNumberOfChannels: 8,
);

/// Apple TV wired to a receiver.
const _hdmi = AppleAudioRoute(
  portType: 'HDMI',
  isDigitalPassthroughPort: true,
  maximumOutputNumberOfChannels: 8,
  outputNumberOfChannels: 8,
  supportsMultichannelContent: true,
);

/// The built-in speaker: no spatial support, no width.
const _builtIn = AppleAudioRoute(portType: 'Speaker', supportsMultichannelContent: true);

AudioOutputDecision decide(AudioOutputMode mode, AppleAudioRoute route, String? codec, {Set<String>? codecs}) =>
    decideAudioOutput(mode: mode, route: route, audioCodec: codec, bitstreamCodecs: codecs ?? appleBitstreamCodecs);

void main() {
  group('normalizeAudioCodec', () {
    test('folds the spellings the backends and mpv each use', () {
      expect(normalizeAudioCodec('EAC3'), 'eac3');
      expect(normalizeAudioCodec('ec-3'), 'eac3');
      expect(normalizeAudioCodec('E-AC-3'), 'eac3');
      expect(normalizeAudioCodec('Dolby Digital Plus'), 'eac3');
      expect(normalizeAudioCodec('AC3'), 'ac3');
      expect(normalizeAudioCodec('a52'), 'ac3');
      expect(normalizeAudioCodec('DTS-HD MA'), 'dtshd');
      expect(normalizeAudioCodec('dts'), 'dts');
      expect(normalizeAudioCodec('TrueHD'), 'truehd');
    });

    test('recognises dca, which is what the backends call plain DTS', () {
      // Missing this silently disabled DTS passthrough on desktop for every
      // user migrated from the legacy toggle.
      expect(normalizeAudioCodec('dca'), 'dts');
      expect(normalizeAudioCodec('DCA'), 'dts');
      expect(
        decide(AudioOutputMode.passthrough, _hdmi, 'dca', codecs: desktopBitstreamCodecs),
        AudioOutputDecision.passthrough,
      );
    });

    test('treats missing and blank as unknown', () {
      expect(normalizeAudioCodec(null), isNull);
      expect(normalizeAudioCodec('   '), isNull);
    });
  });

  group('auto', () {
    test('never bitstreams, even where the codec and route would allow it', () {
      // Regression: auto used to pick passthrough here. On a real Apple TV over
      // HDMI with an E-AC3 track that produced silence and a stalled player, so
      // bitstreaming is opt-in again.
      expect(decide(AudioOutputMode.auto, _hdmi, 'eac3'), AudioOutputDecision.pcmMultichannel);
      expect(decide(AudioOutputMode.auto, _hdmi, 'ac3'), AudioOutputDecision.pcmMultichannel);
      expect(decide(AudioOutputMode.auto, _airPodsStereo, 'eac3'), AudioOutputDecision.pcmStereo);
      expect(decide(AudioOutputMode.auto, _airPodsWide, 'eac3'), AudioOutputDecision.pcmMultichannel);
    });

    test('still widens to multichannel PCM where the route allows it', () {
      // This is what auto is for now: the route, not the codec, decides.
      expect(decide(AudioOutputMode.auto, _airPodsWide, 'dts'), AudioOutputDecision.pcmMultichannel);
      expect(decide(AudioOutputMode.auto, _hdmi, 'dts'), AudioOutputDecision.pcmMultichannel);
    });

    test('falls back to stereo on a narrow route', () {
      expect(decide(AudioOutputMode.auto, _builtIn, 'eac3'), AudioOutputDecision.pcmStereo);
      expect(decide(AudioOutputMode.auto, _builtIn, 'dts'), AudioOutputDecision.pcmStereo);
    });

    test('an unknown codec changes nothing', () {
      expect(decide(AudioOutputMode.auto, _hdmi, null), AudioOutputDecision.pcmMultichannel);
      expect(decide(AudioOutputMode.auto, _airPodsStereo, null), AudioOutputDecision.pcmStereo);
    });
  });

  group('passthrough', () {
    test('bitstreams Dolby regardless of what the route reports', () {
      expect(decide(AudioOutputMode.passthrough, _builtIn, 'eac3'), AudioOutputDecision.passthrough);
      expect(decide(AudioOutputMode.passthrough, _airPodsStereo, 'ac3'), AudioOutputDecision.passthrough);
    });

    test('honours an explicit request when the codec is unreported', () {
      // mpv's own audio-spdif list still gates this per track; refusing here
      // would silently ignore the setting because metadata was missing.
      expect(decide(AudioOutputMode.passthrough, _hdmi, null), AudioOutputDecision.passthrough);
    });

    test('still declines codecs the platform cannot bitstream', () {
      expect(decide(AudioOutputMode.passthrough, _hdmi, 'dts'), AudioOutputDecision.pcmMultichannel);
      expect(decide(AudioOutputMode.passthrough, _builtIn, 'truehd'), AudioOutputDecision.pcmStereo);
    });

    test('accepts DTS and TrueHD on desktop, where the receiver decodes', () {
      expect(
        decide(AudioOutputMode.passthrough, _hdmi, 'dts', codecs: desktopBitstreamCodecs),
        AudioOutputDecision.passthrough,
      );
      expect(
        decide(AudioOutputMode.passthrough, _hdmi, 'TrueHD', codecs: desktopBitstreamCodecs),
        AudioOutputDecision.passthrough,
      );
    });
  });

  group('pcm', () {
    test('never bitstreams, whatever the route and codec', () {
      expect(decide(AudioOutputMode.pcm, _hdmi, 'eac3'), AudioOutputDecision.pcmMultichannel);
      expect(decide(AudioOutputMode.pcm, _airPodsStereo, 'eac3'), AudioOutputDecision.pcmStereo);
      expect(decide(AudioOutputMode.pcm, _builtIn, 'ac3'), AudioOutputDecision.pcmStereo);
    });
  });

  group('off Apple platforms', () {
    test('auto keeps the pre-existing behaviour: no passthrough, stereo path', () {
      // AppleAudioRoute.unknown is what desktop and Android TV pass. Auto must
      // not start bitstreaming there on its own — that would be a behaviour
      // change for users who never asked for it.
      expect(
        decide(AudioOutputMode.auto, AppleAudioRoute.unknown, 'eac3', codecs: desktopBitstreamCodecs),
        AudioOutputDecision.pcmStereo,
      );
    });

    test('an explicit passthrough choice still works', () {
      expect(
        decide(AudioOutputMode.passthrough, AppleAudioRoute.unknown, 'eac3', codecs: desktopBitstreamCodecs),
        AudioOutputDecision.passthrough,
      );
    });
  });

  group('AppleRenderingMode', () {
    test('parses the names the plugin sends', () {
      expect(AppleRenderingMode.parse('dolbyAtmos'), AppleRenderingMode.dolbyAtmos);
      expect(AppleRenderingMode.parse('spatialAudio'), AppleRenderingMode.spatialAudio);
      expect(AppleRenderingMode.parse('monoStereo'), AppleRenderingMode.monoStereo);
    });

    test('missing means not-applicable, unrecognised means unknown', () {
      // The field is absent below iOS 17.2; that is not the same as the OS
      // reporting a mode we do not recognise.
      expect(AppleRenderingMode.parse(null), AppleRenderingMode.notApplicable);
      expect(AppleRenderingMode.parse('somethingNew'), AppleRenderingMode.unknown);
    });

    test('only the wider-than-stereo modes count as immersive', () {
      expect(AppleRenderingMode.dolbyAtmos.isImmersive, isTrue);
      expect(AppleRenderingMode.spatialAudio.isImmersive, isTrue);
      expect(AppleRenderingMode.surround.isImmersive, isTrue);
      expect(AppleRenderingMode.monoStereo.isImmersive, isFalse);
      expect(AppleRenderingMode.notApplicable.isImmersive, isFalse);
    });
  });

  group('AppleAudioRoute', () {
    test('reads a plugin snapshot', () {
      final route = AppleAudioRoute.fromMap(const {
        'maximumOutputNumberOfChannels': 8,
        'outputNumberOfChannels': 6,
        'supportsMultichannelContent': true,
        'spatialAudioEnabled': true,
        'portType': 'HDMI',
        'portName': 'Receiver',
        'isDigitalOutput': true,
        'renderingMode': 'dolbyAtmos',
      });

      expect(route.maximumOutputNumberOfChannels, 8);
      expect(route.isMultichannelCapable, isTrue);
      expect(route.isDigitalPassthroughPort, isTrue);
      expect(route.portType, 'HDMI');
      expect(route.renderingMode, AppleRenderingMode.dolbyAtmos);
    });

    test('degrades to stereo when the plugin sends nothing useful', () {
      final route = AppleAudioRoute.fromMap(const {});

      expect(route.isMultichannelCapable, isFalse);
      expect(route.isDigitalPassthroughPort, isFalse);
      expect(route.spatialAudioEnabled, isFalse);
      expect(route.renderingMode, AppleRenderingMode.notApplicable);
    });

    test('trusts a wired digital port over a channel count of two', () {
      // Measured on an Apple TV 4K wired to a receiver, tvOS audio on Auto:
      // the opt-in was accepted yet the session still reported two channels,
      // while it told mpv it supported three output layouts. Believing the
      // count pinned the device to stereo — no Atmos and no 5.1.
      final route = AppleAudioRoute.fromMap(const {
        'maximumOutputNumberOfChannels': 2,
        'outputNumberOfChannels': 2,
        'supportsMultichannelContent': true,
        'portType': 'HDMIOutput',
        'portName': 'AppleTV',
        'isDigitalOutput': true,
      });

      expect(route.isMultichannelCapable, isTrue);
    });

    test('a stereo count on a non-digital route still means stereo', () {
      // The phone speaker and AirPods keep the old behaviour: nothing to
      // widen to, so asking mpv for 5.1 would only cost an AO reload.
      final route = AppleAudioRoute.fromMap(const {
        'maximumOutputNumberOfChannels': 2,
        'supportsMultichannelContent': true,
        'portType': 'Speaker',
        'isDigitalOutput': false,
      });

      expect(route.isMultichannelCapable, isFalse);
    });
  });

  group('the measured Apple TV route', () {
    /// Exactly what build 212 logged: HDMI to a receiver, opt-in accepted,
    /// but a channel count of two.
    const appleTvHdmi = AppleAudioRoute(
      portType: 'HDMIOutput',
      portName: 'AppleTV',
      isDigitalPassthroughPort: true,
      supportsMultichannelContent: true,
    );

    test('auto now widens to multichannel PCM instead of stereo', () {
      expect(decide(AudioOutputMode.auto, appleTvHdmi, 'eac3'), AudioOutputDecision.pcmMultichannel);
    });

    test('an explicit PCM choice widens too', () {
      expect(decide(AudioOutputMode.pcm, appleTvHdmi, 'eac3'), AudioOutputDecision.pcmMultichannel);
    });

    test('passthrough is unaffected — it never depended on the count', () {
      expect(decide(AudioOutputMode.passthrough, appleTvHdmi, 'eac3'), AudioOutputDecision.passthrough);
    });

    test('a codec the Apple decoder cannot bitstream falls back wide, not narrow', () {
      expect(decide(AudioOutputMode.passthrough, appleTvHdmi, 'truehd'), AudioOutputDecision.pcmMultichannel);
    });
  });

  group('a route where bitstreaming failed', () {
    test('is never bitstreamed again, not even on an explicit request', () {
      // Otherwise every episode repeats the same silence: the receiver's
      // refusal does not change between titles.
      expect(
        decide(AudioOutputMode.passthrough, _hdmi, 'eac3'),
        AudioOutputDecision.passthrough,
        reason: 'sanity: unblocked still bitstreams',
      );
      expect(
        decideAudioOutput(mode: AudioOutputMode.passthrough, route: _hdmi, audioCodec: 'eac3', bitstreamBlocked: true),
        AudioOutputDecision.pcmMultichannel,
      );
    });

    test('still gets the widest PCM the route allows', () {
      // Falling back must not also cost the multichannel bed.
      expect(
        decideAudioOutput(mode: AudioOutputMode.passthrough, route: _hdmi, audioCodec: 'eac3', bitstreamBlocked: true),
        AudioOutputDecision.pcmMultichannel,
      );
      expect(
        decideAudioOutput(
          mode: AudioOutputMode.passthrough,
          route: _builtIn,
          audioCodec: 'eac3',
          bitstreamBlocked: true,
        ),
        AudioOutputDecision.pcmStereo,
      );
    });
  });
}

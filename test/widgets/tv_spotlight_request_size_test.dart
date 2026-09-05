/// ART1: het volledig beeldvullende TV-achtergrondbeeld moet op de resolutie
/// van het toestel worden opgevraagd, niet op de desktopcap.
///
/// `ImageType.art` heeft een plafond van 2560x1440. Dat is de juiste maat voor
/// een retina-desktoppaneel en te klein voor een Apple TV 4K, waar het
/// oppervlak 3840x2160 fysieke pixels telt: de backdrop komt dan 1,5 keer te
/// klein binnen en wordt over het hele scherm opgeschaald. `ImageType.heroArt`
/// bestaat precies voor dat oppervlak, en de fase-8 herokaart is er om die
/// reden al op overgezet (`tv_hero_artwork.dart`).
///
/// De meting hangt aan de aanvraag zelf, niet aan een pixelvergelijking: de
/// neptclient legt vast met welke breedte en hoogte `thumbnailUrl` geroepen
/// wordt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv_spotlight_background.dart';

class _RecordingClient implements MediaServerClient {
  final requests = <({int? width, int? height})>[];

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  String thumbnailUrl(String? path, {int? width, int? height}) {
    requests.add((width: width, height: height));
    return 'https://example.invalid/art?w=$width&h=$height';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('vraagt de backdrop op de resolutie van het TV-oppervlak', (tester) async {
    // Apple TV 4K: 1920x1080 logisch, 3840x2160 fysiek.
    const logical = Size(1920, 1080);
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(logical);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = _RecordingClient();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvSpotlightBackground(
              item: MediaItem(
                id: 'm1',
                backend: MediaBackend.plex,
                kind: MediaKind.movie,
                title: 'Dune: Part Two',
                artPath: '/library/metadata/1/art/1',
              ),
              client: client,
              showInfo: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(client.requests, isNotEmpty, reason: 'er is geen artwork opgevraagd');
    final request = client.requests.first;
    expect(
      request.width,
      greaterThanOrEqualTo(3840),
      reason: 'de backdrop wordt kleiner opgevraagd dan het oppervlak breed is: ${request.width}',
    );
    expect(
      request.height,
      greaterThanOrEqualTo(2160),
      reason: 'de backdrop wordt kleiner opgevraagd dan het oppervlak hoog is: ${request.height}',
    );
  });

  testWidgets('desktop houdt de bestaande 1440p-cap', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(true));

    // Retina desktoppaneel: 1440x900 logisch, 2880x1800 fysiek.
    const logical = Size(1440, 900);
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(logical);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = _RecordingClient();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvSpotlightBackground(
              item: MediaItem(
                id: 'm1',
                backend: MediaBackend.plex,
                kind: MediaKind.movie,
                title: 'Dune: Part Two',
                artPath: '/library/metadata/1/art/1',
              ),
              client: client,
              showInfo: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(client.requests, isNotEmpty);
    expect(
      client.requests.first.width,
      lessThanOrEqualTo(2560),
      reason: 'buiten TV blijft de art-cap van 2560x1440 staan',
    );
  });
}

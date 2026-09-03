import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_part.dart';
import 'package:pleya/media/media_stream.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';
import 'package:pleya/widgets/tv/tv_media_source_picker.dart';

import '../test_helpers/golden.dart';

/// Visual acceptance for the fase-4 source picker (docs/tvos-unified-experience.md
/// hoofdstuk 14, 33.4, 34).
///
/// These render the **real** widget through the **real** overlay-sheet panel
/// path, at the tvOS logical canvas DEC-028 produces (1038x584 — see
/// [kTvGoldenSurfaceSize]), with the production `monoTheme` and the app's own
/// fonts. That is what makes them useful as pictures and not just as
/// assertions: the panel's proportion, its outer margins, row density and type
/// hierarchy are all decided by the same code path a real Apple TV runs.
///
/// What they are not: pixel truth for tvOS. Hoofdstuk 29 is explicit that font
/// rasterization, render scale and HDR differ on the device. They catch a
/// composition regression on this platform; they do not replace hardware
/// verification.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_media_source_picker_golden_test.dart`

MediaItem _item({
  required String serverId,
  required String serverName,
  String id = 'i1',
  String? libraryTitle,
  String? editionTitle,
  MediaBackend backend = MediaBackend.plex,
  String? resolution,
  String? videoCodec,
  bool hdr = false,
  bool dolbyVision = false,
  String? audioCodec,
  int? audioChannels,
  String? audioProfile,
  int? viewOffsetMs,
  int? viewCount,
}) {
  final streams = <MediaStream>[
    if (resolution != null)
      MediaStream(id: 'v', kind: MediaStreamKind.video, codec: videoCodec, hdr: hdr, dolbyVision: dolbyVision),
    if (audioCodec != null)
      MediaStream(
        id: 'a',
        kind: MediaStreamKind.audio,
        codec: audioCodec,
        channels: audioChannels,
        profile: audioProfile,
        selected: true,
      ),
  ];
  // `editionTitle` lives on the Plex variant only, so the Plex rows are built
  // through `MediaItem.plex` — which is also the honest fixture: an edition
  // label is a Plex concept (hoofdstuk 14.3 lists it as optional for a reason).
  if (backend == MediaBackend.plex) {
    return MediaItem.plex(
      id: id,
      kind: MediaKind.movie,
      title: 'Dune: Part Two',
      year: 2024,
      durationMs: 9960000,
      viewOffsetMs: viewOffsetMs,
      viewCount: viewCount,
      libraryTitle: libraryTitle,
      editionTitle: editionTitle,
      serverId: serverId,
      serverName: serverName,
      mediaVersions: resolution == null ? null : _versions(resolution, videoCodec, streams),
    );
  }
  return MediaItem(
    id: id,
    backend: backend,
    kind: MediaKind.movie,
    title: 'Dune: Part Two',
    year: 2024,
    durationMs: 9960000,
    viewOffsetMs: viewOffsetMs,
    viewCount: viewCount,
    libraryTitle: libraryTitle,
    serverId: serverId,
    serverName: serverName,
    mediaVersions: resolution == null ? null : _versions(resolution, videoCodec, streams),
  );
}

List<MediaVersion> _versions(String resolution, String? videoCodec, List<MediaStream> streams) => [
  MediaVersion(
    id: 'm1',
    videoResolution: resolution,
    videoCodec: videoCodec,
    parts: [MediaPart(id: 'p1', streams: streams)],
  ),
];

UnifiedMediaSource _source(MediaItem item, {SourceAvailability availability = SourceAvailability.online}) =>
    UnifiedMediaSource.fromItem(item, availability: availability);

final _nas = _source(
  _item(
    serverId: 'nas',
    serverName: 'NAS',
    libraryTitle: 'Films 4K',
    resolution: '2160',
    videoCodec: 'hevc',
    hdr: true,
    audioCodec: 'eac3',
    audioProfile: 'atmos',
    editionTitle: "Director's Cut",
    viewOffsetMs: 2538000,
  ),
);

final _attic = _source(
  _item(
    serverId: 'attic',
    serverName: 'Zolder',
    id: 'i2',
    libraryTitle: 'Movies',
    backend: MediaBackend.jellyfin,
    resolution: '1080',
    videoCodec: 'h264',
    audioCodec: 'dts',
    audioChannels: 6,
  ),
);

final _sparse = _source(_item(serverId: 'shed', serverName: 'Schuur', id: 'i3', backend: MediaBackend.pleyaServer));

final _offline = _source(
  _item(serverId: 'office', serverName: 'Kantoor', id: 'i4', libraryTitle: 'Archief', resolution: '1080'),
  availability: SourceAvailability.offline,
);

final _authError = _source(
  _item(serverId: 'remote', serverName: 'Vakantiehuis', id: 'i5', libraryTitle: 'Films'),
  availability: SourceAvailability.authError,
);

SourceCoverageState _coverage({required Set<String> expected, required Set<String> checked}) => SourceCoverageState(
  expectedServerIds: expected,
  checkedServerIds: checked,
  uncheckedReasons: {for (final id in expected.difference(checked)) id: UncheckedSourceReason.offline},
);

/// The production app shell around the panel: `InputModeTracker` (which is what
/// makes TV default to keyboard mode, and therefore what makes the focus ring
/// paint at all) and `OverlaySheetHost` — the same host `MainScreen` mounts, so
/// the scrim, the centring and the panel constraints in the image are the real
/// ones. `debugShowCheckedModeBanner` is off: the diagonal banner is harness
/// chrome, not part of the surface being judged.
Widget _shell(WidgetBuilder panel, {FocusNode? initialFocusNode}) {
  final theme = monoTheme(dark: true);
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: InputModeTracker(
        child: OverlaySheetHost(
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: theme.extension<MonoTokens>()!.bg,
              // A poster wall behind the scrim: a panel judged against flat
              // black is judged against nothing, and the whole question here is
              // whether the modal separates from a busy 10-foot page.
              body: Stack(
                children: [
                  Positioned.fill(child: _PosterWall(theme: theme)),
                  Center(
                    child: ElevatedButton(
                      onPressed: () => OverlaySheetController.of(context).show(
                        presentation: OverlaySheetPresentation.panel,
                        initialFocusNode: initialFocusNode,
                        builder: panel,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PosterWall extends StatelessWidget {
  const _PosterWall({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final mono = theme.extension<MonoTokens>()!;
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 2 / 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: 14,
      itemBuilder: (_, index) => DecoratedBox(
        decoration: BoxDecoration(
          color: index.isEven ? mono.surface : mono.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

/// Pumps the picker through the shell above.
Future<void> _pumpPicker(
  WidgetTester tester, {
  required List<UnifiedMediaSource> sources,
  required String focusedSourceKey,
  String? preferredSourceKey,
  String? currentSourceKey,
  SourceCoverageState? coverage,
  String? preferredServerId,
  UnifiedActivationIntent intent = UnifiedActivationIntent.play,
  bool isResolving = false,
}) async {
  setGoldenSurfaceSize(tester);

  // Exactly what `showUnifiedSourcePicker` does in production: the host is told
  // which node to focus, and the same node is handed to the row that should
  // carry it. Without this the host's first-descendant fallback focuses the
  // footer button a frame later, and the picture would show the wrong thing
  // focused for a reason that does not exist in the app.
  final initialFocusNode = FocusNode(debugLabel: 'goldenInitialFocus');
  addTearDown(initialFocusNode.dispose);

  await tester.pumpWidget(
    _shell(
      initialFocusNode: initialFocusNode,
      (context) => TvMediaSourcePicker(
        initialFocusNode: initialFocusNode,
        initialFocusSourceKey: focusedSourceKey,
        sources: sources,
        focusedSourceKey: focusedSourceKey,
        preferredSourceKey: preferredSourceKey,
        currentSourceKey: currentSourceKey,
        preferredServerId: preferredServerId,
        title: 'Dune: Part Two',
        year: 2024,
        intent: intent,
        coverage: coverage ?? SourceCoverageState.complete({'nas', 'attic'}),
        isResolving: isResolving,
        onSelectSource: (_) {},
        onFocusSource: (_) {},
        onClose: () {},
        onManageServers: () {},
        onSetPreferredServer: (_) {},
      ),
    ),
  );

  await tester.tap(find.text('open'));
  // A resolving picker holds an indeterminate progress indicator, so there is
  // no settled frame to wait for; pump past the panel's enter animation
  // instead and render whatever frame that lands on.
  if (isResolving) {
    // Enough frames for the host's two-stage autofocus and the panel's enter
    // animation; `pumpAndSettle` cannot be used because the progress indicator
    // never settles.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  // The plain case, and the one that says most about the surface: nothing is
  // marked, so the only things carrying the picture are the depth ramp, the
  // type hierarchy and the focus ring.
  testWidgets('two online sources, nothing marked', (tester) async {
    await _pumpPicker(tester, sources: [_nas, _attic], focusedSourceKey: _nas.sourceKey);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_two_online');
  });

  // Hoofdstuk 14.8a. Split from "last used" on purpose: the two markers are a
  // different statement with different authority, and the whole point of
  // rendering both is being able to look at them side by side and check that
  // they read as different without either shouting.
  testWidgets('the profile default is marked', (tester) async {
    await _pumpPicker(tester, sources: [_nas, _attic], focusedSourceKey: _nas.sourceKey, preferredServerId: 'nas');
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_preferred_server');
  });

  // Hoofdstuk 14.8: the per-title memory, which only sets focus. Focus is on
  // the *other* row here, so the marker has to hold its own without the ring
  // helping it — that is the case where an over-quiet marker disappears.
  testWidgets('the remembered source is marked while another row has focus', (tester) async {
    await _pumpPicker(
      tester,
      sources: [_nas, _attic],
      focusedSourceKey: _attic.sourceKey,
      preferredSourceKey: _nas.sourceKey,
    );
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_last_used');
  });

  testWidgets('rich, sparse, offline and auth rows together', (tester) async {
    await _pumpPicker(
      tester,
      sources: [_nas, _attic, _sparse, _authError, _offline],
      focusedSourceKey: _attic.sourceKey,
      coverage: _coverage(expected: {'nas', 'attic', 'shed', 'remote', 'office'}, checked: {'nas', 'attic', 'shed'}),
    );
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_mixed_states');
  });

  // Hoofdstuk 14.5 plus the partial-coverage header of 14.2. Play intent, so
  // this render is about the spinner line and the amber coverage half only —
  // the details intent gets its own picture below rather than riding along in
  // this one, where a second difference would be impossible to attribute.
  testWidgets('still resolving, with partial coverage', (tester) async {
    await _pumpPicker(
      tester,
      sources: [_nas, _attic],
      focusedSourceKey: _nas.sourceKey,
      isResolving: true,
      coverage: _coverage(expected: {'nas', 'attic', 'shed'}, checked: {'nas', 'attic'}),
    );
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_resolving');
  });

  // Hoofdstuk 15's "Wijzigen": a settled picker reopened from a detail page,
  // asking a different question and marking the source already on screen.
  testWidgets('details intent, marking the source already open', (tester) async {
    await _pumpPicker(
      tester,
      sources: [_nas, _attic],
      focusedSourceKey: _nas.sourceKey,
      currentSourceKey: _nas.sourceKey,
      intent: UnifiedActivationIntent.details,
    );
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_details_intent');
  });

  testWidgets('nothing reachable', (tester) async {
    await _pumpPicker(
      tester,
      sources: [_authError, _offline],
      focusedSourceKey: _authError.sourceKey,
      coverage: _coverage(expected: {'remote', 'office'}, checked: {}),
    );
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_none_reachable');
  });

  testWidgets('playback failure alternative', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(_shell((context) => TvPlaybackFailureAlternative(onChooseAnother: () {}, onClose: () {})));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_source_picker_playback_failure');
  });
}

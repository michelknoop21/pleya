import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/mpv/player/player_state.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/video_controls/widgets/tv_quality_summary_line.dart';

import '../test_helpers/watch_together_fakes.dart';

/// MOC-18: the persistent quality/source line under the player title.
void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  Future<void> pump(WidgetTester tester, {required _QualityPlayer player, required bool isTranscoding}) async {
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TvQualitySummaryLine(player: player, isTranscoding: isTranscoding),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows resolution, codec, channels and a Direct play pill', (tester) async {
    final player = _QualityPlayer(
      resolution: '2160',
      codec: 'hevc',
      track: const TrackSelection(audio: _atmos),
    );
    await pump(tester, player: player, isTranscoding: false);

    expect(find.textContaining('2160p'), findsOneWidget);
    expect(find.textContaining('HEVC'), findsOneWidget);
    expect(find.textContaining('5.1'), findsOneWidget);
    expect(find.text(t.nowWatching.directPlay), findsOneWidget);
    expect(find.text(t.nowWatching.transcode), findsNothing);
  });

  testWidgets('shows a Transcode pill instead when the stream is transcoding', (tester) async {
    final player = _QualityPlayer(resolution: '1080', codec: 'h264');
    await pump(tester, player: player, isTranscoding: true);

    expect(find.text(t.nowWatching.transcode), findsOneWidget);
    expect(find.text(t.nowWatching.directPlay), findsNothing);
  });

  testWidgets('shows the active subtitle language with a captions icon', (tester) async {
    final player = _QualityPlayer(
      resolution: '1080',
      codec: 'h264',
      track: const TrackSelection(subtitle: _dutchSubtitle),
    );
    await pump(tester, player: player, isTranscoding: false);

    expect(find.text('Dutch'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == Symbols.closed_caption_rounded), findsOneWidget);
  });

  testWidgets('renders nothing when no live property has resolved yet', (tester) async {
    final player = _QualityPlayer(resolution: null, codec: null);
    await pump(tester, player: player, isTranscoding: false);

    expect(find.byType(Row), findsNothing);
  });
}

const _atmos = AudioTrack(id: '1', codec: 'eac3', channels: 6);
const _dutchSubtitle = SubtitleTrack(id: '1', language: 'nl');

/// A player whose `getProperty` answers the two mpv properties
/// [TvQualitySummaryLine] reads, and whose `track` state is fixed for the
/// test (the fake's own `track` stream never emits, matching the real
/// player's behavior of exposing the current selection only via `state`).
class _QualityPlayer extends FakeSyncPlayer {
  _QualityPlayer({required this.resolution, required this.codec, this.track = const TrackSelection()});

  final String? resolution;
  final String? codec;
  final TrackSelection track;

  @override
  PlayerState get state => super.state.copyWith(track: track);

  @override
  Future<String?> getProperty(String name) async {
    return switch (name) {
      'height' => resolution,
      'video-codec' => codec,
      _ => null,
    };
  }
}

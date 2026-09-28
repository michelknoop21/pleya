import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/screens/media_detail/mobile/detail_tech_table.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_quality_labels.dart';

void main() {
  setUp(() async => LocaleSettings.setLocale(AppLocale.nl));

  testWidgets('single audio track: row without chevron and not tappable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailTechTable(
            videoLabel: '1080p (H.264)',
            audioLabel: 'Engels (AAC stereo)',
            onAudioTap: null,
            subtitleLabel: 'Uit',
            onSubtitleTap: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget); // alleen de ondertitelrij
    expect(find.text('Ondertiteling'), findsOneWidget);
    expect(find.ancestor(of: find.text('Engels (AAC stereo)'), matching: find.byType(InkWell)), findsNothing);
  });

  testWidgets('light theme: values take the page text colour, not white', (tester) async {
    final theme = monoTheme(dark: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: DetailTechTable(videoLabel: '1080p (H.264)', audioLabel: 'Engels (AAC stereo)', subtitleLabel: 'Uit'),
        ),
      ),
    );
    for (final value in ['1080p (H.264)', 'Engels (AAC stereo)', 'Uit']) {
      expect(tester.widget<Text>(find.text(value)).style?.color, theme.colorScheme.onSurface, reason: value);
    }
    expect(tester.widget<Text>(find.text('Video')).style?.color, isNot(Colors.white.withValues(alpha: 0.7)));
  });

  testWidgets('no labels draws nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DetailTechTable(videoLabel: null, audioLabel: null, subtitleLabel: null)),
    );
    expect(find.byType(Text), findsNothing);
  });

  test('labels follow D-01', () {
    expect(
      detailVideoLabel(MediaFileInfo(videoResolution: '4k', videoCodec: 'hevc', videoProfile: 'main 10')),
      '4K (HEVC Main 10)',
    );
    final dutch = MediaAudioTrack(id: 1, languageCode: 'nld', codec: 'eac3', channels: 6, selected: true);
    // The language name follows the device locale, not the app's.
    expect(detailAudioLabel(dutch), '${dutch.label.primary} (EAC3 5.1)');
  });
}

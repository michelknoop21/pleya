import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_audio_track_picker_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  final tracks = [
    MediaAudioTrack(id: 1, languageCode: 'eng', codec: 'aac', channels: 2, selected: true),
    MediaAudioTrack(id: 2, languageCode: 'nld', codec: 'eac3', channels: 6, selected: false),
  ];

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('detail selector shows every available audio language', (tester) async {
    await pump(tester, MobileAudioTrackSelector(tracks: tracks, selectedTrackId: 1));

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('English · Dutch'), findsOneWidget);
  });

  testWidgets('picker reports the language chosen for playback', (tester) async {
    MediaAudioTrack? chosen;
    await pump(
      tester,
      MobileAudioTrackPickerSheet(tracks: tracks, selectedTrackId: 1, onChosen: (track) => chosen = track),
    );

    await tester.tap(find.text('Dutch'));
    expect(chosen?.id, 2);
  });
}

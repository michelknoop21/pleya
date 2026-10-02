import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_audio_track_picker_sheet.dart';
import 'package:pleya/widgets/mobile/mobile_subtitle_track_picker_sheet.dart';

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

  testWidgets('picker reports the chosen language and names what it applies to', (tester) async {
    MediaAudioTrack? chosen;
    await pump(
      tester,
      MobileAudioTrackPickerSheet(
        tracks: tracks,
        selectedTrackId: 1,
        scopeLabel: 'Sintel · applies to this film',
        onChosen: (track) => chosen = track,
      ),
    );

    expect(find.text('Sintel · applies to this film'), findsOneWidget);
    expect(find.text(t.discover.trackChoiceNote), findsOneWidget);
    await tester.tap(find.text('Dutch'));
    expect(chosen?.id, 2);
  });

  testWidgets('subtitle picker offers Off first and reports it as null', (tester) async {
    MediaSubtitleTrack? chosen = MediaSubtitleTrack(id: 9, selected: false, forced: false);
    await pump(
      tester,
      MobileSubtitleTrackPickerSheet(
        tracks: [MediaSubtitleTrack(id: 3, languageCode: 'nld', selected: true, forced: false)],
        selectedTrackId: 3,
        onChosen: (track) => chosen = track,
      ),
    );

    await tester.tap(find.text('Off'));
    expect(chosen, isNull);
  });

  testWidgets('the note only promises remembering when the pick is stored', (tester) async {
    await pump(tester, MobileAudioTrackPickerSheet(tracks: tracks, remembered: false, onChosen: (_) {}));
    expect(find.text(t.discover.trackChoiceNote), findsNothing);
    expect(find.text(t.discover.trackChoiceNoteOnce), findsOneWidget);
    await pump(tester, MobileSubtitleTrackPickerSheet(tracks: const [], remembered: false, onChosen: (_) {}));
    expect(find.text(t.discover.trackChoiceNoteOnce), findsOneWidget);
    await pump(tester, MobileSubtitleTrackPickerSheet(tracks: const [], onChosen: (_) {}));
    expect(find.text(t.discover.trackChoiceNote), findsOneWidget);
  });
}

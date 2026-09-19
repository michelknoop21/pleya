/// MOC-17: de detailbalk onder de gids is context, geen tweede activatiepad.
///
/// PB-8 is er expliciet over: "Een gefocust programma mag een blijvend
/// detailgebied voeden zonder de focus te stelen ... De detailbalk is context,
/// geen tweede verplichte activatiestap." De parity-audit noemt een balk met
/// een Kijken-knop erin als ARCHITECTURAL CONFLICT, want dat zou een tweede
/// pad naar afspelen maken naast SELECT op een lopend programma.
///
/// Wat de balk dus is: een leesbare weergave van waar de ring staat, met twee
/// labels die zeggen wat SELECT en lange SELECT doen. Wat hij niet is: iets
/// wat de remote kan bereiken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/models/livetv_program.dart';
import 'package:pleya/screens/livetv/tabs/guide_detail_band.dart';
import 'package:pleya/theme/mono_theme.dart';

Widget _host(Widget child) => TranslationProvider(
  child: MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(body: SizedBox(width: 1920, height: 200, child: child)),
  ),
);

LiveTvProgram _program() => LiveTvProgram(
  channelIdentifier: 'ch-2',
  title: 'Andere Tijden',
  summary: 'Geschiedenisprogramma over de Elfstedentocht van 1963.',
  beginsAt: DateTime(2026, 9, 19, 20, 45).millisecondsSinceEpoch ~/ 1000,
  endsAt: DateTime(2026, 9, 19, 21, 35).millisecondsSinceEpoch ~/ 1000,
);

void main() {
  testWidgets('the band names the focused program and its channel', (tester) async {
    await initializeDateFormatting('en');
    await tester.pumpWidget(
      _host(
        GuideDetailBand(
          channel: LiveTvChannel(key: 'ch-2', title: 'NPO 2', number: '2'),
          program: _program(),
          isRecordingScheduled: false,
        ),
      ),
    );

    expect(find.text('Andere Tijden'), findsOneWidget);
    expect(find.textContaining('NPO 2'), findsOneWidget);
    expect(find.textContaining('Elfstedentocht'), findsOneWidget);
  });

  testWidgets('nothing in the band can take the focus', (tester) async {
    await initializeDateFormatting('en');
    await tester.pumpWidget(
      _host(
        GuideDetailBand(
          channel: LiveTvChannel(key: 'ch-2', title: 'NPO 2', number: '2'),
          program: _program(),
          isRecordingScheduled: true,
        ),
      ),
    );

    // PB-8: geen tweede activatiestap. Een focusbare knop hier zou een tweede
    // pad naar afspelen zijn naast SELECT op het programma zelf.
    //
    // Gescoped op de subtree van GuideDetailBand: MaterialApp zelf zet al
    // FocusScope-knopen neer voor Navigator en de modale route, en die zijn
    // altijd canRequestFocus, dus een ongescoped predicate zou hier nooit op
    // nul uitkomen, ongeacht wat de balk zelf doet.
    expect(find.byType(FocusableWrapper), findsNothing);
    expect(
      find.descendant(
        of: find.byType(GuideDetailBand),
        matching: find.byWidgetPredicate((w) => w is Focus && w.canRequestFocus),
      ),
      findsNothing,
      reason: 'de balk is leesbaar, niet bereikbaar',
    );
  });

  testWidgets('with nothing focused the band keeps its height and says nothing', (tester) async {
    await tester.pumpWidget(_host(const GuideDetailBand(channel: null, program: null, isRecordingScheduled: false)));

    // Hoogte houden en niet wegvallen: een band die verschijnt en verdwijnt
    // duwt het raster erboven op en neer bij elke focuswissel, en dan
    // verspringt de rij onder de remote.
    expect(find.byType(GuideDetailBand), findsOneWidget);
    expect(find.text(t.liveTv.unknownProgram), findsNothing);
  });

  testWidgets('a scheduled recording says so, and says how to manage it', (tester) async {
    await initializeDateFormatting('en');
    await tester.pumpWidget(
      _host(
        GuideDetailBand(
          channel: LiveTvChannel(key: 'ch-2', title: 'NPO 2', number: '2'),
          program: _program(),
          isRecordingScheduled: true,
        ),
      ),
    );

    expect(find.textContaining(t.liveTv.recordingScheduled), findsOneWidget);
    expect(find.text(t.liveTv.manageRecording), findsOneWidget);
  });
}

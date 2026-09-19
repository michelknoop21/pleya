/// MOC-17: de gids heeft op tien voet een eigen dichtheid.
///
/// De maten hieronder zijn gekozen voor een desktopvenster: tien zenderrijen
/// in 1080 logische pixels, en typografie uit `theme.textTheme`. Op een Apple
/// TV is de logische viewport ook 1920x1080, dus `TvLayoutConstants.scaleOf`
/// is daar 1.0 en er is geen schaal die dit vanzelf goedmaakt. Mockup 17
/// tekent vijf rijen.
///
/// Deze test bewaakt de beslissing en niet het beeld. Een golden zou hetzelfde
/// beweren en zou op de macOS-tegen-Linux-drift blijven hangen die CAT5
/// beschrijft.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/livetv/tabs/guide_tab.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';

Future<GuideMetrics> metricsIn(WidgetTester tester, {required bool inShell}) async {
  late GuideMetrics measured;
  Widget probe(BuildContext context) {
    measured = guideMetricsFor(context);
    return const SizedBox.shrink();
  }

  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 1920,
        height: 1080,
        child: inShell ? TvShellSurface(child: Builder(builder: probe)) : Builder(builder: probe),
      ),
    ),
  );
  return measured;
}

void main() {
  testWidgets('inside the TV shell the guide is denser per row and wider per channel', (tester) async {
    final tv = await metricsIn(tester, inShell: true);
    final desktop = await metricsIn(tester, inShell: false);

    expect(tv.rowHeight, greaterThan(desktop.rowHeight));
    expect(tv.channelColumnWidth, greaterThan(desktop.channelColumnWidth));
    expect(tv.slotWidth, greaterThan(desktop.slotWidth));

    // Vijf rijen en de tijdkop passen in de hoogte die de shell overlaat.
    // 1080 min de topnavband (ongeveer 96) min de paginakop (ongeveer 110)
    // min de detailbalk uit Task 7 (ongeveer 170) laat ruwweg 700 over.
    expect(tv.timeHeaderHeight + 5 * tv.rowHeight, lessThanOrEqualTo(700));
  });

  testWidgets('off the shell nothing about the desktop guide moves', (tester) async {
    final desktop = await metricsIn(tester, inShell: false);

    expect(desktop.rowHeight, 64);
    expect(desktop.channelColumnWidth, 132);
    expect(desktop.slotWidth, 180);
    expect(desktop.timeHeaderHeight, 40);
  });
}

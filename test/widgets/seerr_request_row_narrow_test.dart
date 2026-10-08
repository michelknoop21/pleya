import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/seerr_request_row.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('a pending request with every action fits a 390pt phone and keeps its title readable', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: ListView(
              children: [
                SeerrRequestRow(
                  request: const SeerrRequest(
                    id: 1,
                    status: SeerrRequestStatus.pending,
                    mediaType: 'tv',
                    tmdbId: 5,
                    mediaTitle: 'Wadlopers',
                    mediaYear: '2023',
                    seasons: [3, 4, 5],
                    requestedByName: 'Ravi',
                  ),
                  onApprove: () {},
                  onDecline: () {},
                  onEdit: () {},
                  onCancel: () {},
                  onMore: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull, reason: 'no overflow');
    final title = tester.getRect(find.text('Wadlopers'));
    expect(title.width, greaterThan(80), reason: 'the facts column must not be squeezed away');
    for (final label in [t.seerr.approve, t.seerr.decline, t.seerr.edit, t.seerr.cancelRequest]) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(390), reason: label);
    }
  });
}

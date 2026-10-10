/// The line beside the button on a short screen with large text: left out,
/// so the buttons do not push the choices out and nothing overflows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/widgets/seerr_request_form_parts.dart';
import 'package:pleya/widgets/seerr_request_sheet.dart';

import '../test_helpers/seerr_fake.dart';

const _show = SeerrMedia(tmdbId: 1399, mediaType: 'tv', title: 'Wadlopers');

void main() {
  late FakeSeerr fake;

  setUp(() {
    fake = FakeSeerr()
      ..on('GET /user/7/quota', {
        'movie': {'limit': 5, 'remaining': 0},
        'tv': {'limit': 5, 'remaining': 0},
      })
      ..on('GET /tv/1399', {
        'id': 1399,
        'name': 'Wadlopers',
        'seasons': [
          for (var n = 1; n <= 6; n++) {'seasonNumber': n, 'episodeCount': 8},
        ],
      });
    for (final service in ['radarr', 'sonarr']) {
      fake.on('GET /service/$service', [
        {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': false},
      ]);
    }
  });

  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

  // (locale, size, text scale, safe area, keyboard)
  final cases = <(AppLocale, Size, double, EdgeInsets, double)>[
    for (final locale in [AppLocale.nl, AppLocale.en])
      for (final scale in [1.0, 1.65, 2.0, 2.35]) ...[
        (locale, const Size(568, 320), scale, EdgeInsets.zero, 0),
        (locale, const Size(568, 320), scale, const EdgeInsets.only(left: 44, right: 44, bottom: 21), 0),
        // The form has no text field, so a keyboard rarely opens over it. The
        // insets are put in the media query below the scaffold, which strips
        // them: the line gives way to the keyboard, the layout stays as on main.
        if (scale == 1.0) (locale, const Size(568, 320), scale, EdgeInsets.zero, 140),
        (locale, const Size(667, 375), scale, EdgeInsets.zero, 0),
        (locale, const Size(320, 568), scale, EdgeInsets.zero, 0),
        (locale, const Size(390, 844), scale, EdgeInsets.zero, 0),
        (locale, const Size(375, 667), scale, EdgeInsets.zero, 0),
      ],
  ];

  for (final (locale, size, scale, padding, keyboard) in cases) {
    final name =
        '${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()} at $scale'
        '${padding == EdgeInsets.zero ? '' : ' with safe areas'}${keyboard > 0 ? ' with keyboard' : ''}';

    testWidgets('$name: no overflow, the choices keep room and the buttons stay in reach', (tester) async {
      await tester.runAsync(() => LocaleSettings.setLocale(locale));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(
        left: padding.left,
        right: padding.right,
        top: padding.top,
        bottom: padding.bottom,
      );
      addTearDown(tester.view.reset);
      final provider = await seerrProvider(fake);
      addTearDown(provider.dispose);
      await pumpSeerr(
        tester,
        provider,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: const SeerrRequestSheet(media: _show),
          ),
        ),
      );
      await seerrSettle(tester);

      expect(tester.takeException(), isNull);
      final list = tester.getSize(find.byType(ListView)).height;
      // Main, with no line beside the button, kept 46 px on 568x320 at 1.65
      // in Dutch, and 18 px at 2.35, where the buttons stand above each other.
      expect(list, greaterThan(keyboard > 0 ? 30 : (scale <= 1.65 ? 40 : 15)));
      final buttons = tester.getRect(find.byType(SeerrFormButtons));
      expect(buttons.top, greaterThanOrEqualTo(0));
      expect(buttons.bottom, lessThanOrEqualTo(size.height));
      expect(
        find
            .descendant(of: seerrNode(AutomationIds.requestsFormButton, 'close'), matching: find.byType(TextButton))
            .hitTestable(),
        findsOneWidget,
      );
    });
  }
}

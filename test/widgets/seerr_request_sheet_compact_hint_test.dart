/// The line beside the button on a short screen with large text: left out,
/// so the buttons do not push the choices out and nothing overflows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/widgets/seerr_request_edit_sheet.dart';
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
      for (final scale in [1.0, 1.3, 1.65, 2.0, 2.35]) ...[
        (locale, const Size(568, 320), scale, EdgeInsets.zero, 0),
        (locale, const Size(568, 320), scale, const EdgeInsets.only(left: 44, right: 44, bottom: 21), 0),
        // A keyboard over the form: real view insets, which the scaffold
        // turns into a shorter body, so the line measures what is left.
        if (scale == 1.0) (locale, const Size(667, 375), scale, EdgeInsets.zero, 140),
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
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
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
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: const SeerrRequestSheet(media: _show),
          ),
        ),
      );
      await seerrSettle(tester);

      expect(tester.takeException(), isNull);
      final list = tester.getSize(find.byType(ListView)).height;
      // Main, with no line beside the button, kept 86 px on 568x320 at 1.3 in
      // Dutch, 46 at 1.65 and 18 at 2.35, where the buttons stand above each
      // other. Upright and on 667x375 at normal size the line stays, and the
      // list keeps at least what the 36 px of the first version was worth.
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
  // The edit form: the reason a save is off stays beside the button, as on
  // main, on every combination where it fitted. Only where main overflowed
  // (568x320 at 2.35: 66 px in Dutch, 19 in English) it is the first message
  // of the list instead.
  for (final locale in [AppLocale.nl, AppLocale.en]) {
    for (final size in const [Size(568, 320), Size(667, 375), Size(320, 568), Size(390, 844), Size(375, 667)]) {
      for (final scale in [1.0, 1.3, 1.65, 2.0, 2.35]) {
        final name = 'edit ${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()} at $scale';
        testWidgets('$name: no overflow and the reason for the disabled save is shown', (tester) async {
          await tester.runAsync(() => LocaleSettings.setLocale(locale));
          final edit = FakeSeerr()
            ..on('GET /tv/1012', {
              'id': 1012,
              'name': 'Wadlopers',
              'seasons': [
                for (var n = 1; n <= 5; n++) {'seasonNumber': n, 'episodeCount': 8},
              ],
              'mediaInfo': {
                'status': 4,
                'seasons': [
                  {'seasonNumber': 1, 'status': 5},
                  {'seasonNumber': 2, 'status': 2},
                  {'seasonNumber': 3, 'status': 2},
                  {'seasonNumber': 5, 'status': 2},
                ],
              },
            });
          edit.routes['GET /request/12'] = (_) => FakeSeerr.json(
            seerrRequestJson(
              12,
              type: 'tv',
              status: 1,
              seasons: [],
              requestedBy: 7,
              serverId: 2,
              profileId: 6,
              rootFolder: '/media/series',
              languageProfileId: 1,
              tags: [9],
            ),
          );
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final provider = await seerrProvider(edit);
          addTearDown(provider.dispose);
          final request = SeerrRequest.tryFromJson(seerrRequestJson(12, type: 'tv', seasons: []))!;
          await pumpSeerr(
            tester,
            provider,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: SeerrRequestEditSheet(request: request),
              ),
            ),
          );
          await seerrSettle(tester);

          expect(tester.takeException(), isNull);
          final reason = find.text(t.seerr.editKeepOneSeason);
          expect(reason, findsOneWidget);
          final inList = size == const Size(568, 320) && scale == 2.35;
          expect(
            find.descendant(of: find.byType(SeerrFormButtons), matching: reason),
            inList ? findsNothing : findsOneWidget,
            reason: inList ? 'only where the form overflowed on main' : 'beside the button, as on main',
          );
          expect(find.descendant(of: find.byType(ListView), matching: reason), inList ? findsOneWidget : findsNothing);
          expect(tester.getRect(find.byType(SeerrFormButtons)).bottom, lessThanOrEqualTo(size.height));
        });
      }
    }
  }
}

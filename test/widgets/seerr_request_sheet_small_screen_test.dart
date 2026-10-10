/// The request form on a small screen with large text, in the state that says
/// the most: no default instance to send to, with and without a reached limit.
/// Whatever the messages need, the row with the two buttons stays in reach.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/widgets/seerr_request_sheet.dart';

import '../test_helpers/seerr_fake.dart';

const _movie = SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge');
const _show = SeerrMedia(tmdbId: 1399, mediaType: 'tv', title: 'Wadlopers');

Finder _button(String instance) => seerrNode(AutomationIds.requestsFormButton, instance);
Finder _notice(String kind) => seerrNode(AutomationIds.requestsFormNotice, kind);

void main() {
  late FakeSeerr fake;

  /// Only an HD instance that is not the default: the list is read, and HD
  /// has nowhere to go.
  void blocked({bool quotaReached = false}) {
    fake = FakeSeerr()
      ..on('GET /user/7/quota', {
        'movie': {'limit': 5, 'remaining': quotaReached ? 0 : 3},
        'tv': {'limit': 5, 'remaining': quotaReached ? 0 : 3},
      })
      ..on('GET /tv/1399', {
        'id': 1399,
        'name': 'Wadlopers',
        'seasons': [
          for (var n = 1; n <= 3; n++) {'seasonNumber': n, 'episodeCount': 8},
        ],
      });
    for (final service in ['radarr', 'sonarr']) {
      fake.on('GET /service/$service', [
        {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': false},
      ]);
    }
  }

  Future<void> open(WidgetTester tester, SeerrMedia media, {required Size size, double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = await seerrProvider(fake);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: SeerrRequestSheet(media: media),
        ),
      ),
    );
    await seerrSettle(tester);
  }

  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

  for (final locale in [AppLocale.nl, AppLocale.en]) {
    for (final portrait in [const Size(320, 568), const Size(375, 667)]) {
      for (final size in [portrait, portrait.flipped]) {
        for (final scale in [1.0, 1.3]) {
          for (final quotaReached in [false, true]) {
            for (final media in [_movie, _show]) {
              final name =
                  '${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()} at $scale, '
                  '${media.mediaType}${quotaReached ? ', limit reached' : ''}';
              testWidgets('$name: nothing overflows and both buttons can be pressed', (tester) async {
                await tester.runAsync(() => LocaleSettings.setLocale(locale));
                blocked(quotaReached: quotaReached);
                await open(tester, media, size: size, textScale: scale);

                expect(tester.takeException(), isNull);
                expect(_notice('route'), findsOneWidget);
                expect(find.text(t.seerr.quotaReached), quotaReached ? findsOneWidget : findsNothing);
                expect(
                  find.descendant(of: _button('close'), matching: find.byType(TextButton)).hitTestable(),
                  findsOneWidget,
                );
                expect(
                  find.descendant(of: _button('submit'), matching: find.byType(FilledButton)).hitTestable(),
                  findsOneWidget,
                );
              });
            }
          }
        }
      }
    }
  }

  testWidgets('on a television the blocked form opens on Cancel, and the remote leaves and finds it again', (
    tester,
  ) async {
    blocked();
    await open(tester, _show, size: const Size(1920, 1080));
    expect(_notice('route'), findsOneWidget);
    expect(seerrHasFocus(tester, _button('close')), isTrue, reason: 'the button that cannot send does not get it');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await seerrSettle(tester);
    expect(seerrHasFocus(tester, _button('close')), isFalse, reason: 'the seasons are still in reach');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await seerrSettle(tester);
    expect(seerrHasFocus(tester, _button('close')), isTrue);
  });
}

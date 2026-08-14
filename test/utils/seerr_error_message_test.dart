import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/utils/seerr_error_message.dart';

void main() {
  group('seerrErrorKindOf', () {
    test('keeps auth and permission failures apart from everything else', () {
      // These are the two the discover screen used to collapse into the
      // generic message, which told the user to retry something that retrying
      // cannot fix.
      expect(seerrErrorKindOf(SeerrException.auth()), SeerrErrorKind.auth);
      expect(seerrErrorKindOf(SeerrException.forbidden()), SeerrErrorKind.forbidden);
    });

    test('recognises a transport failure', () {
      expect(seerrErrorKindOf(SeerrException.network('no route to host')), SeerrErrorKind.network);
    });

    test('treats a plain HTTP failure and a non-seerr throw as generic', () {
      expect(seerrErrorKindOf(SeerrException.http(500, null)), SeerrErrorKind.generic);
      expect(seerrErrorKindOf(StateError('parse blew up')), SeerrErrorKind.generic);
    });
  });

  group('dominantSeerrErrorKind', () {
    test('an actionable failure outranks a generic one', () {
      // Every visible row failed; the message has to name the one the user can
      // do something about, not whichever row happened to be first.
      expect(dominantSeerrErrorKind([SeerrErrorKind.generic, SeerrErrorKind.auth]), SeerrErrorKind.auth);
      expect(dominantSeerrErrorKind([SeerrErrorKind.generic, SeerrErrorKind.forbidden]), SeerrErrorKind.forbidden);
      expect(dominantSeerrErrorKind([SeerrErrorKind.generic, SeerrErrorKind.network]), SeerrErrorKind.network);
    });

    test('auth outranks permission, which outranks the network', () {
      expect(dominantSeerrErrorKind([SeerrErrorKind.forbidden, SeerrErrorKind.auth]), SeerrErrorKind.auth);
      expect(dominantSeerrErrorKind([SeerrErrorKind.network, SeerrErrorKind.forbidden]), SeerrErrorKind.forbidden);
    });

    test('falls back to generic when there is nothing better to say', () {
      expect(dominantSeerrErrorKind([SeerrErrorKind.generic]), SeerrErrorKind.generic);
      expect(dominantSeerrErrorKind(const []), SeerrErrorKind.generic);
    });
  });

  group('seerrErrorMessage', () {
    test('gives each kind its own wording', () {
      final messages = SeerrErrorKind.values.map(seerrErrorMessage).toList();

      expect(messages.toSet(), hasLength(SeerrErrorKind.values.length), reason: 'no two kinds should read the same');
      for (final m in messages) {
        expect(m, isNotEmpty);
      }
    });

    test('an expired session no longer reads as a generic retry', () {
      expect(seerrErrorMessage(SeerrErrorKind.auth), isNot(seerrErrorMessage(SeerrErrorKind.generic)));
      expect(seerrErrorMessage(SeerrErrorKind.forbidden), isNot(seerrErrorMessage(SeerrErrorKind.generic)));
    });
  });
}

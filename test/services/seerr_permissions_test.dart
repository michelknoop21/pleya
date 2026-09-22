import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';

import '../test_helpers/prefs.dart';

/// Overseerr's 4K permission is per media type, and Pleya has to ask the same
/// question it does.
///
/// Overseerr checks `hasPermission([REQUEST_4K, REQUEST_4K_MOVIE], {type:'or'})`
/// for a movie and `[REQUEST_4K, REQUEST_4K_TV]` for a series: the umbrella
/// flag, or the one for that type, never the union of all three. Collapsing
/// them into one OR offered the 4K switch on a film to someone who only holds
/// the series permission, and the request came back 403 after they had already
/// filled the sheet in.
const int _request = SeerrPermission.request;
const int _admin = SeerrPermission.admin;
const int _any4k = SeerrPermission.request4k;
const int _movie4k = SeerrPermission.request4kMovie;
const int _tv4k = SeerrPermission.request4kTv;

void main() {
  group('the 4K permission matrix', () {
    /// (name, permissions, may request a 4K movie, may request a 4K series)
    const cases = <(String, int, bool, bool)>[
      ('no permissions at all', 0, false, false),
      ('plain REQUEST, no 4K', _request, false, false),
      ('generic REQUEST_4K covers both', _request | _any4k, true, true),
      ('REQUEST_4K_MOVIE is movies only', _request | _movie4k, true, false),
      ('REQUEST_4K_TV is series only', _request | _tv4k, false, true),
      ('both type flags cover both', _request | _movie4k | _tv4k, true, true),
      ('generic plus a type flag still covers both', _request | _any4k | _tv4k, true, true),
      ('ADMIN implies everything', _admin, true, true),
      ('ADMIN without any 4K flag still implies everything', _admin | _request, true, true),
    ];

    for (final (name, permissions, movie, tv) in cases) {
      test(name, () {
        expect(
          SeerrPermission.canRequest4k(permissions, isMovie: true),
          movie,
          reason: '$name: 4K movie request should be ${movie ? 'allowed' : 'refused'}',
        );
        expect(
          SeerrPermission.canRequest4k(permissions, isMovie: false),
          tv,
          reason: '$name: 4K series request should be ${tv ? 'allowed' : 'refused'}',
        );
      });
    }

    test('the series permission alone never unlocks a 4K movie', () {
      // The case the union used to get wrong: 4096 | 32 == 4128, and
      // `4128 & (1024|2048|4096)` is non-zero, so the switch appeared on films.
      expect(SeerrPermission.canRequest4k(_request | _tv4k, isMovie: true), isFalse);
    });
  });

  group('the provider asks per media type', () {
    setUp(resetSharedPreferencesForTest);

    Future<SeerrProvider> providerWith(int permissions) async {
      final provider = SeerrProvider();
      await provider.onActiveProfileChanged('user-1');
      await provider.commit(
        SeerrSession(
          baseUrl: 'https://seerr.example',
          authMode: SeerrAuthMode.apiKey,
          apiKey: 'k',
          userId: 1,
          permissions: permissions,
        ),
      );
      return provider;
    }

    test('a series-only 4K permission does not offer 4K on a film', () async {
      final provider = await providerWith(_request | _tv4k);
      addTearDown(provider.dispose);

      expect(provider.canRequest4kFor(isMovie: true), isFalse);
      expect(provider.canRequest4kFor(isMovie: false), isTrue);
    });

    test('a movie-only 4K permission does not offer 4K on a series', () async {
      final provider = await providerWith(_request | _movie4k);
      addTearDown(provider.dispose);

      expect(provider.canRequest4kFor(isMovie: true), isTrue);
      expect(provider.canRequest4kFor(isMovie: false), isFalse);
    });

    test('no session means no 4K anywhere', () {
      final provider = SeerrProvider();
      addTearDown(provider.dispose);

      expect(provider.canRequest4kFor(isMovie: true), isFalse);
      expect(provider.canRequest4kFor(isMovie: false), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/screens/settings/add_plex_account_screen.dart';

void main() {
  const plexId = 'plex.6bf2014a773a93f8';
  final created = DateTime(2026, 1, 1);

  group('profileAlreadyUsesConnection', () {
    test('a Plex Home profile already owns its parent account', () {
      // Signing into the account a Home profile belongs to must not route
      // into the borrow step: every candidate from that account is filtered
      // out there, which left an empty "Nothing to borrow yet" page.
      final michel = Profile.plexHome(
        id: 'plex-home-$plexId-6bf2014a773a93f8',
        displayName: 'Michel',
        parentConnectionId: plexId,
        createdAt: created,
      );

      expect(profileAlreadyUsesConnection(michel, plexId, const []), isTrue);
    });

    test('a stored profile connection to the account counts as owned', () {
      final local = Profile.local(id: 'local-a', displayName: 'A', createdAt: created);
      const pcs = [ProfileConnection(profileId: 'local-a', connectionId: plexId, userIdentifier: 'u1')];

      expect(profileAlreadyUsesConnection(local, plexId, pcs), isTrue);
    });

    test('another profile\'s row or another account does not count', () {
      final local = Profile.local(id: 'local-a', displayName: 'A', createdAt: created);
      const pcs = [
        ProfileConnection(profileId: 'local-b', connectionId: plexId, userIdentifier: 'u1'),
        ProfileConnection(profileId: 'local-a', connectionId: 'plex.other', userIdentifier: 'u2'),
      ];

      expect(profileAlreadyUsesConnection(local, plexId, pcs), isFalse);
    });
  });
}

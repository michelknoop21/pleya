import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_account_key.dart';
import 'package:pleya/assistant/assistant_people.dart';
import 'package:pleya/assistant/current_user_context.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/profiles/profile_server_identity.dart';

ServerUser _user(String id, String name) =>
    ServerUser(id: id, name: name, role: ServerUserRole.member, allLibraries: true);

bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

void main() {
  group('resolvePeople', () {
    final users = [_user('1', 'Michel'), _user('2', 'Anna'), _user('3', 'Anna'), _user('4', 'Pim')];

    AssistantPeopleMatch resolve(List<String> names, {List<ProfileServerIdentity> profiles = const []}) =>
        resolvePeople(names: names, users: users, profiles: profiles, sameUserId: _same, requesterUserId: '1');

    test('an exact name finds one account; "me" is the requester', () {
      final m = resolve(['pim', 'me']);
      expect(m.selected.keys, unorderedEquals(['4', '1']));
      expect(m.ambiguous, isEmpty);
      expect(m.missing, isEmpty);
    });

    test('two accounts with the same name are offered as choices, never merged or guessed', () {
      final m = resolve(['Anna']);
      expect(m.selected, isEmpty);
      expect(m.ambiguous.single.choices.map((u) => u.id), ['2', '3']);
    });

    test('an unknown name is missing, not approximated', () {
      final m = resolve(['Annaa']);
      expect(m.missing, ['Annaa']);
      expect(m.selected, isEmpty);
    });

    test('a Pleya profile label resolves through its verified server identity', () {
      final m = resolve(
        ['Mama'],
        profiles: const [
          ProfileServerIdentity(profileId: 'p1', displayName: 'Mama', userIds: {'3'}),
        ],
      );
      expect(m.selected.keys, ['3']);
      expect(m.aliases, {'Mama': '3'});
    });
  });

  group('othersOf', () {
    const plexTv = AssistantAccountProvider.plexTv;
    final me = CurrentUserContext.build(const [
      AssistantSelfSource(serverId: 'plex-a', backend: MediaBackend.plex, plexTvAccountId: 42),
      AssistantSelfSource(serverId: 'jf', backend: MediaBackend.jellyfin, userId: 'u-1'),
      AssistantSelfSource(serverId: 'jf2', backend: MediaBackend.jellyfin),
    ]);
    final self = (name: 'Michel', key: const AssistantAccountKey(plexTv, '42') as AssistantAccountKey?);
    final namesake = (name: 'Michel', key: const AssistantAccountKey(plexTv, '77') as AssistantAccountKey?);
    final anna = (name: 'Anna', key: const AssistantAccountKey(plexTv, '8') as AssistantAccountKey?);
    final jfSelf = (
      name: 'm',
      key: const AssistantAccountKey(AssistantAccountProvider.jellyfin, 'u-1', serverId: 'jf') as AssistantAccountKey?,
    );
    final keyless = (name: 'Guest', key: null as AssistantAccountKey?);
    final unknownSource = (
      name: 'Kid',
      key: const AssistantAccountKey(AssistantAccountProvider.jellyfin, 'k-1', serverId: 'jf2') as AssistantAccountKey?,
    );

    AssistantOthers<({String name, AssistantAccountKey? key})> run(List<({String name, AssistantAccountKey? key})> p) =>
        othersOf(p, keyOf: (x) => x.key, me: me);

    test('me is removed by account id, a namesake with another id stays an other', () {
      final r = run([self, namesake, anna, jfSelf]);
      expect(r.others.map((p) => p.key!.accountId), ['77', '8']);
      expect(r.leftOut, isEmpty);
    });

    test('a person without a key, or on a source where "me" is unknown, is left out, never counted as an other', () {
      final r = run([anna, keyless, unknownSource]);
      expect(r.others.map((p) => p.name), ['Anna']);
      expect(r.leftOut.map((p) => p.name), ['Guest', 'Kid']);
    });

    test('with no known self anywhere there are no others: it never falls back to everyone', () {
      final nobody = CurrentUserContext.build(const []);
      final r = othersOf([anna, namesake], keyOf: (x) => x.key, me: nobody);
      expect(r.others, isEmpty);
      expect(r.leftOut, hasLength(2));
    });
  });
}

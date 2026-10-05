import '../media/server_administration.dart';
import '../profiles/profile_server_identity.dart';
import 'assistant_account_key.dart';
import 'current_user_context.dart';

/// What a list of names resolved to on one server. A name only ever finds an
/// account; it never merges two accounts into one person.
class AssistantPeopleMatch {
  const AssistantPeopleMatch({
    required this.selected,
    required this.aliases,
    required this.ambiguous,
    required this.missing,
  });

  /// Account id to account, starting with whoever was passed as [initial].
  final Map<String, ServerUser> selected;

  /// A name that resolved through a local Pleya profile to this account id.
  final Map<String, String> aliases;

  /// Names that matched several accounts: the user chooses, never the model.
  final List<({String name, List<ServerUser> choices})> ambiguous;
  final List<String> missing;
}

/// Finds the accounts [names] mean among [users]: "me" is [requesterUserId];
/// a Pleya profile label resolves through its verified server identities;
/// otherwise the exact account name. Several hits are offered as choices.
AssistantPeopleMatch resolvePeople({
  required List<String> names,
  required List<ServerUser> users,
  required List<ProfileServerIdentity> profiles,
  required bool Function(String a, String b) sameUserId,
  required String requesterUserId,
  Map<String, ServerUser> initial = const {},
}) {
  final selected = {...initial};
  final aliases = <String, String>{};
  final ambiguous = <({String name, List<ServerUser> choices})>[];
  final missing = <String>[];
  for (final name in names) {
    final wanted = name.trim().toLowerCase();
    final matchingProfiles = profiles.where((p) => p.displayName.trim().toLowerCase() == wanted).toList();
    final aliasIds = {for (final p in matchingProfiles) ...p.userIds};
    final matches = users
        .where(
          (u) => wanted == 'me'
              ? sameUserId(u.id, requesterUserId)
              : matchingProfiles.isNotEmpty
              ? aliasIds.any((alias) => sameUserId(alias, u.id))
              : u.name.trim().toLowerCase() == wanted,
        )
        .toList();
    if (matches.length == 1 && matchingProfiles.length <= 1) {
      selected[matches.single.id] = matches.single;
      if (matchingProfiles.isNotEmpty) aliases[name] = matches.single.id;
    } else if (matches.isEmpty) {
      missing.add(name);
    } else {
      ambiguous.add((name: name, choices: matches));
    }
  }
  return AssistantPeopleMatch(selected: selected, aliases: aliases, ambiguous: ambiguous, missing: missing);
}

/// "Everyone but me", decided on account keys and never on names.
class AssistantOthers<T> {
  const AssistantOthers({required this.others, required this.leftOut});

  /// Provably somebody else.
  final List<T> others;

  /// Neither provably me nor provably somebody else: no key, or "me" is unknown
  /// on that source. They are reported as left out, never counted as others
  /// and never folded back into "everyone".
  final List<T> leftOut;
}

/// Splits [people] into the others and those that cannot be told apart from
/// me. [keyOf] gives a person's account key, null when the source has none.
AssistantOthers<T> othersOf<T>(
  Iterable<T> people, {
  required AssistantAccountKey? Function(T) keyOf,
  required CurrentUserContext me,
}) {
  final others = <T>[];
  final leftOut = <T>[];
  for (final person in people) {
    final key = keyOf(person);
    if (key == null || !me.canTell(key)) {
      leftOut.add(person);
    } else if (!me.isSelf(key)) {
      others.add(person);
    }
  }
  return AssistantOthers(others: others, leftOut: leftOut);
}

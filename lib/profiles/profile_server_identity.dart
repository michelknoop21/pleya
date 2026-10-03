/// A Pleya profile's backend identity metadata, without tokens or hydrated
/// connections. Empty or multiple userIds require explicit clarification.
class ProfileServerIdentity {
  const ProfileServerIdentity({required this.profileId, required this.displayName, required this.userIds});
  final String profileId;
  final String displayName;
  final Set<String> userIds;
}

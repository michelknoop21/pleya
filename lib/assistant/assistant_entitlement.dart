/// Whether this account may use Pleya Assistant.
///
/// Independent of server rights and of the model provider: an entitlement
/// never grants rights on a server, and a free local model or an own API key
/// never grants the entitlement.
enum AssistantEntitlementState { entitled, notEntitled, unknown }

class AssistantEntitlement {
  const AssistantEntitlement();

  /// Product rollout gate, not a user entitlement. Off: Big P does not exist
  /// in this build at all.
  static const bool rolloutEnabled = bool.fromEnvironment('PLEYA_ASSISTANT_ENABLED');

  /// Callers treat anything but [AssistantEntitlementState.entitled] as no.
  // ponytail: no purchase system exists yet, so every account in a rolled-out
  // build is entitled. A StoreKit or account check replaces this body; the
  // callers (tile, run start, sensitive execution) stay as they are.
  Future<AssistantEntitlementState> check() async =>
      rolloutEnabled ? AssistantEntitlementState.entitled : AssistantEntitlementState.notEntitled;
}

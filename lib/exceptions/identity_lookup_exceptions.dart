/// Why a server could not answer an identity question ("do you have this
/// title", "which numbers does this title carry"). Both are "could not check",
/// never "not there": a caller must not read either as an empty answer, cache
/// it as a negative, or count the server as fully checked.
sealed class IdentityLookupException implements Exception {
  const IdentityLookupException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server did not give a usable answer right now: offline, a transport
/// failure, a timeout, 429, 5xx or an answer that broke the contract. Trying
/// again later may work, so nothing about it may be stored as final.
class IdentityLookupUnavailable extends IdentityLookupException {
  const IdentityLookupUnavailable(super.message);
}

/// The server cannot answer this question at all: it predates the capability,
/// or the identity carries nothing it can be asked about. Retrying changes
/// nothing until the server is updated or the identity gains a number.
class IdentityLookupUnsupported extends IdentityLookupException {
  const IdentityLookupUnsupported(super.message);
}

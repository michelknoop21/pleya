/// Why the last search produced nothing.
///
/// Its own small library because both presentations of Search need the same
/// word for it: the shared list on TV and desktop, and the phone body fase 4
/// added. "We could not reach anything" and "your library really has no match"
/// are different situations with different exits, and the screen has told them
/// apart since long before the mobile body existed.
library;

enum SearchFailure {
  /// Servers were connected, but every one of them failed or timed out.
  network,

  /// There were no connected servers to ask.
  noServers,
}

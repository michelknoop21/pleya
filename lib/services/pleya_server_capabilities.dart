import '../media/server_capabilities.dart';
import '../models/pleya_server/pleya_wire.dart';

/// Turns what a Pleya Server says about itself into what the app may offer.
///
/// The other four backends carry a hardcoded [ServerCapabilities] constant,
/// because Plex and Jellyfin do not say what they can do. Pleya Server does:
/// `GET /info` carries a `capabilities` object and the specification calls it
/// "always leading over `feature_level`". Hardcoding it here would mean a
/// server that gains a feature needs an app release before anyone can use it,
/// which is the coupling the field exists to remove.
///
/// ## Both halves have to be true
///
/// A flag is on only when the **server offers** it and **this build implements**
/// it. `ServerCapabilities` documents what a backend supports *in this app's
/// current implementation*, and an affordance that appears because the server
/// said yes, with nothing wired behind it, is worse than one that stays hidden:
/// it is PS-3 acceptance criterion 4 failing in the most literal way.
///
/// [_offered] spells both halves out at every field, so the client half is
/// visible as a named phase rather than as an absent line. A later phase flips
/// its own `false` and nothing else moves.
class PleyaServerCapabilityResolver {
  const PleyaServerCapabilityResolver._();

  /// `server && client`, written so both halves stay readable.
  ///
  /// [implementedHere] is a constant per field on purpose. It is the answer to
  /// "can this build do anything with a yes", and that answer changes by
  /// editing code, never at runtime.
  static bool _offered(bool advertised, {required bool implementedHere}) => advertised && implementedHere;

  /// What the app may do before `GET /info` has ever answered.
  ///
  /// Nothing. A connection that has not answered is not a server that browses;
  /// it is a server that has told us nothing. Claiming otherwise is how a
  /// screen calls an endpoint that is not there and shows a failure where a
  /// spinner belonged.
  static const ServerCapabilities unknown = ServerCapabilities(videoTranscoding: false, alphaBar: AlphaBarMode.none);

  static ServerCapabilities resolve(PleyaCapabilities wire) => ServerCapabilities(
    // No play-queue resource in the protocol. A shared queue is server-side
    // state Pleya Server does not keep.
    serverSidePlayQueue: false,

    // No playlist or collection endpoints. G1 in the replacement matrix: it
    // needs a phase before it needs a flag.
    serverSidePlaylists: false,

    // PS-4 brought watch state, so these two have somewhere to write to.
    //
    // Removal from Continue Watching maps onto `mark_unwatched`: the contract
    // has no separate flag, and position zero with watched false is exactly the
    // state that keeps a title out of the row. The dedicated flag arrives with
    // the personal layer in PS-9P.
    continueWatchingRemoval: _offered(wire.watchState, implementedHere: true),
    // The offline queue replays with `backlog: true`, and the server treats a
    // backlog as history: it never acquires ownership and never moves a newer
    // canonical state (DEC-049, rule 6). That is what makes replaying safe.
    offlineWatchQueue: _offered(wire.watchState, implementedHere: true),
    // Track preferences are PS-9T, because they only become true once the
    // playback plan can resolve a stored language onto the actual streams of
    // the version it picks. Storing a stream index instead would point at a
    // different track after any re-encode.
    trackPreferencePersistence: _offered(wire.watchState, implementedHere: false),

    // PS-8 on the server, PS-6 for the client's side of the negotiation.
    // Leaving this on the wire flag alone would put quality presets in the
    // player with nothing behind them the moment a server flips it.
    videoTranscoding: _offered(wire.transcode, implementedHere: false),

    // PS-10.
    serverSideSync: _offered(wire.downloads, implementedHere: false),

    // No Live TV surface in v1, and a tab that opens on an empty screen is
    // exactly what criterion 4 forbids.
    liveTv: _offered(wire.liveTv, implementedHere: false),
    liveTvDvr: false,

    // PS-9 brings users, and favourites and ratings are per-user by
    // definition. One bootstrap identity has nobody to be favourite for.
    serverFavorites: _offered(wire.users, implementedHere: false),
    numericUserRating: _offered(wire.users, implementedHere: false),

    // Subtitle *search* is a marketplace call. The server serves the sidecars
    // the scanner found on disk and looks nothing up.
    subtitleSearch: false,
    externalSubtitleSearch: false,

    // The server hands over building blocks (recently_added,
    // continue_watching, next_up) and the client's own recommendation engine
    // builds the rows. That is the opposite of a rich hub.
    richHubs: false,

    // One endpoint, one server. There is no candidate list to fail over
    // between, which is why the connection has a single baseUrl.
    endpointFailover: false,

    // The Discord payload is Plex-shaped. Making it backend-neutral is its own
    // piece of work and stands in the matrix as such.
    discordRpc: false,

    // PS-7 brings metadata. There is nothing to edit before there is anything
    // to edit.
    richMetadataEdit: false,

    // The contract has no first-character endpoint and no name-prefix filter.
    // A client-side bar over a cursored list jumps to the wrong place on any
    // library larger than one page. G13.
    alphaBar: AlphaBarMode.none,

    // No trickplay or BIF equivalent in v1.
    scrubThumbnails: false,

    // No folder listing on the contract; `storage_locations` stays
    // server-side. A matrix gap, not a client shortcut.
    folderGrouping: false,
  );
}

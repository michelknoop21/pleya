/// The one owner of "the remote should leave the top navigation and enter the
/// active destination's content" on the fase-7 TV shell.
///
/// ## Why this exists
///
/// Three independent code paths used to move the focus into TV content, none
/// of them aware of the other two:
///
///  1. `MainScreen._selectTab`, which calls `focusActiveTabIfReady()` on every
///     tab change;
///  2. `MainScreen._selectTvDestination`, which called `_focusContent`
///     unconditionally — so activating *any* destination in the bar dropped the
///     remote straight into that destination's content;
///  3. `DiscoverScreen`'s initial-load post-frame, which called
///     `focusPrimary()` as soon as content landed, guarded only by `mounted`
///     and `ModalRoute.isCurrent`.
///
/// Each one is defensible on its own and together they are unpredictable: on a
/// cold Home the third fired regardless of what the viewer had done in the
/// meantime, so the billboard's Afspelen pill claimed the remote seconds after
/// the viewer had deliberately walked the bar. Fixing (2) alone leaks through
/// (3); fixing (2) and (3) with separate guards leaves two things that have to
/// be kept in agreement forever.
///
/// So there is one flag, and it is an *intent*: something the viewer asked for,
/// armed by the press that asked for it and consumed exactly once by whoever
/// manages to satisfy it. Content arriving on its own is not a request and can
/// never move the focus.
///
/// ## The contract
///
/// | Event | Behaviour |
/// |---|---|
/// | **Focus** moving to a different bar item | the destination switches under the ring, the **bar keeps the focus**, no intent is armed |
/// | Select on a **different** destination | cannot happen any more: focus already made it the active one before Select could be pressed |
/// | Select on the **already active** destination | [TvContentFocusIntent.restore] — hoofdstuk 7.2's "back where you were", and now also what Select on the bar always means |
/// | **DOWN** out of the bar | [TvContentFocusIntent.primary]. Content ready → satisfied and consumed on the spot. Not ready → stays armed |
/// | Content arriving late | may only [consume] an intent that is already armed. It never arms one |
///
/// ## Focus is the destination
///
/// LEFT/RIGHT on the bar changes the page. Select is not required and never
/// was the only way in, it is simply no longer the *switch*: by the time it is
/// pressed the focused item is already active, so it lands on the "already
/// active" row above and means "go into this content" — the same thing DOWN
/// means, through the same intent, with no second code path.
///
/// The half that matters is what stays put. A destination switching under the
/// ring arms nothing, so a viewer walking the bar keeps the remote in the bar
/// however slowly the pages behind it load, and a server answering three
/// destinations later cannot pull them into content they have already walked
/// past. [onDestinationFocused] is that rule.
///
/// Anything that puts the remote back in the bar [cancel]s: an intent the
/// viewer has walked away from must not be honoured a second later by a server
/// that finally answered.
library;

/// What "focus the content" was asked to mean.
enum TvContentFocusIntent {
  /// The destination's own primary target — on Home, hoofdstuk 7.1's Afspelen
  /// pill, falling through to the first row when there is no hero.
  primary,

  /// Put the remote back where it was inside this destination (hoofdstuk 7.2).
  restore,
}

class TvContentFocusAuthority {
  TvContentFocusIntent? _pending;

  /// The armed intent, without consuming it. For assertions and for a caller
  /// that wants to branch before deciding to act.
  TvContentFocusIntent? get pending => _pending;

  bool get hasPendingIntent => _pending != null;

  /// Arms an intent, replacing any older one: two presses inside one frame
  /// mean the second is what the viewer wants.
  void arm(TvContentFocusIntent intent) => _pending = intent;

  /// Drops the armed intent without acting on it.
  void cancel() => _pending = null;

  /// Takes the armed intent and disarms it, or returns null when nothing was
  /// armed.
  ///
  /// Callers that can *fail* to place the focus must check first and only
  /// consume on success — a DOWN pressed before the first server answered has
  /// to stay armed until there is something to land on.
  TvContentFocusIntent? consume() {
    final intent = _pending;
    _pending = null;
    return intent;
  }

  /// Select on a destination in the bar. Returns the intent the shell should
  /// act on, or null when the answer is "change the page, leave the ring".
  ///
  /// The policy lives here rather than in `MainScreen._selectTvDestination`
  /// deliberately. "One focus authority" is not just one flag: the *rule* has
  /// to have one home too, or the next surface that activates a destination
  /// gets to invent its own reading of hoofdstuk 7.2 — which is how there came
  /// to be three of these in the first place.
  /// The ring moved to another bar item, which now switches the page.
  ///
  /// Always "change the page, leave the ring": there is no reading of this
  /// gesture under which the viewer asked to be put inside the content. Any
  /// intent armed by an earlier press was armed against a destination that is
  /// no longer on screen, so it is cancelled rather than left to be honoured
  /// by whichever page finishes loading first.
  void onDestinationFocused() => cancel();

  TvContentFocusIntent? onDestinationSelected({required bool wasActive}) {
    if (!wasActive) {
      // A different destination. The page behind the bar changes and the remote
      // stays on the item the viewer just pressed; anything armed by an earlier
      // press was armed against a destination that is no longer on screen.
      cancel();
      return null;
    }
    arm(TvContentFocusIntent.restore);
    return TvContentFocusIntent.restore;
  }
}

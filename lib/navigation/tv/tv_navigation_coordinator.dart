import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../automation/automation_route_state.dart';
import '../../automation/pleya_verify.dart';
import '../navigation_tabs.dart';
import 'tv_destination.dart';
import 'tv_nested_surface.dart';

/// Owns the TV root shell's navigation state: which destination is active,
/// which navigation item the remote is on, and where the focus was inside each
/// destination's content.
///
/// **Active is not focused.** Hoofdstuk 7.2 lets the remote walk the bar
/// without changing the page: Films can be the active destination while Search
/// is merely the focused item, and the two states are drawn differently (a
/// white pill versus a white ring). Keeping them in one field would make
/// Left/Right rebuild the whole content subtree and refetch a catalogue on
/// every step, which hoofdstuk 24 forbids and which is why they are two fields
/// here.
///
/// **Focus memory is keyed, not indexed.** Hoofdstuk 7.6 wants Films to come
/// back to the card it was left on. The memory therefore stores the place a
/// screen reported — [TvDestinationFocusMemory] — per destination, and a
/// conditional Live TV slot appearing cannot shift what any other destination
/// remembers; an index would have.
class TvNavigationCoordinator extends ChangeNotifier {
  TvNavigationCoordinator({TvDestinationId initial = tvRootDestination}) : _active = initial, _focused = initial {
    _publishRoute();
  }

  /// Where the TV shell stands, published for `/v1/route`.
  ///
  /// Hooked into [notifyListeners] rather than sprinkled over the eight
  /// mutators, because every one of them already ends in a notify and a ninth
  /// added later would otherwise be the one that forgets. [AutomationRouteState]
  /// itself drops a repeat, so the focus-ring moves that also notify (and change
  /// no route) cost nothing.
  @override
  void notifyListeners() {
    _publishRoute();
    super.notifyListeners();
  }

  void _publishRoute() {
    if (!kPleyaVerify) return;
    AutomationRouteState.instance.updateTv(destination: _active.name, nestedRoute: activeNestedRoute?.id);
  }

  TvDestinationId _active;
  TvDestinationId _focused;

  final Map<TvDestinationId, TvDestinationFocusMemory> _contentFocusMemory = {};

  /// One nested stack per destination — see [TvNestedRoute].
  final Map<TvDestinationId, List<TvNestedRoute>> _nested = {};

  /// The destination whose content is on screen. Drawn as the white pill.
  TvDestinationId get active => _active;

  /// The destination the remote is currently on inside the bar. Drawn with the
  /// white focus ring. Equal to [active] until the user walks away from it.
  TvDestinationId get focusedDestination => _focused;

  /// The destinations currently in the bar, left to right.
  List<TvDestinationId> get destinations => List.unmodifiable(_destinations);
  List<TvDestinationId> _destinations = buildTvDestinations(const TvNavConditions(hasLiveTv: false));

  /// Recompute the bar from [conditions].
  ///
  /// Returns the destination the shell should move to when the active one has
  /// just disappeared, and null when nothing needs to move. Hoofdstuk 19: "als
  /// de gebruiker Live TV open heeft, gaat Pleya naar Home met een korte
  /// melding" — deciding that here rather than in the widget keeps the rule in
  /// one testable place.
  TvDestinationId? updateConditions(TvNavConditions conditions) {
    final next = buildTvDestinations(conditions);
    if (listEquals(next, _destinations)) return null;
    _destinations = next;

    // A destination that is gone must not keep the focus ring either, or the
    // bar would have a focused item nobody can see.
    if (!next.contains(_focused)) _focused = next.contains(_active) ? _active : tvRootDestination;

    final displaced = next.contains(_active) ? null : tvRootDestination;
    if (displaced != null) _active = displaced;
    notifyListeners();
    return displaced;
  }

  /// Make [id] the active destination. No-op when it already is, so re-selecting
  /// the current destination cannot trigger a rebuild or a refetch (hoofdstuk
  /// 7.2: "Select op de reeds actieve bestemming … start geen automatische
  /// netwerkrefresh").
  bool activate(TvDestinationId id) {
    if (!_destinations.contains(id)) return false;
    _focused = id;
    if (_active == id) return false;
    _active = id;
    notifyListeners();
    return true;
  }

  /// Move the focus ring without changing the page.
  ///
  /// **Nothing on the TV shell calls this any more.** Since 2 September 2026
  /// focus on a bar item *is* the navigation, so the bar's focus callback goes
  /// to `MainScreen._focusTvDestination`, which activates. Kept because
  /// "move the ring only" is still a coherent coordinator operation and the
  /// unit tests pin its semantics — but wiring the bar back to it would
  /// reinstate the select-to-switch behaviour that is now a regression.
  void focusDestination(TvDestinationId id) {
    if (!_destinations.contains(id) || _focused == id) return;
    _focused = id;
    notifyListeners();
  }

  /// The neighbour [delta] steps from the focused item, or null at the ends.
  ///
  /// Null rather than a wrap-around: hoofdstuk 7.2 says "Geen wrap van laatste
  /// naar eerste item". On a remote a wrap means holding Right walks the bar
  /// forever and the user loses track of where they are.
  TvDestinationId? neighbourOf(TvDestinationId id, int delta) {
    final index = _destinations.indexOf(id);
    if (index < 0) return null;
    final target = index + delta;
    if (target < 0 || target >= _destinations.length) return null;
    return _destinations[target];
  }

  /// Remember where the viewer stood inside [id]'s content.
  ///
  /// Written by the surfaces inside a destination that do **not** survive a
  /// destination switch — today exactly one: the complete catalog, which is a
  /// [TvNestedRoute] and is therefore built and torn down on every switch away
  /// and back. A destination's own root screen lives in `MainScreen`'s
  /// `IndexedStack` and keeps its own state, so it has nothing to store here
  /// and deliberately does not; two writers per destination would be two
  /// answers to the same question.
  void rememberContentFocus(TvDestinationId id, TvDestinationFocusMemory memory) {
    if (memory.isEmpty) {
      _contentFocusMemory.remove(id);
      return;
    }
    _contentFocusMemory[id] = memory;
  }

  /// Where [id]'s content stood last. [TvDestinationFocusMemory.empty] when it
  /// was never entered — an absent place rather than a null, so a caller that
  /// restores one field at a time does not have to null-check each of them.
  TvDestinationFocusMemory contentFocusFor(TvDestinationId id) =>
      _contentFocusMemory[id] ?? TvDestinationFocusMemory.empty;

  // ---------------------------------------------------------------------------
  // Nested routes inside a destination (hoofdstuk 7.5 step 2)
  // ---------------------------------------------------------------------------

  /// [id]'s nested stack, deepest last. Empty means the destination's own root
  /// screen is on show.
  List<TvNestedRoute> nestedRoutesFor(TvDestinationId id) => List.unmodifiable(_nested[id] ?? const []);

  /// What the active destination is currently showing above its root, or null.
  TvNestedRoute? get activeNestedRoute {
    final stack = _nested[_active];
    return (stack == null || stack.isEmpty) ? null : stack.last;
  }

  /// Whether Back should pop inside the destination before reaching the root
  /// contract.
  bool get activeCanPop => activeNestedRoute != null;

  /// Opens [route] inside [id].
  ///
  /// Re-pushing the route already on top is a no-op: a second Select on a tile
  /// that is already open must not stack two copies of the same screen, which
  /// would then need two Backs to leave.
  void pushNested(TvDestinationId id, TvNestedRoute route) {
    final stack = _nested.putIfAbsent(id, () => []);
    if (stack.isNotEmpty && stack.last.id == route.id) return;
    stack.add(route);
    notifyListeners();
  }

  /// Pops the active destination's top nested route and returns it, so the
  /// caller can restore the focus it came from. Null when there was nothing to
  /// pop — the signal to fall through to the next step of the back chain
  /// rather than swallow the press.
  TvNestedRoute? popNested() {
    final stack = _nested[_active];
    if (stack == null || stack.isEmpty) return null;
    final popped = stack.removeLast();
    notifyListeners();
    return popped;
  }

  /// Drops every nested stack. Used on a profile switch for the same reason
  /// [clearFocusMemory] is: a route built for one profile has no business
  /// staying on screen for the next.
  void clearNestedRoutes() {
    if (_nested.isEmpty) return;
    _nested.clear();
    notifyListeners();
  }

  /// Drop every remembered position.
  ///
  /// Hoofdstuk 7.6: "profielwissel → geheugen volledig wissen". A remembered
  /// group id from another profile could point at a title this profile is not
  /// allowed to see, so this is a privacy boundary and not only tidiness.
  void clearFocusMemory() => _contentFocusMemory.clear();

  /// Sync the bar to a tab that was selected from outside it — a companion
  /// remote, a deep link, an offline-mode switch. Unknown tabs light up Mijn
  /// Pleya (see [tvDestinationForTab]) rather than leaving the bar blank.
  void syncToTab(NavigationTabId tab) {
    final id = tvDestinationForTab(tab);
    if (id == null || !_destinations.contains(id)) return;
    if (_active == id) return;
    _active = id;
    _focused = id;
    notifyListeners();
  }
}

/// Hoofdstuk 7.6's `TvDestinationFocusMemory`: where a destination's content
/// was left, so returning to it returns to the same place rather than to the
/// top of the page.
///
/// **Stable ids, never positions.** [groupId] is the merge engine's own group
/// id, which hoofdstuk 12 guarantees survives paging and a late server joining;
/// a row or card index would name a different title one round later. The
/// chapter's record also lists `rowId`, which has no writer here: the one
/// surface that needs this memory is the complete catalog, whose grid is a
/// single flat run of groups, and the rails that *do* have rows
/// (`TvDiscoveryRail` on the landings) keep their own per-hub tile memory in a
/// screen that is never torn down. A field nothing writes is a field the next
/// reader has to disprove, so it is not declared until something needs it.
@immutable
class TvDestinationFocusMemory {
  const TvDestinationFocusMemory({this.focusedElementId, this.groupId, this.scrollOffset});

  /// Nothing remembered — a destination the viewer has not been inside yet.
  static const TvDestinationFocusMemory empty = TvDestinationFocusMemory();

  /// The control the remote was last on outside the content itself, by the
  /// screen's own key: the catalog's last used header action, so UP out of the
  /// grid still returns to Filters rather than resetting to Sources.
  final String? focusedElementId;

  /// The card the remote was on, by `UnifiedMediaGroup.groupId`.
  final String? groupId;

  /// The content scroll offset in logical pixels. Restored clamped to the live
  /// extent: the catalog can come back shorter than it was left (a filter
  /// applied elsewhere, a server gone), and an offset past the end would land
  /// the viewer on empty space.
  final double? scrollOffset;

  bool get isEmpty => focusedElementId == null && groupId == null && scrollOffset == null;

  TvDestinationFocusMemory copyWith({String? focusedElementId, String? groupId, double? scrollOffset}) =>
      TvDestinationFocusMemory(
        focusedElementId: focusedElementId ?? this.focusedElementId,
        groupId: groupId ?? this.groupId,
        scrollOffset: scrollOffset ?? this.scrollOffset,
      );

  @override
  bool operator ==(Object other) =>
      other is TvDestinationFocusMemory &&
      other.focusedElementId == focusedElementId &&
      other.groupId == groupId &&
      other.scrollOffset == scrollOffset;

  @override
  int get hashCode => Object.hash(focusedElementId, groupId, scrollOffset);

  @override
  String toString() => 'TvDestinationFocusMemory(element: $focusedElementId, group: $groupId, offset: $scrollOffset)';
}

/// A screen shown inside a destination, above its root, with the top navigation
/// still on screen.
///
/// **Why this is not a Flutter `Navigator`.** `Navigator.push` finds the
/// *nearest* enclosing navigator, and half of what a TV surface pushes is media
/// detail: a card in Bibliotheken, Kijklijst or a discovery rail calls
/// `navigateToMediaItem`. A navigator inside the shell's content area would
/// capture those too, rendering a detail screen in the box under the bar
/// instead of full-bleed over the whole shell the way it does today — and it
/// would make hoofdstuk 7.5 ambiguous, because step 2 (pop a nested route) and
/// step 3 (pop a detail route) would be the same pop on the same stack.
///
/// So nesting is explicit and opt-in: a caller that wants to stay inside the
/// shell pushes one of these, and everything else keeps going to the profile
/// navigator `ProfileSessionScreen` owns, unchanged. Hoofdstuk 33's shared
/// shell is binding on all eight references, which is why "Alle films" belongs
/// here and a detail page does not.
class TvNestedRoute {
  TvNestedRoute({required this.id, required this.builder, this.restoreFocusKey, this.screenKey});

  /// Stable identity, used to recognise a re-push of the same screen.
  final String id;

  final WidgetBuilder builder;

  /// The focus key to return to when this route pops (hoofdstuk 7.6).
  final String? restoreFocusKey;

  /// Reaches the pushed screen's `State`, so the shell can ask it where its
  /// focus belongs the way it asks a destination — a route that opens with
  /// nothing focused is a route a remote cannot use. Lives on the route rather
  /// than being made per push, so it survives for as long as the route is on
  /// the stack.
  ///
  /// Optional, and no longer the mechanism focus entry depends on: it is the
  /// *preferred* answer where a screen has one, and [surfaceKey] is the answer
  /// for the six sections that have no `FocusableTab` to ask — three of which
  /// are `StatelessWidget`s, so no key could ever resolve to a `State` for
  /// them. See [TvNestedSurface].
  final GlobalKey? screenKey;

  /// Reaches the [TvNestedSurface] the shell wraps every nested route in.
  ///
  /// Created here rather than in the builder, for the reason the route's own
  /// existence is: `pushNested` discards a re-push of the same id, so the
  /// route object on the stack is stable while a freshly built one is not. A
  /// key made inside `builder` would be new on every rebuild and would resolve
  /// to a state nobody else can reach.
  final GlobalKey<TvNestedSurfaceState> surfaceKey = GlobalKey<TvNestedSurfaceState>();
}

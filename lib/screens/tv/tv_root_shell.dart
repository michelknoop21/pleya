/// The TV root (fase 7, hoofdstuk 6.2 of docs/tvos-unified-experience.md).
///
/// One authority, and only one. `MainScreen` builds this instead of the
/// `SideNavigationRail` branch when the app is running on a TV; desktop and
/// mobile take the branches they always took (hoofdstuk 6.1). Nothing below
/// this widget builds root navigation of its own, and there is no arrangement
/// in which a rail and a bar are on screen together.
///
/// ```
/// TvRootShell
/// ├─ TvTopNavigation      (profile · Search · Home · Series · Films · [Live TV] · Mijn Pleya)
/// └─ active destination   (the existing screens list, unchanged)
/// ```
///
/// **Why this is a presentation change and not a new navigator.** The route
/// catalogue, the screens list, `_currentTab` and `_selectTab` all stay in
/// `MainScreen`, and a `TvDestinationId` resolves to the `NavigationTabId` that
/// was always there. `ProfileSessionScreen` still owns the one nested
/// `Navigator` every content route is pushed on. So a deep link, the companion
/// remote and an offline-mode switch keep working through the paths they
/// already used, and this file only decides what the root *looks* like and
/// where the focus goes.
///
/// **Focus ownership.** [SidebarFocusCoordinator] is reused verbatim as the
/// nav-versus-content authority. Its name says sidebar because that is what it
/// was written for, but what it actually owns is "which of the two halves of
/// the shell holds the focus, derived from the scope rather than mirrored" —
/// which is exactly what a top bar needs too. Renaming it would have touched
/// every desktop call site to say the same thing, so the contract is documented
/// here instead: on TV, `focusSidebar` means *focus the top navigation*. That
/// is also why every content screen's existing `onNavigateLeft: _focusSidebar`
/// keeps working — at the left edge of a TV page it now escapes upward to the
/// bar rather than sideways to a rail, which is a way out rather than a dead
/// end. The contract's primary direction, UP out of the top content row, is
/// wired explicitly by the screens that have a header.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/multi_server_provider.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../navigation/main_screen_scope.dart';
import '../../navigation/tv/tv_destination.dart';
import '../../navigation/tv/tv_navigation_coordinator.dart';
import '../../profiles/profile.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/tv/tv_top_navigation.dart';
import '../../widgets/tv/tv_unified_layout.dart';

class TvRootShell extends StatelessWidget {
  const TvRootShell({
    super.key,
    required this.coordinator,
    required this.navNodes,
    required this.navFocusScope,
    required this.contentFocusScope,
    required this.isNavFocused,
    required this.profile,
    required this.onSelectDestination,
    required this.onFocusContent,
    required this.onFocusNav,
    required this.onOpenProfiles,
    required this.onOverlaySheetOpenChanged,
    required this.onKeyEvent,
    required this.selectLibrary,
    required this.openSettings,
    required this.child,
  });

  final TvNavigationCoordinator coordinator;

  /// Owned by `MainScreen`, not by the bar: a rebuild of the bar must not
  /// dispose the node that currently holds the remote's focus.
  final FocusMemoryTracker navNodes;

  final FocusScopeNode navFocusScope;
  final FocusScopeNode contentFocusScope;
  final bool isNavFocused;
  final Profile? profile;

  final ValueChanged<TvDestinationId> onSelectDestination;

  /// Down out of the bar.
  ///
  /// `restorePreviousFocus` is true for a move *within* the current destination
  /// and false for a move to another one, because the content scope is shared
  /// across destinations: restoring its remembered child after a switch would
  /// land on a row of the destination the viewer just left, still mounted and
  /// entirely invisible.
  ///
  /// Each destination therefore restores its own position in
  /// `focusActiveTabIfReady`, which is what hoofdstuk 7.1 and 7.4 ask for on
  /// the way in from the bar: Mijn Pleya returns to the tile you were on, the
  /// landing to its page header, the catalog to the header action you last
  /// used. The card itself is one step further down and is restored by the
  /// screen: a landing's rails keep their own tile, and the catalog is handed
  /// its card and its scroll offset back through
  /// [TvNavigationCoordinator.contentFocusFor] — it is the one surface here
  /// that does not survive a destination switch (register I22/I23).
  final void Function({bool restorePreviousFocus}) onFocusContent;

  final VoidCallback onFocusNav;
  final VoidCallback onOpenProfiles;
  final ValueChanged<bool> onOverlaySheetOpenChanged;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  final void Function(String libraryGlobalKey)? selectLibrary;
  final VoidCallback? openSettings;

  /// The active destination's screen — the same `IndexedStack` the other two
  /// shells host, so switching destinations never rebuilds a provider graph
  /// (hoofdstuk 24).
  ///
  /// A *nested* route is the exception and cannot be otherwise: only the active
  /// destination's top route is built, so switching away tears it down. That is
  /// why the catalog's own place travels through [coordinator] rather than
  /// living in its `State`, and why `UnifiedCatalogProvider` — which holds the
  /// loaded pages — is registered above this shell in the profile subtree and
  /// is not restarted by a rebuild of the screen that reads it.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);

    return OverlaySheetHost(
      onOpenChanged: onOverlaySheetOpenChanged,
      // Same contract as the rail shell: the key path below owns the whole
      // back chain (overlay → nested route → content → topnav → system), so a
      // bare route pop must not be able to short-circuit it. The host still
      // closes an open sheet on system back, which is step 1 of hoofdstuk 7.5.
      canPop: false,
      child: Focus(
        onKeyEvent: (node, event) => onKeyEvent(event),
        child: DecoratedBox(
          // The shell owns the page background, lift included.
          //
          // A very slight rise towards the top of the frame gives the page a
          // horizon, so content stands in a room rather than floating on a
          // uniform slab. `TvUnifiedCatalogScreen` painted that itself while it
          // owned the whole viewport; under a top bar its box starts below the
          // band, so the gradient began there and left a hard full-width step
          // at the seam — one row from #141414 to #181818. Small in absolute
          // terms, but it sits exactly where an OLED panel separates best, and
          // a perfectly straight full-width edge is the shape the eye catches
          // first. It also read backwards: the bar looked like a darker chrome
          // strip laid over the page, where the north star has it sitting *on*
          // the page background with no boundary at all.
          //
          // So the lift lives here, where the page now actually starts. The
          // catalog keeps its own copy for a standalone mount — see
          // [TvShellSurface].
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(tk.text.withValues(alpha: TvCatalogLayout.pageLift), tk.bg),
                tk.bg,
              ],
              stops: const [0, 0.55],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return MainScreenFocusScope(
                focusSidebar: onFocusNav,
                focusContent: onFocusContent,
                isSidebarFocused: isNavFocused,
                // A top bar takes height, not width. Every horizontal value the
                // scope carries is therefore the full viewport: content on TV
                // starts at the left edge and is as wide as the screen, and the
                // bleed builders that counter-animate a sliding rail have
                // nothing to counter here. Passing the real numbers rather than
                // leaving them null is what keeps `foregroundWidthOf` and
                // `fullBleedWidthOf` agreeing on this shell.
                sideNavigationWidth: 0,
                reservedSideNavigationWidth: 0,
                foregroundLeft: 0,
                foregroundWidth: constraints.maxWidth,
                viewportWidth: constraints.maxWidth,
                selectLibrary: selectLibrary,
                openSettings: openSettings,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FocusScope(
                      node: navFocusScope,
                      child: ListenableBuilder(
                        listenable: coordinator,
                        builder: (context, _) => TvTopNavigation(
                          destinations: coordinator.destinations,
                          active: coordinator.active,
                          nodes: navNodes,
                          profile: profile,
                          onSelect: onSelectDestination,
                          onFocusDestination: coordinator.focusDestination,
                          onNavigateDown: () => onFocusContent(restorePreviousFocus: true),
                          onOpenProfiles: onOpenProfiles,
                          // Hoofdstuk 18.4. Read here rather than passed down
                          // from `MainScreen` so the bar is the only thing that
                          // rebuilds when a token expires, and read through a
                          // selector on the *auth* flag specifically: a server
                          // merely going offline is not something the viewer
                          // can act on, and marking it would train them to
                          // ignore the dot that means they can.
                          // Nullable: this shell is also mounted in tests and
                          // in early startup frames that have no registry yet,
                          // and "no provider" is not "attention required".
                          needsAttention: context.select<MultiServerProvider?, bool>(
                            (p) => p?.hasAuthErrorServers ?? false,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: FocusScope(
                        node: contentFocusScope,
                        // No autofocus: focus is moved deliberately, so a
                        // rebuild cannot pull the remote back out of the bar.
                        child: TvShellSurface(
                          child: ListenableBuilder(
                            listenable: coordinator,
                            builder: (context, screens) {
                              final nested = coordinator.activeNestedRoute;
                              // The destination's own screens stay mounted
                              // underneath: the `IndexedStack` keeps its scroll
                              // position, its providers and its focus nodes, so
                              // popping "Alle films" returns to a landing that
                              // never went away (hoofdstuk 24 — a nested route is
                              // not allowed to cost a reload). The route on top
                              // is built for the active destination only, so a
                              // destination switch does tear it down — see
                              // [child] on where its place is kept instead.
                              return Stack(
                                children: [
                                  // Offstage rather than removed, for the reason
                                  // above; `TickerMode` stops its animations from
                                  // running behind the route on top of it.
                                  Offstage(
                                    offstage: nested != null,
                                    child: TickerMode(enabled: nested == null, child: screens!),
                                  ),
                                  if (nested != null) Builder(builder: nested.builder),
                                ],
                              );
                            },
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Marks the subtree that the fase-7 TV shell already frames.
///
/// Two things a full-page TV screen normally provides for itself the shell now
/// provides instead: the page background, including hoofdstuk 8's slight lift
/// towards the top of the frame, and the top safe inset. A screen that painted
/// them again under the bar painted them twice — the lift left a hard
/// full-width step at the seam, and the inset stacked into a band of dead space
/// that pushed the first grid row about thirteen per cent of the canvas below
/// where the north star puts it.
///
/// A marker rather than a constructor flag, because the screens that read it are
/// reached both through the screens list and through nested routes, and
/// threading a boolean down both paths would be one more thing to forget. Its
/// absence is the standalone case — a golden, a focus test — where the screen
/// still owns its own frame and nothing about it changes.
class TvShellSurface extends InheritedWidget {
  const TvShellSurface({super.key, required super.child});

  static bool isPresent(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TvShellSurface>() != null;

  @override
  bool updateShouldNotify(TvShellSurface oldWidget) => false;
}

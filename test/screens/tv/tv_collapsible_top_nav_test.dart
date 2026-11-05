/// DEC-115: film and series detail open under a collapsible top navigation.
///
/// Driven through the production [TvRootShell] and [TvTopNavigation], with a
/// real [SidebarFocusCoordinator] as the nav-versus-content authority, wired the
/// way `MainScreen` wires it. The route on top is a probe with two focus stops
/// rather than `MediaDetailScreen`: the shell contract is what is under test
/// here, and the detail's own use of the inset the shell publishes is covered
/// in `media_detail_screen_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/sidebar_focus_coordinator.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

const _window = Size(1920, 1080);

/// What the route on top could observe about the space it was given.
class _Reading {
  _Reading(this.size, this.topPadding);

  final Size size;
  final double topPadding;
}

/// `MainScreen`'s TV wiring, reduced to the parts the shell talks to.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.coordinator});

  final TvNavigationCoordinator coordinator;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _focus = SidebarFocusCoordinator();
  final navNodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
  final _contentFocus = TvContentFocusAuthority();

  TvNavigationCoordinator get _nav => widget.coordinator;

  bool get isNavFocused => _focus.isSidebarFocused;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    _focus.dispose();
    navNodes.dispose();
    super.dispose();
  }

  /// `MainScreen._pushTvContentRoute`.
  void open(TvNestedRoute route) {
    _nav.pushNested(_nav.active, route);
    _focusContent(restorePreviousFocus: false);
  }

  /// `MainScreen._focusSidebar` on TV.
  void _focusNav() {
    _nav.activeNestedRoute?.surfaceKey.currentState?.cancelPendingEntry();
    _focus.focusSidebar(focusActiveItem: _focusActiveNavItem);
  }

  void _focusActiveNavItem() {
    final node = navNodes.get(_nav.focusedDestination.focusKey);
    if (node.canRequestFocus) node.requestFocus();
  }

  /// `MainScreen._focusContent` and `_focusTvNestedRoute`.
  void _focusContent({bool restorePreviousFocus = true}) => _focus.focusContent(
    restorePreviousFocus: restorePreviousFocus,
    focusDefault: () => WidgetsBinding.instance.addPostFrameCallback((_) {
      _nav.activeNestedRoute?.surfaceKey.currentState?.focusEntry();
    }),
  );

  /// Back, through the production [tvBackStep].
  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    switch (tvBackStep(hasNestedRoute: _nav.activeCanPop, isNavigationFocused: isNavFocused)) {
      case TvBackStep.popNested:
        // `MainScreen._popTvNestedRoute`.
        _nav.popNested();
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusContent());
      case TvBackStep.focusTopNavigation:
        _focusNav();
      case TvBackStep.rootContract:
        break;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => TvRootShell(
    coordinator: _nav,
    contentFocus: _contentFocus,
    navNodes: navNodes,
    navFocusScope: _focus.sidebarScope,
    contentFocusScope: _focus.contentScope,
    isNavFocused: isNavFocused,
    profile: null,
    onSelectDestination: (destination) {
      _nav.activate(destination);
      _focusContent(restorePreviousFocus: false);
    },
    onFocusDestination: _nav.activate,
    onFocusContent: _focusContent,
    onFocusNav: _focusNav,
    onOpenProfiles: () {},
    onOverlaySheetOpenChanged: (_) {},
    onKeyEvent: _onKey,
    selectLibrary: null,
    openSettings: null,
    dismissNestedRoute: ([_]) {},
    child: const SizedBox.expand(key: ValueKey('destination root'), child: Text('destination root')),
  );
}

/// Two focus stops, both of which leave upward to the bar the way detail's
/// top zone does (`_focusTopNavigationFromDetail`).
class _RouteProbe extends StatelessWidget {
  const _RouteProbe({required this.top, required this.bottom, required this.onBuild});

  final FocusNode top;
  final FocusNode bottom;
  final void Function(_Reading) onBuild;

  KeyEventResult _upToNav(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    MainScreenFocusScope.of(context, listen: false)?.focusSidebar();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    onBuild(_Reading(MediaQuery.sizeOf(context), MediaQuery.paddingOf(context).top));
    return SizedBox.expand(
      key: const ValueKey('route'),
      child: Column(
        children: [
          Focus(
            focusNode: top,
            onKeyEvent: (_, event) => _upToNav(context, event),
            child: const SizedBox(height: 40, child: Text('top stop')),
          ),
          Focus(
            focusNode: bottom,
            onKeyEvent: (_, event) => _upToNav(context, event),
            child: const SizedBox(height: 40, child: Text('bottom stop')),
          ),
        ],
      ),
    );
  }
}

void main() {
  late TvNavigationCoordinator coordinator;
  late FocusNode top;
  late FocusNode bottom;
  late _Reading reading;
  final hostKey = GlobalKey<_HostState>();

  setUp(() {
    coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    top = FocusNode(debugLabel: 'top stop');
    bottom = FocusNode(debugLabel: 'bottom stop');
  });

  tearDown(() {
    coordinator.dispose();
    top.dispose();
    bottom.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = _window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: _Host(key: hostKey, coordinator: coordinator),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, TvTopNavPresentation topNav) async {
    hostKey.currentState!.open(
      TvNestedRoute(
        id: 'detail',
        topNav: topNav,
        builder: (_) => _RouteProbe(top: top, bottom: bottom, onBuild: (r) => reading = r),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect navRect(WidgetTester tester) => tester.getRect(find.byType(TvTopNavigation));
  Rect routeRect(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('route')));
  FocusNode? primary() => FocusManager.instance.primaryFocus;

  group('a persistent route (the default)', () {
    testWidgets('sits below a visible bar, with no top inset of its own', (tester) async {
      await pump(tester);
      await open(tester, TvTopNavPresentation.persistent);

      expect(navRect(tester).top, 0);
      expect(routeRect(tester).top, greaterThan(0), reason: 'PB-1: the box starts under the bar');
      expect(reading.size.height, lessThan(_window.height));
      expect(reading.topPadding, 0);
    });
  });

  group('a collapsible route', () {
    testWidgets('opens on the whole window with the bar tucked away and the remote in the route', (tester) async {
      await pump(tester);
      await open(tester, TvTopNavPresentation.collapsible);

      expect(routeRect(tester), Offset.zero & _window, reason: 'the route runs up behind the bar');
      expect(reading.size, _window);
      expect(reading.topPadding, TvTopNavLayout.topInset, reason: 'scale 1.0 at 1080: the bar\'s own overscan inset');
      expect(navRect(tester).bottom, lessThanOrEqualTo(0), reason: 'the bar is slid out of view');
      expect(hostKey.currentState!.isNavFocused, isFalse);
      expect(primary(), top, reason: 'the remote lands on the route, never on a hidden bar item');
    });

    testWidgets('leaves the destination root underneath in the box it had', (tester) async {
      await pump(tester);
      final before = tester.getRect(find.byKey(const ValueKey('destination root')));

      await open(tester, TvTopNavPresentation.collapsible);

      expect(tester.getRect(find.byKey(const ValueKey('destination root'), skipOffstage: false)), before);
    });

    testWidgets('UP shows the bar over the route and puts the ring on the active destination', (tester) async {
      await pump(tester);
      await open(tester, TvTopNavPresentation.collapsible);
      final box = routeRect(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(hostKey.currentState!.isNavFocused, isTrue);
      expect(navRect(tester).top, 0, reason: 'the bar is back on screen');
      expect(primary(), hostKey.currentState!.navNodes.get(coordinator.active.focusKey));
      expect(routeRect(tester), box, reason: 'the bar lies over the route; nothing underneath moves');
    });

    testWidgets('DOWN tucks the bar away again and returns the remote to where it was', (tester) async {
      await pump(tester);
      await open(tester, TvTopNavPresentation.collapsible);
      bottom.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(hostKey.currentState!.isNavFocused, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(hostKey.currentState!.isNavFocused, isFalse);
      expect(navRect(tester).bottom, lessThanOrEqualTo(0));
      expect(primary(), bottom, reason: 'the remembered stop, not the route default');
    });

    testWidgets('Back from the route closes it and brings the persistent bar back', (tester) async {
      await pump(tester);
      await open(tester, TvTopNavPresentation.collapsible);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(coordinator.activeCanPop, isFalse);
      expect(find.byKey(const ValueKey('route')), findsNothing);
      expect(navRect(tester).top, 0);
    });

    testWidgets('Back from the opened bar still closes the route first', (tester) async {
      await pump(tester);
      await open(tester, TvTopNavPresentation.collapsible);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(coordinator.activeCanPop, isFalse);
      expect(navRect(tester).top, 0);
    });

    testWidgets('moving the ring to another destination shows that destination under a visible bar', (tester) async {
      await pump(tester);
      final start = coordinator.active;
      await open(tester, TvTopNavPresentation.collapsible);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      final other = coordinator.destinations.firstWhere((d) => d != start);
      hostKey.currentState!.navNodes.get(other.focusKey).requestFocus();
      await tester.pumpAndSettle();

      expect(coordinator.active, other);
      expect(find.byKey(const ValueKey('route')), findsNothing, reason: 'the route belongs to the destination left');
      expect(navRect(tester).top, 0);
      expect(hostKey.currentState!.isNavFocused, isTrue);
    });
  });
}

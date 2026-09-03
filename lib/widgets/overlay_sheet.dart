import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/dpad_navigator.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';
import '../utils/platform_detector.dart';
import 'overlay_sheet_geometry.dart';

/// Entry in the sheet page stack.
class _OverlaySheetEntry {
  final WidgetBuilder builder;
  final Completer<dynamic> completer;
  final FocusNode? initialFocusNode;

  _OverlaySheetEntry({required this.builder, required this.completer, this.initialFocusNode});
}

/// Provides [OverlaySheetController] to descendants via [of] / [maybeOf].
class _OverlaySheetScope extends InheritedWidget {
  final OverlaySheetController controller;

  const _OverlaySheetScope({required this.controller, required super.child});

  @override
  bool updateShouldNotify(_OverlaySheetScope oldWidget) => controller != oldWidget.controller;
}

/// Controller for the overlay-based bottom sheet system.
///
/// Use [of] or [maybeOf] to access from descendants.
class OverlaySheetController {
  final _OverlaySheetHostState _state;

  OverlaySheetController._(this._state);

  static OverlaySheetController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_OverlaySheetScope>();
    assert(scope != null, 'No OverlaySheetHost found in context');
    return scope!.controller;
  }

  static OverlaySheetController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_OverlaySheetScope>()?.controller;
  }

  /// Whether a sheet is currently showing (including while animating closed).
  bool get isOpen => _state._isOpen;

  /// Show a sheet with [builder] content. Returns a Future that completes
  /// when the sheet is closed (with an optional result).
  ///
  /// [alignment] controls where the sheet appears. Leave it out and the host
  /// picks: [Alignment.bottomCenter] off TV, and the centred 10-foot panel on
  /// a television. Naming one is a statement that this surface belongs at that
  /// edge, and it is honoured on every platform including TV (OVR2).
  Future<T?> show<T>({
    required WidgetBuilder builder,
    BoxConstraints? constraints,
    Color? backgroundColor,
    bool barrierDismissible = true,
    FocusNode? initialFocusNode,
    Alignment? alignment,
    bool showDragHandle = false,
    OverlaySheetPresentation presentation = OverlaySheetPresentation.sheet,
  }) {
    return _state._show<T>(
      builder: builder,
      constraints: constraints,
      backgroundColor: backgroundColor,
      barrierDismissible: barrierDismissible,
      initialFocusNode: initialFocusNode,
      alignment: alignment,
      showDragHandle: showDragHandle,
      presentation: presentation,
    );
  }

  /// Push a sub-page within the open sheet. Returns a Future that completes
  /// when the pushed page is popped (with an optional result).
  Future<T?> push<T>({required WidgetBuilder builder, FocusNode? initialFocusNode}) {
    return _state._push<T>(builder: builder, initialFocusNode: initialFocusNode);
  }

  /// Pop the top sub-page, or close the sheet if on the last page.
  void pop([dynamic result]) {
    _state._pop(result);
  }

  /// Force close the sheet, completing all pending completers.
  void close([dynamic result]) {
    _state._close(result);
  }

  /// Re-focus the first focusable descendant within the sheet.
  /// Useful after internal page changes via setState.
  void refocus() {
    _state._refocus();
  }

  /// Show a sheet using the overlay system if available, otherwise fall back
  /// to [showModalBottomSheet]. Returns the result from the sheet.
  static Future<T?> showAdaptive<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    BoxConstraints? constraints,
    Color? backgroundColor,
    bool barrierDismissible = true,
    bool isScrollControlled = false,
    FocusNode? initialFocusNode,
    Alignment? alignment,
    bool showDragHandle = false,
    OverlaySheetPresentation presentation = OverlaySheetPresentation.sheet,
    bool restoreLauncherFocus = false,
  }) {
    if (restoreLauncherFocus) {
      return _withLauncherFocusRestore(
        () => showAdaptive<T>(
          context,
          builder: builder,
          constraints: constraints,
          backgroundColor: backgroundColor,
          barrierDismissible: barrierDismissible,
          isScrollControlled: isScrollControlled,
          initialFocusNode: initialFocusNode,
          alignment: alignment,
          showDragHandle: showDragHandle,
          presentation: presentation,
        ),
      );
    }
    final controller = maybeOf(context);
    if (controller != null) {
      return controller.show<T>(
        builder: builder,
        constraints: constraints,
        backgroundColor: backgroundColor,
        barrierDismissible: barrierDismissible,
        initialFocusNode: initialFocusNode,
        alignment: alignment,
        showDragHandle: showDragHandle,
        presentation: presentation,
      );
    }
    // Apply the same default constraints the overlay system uses so sheets
    // shown without an OverlaySheetHost still have sensible sizing on desktop.
    final effectiveConstraints = resolveOverlaySheetGeometry(
      presentation: presentation,
      viewport: MediaQuery.sizeOf(context),
      alignment: alignment,
      isTV: PlatformDetector.isTV(),
      explicitConstraints: constraints,
    ).constraints;
    // The route fallback has no _autoFocus equivalent — honor the caller's
    // initialFocusNode here too, or the sheet opens with nothing focused and
    // the D-pad is dead on hostless screens.
    _scheduleFallbackFocus(initialFocusNode);
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      constraints: effectiveConstraints,
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
      barrierColor: Colors.black54,
      isScrollControlled: isScrollControlled,
    );
  }

  /// Runs [show] with the launcher's focus captured up front and handed back
  /// once the surface is gone.
  ///
  /// An overlay sheet is not a route, so nothing pops focus back for it. Every
  /// remote-driven launcher — a header action opening a filter panel, a card
  /// opening the source picker — needs the same three-line dance, and the
  /// version that lived inside `showUnifiedSourcePicker` was about to be copied
  /// a second and third time. It lives here instead, opt-in so no existing
  /// pointer-driven caller changes behaviour (hoofdstuk 14.4's "annuleren
  /// herstelt exacte kaart of CTA", generalised in fase 5A).
  ///
  /// Three properties it has to hold, and why each is where it is:
  ///
  /// * **Nested drill-down never overwrites the launcher.** The capture happens
  ///   once, at `show` time; `push` (a panel's own sub-page) does not capture,
  ///   so closing the whole stack still restores the node that opened it.
  /// * **A detached launcher is safe.** A picker that ended in a route
  ///   replacement has no card left to go back to, so the node is re-checked
  ///   for `context != null` at restore time rather than trusted.
  /// * **It runs after the close animation.** Restoring inside the frame that
  ///   is still tearing the surface down would hand focus to a node the sheet's
  ///   own scope is about to take back.
  static Future<T?> _withLauncherFocusRestore<T>(Future<T?> Function() show) {
    final opener = FocusManager.instance.primaryFocus;
    return show().whenComplete(() {
      if (opener == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (opener.context != null && opener.canRequestFocus) opener.requestFocus();
      });
    });
  }

  static void _scheduleFallbackFocus(FocusNode? node) {
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.canRequestFocus) node.requestFocus();
    });
  }

  /// Push a sub-page using the overlay system if available, otherwise fall
  /// back to [showModalBottomSheet]. Returns the result from the page.
  static Future<T?> pushAdaptive<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    FocusNode? initialFocusNode,
  }) {
    final controller = maybeOf(context);
    if (controller != null) {
      return controller.push<T>(builder: builder, initialFocusNode: initialFocusNode);
    }
    _scheduleFallbackFocus(initialFocusNode);
    return showModalBottomSheet<T>(context: context, builder: builder);
  }

  /// Close the sheet entirely. Uses overlay controller if available,
  /// otherwise pops the route.
  static void closeAdaptive(BuildContext context, [dynamic result]) {
    final controller = maybeOf(context);
    if (controller != null) {
      controller.close(result);
    } else {
      Navigator.pop(context, result);
    }
  }

  /// Pop one level (sub-page or close if last page). Uses overlay controller
  /// if available, otherwise pops the route.
  static void popAdaptive(BuildContext context, [dynamic result]) {
    final controller = maybeOf(context);
    if (controller != null) {
      controller.pop(result);
    } else {
      Navigator.pop(context, result);
    }
  }
}

/// Host widget for the overlay-based bottom sheet system.
///
/// Sheets are rendered as overlays within this widget's Stack instead of as
/// modal routes, eliminating the route-based back-button race condition on
/// Android TV and providing centralized focus management for keyboard/dpad
/// navigation on all platforms.
///
/// ## Back handling
///
/// The host already owns the dpad/key back path (its sheet [FocusScope] closes
/// the sheet on BACK when focus is inside it). For the system/route back path
/// (Android gesture, iOS swipe, predictive back), opt in via [canPop]: the host
/// then renders its own [PopScope] that closes an open sheet instead of popping
/// the screen, so callers don't have to hand-roll it. When [canPop] is null
/// (the default) the host adds no [PopScope] and behaves exactly as before.
class OverlaySheetHost extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onOpenChanged;

  /// Whether the enclosing route may pop when no sheet is open (the screen's own
  /// business rule, mirroring [PopScope.canPop]).
  ///
  /// When non-null the host installs a [PopScope]:
  /// - a system back with a sheet open closes the sheet (never pops the screen);
  /// - otherwise, if `canPop` is true the route pops natively (preserving the
  ///   iOS interactive swipe-back), and if false [onSystemBack] runs instead.
  ///
  /// When null (default) the host installs no [PopScope] — today's behavior.
  final bool? canPop;

  /// Called for a system/route back when no sheet is open and [canPop] is false.
  /// Not called when a sheet is open (the sheet is closed instead) or when
  /// [canPop] allows a native pop. Implementations that also have a dpad key
  /// handler should start with `if (BackKeyCoordinator.consumeIfHandled()) return;`
  /// so the system path dedups against the key path.
  final VoidCallback? onSystemBack;

  const OverlaySheetHost({super.key, required this.child, this.onOpenChanged, this.canPop, this.onSystemBack});

  @override
  State<OverlaySheetHost> createState() => _OverlaySheetHostState();
}

class _OverlaySheetHostState extends State<OverlaySheetHost> with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final CurvedAnimation _slideCurve;
  late final Animation<double> _barrierAnimation;
  late final OverlaySheetController _controller;

  final List<_OverlaySheetEntry> _pageStack = [];
  final _sheetFocusScopeNode = FocusScopeNode(debugLabel: 'OverlaySheetScope');

  bool _isOpen = false;
  bool _isClosing = false;
  bool _barrierDismissible = true;
  bool _showDragHandle = false;
  BoxConstraints? _constraints;
  Color? _explicitBackgroundColor;

  /// Null when the caller named no alignment. Kept as null rather than
  /// collapsed to a default, because the geometry resolver treats "no opinion"
  /// and "bottomCenter, deliberately" as different questions on a television.
  Alignment? _alignment;
  OverlaySheetPresentation _presentation = OverlaySheetPresentation.sheet;
  Offset? _lastPointerPosition;
  double? _sheetHorizontalAnchor;

  // Drag-to-dismiss state
  double _dragOffset = 0;
  bool _isDragging = false;
  final _sheetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = OverlaySheetController._(this);

    _animationController = AnimationController(duration: const Duration(milliseconds: 250), vsync: this);

    _slideCurve = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _barrierAnimation = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    for (final entry in _pageStack) {
      if (!entry.completer.isCompleted) {
        entry.completer.complete(null);
      }
    }
    _unregisterFallbackKeyHandler();
    _sheetFocusScopeNode.dispose();
    _slideCurve.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<T?> _show<T>({
    required WidgetBuilder builder,
    BoxConstraints? constraints,
    Color? backgroundColor,
    bool barrierDismissible = true,
    FocusNode? initialFocusNode,
    Alignment? alignment,
    bool showDragHandle = false,
    OverlaySheetPresentation presentation = OverlaySheetPresentation.sheet,
  }) {
    // If already open, close first (instant)
    final wasOpen = _isOpen;
    if (_isOpen) {
      for (final entry in _pageStack) {
        if (!entry.completer.isCompleted) {
          entry.completer.complete(null);
        }
      }
      _pageStack.clear();
      _isClosing = false;
    }

    final completer = Completer<T?>();
    final entry = _OverlaySheetEntry(builder: builder, completer: completer, initialFocusNode: initialFocusNode);
    final horizontalAnchor = _resolveSheetHorizontalAnchor(alignment, presentation, constraints);

    setState(() {
      _pageStack.add(entry);
      _isOpen = true;
      _isClosing = false;
      _barrierDismissible = barrierDismissible;
      _showDragHandle = showDragHandle;
      _constraints = constraints;
      _explicitBackgroundColor = backgroundColor;
      _alignment = alignment;
      _presentation = presentation;
      _sheetHorizontalAnchor = horizontalAnchor;
      _dragOffset = 0;
      _isDragging = false;
    });
    if (!wasOpen) widget.onOpenChanged?.call(true);

    BackKeyUpSuppressor.clearSuppression();
    _registerFallbackKeyHandler();
    _animationController.forward(from: 0);
    _autoFocus();

    return completer.future;
  }

  Future<T?> _push<T>({required WidgetBuilder builder, FocusNode? initialFocusNode}) {
    if (!_isOpen || _isClosing) {
      return Future.value(null);
    }

    final completer = Completer<T?>();
    final entry = _OverlaySheetEntry(builder: builder, completer: completer, initialFocusNode: initialFocusNode);

    setState(() {
      _pageStack.add(entry);
    });

    _autoFocus();
    return completer.future;
  }

  void _pop([dynamic result]) {
    if (!_isOpen || _isClosing || _pageStack.isEmpty) return;

    if (_pageStack.length == 1) {
      _close(result);
      return;
    }

    final removed = _pageStack.removeLast();
    if (!removed.completer.isCompleted) {
      removed.completer.complete(result);
    }

    setState(() {});
    _autoFocus();
  }

  void _close([dynamic result]) {
    if (!_isOpen || _isClosing) return;
    _isClosing = true;

    _animationController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        for (final entry in _pageStack) {
          if (!entry.completer.isCompleted) {
            entry.completer.complete(result);
          }
        }
        _pageStack.clear();
        _isOpen = false;
        _isClosing = false;
        _dragOffset = 0;
        _isDragging = false;
        _sheetHorizontalAnchor = null;
      });
      _unregisterFallbackKeyHandler();
      widget.onOpenChanged?.call(false);
    });
  }

  void _rememberPointerPosition(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _lastPointerPosition = event.localPosition;
  }

  /// The x the sheet should centre on, or null to fall back to [alignment].
  ///
  /// A panel never anchors to the pointer: that is the whole point of the
  /// presentation, and it is what put Filters/Sort in the bottom-right corner
  /// of a wide window.
  double? _resolveSheetHorizontalAnchor(
    Alignment? alignment,
    OverlaySheetPresentation presentation,
    BoxConstraints? constraints,
  ) {
    if (!PlatformDetector.isDesktopOS() || PlatformDetector.isTV()) return null;
    if (InputModeTracker.isKeyboardMode(context)) return null;
    final resolved = alignment ?? Alignment.bottomCenter;
    if (resolved.x != 0 || resolved.y <= 0) return null;
    final geometry = resolveOverlaySheetGeometry(
      presentation: presentation,
      viewport: MediaQuery.sizeOf(context),
      alignment: alignment,
      isTV: PlatformDetector.isTV(),
      explicitConstraints: constraints,
    );
    if (!geometry.allowPointerAnchor) return null;
    return _lastPointerPosition?.dx;
  }

  void _autoFocus() {
    // Op TV altijd focussen: er is geen pointer, en de mode-tracker kan bij
    // opstart nog kortstondig op pointer staan.
    if (!InputModeTracker.isKeyboardMode(context) && !PlatformDetector.isTV()) return;

    // First post-frame: the FocusScope is now built and the node is attached.
    // Grab scope focus immediately so key events (especially back) are trapped.
    // Second post-frame: ListView.builder items are laid out and their
    // FocusNodes are registered — focus the first descendant for dpad nav.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isOpen) return;
      _sheetFocusScopeNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isOpen) return;
        // If the current top entry has an initialFocusNode that is attached,
        // focus that instead of the first descendant.
        final topEntry = _pageStack.isNotEmpty ? _pageStack.last : null;
        final initialNode = topEntry?.initialFocusNode;
        if (initialNode != null && initialNode.context != null) {
          initialNode.requestFocus();
        } else {
          _focusFirstDescendant();
        }

        // Clear stale select suppression from the press that opened this sheet,
        // but only if no select key is currently held down. This handles:
        // - Short press: key already released → clear flag (prevents first
        //   select inside the sheet from being eaten).
        // - Long press: key still held → keep flag so KeyRepeat/KeyUp events
        //   from the long press are correctly suppressed.
        if (!HardwareKeyboard.instance.logicalKeysPressed.any((k) => k.isSelectKey)) {
          SelectKeyUpSuppressor.clearSuppression();
        }
      });
    });
  }

  void _refocus() {
    if (!InputModeTracker.isKeyboardMode(context) && !PlatformDetector.isTV()) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isOpen) return;
      _sheetFocusScopeNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isOpen) return;
        final topEntry = _pageStack.isNotEmpty ? _pageStack.last : null;
        final initialNode = topEntry?.initialFocusNode;
        if (initialNode != null && initialNode.context != null) {
          initialNode.requestFocus();
        } else {
          _focusFirstDescendant();
        }
      });
    });
  }

  void _focusFirstDescendant() {
    final descendants = _sheetFocusScopeNode.traversalDescendants.toList();
    if (descendants.isNotEmpty) {
      descendants.first.requestFocus();
    } else {
      _sheetFocusScopeNode.requestFocus();
    }
  }

  void _handleBack() {
    if (_pageStack.length > 1) {
      _pop();
    } else {
      _close();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    // Suppress stale select key-ups
    if (SelectKeyUpSuppressor.consumeIfSuppressed(event)) {
      return KeyEventResult.handled;
    }

    // Suppress stale back key-ups
    if (BackKeyUpSuppressor.consumeIfSuppressed(event)) {
      return KeyEventResult.handled;
    }

    // Back key: pop sub-page or close sheet
    if (event.logicalKey.isBackKey) {
      return handleBackKeyAction(event, _handleBack);
    }

    // Let all other keys pass through. Directional keys need to reach
    // Flutter's DirectionalFocusAction for dpad/arrow navigation, and
    // select/enter keys need to reach ActivateAction for item taps.
    // The FocusScope traps traversal within the sheet; the screen-level
    // Focus catches any leaked nav keys.
    return KeyEventResult.ignored;
  }

  // Vangnet voor als de focus buiten de sheet-scope staat (of nooit binnenkwam):
  // de sheet is geen route, dus zonder dit sluit Menu/escape hem niet en blijft
  // de D-pad het onderliggende scherm besturen. Alleen actief terwijl open.
  bool _fallbackHandlerRegistered = false;

  void _registerFallbackKeyHandler() {
    if (_fallbackHandlerRegistered) return;
    _fallbackHandlerRegistered = true;
    HardwareKeyboard.instance.addHandler(_fallbackKeyHandler);
  }

  void _unregisterFallbackKeyHandler() {
    if (!_fallbackHandlerRegistered) return;
    _fallbackHandlerRegistered = false;
    HardwareKeyboard.instance.removeHandler(_fallbackKeyHandler);
  }

  bool _fallbackKeyHandler(KeyEvent event) {
    if (!_isOpen || _isClosing || !mounted) return false;
    // Focus binnen de sheet-scope → de scope's eigen onKeyEvent
    // (_handleKeyEvent) handelt het event al af.
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && (primary == _sheetFocusScopeNode || primary.ancestors.contains(_sheetFocusScopeNode))) {
      return false;
    }
    // Route bovenop de host (dialog boven de sheet): die handelt zijn eigen
    // back/keys af.
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (BackKeyUpSuppressor.consumeIfSuppressed(event)) return true;
    if (event.logicalKey.isBackKey) {
      return handleBackKeyAction(event, _handleBack) == KeyEventResult.handled;
    }
    // Focus-trap: nav/select-press terwijl de focus ontsnapt is → focus terug
    // in de sheet, en deze ene press inslikken zodat het onderliggende scherm
    // niet meebeweegt.
    if (event is KeyDownEvent && event.logicalKey.isNavigationKey) {
      _refocus();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _rememberPointerPosition,
      onPointerHover: _rememberPointerPosition,
      child: Stack(
        children: [
          widget.child,
          // Barrier + sheet only when open
          if (_isOpen) ...[
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _barrierAnimation,
                builder: (context, child) {
                  return GestureDetector(
                    onTap: _barrierDismissible ? () => _close() : null,
                    child: ColoredBox(color: Colors.black.withValues(alpha: _barrierAnimation.value)),
                  );
                },
              ),
            ),
            _buildSheet(context),
          ],
        ],
      ),
    );

    // When a screen opts in via [canPop], the host owns the system/route back
    // path so callers don't hand-roll it: a back with a sheet open closes the
    // sheet (sub-page aware, matching the dpad path) instead of popping the
    // screen; otherwise the route pops natively (canPop true) or [onSystemBack]
    // runs (canPop false). `!_isClosing` lets a press during the ~250ms close
    // animation fall through instead of being swallowed.
    final canPop = widget.canPop;
    if (canPop != null) {
      content = PopScope(
        canPop: canPop && !_isOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_isOpen && !_isClosing) {
            _handleBack();
            return;
          }
          widget.onSystemBack?.call();
        },
        child: content,
      );
    }

    return _OverlaySheetScope(controller: _controller, child: content);
  }

  double _getSheetHeight() {
    final renderBox = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size.height ?? 300;
  }

  void _checkDismiss(double velocity) {
    final sheetHeight = _getSheetHeight();
    if (_dragOffset > sheetHeight * 0.25 || velocity > 500) {
      _close();
    } else {
      setState(() {
        _dragOffset = 0;
      });
    }
  }

  Widget _buildSheet(BuildContext context) {
    // Resolved every build, not once at show time: a window resize has to move
    // the panel with it, and the geometry is a pure function of the viewport.
    final geometry = resolveOverlaySheetGeometry(
      presentation: _presentation,
      viewport: MediaQuery.sizeOf(context),
      alignment: _alignment,
      isTV: PlatformDetector.isTV(),
      explicitConstraints: _constraints,
    );
    final isTop = geometry.alignment.y < 0;
    final showHandle = _showDragHandle && geometry.allowDragHandle;

    final effectiveConstraints = geometry.constraints;
    final borderRadius = geometry.borderRadius;

    final colorScheme = Theme.of(context).colorScheme;

    Widget content = _pageStack.isNotEmpty ? Builder(builder: _pageStack.last.builder) : const SizedBox.shrink();
    // Keep sheet scrollables from attaching to the route's primary controller.
    content = PrimaryScrollController.none(child: content);

    // Wrap content in NotificationListener for scroll-aware drag-to-dismiss
    if (showHandle) {
      content = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is OverscrollNotification) {
            // Android (ClampingScrollPhysics): overscroll fires reliably
            if (notification.overscroll < 0) {
              setState(() {
                _dragOffset += -notification.overscroll;
              });
              return true;
            }
          } else if (notification is ScrollUpdateNotification) {
            // iOS (BouncingScrollPhysics): pixels go negative when bouncing past top
            if (notification.metrics.pixels < 0) {
              setState(() {
                _dragOffset = -notification.metrics.pixels;
              });
              return true;
            }
            // If user scrolled back down from overscroll, reset drag offset
            if (_dragOffset > 0 && notification.metrics.pixels >= 0) {
              setState(() {
                _dragOffset = 0;
              });
            }
          } else if (notification is ScrollEndNotification) {
            if (_dragOffset > 0) {
              _checkDismiss(0);
              return true;
            }
          }
          return false;
        },
        child: content,
      );
    }

    // Build the sheet content column (handle + content)
    Widget sheetContent;
    if (showHandle) {
      sheetContent = Column(
        mainAxisSize: .min,
        children: [
          // M3 drag handle: 32x4, rounded, with 12dp top / 4dp bottom margin
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          Flexible(child: content),
        ],
      );
    } else {
      sheetContent = content;
    }

    Widget sheet = FocusScope(
      node: _sheetFocusScopeNode,
      onKeyEvent: _handleKeyEvent,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKeyEvent,
        child: CustomSingleChildLayout(
          delegate: _OverlaySheetLayoutDelegate(
            alignment: geometry.alignment,
            horizontalAnchor: geometry.allowPointerAnchor ? _sheetHorizontalAnchor : null,
            edgePadding: geometry.edgePadding,
            verticalEdgePadding: geometry.verticalEdgePadding,
          ),
          child: AnimatedBuilder(
            animation: _slideCurve,
            builder: (context, child) {
              // Pixel transform rather than FractionalTranslation so
              // mouse-tracker hit testing never depends on the sheet child's
              // just-invalidated layout.
              final travel = geometry.enterOffset * (1 - _slideCurve.value);
              final moved = Transform.translate(offset: travel, child: child);
              return geometry.fadeIn ? FadeTransition(opacity: _slideCurve, child: moved) : moved;
            },
            child: Transform.translate(
              offset: Offset(0, _dragOffset.clamp(0, double.infinity)),
              child: SafeArea(
                left: true,
                right: true,
                top: false,
                bottom: false,
                // The shadow is drawn *outside* the Material, because the
                // Material clips to `borderRadius` and would eat it. Only the
                // centred 10-foot panel asks for one (`geometry.shadows`);
                // every other presentation gets a const-empty list and the
                // wrapper collapses to the Material it always was.
                child: _CastShadow(
                  shadows: geometry.shadows,
                  borderRadius: borderRadius,
                  child: Material(
                    key: _sheetKey,
                    color: _explicitBackgroundColor ?? colorScheme.surface,
                    borderRadius: borderRadius,
                    clipBehavior: Clip.antiAlias,
                    // A floating panel touches no edge, so it needs no notch or
                    // home-indicator padding; an edge-hugging sheet does.
                    child: SafeArea(
                      top: !geometry.isCentered && isTop,
                      bottom: !geometry.isCentered && !isTop,
                      left: false,
                      right: false,
                      child: ConstrainedBox(constraints: effectiveConstraints, child: sheetContent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Swipe-down-to-dismiss on non-scrollable areas (skip on TV and top-aligned)
    if (showHandle) {
      sheet = RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer()..onlyAcceptDragOnThreshold = true,
            (instance) {
              instance
                ..onStart = (_) {
                  _isDragging = true;
                  _dragOffset = 0;
                }
                ..onUpdate = (details) {
                  if (!_isDragging) return;
                  setState(() {
                    _dragOffset += details.delta.dy;
                  });
                }
                ..onEnd = (details) {
                  if (!_isDragging) return;
                  _isDragging = false;
                  _checkDismiss(details.primaryVelocity ?? 0);
                };
            },
          ),
        },
        child: sheet,
      );
    }

    return sheet;
  }
}

/// Paints [shadows] behind [child], or gets out of the way entirely when there
/// are none — which is every presentation except the centred 10-foot panel.
class _CastShadow extends StatelessWidget {
  const _CastShadow({required this.shadows, required this.borderRadius, required this.child});

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (shadows.isEmpty) return child;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: child,
    );
  }
}

class _OverlaySheetLayoutDelegate extends SingleChildLayoutDelegate {
  final Alignment alignment;
  final double? horizontalAnchor;
  final double edgePadding;

  /// Top and bottom inset. Zero for every edge-hugging sheet, so the maths
  /// below collapses to what it has always been; non-zero only for a surface
  /// that a television placed itself, where the outer band is overscan.
  final double verticalEdgePadding;

  const _OverlaySheetLayoutDelegate({
    required this.alignment,
    required this.horizontalAnchor,
    required this.edgePadding,
    this.verticalEdgePadding = 0,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final maxWidth = size.width > edgePadding * 2 ? size.width - edgePadding * 2 : size.width;
    final maxHeight = size.height > verticalEdgePadding * 2 ? size.height - verticalEdgePadding * 2 : size.height;
    return BoxConstraints.loose(Size(maxWidth, maxHeight));
  }

  /// The band the child may be placed in along one axis, as (min, max) offsets.
  ///
  /// The padding is what fits, never more: a child that exactly fills the
  /// padded width keeps its inset on both sides, and a child wider than the
  /// viewport falls back to zero rather than to a negative offset. The old form
  /// of this used a strict `>` comparison, which meant a surface sized to
  /// exactly the padded width lost its inset and was flushed against the left,
  /// with all the slack piling up on the other side.
  static (double, double) _band(double available, double child, double padding) {
    final free = available - child;
    final pad = padding <= 0 ? 0.0 : math.min(padding, math.max(0.0, free / 2));
    final minOffset = pad;
    final maxOffset = math.max(minOffset, free - pad);
    return (minOffset, maxOffset);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final (minLeft, maxLeft) = _band(size.width, childSize.width, edgePadding);
    final left = horizontalAnchor == null
        ? minLeft + (maxLeft - minLeft) * (alignment.x + 1) / 2
        : (horizontalAnchor! - childSize.width / 2).clamp(minLeft, maxLeft).toDouble();

    final (minTop, maxTop) = _band(size.height, childSize.height, verticalEdgePadding);
    final top = minTop + (maxTop - minTop) * (alignment.y + 1) / 2;

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_OverlaySheetLayoutDelegate oldDelegate) {
    return alignment != oldDelegate.alignment ||
        horizontalAnchor != oldDelegate.horizontalAnchor ||
        edgePadding != oldDelegate.edgePadding ||
        verticalEdgePadding != oldDelegate.verticalEdgePadding;
  }
}

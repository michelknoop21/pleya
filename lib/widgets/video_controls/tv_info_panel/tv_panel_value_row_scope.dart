import 'package:flutter/widgets.dart';

/// Which value row of the player panel currently owns LEFT and RIGHT.
///
/// DEC-107. A value row used to consume LEFT and RIGHT whenever it had a step
/// to make, and `clampedSteps` only handed the key back at the ends of the
/// list. A value sitting in the middle of its list therefore had no way out of
/// its column: from Aspect ratio the right-hand column was unreachable without
/// changing the aspect ratio (PLR5). A row is now entered first — Select — and
/// only then do LEFT and RIGHT step it.
///
/// At most one row is entered at a time and a row that loses the focus lets go
/// on its own, so the panel can never hold an entered row that is off screen.
class TvPanelValueRowController extends ChangeNotifier {
  Object? _entered;

  /// A row's own dispose can outlive the panel's: `TvInfoPanel.dispose` runs
  /// before the rows below it are unmounted, and the row's deferred release
  /// then lands on a controller that is already gone.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Whether any row is entered. The panel's Menu handler reads this: Menu
  /// leaves the row first and only closes the panel once none is entered.
  bool get hasEnteredRow => _entered != null;

  bool isEntered(Object token) => identical(_entered, token);

  void enter(Object token) {
    if (_disposed || identical(_entered, token)) return;
    _entered = token;
    notifyListeners();
  }

  /// Leaves the entered row. With a [token] it only leaves that row, so a row
  /// that is disposed after another one was entered cannot clear the new one.
  void leave([Object? token]) {
    if (_disposed || _entered == null) return;
    if (token != null && !identical(_entered, token)) return;
    _entered = null;
    notifyListeners();
  }

  void toggle(Object token) => isEntered(token) ? leave(token) : enter(token);
}

/// Hands [TvPanelValueRowController] to the rows without threading it through
/// the three tab widgets that build them.
class TvPanelValueRowScope extends InheritedNotifier<TvPanelValueRowController> {
  const TvPanelValueRowScope({super.key, required TvPanelValueRowController super.notifier, required super.child});

  static TvPanelValueRowController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvPanelValueRowScope>()?.notifier;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_navigation_hooks.dart';
import 'package:pleya/navigation/navigation_tabs.dart';

/// The three hooks are registered in `initState` and given back in `dispose`,
/// always as a bound instance-method tear-off. Dart creates a new closure
/// object for each tear-off expression, so the one `dispose` hands over is
/// `==` to the one `initState` registered but never `identical` to it. These
/// pin that unregistering compares the way the callers actually behave.
///
/// Left unfixed, `screen.books_filters` stayed registered after `Alle boeken`
/// was popped: `/v1/open` got `true` from `openRoute`, `_openFilters` bailed on
/// `!mounted`, and the scenario failed on a generic readiness timeout instead
/// of the documented "no opener registered". The five Boeken-home openers had
/// the same shape, and each one held a disposed `State` alive with it.
class _Owner {
  _Owner(this.calls);

  final List<String> calls;

  void open() => calls.add('open');

  void selectTab(NavigationTabId tab) => calls.add('tab:${tab.name}');

  void handoff() => calls.add('handoff');
}

void main() {
  late AutomationNavigationHooks hooks;
  late List<String> calls;

  setUp(() {
    hooks = AutomationNavigationHooks.instance;
    calls = [];
  });

  test('two tear-offs of one method on one object are == but not identical', () {
    // The premise the three unregisters rest on, asserted rather than assumed:
    // this is the whole reason `identical` was the wrong operator.
    final owner = _Owner(calls);

    expect(owner.open == owner.open, isTrue);
    expect(identical(owner.open, owner.open), isFalse);
    expect(_Owner(calls).open == owner.open, isFalse, reason: 'a different owner must not unregister this one');
  });

  group('route openers', () {
    tearDown(() {
      for (final id in ['screen.a', 'screen.b']) {
        hooks.unregisterRouteOpener(id, () {});
      }
    });

    test('a screen that registers in initState can give it back in dispose', () {
      final owner = _Owner(calls);
      hooks.registerRouteOpener('screen.a', owner.open);

      expect(hooks.openRoute('screen.a'), isTrue);

      hooks.unregisterRouteOpener('screen.a', owner.open);

      expect(
        hooks.openRoute('screen.a'),
        isFalse,
        reason: 'a popped screen leaves no opener behind, so /v1/open can say so instead of timing out',
      );
      expect(calls, ['open'], reason: 'the stale opener must not be callable after dispose');
    });

    test('one screen cannot unregister another screen\'s opener for the same id', () {
      final mounted = _Owner(calls);
      final gone = _Owner(calls);
      hooks.registerRouteOpener('screen.a', mounted.open);

      hooks.unregisterRouteOpener('screen.a', gone.open);

      expect(
        hooks.openRoute('screen.a'),
        isTrue,
        reason: 'a late dispose from a replaced instance must not take the live registration with it',
      );
    });

    test('a second screen taking over the id owns it, and the first one leaves it alone', () {
      // The push/pop order Boeken-home and Alle boeken produce: the new
      // instance registers before the old one disposes.
      final first = _Owner(calls);
      final second = _Owner(calls);
      hooks.registerRouteOpener('screen.a', first.open);
      hooks.registerRouteOpener('screen.a', second.open);

      hooks.unregisterRouteOpener('screen.a', first.open);

      expect(hooks.openRoute('screen.a'), isTrue);
    });

    test('openers are kept per screen id', () {
      final owner = _Owner(calls);
      hooks.registerRouteOpener('screen.a', owner.open);
      hooks.registerRouteOpener('screen.b', owner.open);

      hooks.unregisterRouteOpener('screen.a', owner.open);

      expect(hooks.openRoute('screen.a'), isFalse);
      expect(hooks.openRoute('screen.b'), isTrue);
    });
  });

  test('the select-tab hook is given back the same way', () {
    final owner = _Owner(calls);
    hooks.registerSelectTab(owner.selectTab);
    expect(hooks.selectTab(NavigationTabId.books), isTrue);

    hooks.unregisterSelectTab(owner.selectTab);

    expect(hooks.selectTab(NavigationTabId.books), isFalse);
    expect(calls, ['tab:books']);
  });

  test('the first-profile handoff is given back the same way', () {
    final owner = _Owner(calls);
    hooks.registerFirstProfileHandoff(owner.handoff);
    expect(hooks.handoffToFirstProfile(), isTrue);

    hooks.unregisterFirstProfileHandoff(owner.handoff);

    expect(hooks.handoffToFirstProfile(), isFalse);
    expect(calls, ['handoff']);
  });
}

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

  Future<bool> open() async {
    calls.add('open');
    return true;
  }

  void selectTab(NavigationTabId tab) => calls.add('tab:${tab.name}');

  void handoff() => calls.add('handoff');
}

/// An opener shaped the way the Boeken-home ones are: it looks something up
/// before it can push, so it has an `await` before its `Navigator.push`.
class _AsyncOwner {
  _AsyncOwner(this.calls, {required this.findsBook});

  final List<String> calls;
  final bool findsBook;

  Future<bool> open() async {
    await Future<void>.delayed(Duration.zero);
    if (!findsBook) {
      calls.add('bail');
      return false;
    }
    calls.add('push');
    return true;
  }
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
        hooks.unregisterRouteOpener(id, () async => true);
      }
    });

    test('a screen that registers in initState can give it back in dispose', () async {
      final owner = _Owner(calls);
      hooks.registerRouteOpener('screen.a', owner.open);

      expect(await hooks.openRoute('screen.a'), isTrue);

      hooks.unregisterRouteOpener('screen.a', owner.open);

      expect(
        await hooks.openRoute('screen.a'),
        isFalse,
        reason: 'a popped screen leaves no opener behind, so /v1/open can say so instead of timing out',
      );
      expect(calls, ['open'], reason: 'the stale opener must not be callable after dispose');
    });

    test('one screen cannot unregister another screen\'s opener for the same id', () async {
      final mounted = _Owner(calls);
      final gone = _Owner(calls);
      hooks.registerRouteOpener('screen.a', mounted.open);

      hooks.unregisterRouteOpener('screen.a', gone.open);

      expect(
        await hooks.openRoute('screen.a'),
        isTrue,
        reason: 'a late dispose from a replaced instance must not take the live registration with it',
      );
    });

    test('a second screen taking over the id owns it, and the first one leaves it alone', () async {
      // The push/pop order Boeken-home and Alle boeken produce: the new
      // instance registers before the old one disposes.
      final first = _Owner(calls);
      final second = _Owner(calls);
      hooks.registerRouteOpener('screen.a', first.open);
      hooks.registerRouteOpener('screen.a', second.open);

      hooks.unregisterRouteOpener('screen.a', first.open);

      expect(await hooks.openRoute('screen.a'), isTrue);
    });

    test('openers are kept per screen id', () async {
      final owner = _Owner(calls);
      hooks.registerRouteOpener('screen.a', owner.open);
      hooks.registerRouteOpener('screen.b', owner.open);

      hooks.unregisterRouteOpener('screen.a', owner.open);

      expect(await hooks.openRoute('screen.a'), isFalse);
      expect(await hooks.openRoute('screen.b'), isTrue);
    });

    /// An opener that has to look something up cannot answer before it has.
    /// As a `VoidCallback` a `Future<void>` opener returned at its first
    /// `await`, so `openRoute` reported success before the lookup and before
    /// the push; with `/v1/open`'s one-shot guard that burned the only attempt
    /// on a bail, and the endpoint then waited out its whole `timeoutMs`.
    test('an opener that bails says so, so the caller can ask again', () async {
      final bails = _AsyncOwner(calls, findsBook: false);
      hooks.registerRouteOpener('screen.a', bails.open);

      expect(await hooks.openRoute('screen.a'), isFalse, reason: 'nothing was pushed');
      expect(calls, ['bail']);

      // The shelf answers on the next turn. Retrying is safe precisely because
      // the first attempt reported that it pushed nothing.
      final finds = _AsyncOwner(calls, findsBook: true);
      hooks.registerRouteOpener('screen.a', finds.open);

      expect(await hooks.openRoute('screen.a'), isTrue);
      expect(calls, ['bail', 'push']);
    });

    test('an opener answers only after its await, not at it', () async {
      final owner = _AsyncOwner(calls, findsBook: true);
      hooks.registerRouteOpener('screen.a', owner.open);

      final pending = hooks.openRoute('screen.a');
      expect(calls, isEmpty, reason: 'the lookup has not run yet');

      expect(await pending, isTrue);
      expect(calls, ['push'], reason: 'the answer arrives with the push, not before it');
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

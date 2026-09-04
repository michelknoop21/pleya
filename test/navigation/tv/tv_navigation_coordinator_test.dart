import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';

void main() {
  group('initial state', () {
    test('active and focusedDestination both start at the initial destination', () {
      final coordinator = TvNavigationCoordinator(initial: TvDestinationId.movies);
      addTearDown(coordinator.dispose);

      expect(coordinator.active, TvDestinationId.movies);
      expect(coordinator.focusedDestination, TvDestinationId.movies);
    });

    test('defaults to the tv root destination', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.active, tvRootDestination);
      expect(coordinator.focusedDestination, tvRootDestination);
    });
  });

  group('focusDestination', () {
    test('moves the focus ring without changing the active destination', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      var notified = 0;
      coordinator.addListener(() => notified++);
      coordinator.focusDestination(TvDestinationId.movies);

      expect(coordinator.focusedDestination, TvDestinationId.movies);
      expect(coordinator.active, tvRootDestination);
      expect(notified, 1);
    });

    test('moving the ring to the destination it already sits on does not notify', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      var notified = 0;
      coordinator.addListener(() => notified++);
      coordinator.focusDestination(tvRootDestination);

      expect(notified, 0);
    });
  });

  group('activate', () {
    test('activating a different destination changes active, moves the ring, notifies, and returns true', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      var notified = 0;
      coordinator.addListener(() => notified++);
      final result = coordinator.activate(TvDestinationId.movies);

      expect(result, isTrue);
      expect(coordinator.active, TvDestinationId.movies);
      expect(coordinator.focusedDestination, TvDestinationId.movies);
      expect(notified, 1);
    });

    test('re-activating the already-active destination returns false and does not notify', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      var notified = 0;
      coordinator.addListener(() => notified++);
      final result = coordinator.activate(tvRootDestination);

      expect(result, isFalse);
      expect(coordinator.active, tvRootDestination);
      expect(notified, 0, reason: 'no refetch on re-select');
    });

    test('activating a destination not currently in the bar returns false and changes nothing', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));

      var notified = 0;
      coordinator.addListener(() => notified++);
      final result = coordinator.activate(TvDestinationId.liveTv);

      expect(result, isFalse);
      expect(coordinator.active, tvRootDestination);
      expect(coordinator.focusedDestination, tvRootDestination);
      expect(notified, 0);
    });
  });

  group('neighbourOf', () {
    test('returns the next destination for a positive delta', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.neighbourOf(TvDestinationId.home, 1), TvDestinationId.series);
    });

    test('returns the previous destination for a negative delta', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.neighbourOf(TvDestinationId.home, -1), TvDestinationId.search);
    });

    test('there is no wrap: the first destination has no neighbour to its left', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.neighbourOf(TvDestinationId.search, -1), isNull);
    });

    test('there is no wrap: the last destination has no neighbour to its right', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.neighbourOf(TvDestinationId.myPleya, 1), isNull);
    });
  });

  group('updateConditions', () {
    test('returns null and leaves everything alone when the bar is unchanged', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      var notified = 0;
      coordinator.addListener(() => notified++);
      final result = coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));

      expect(result, isNull);
      expect(notified, 0);
    });

    test('live tv disappearing while it was active moves active to the root destination', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      coordinator.activate(TvDestinationId.liveTv);

      final result = coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));

      expect(result, tvRootDestination);
      expect(coordinator.active, tvRootDestination);
    });

    test('live tv disappearing while it was not active returns null and leaves active alone', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      coordinator.activate(TvDestinationId.movies);

      final result = coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));

      expect(result, isNull);
      expect(coordinator.active, TvDestinationId.movies);
    });

    test('live tv disappearing while it only held the focus ring moves the ring off it', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      coordinator.activate(TvDestinationId.movies);
      coordinator.focusDestination(TvDestinationId.liveTv);

      coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));

      expect(coordinator.focusedDestination, isNot(TvDestinationId.liveTv));
      expect(coordinator.focusedDestination, coordinator.active);
    });
  });

  group('content focus memory', () {
    test('rememberContentFocus and contentFocusFor round-trip per destination', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      coordinator.rememberContentFocus(
        TvDestinationId.movies,
        const TvDestinationFocusMemory(focusedElementId: 'filters', groupId: 'movie_42', scrollOffset: 640),
      );
      coordinator.rememberContentFocus(TvDestinationId.series, const TvDestinationFocusMemory(groupId: 'series_7'));

      expect(coordinator.contentFocusFor(TvDestinationId.movies).groupId, 'movie_42');
      expect(coordinator.contentFocusFor(TvDestinationId.movies).focusedElementId, 'filters');
      expect(coordinator.contentFocusFor(TvDestinationId.movies).scrollOffset, 640);
      // Each destination keeps its own place: Series must not inherit Films'
      // offset merely because Films was visited more recently.
      expect(coordinator.contentFocusFor(TvDestinationId.series).groupId, 'series_7');
      expect(coordinator.contentFocusFor(TvDestinationId.series).scrollOffset, isNull);
    });

    test('a destination that was never entered has an empty place, not a null', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.contentFocusFor(TvDestinationId.movies), TvDestinationFocusMemory.empty);
      expect(coordinator.contentFocusFor(TvDestinationId.movies).isEmpty, isTrue);
    });

    test('remembering an empty place forgets the destination rather than storing nothing', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.rememberContentFocus(TvDestinationId.movies, const TvDestinationFocusMemory(groupId: 'movie_42'));

      coordinator.rememberContentFocus(TvDestinationId.movies, TvDestinationFocusMemory.empty);

      expect(coordinator.contentFocusFor(TvDestinationId.movies).isEmpty, isTrue);
    });

    test('clearFocusMemory empties every destination', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.rememberContentFocus(TvDestinationId.movies, const TvDestinationFocusMemory(groupId: 'movie_42'));
      coordinator.rememberContentFocus(TvDestinationId.series, const TvDestinationFocusMemory(groupId: 'series_7'));

      coordinator.clearFocusMemory();

      expect(coordinator.contentFocusFor(TvDestinationId.movies).isEmpty, isTrue);
      expect(coordinator.contentFocusFor(TvDestinationId.series).isEmpty, isTrue);
    });
  });

  group('nested routes', () {
    TvNestedRoute route(String id) => TvNestedRoute(id: id, builder: (_) => const SizedBox.shrink());

    test('pushNested makes the route the active nested route and pops back to none', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.activate(TvDestinationId.movies);

      coordinator.pushNested(TvDestinationId.movies, route('all_movies'));

      expect(coordinator.activeNestedRoute?.id, 'all_movies');
      expect(coordinator.activeCanPop, isTrue);

      final popped = coordinator.popNested();

      expect(popped?.id, 'all_movies');
      expect(coordinator.activeNestedRoute, isNull);
      expect(coordinator.activeCanPop, isFalse);
    });

    test('pushing the same route id twice does not stack it twice', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.activate(TvDestinationId.movies);

      coordinator.pushNested(TvDestinationId.movies, route('all_movies'));
      coordinator.pushNested(TvDestinationId.movies, route('all_movies'));

      expect(coordinator.nestedRoutesFor(TvDestinationId.movies), hasLength(1));
      expect(coordinator.popNested()?.id, 'all_movies');
      expect(coordinator.popNested(), isNull, reason: 'a single push must need only a single pop');
    });

    test('popNested returns the popped route and then null once the stack is empty', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.activate(TvDestinationId.movies);

      expect(coordinator.popNested(), isNull);

      coordinator.pushNested(TvDestinationId.movies, route('all_movies'));
      expect(coordinator.popNested()?.id, 'all_movies');
      expect(coordinator.popNested(), isNull);
    });

    test('nested stacks are kept per destination', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.pushNested(TvDestinationId.movies, route('all_movies'));

      coordinator.activate(TvDestinationId.series);

      expect(coordinator.activeNestedRoute, isNull, reason: 'the route pushed on movies is not visible on series');
      expect(coordinator.nestedRoutesFor(TvDestinationId.movies), hasLength(1));
    });

    test('clearNestedRoutes empties every destination', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.pushNested(TvDestinationId.movies, route('all_movies'));
      coordinator.pushNested(TvDestinationId.series, route('all_series'));

      coordinator.clearNestedRoutes();

      expect(coordinator.nestedRoutesFor(TvDestinationId.movies), isEmpty);
      expect(coordinator.nestedRoutesFor(TvDestinationId.series), isEmpty);
    });
  });

  group('syncToTab', () {
    test('syncing to a tab with no pill of its own lights up my pleya', () {
      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);

      coordinator.syncToTab(NavigationTabId.settings);

      expect(coordinator.active, TvDestinationId.myPleya);
    });
  });
}

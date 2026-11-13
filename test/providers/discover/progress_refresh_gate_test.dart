import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/providers/discover/progress_refresh_gate.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

WatchStateEvent _event({
  String id = 'ep-1',
  WatchStateChangeType type = WatchStateChangeType.progressUpdate,
  bool isFinal = false,
  bool? watched = false,
}) => WatchStateEvent(
  itemId: id,
  serverId: ServerId('srv'),
  changeType: type,
  parentChain: const [],
  mediaType: 'episode',
  isNowWatched: watched,
  isFinal: isFinal,
);

void main() {
  late DateTime clock;
  late ProgressRefreshGate gate;
  setUp(() {
    clock = DateTime(2026, 11, 13, 19, 43);
    gate = ProgressRefreshGate(now: () => clock);
  });
  void wait(int seconds) => clock = clock.add(Duration(seconds: seconds));

  test('a running play refreshes on its first report and on its last, not in between', () {
    final refreshed = <bool>[gate.shouldRefresh(_event())];
    // The cadence of log hbv3g: a report every 30 to 40 seconds.
    for (final gap in [40, 40, 40, 30, 11, 40]) {
      wait(gap);
      refreshed.add(gate.shouldRefresh(_event()));
    }
    wait(20);
    refreshed.add(gate.shouldRefresh(_event(isFinal: true)));

    expect(refreshed, [true, false, false, false, false, false, false, true]);
  });

  test('a report after a quiet stretch refreshes again', () {
    gate.shouldRefresh(_event());
    wait(91);

    expect(gate.shouldRefresh(_event()), isTrue);
  });

  test('crossing the watched threshold refreshes once', () {
    gate.shouldRefresh(_event());
    wait(30);
    expect(gate.shouldRefresh(_event(watched: true)), isTrue);
    wait(30);
    expect(gate.shouldRefresh(_event(watched: true)), isFalse);
  });

  test('another title is judged on its own', () {
    gate.shouldRefresh(_event());
    wait(10);

    expect(gate.shouldRefresh(_event(id: 'ep-2')), isTrue);
  });

  test('every other kind of event always refreshes, and starts the title over', () {
    gate.shouldRefresh(_event());
    wait(10);
    expect(gate.shouldRefresh(_event(type: WatchStateChangeType.watched, watched: true)), isTrue);
    expect(gate.shouldRefresh(_event(type: WatchStateChangeType.unwatched)), isTrue);
    expect(gate.shouldRefresh(_event(type: WatchStateChangeType.removedFromContinueWatching)), isTrue);
    wait(10);
    expect(gate.shouldRefresh(_event()), isTrue, reason: 'a rewatch right after has to surface');
  });
}

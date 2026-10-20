import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';

// A-23: the receiver confirms a handoff on real progress, not on the playing event.

bool _ack({
  String? id = 'h1',
  bool acknowledged = false,
  bool playing = true,
  int? first = 226000,
  int position = 227000,
}) => shouldAcknowledgeHandoff(
  handoffId: id,
  acknowledged: acknowledged,
  playing: playing,
  firstPositionMs: first,
  positionMs: position,
);

void main() {
  test('no ack without a handoff id', () => expect(_ack(id: null), isFalse));
  test('no ack before one second of progress', () {
    expect(_ack(position: 226000), isFalse);
    expect(_ack(position: 226999), isFalse);
  });
  test('ack once the position moved a second while playing', () {
    expect(_ack(position: 227000), isTrue);
    expect(_ack(position: 230000), isTrue);
  });
  test('no ack while not playing', () => expect(_ack(playing: false), isFalse));
  test('no ack without a first position', () => expect(_ack(first: null), isFalse));
  test('only once', () => expect(_ack(acknowledged: true), isFalse));
  _seekTests();
}

void _feed(List<int> positions, void Function(int baseline, int position) onEach) {
  int? baseline;
  int? previous;
  for (final p in positions) {
    baseline = nextHandoffBaselineMs(baselineMs: baseline, previousMs: previous, positionMs: p);
    previous = p;
    onEach(baseline, p);
  }
}

bool _ackAfter(List<int> positions) {
  var acked = false;
  _feed(positions, (b, p) {
    if (!acked) acked = _ack(first: b, position: p);
  });
  return acked;
}

void _seekTests() {
  group('seek is no progress', () {
    test('jump 1404 s to 1410 s gives no ack', () => expect(_ackAfter([1404000, 1410000]), isFalse));
    test('then one second of normal progress acks', () {
      expect(_ackAfter([1404000, 1410000, 1410500]), isFalse);
      expect(_ackAfter([1404000, 1410000, 1410500, 1411000]), isTrue);
    });
    test('step backwards resets', () {
      expect(_ackAfter([1404000, 1404500, 1400000, 1400500]), isFalse);
      // Only a reset baseline (1400000) sees this second of progress.
      expect(_ackAfter([1404000, 1400000, 1400500, 1401000]), isTrue);
    });
    test('plain progress acks', () => expect(_ackAfter([1000, 1500, 2000]), isTrue));
  });
}

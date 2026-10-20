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
}

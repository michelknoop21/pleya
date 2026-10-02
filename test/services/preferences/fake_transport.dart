import 'dart:async';
import 'dart:convert';

import 'package:pleya/services/preferences/preference_transport.dart';

/// An in-memory transport. Records what it was asked to do, so a test can tell
/// "nothing was sent" apart from "something was sent and thrown away".
class FakeTransport implements PreferenceTransport {
  final Map<String, String> store = {};
  final List<String> writes = [];
  final List<String> removes = [];
  final StreamController<RemotePreferenceChange> controller = StreamController.broadcast();

  bool failReadAll = false;
  bool available = true;
  Object? throwOnWrite;
  Object? throwOnRemove;
  int? valueCap = 100 * 1024;

  /// KVS refuses keys over 64 UTF-8 bytes. The fake throws instead of
  /// dropping, so an engine path that forgot its own check fails the test.
  int? keyCap = 64;

  @override
  String get name => 'fake';

  @override
  int? get maxValueBytes => valueCap;

  @override
  int? get maxKeyBytes => keyCap;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<RemotePreferenceChange> get changes => controller.stream;

  @override
  Future<Map<String, String>?> readAll() async => failReadAll ? null : Map<String, String>.from(store);

  @override
  Future<void> write(String key, String encoded) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    final cap = keyCap;
    if (cap != null && utf8.encode(key).length > cap) throw ArgumentError('cloud key over $cap bytes: $key');
    writes.add(key);
    store[key] = encoded;
  }

  @override
  Future<void> remove(String key) async {
    if (throwOnRemove != null) throw throwOnRemove!;
    removes.add(key);
    store.remove(key);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async => controller.close();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/item_watcher.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/screens/settings/activity_sharing_controller.dart';

class _Client implements HouseholdActivityClient {
  _Client({this.stored, this.failSave = false});

  bool? stored;
  bool failSave;
  final saved = <bool>[];

  @override
  Future<List<ItemWatcher>> fetchHouseholdActivity(String itemId) async => const [];

  @override
  Future<bool?> fetchActivitySharing() async => stored;

  @override
  Future<bool> saveActivitySharing(bool share) async {
    if (failSave) throw StateError('no');
    saved.add(share);
    stored = share;
    return share;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  ActivitySharingController controller(_Client client) => ActivitySharingController(client: client, serverName: 'NAS');

  test('nothing is known before the read, and no save happens then', () async {
    final client = _Client(stored: true);
    final sharing = controller(client);

    expect(sharing.value, isNull);
    expect(await sharing.toggle(), isTrue);
    expect(client.saved, isEmpty);
  });

  test('a restricted user reads off, and may turn it on', () async {
    final client = _Client(stored: false);
    final sharing = controller(client);
    await sharing.load();

    expect(sharing.value, isFalse);
    expect(await sharing.toggle(), isTrue);
    expect(sharing.value, isTrue);
    expect(client.saved, [true]);
  });

  test('a failed save keeps the old value and says so', () async {
    final client = _Client(stored: true, failSave: true);
    final sharing = controller(client);
    await sharing.load();

    expect(await sharing.toggle(), isFalse);
    expect(sharing.value, isTrue);
  });

  test('a read without an answer offers another try, and that one can land', () async {
    final client = _Client();
    final sharing = controller(client);
    await sharing.load();
    expect(sharing.unreadable, isTrue);

    client.stored = true;
    await sharing.load();
    expect(sharing.unreadable, isFalse);
    expect(sharing.value, isTrue);
  });

  test('a second press while saving does nothing', () async {
    final client = _Client(stored: true);
    final sharing = controller(client);
    await sharing.load();

    await Future.wait([sharing.toggle(), sharing.toggle()]);

    expect(client.saved, [false]);
  });
}

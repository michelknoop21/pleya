import 'package:flutter/foundation.dart';

import '../../media/media_server_client.dart';
import '../../mixins/disposable_change_notifier_mixin.dart';
import '../../utils/app_logger.dart';

/// The viewer's choice to share their activity, on one server.
///
/// The server holds it, so nothing here is remembered on the device, and a
/// restricted user simply reads off until they turn it on. [value] only moves
/// when the server confirmed it: a failed save leaves what is still true on
/// screen, and the row says so.
class ActivitySharingController extends ChangeNotifier with DisposableChangeNotifierMixin {
  ActivitySharingController({required this.client, required this.serverName});

  final HouseholdActivityClient client;
  final String? serverName;

  bool? _value;
  bool _loading = false;
  bool _saving = false;

  /// Null while it is on its way and when it could not be read.
  bool? get value => _value;

  /// Whether a read finished without an answer, so the row offers another try.
  bool get unreadable => _value == null && !_loading;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    safeNotifyListeners();
    final value = await client.fetchActivitySharing();
    _loading = false;
    _value = value;
    safeNotifyListeners();
  }

  /// Flips the choice. False when the save failed and nothing changed; true
  /// when it landed, or when there was nothing to do yet.
  Future<bool> toggle() async {
    final current = _value;
    if (current == null || _saving) return true;
    _saving = true;
    try {
      _value = await client.saveActivitySharing(!current);
      return true;
    } catch (e) {
      appLogger.w('Activity sharing could not be saved', error: e);
      return false;
    } finally {
      _saving = false;
      safeNotifyListeners();
    }
  }
}

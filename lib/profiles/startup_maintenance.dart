import '../connection/connection_bootstrap.dart';
import '../connection/connection_registry.dart';
import '../services/multi_server_manager.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';
import 'borrowed_connection_backfill.dart';
import 'profile_connection_cleanup.dart';
import 'profile_connection_registry.dart';

/// Boot-time data maintenance, run by the setup screen before the
/// `ActiveProfileBinder` starts: legacy bootstrap, pruning unreferenced
/// Jellyfin connections, and the one-time borrowed backfill.
///
/// The backfill has its own `try`: a failing bootstrap or prune must not skip
/// it, because only the backfill takes admin rights away from pre-v20 borrow
/// rows. If the backfill itself fails, its flag stays unset and the next
/// launch retries; this session then binds with the rows as they are.
/// Never throws.
Future<void> runStartupMaintenance({
  required ConnectionBootstrap bootstrap,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  try {
    await bootstrap.run();
    final pruned = await pruneUnreferencedJellyfinConnections(
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      serverManager: serverManager,
    );
    if (pruned > 0) {
      appLogger.i('Setup: pruned $pruned unreferenced Jellyfin connection${pruned == 1 ? '' : 's'}');
    }
  } catch (e, st) {
    appLogger.w('Boot-time migration failed', error: e, stackTrace: st);
  }

  try {
    await backfillBorrowedJellyfinRows(
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
    );
  } catch (e, st) {
    appLogger.w('Borrowed backfill failed, retrying on next launch', error: e, stackTrace: st);
  }
}

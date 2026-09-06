import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/icloud_sync_service.dart';
import 'package:pleya/services/settings_export_service.dart';

void main() {
  test('mergeProgressMaps: progress = max, both sides kept', () {
    final merged = ICloudSyncService.mergeProgressMaps(
      '{"a":5000,"b":90000}',
      '{"a":60000,"c":123}',
      watchedMap: false,
    );
    expect(merged, '{"a":60000,"b":90000,"c":123}');
  });

  test('mergeProgressMaps: watched = OR', () {
    final merged = ICloudSyncService.mergeProgressMaps(
      '{"a":true,"b":false}',
      '{"b":true,"c":false}',
      watchedMap: true,
    );
    expect(merged, '{"a":true,"b":true,"c":false}');
  });

  test('mergeProgressMaps: corrupt input keeps local', () {
    expect(ICloudSyncService.mergeProgressMaps('{"a":1}', 'not-json', watchedMap: false), '{"a":1}');
    expect(ICloudSyncService.mergeProgressMaps(null, '{"a":1}', watchedMap: false), '{"a":1}');
  });

  test('local progress keys are recognized, but neither they nor share keys export', () {
    expect(ICloudSyncService.isLocalProgressKey('local_progress_x'), isTrue);
    expect(ICloudSyncService.isLocalProgressKey('local_watched_x'), isTrue);
    // PREF1: isExportable now asks the registry, which registers
    // `local_progress_`/`local_watched_` as device-local runtime caches (a
    // frozen copy from the legacy-store migration, not the live value the
    // actual sync path reads). `mergeProgressMaps` above is legacy inbound
    // compatibility only, kept to read what older clients already wrote to
    // iCloud, not evidence that the export/import file should carry these.
    expect(SettingsExportService.isExportable('local_progress_x'), isFalse);
    for (final denied in [
      'pleya_share_catalog_abc',
      'pleya_share_pendingwatch_abc',
      'pleya_share_tokens',
      'pleya_share_guests',
      'pleya_share_watch_abc',
    ]) {
      expect(SettingsExportService.isExportable(denied), isFalse, reason: denied);
    }
  });
}

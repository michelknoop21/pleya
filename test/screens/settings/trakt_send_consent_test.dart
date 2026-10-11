import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/settings/trakt_settings_screen.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  test('a fresh install sends nothing back to Trakt: both write-backs default to off', () async {
    final settings = await SettingsService.getInstance();

    expect(settings.read(SettingsService.enableTraktScrobble), isFalse);
    expect(settings.read(SettingsService.enableTraktWatchedSync), isFalse);
  });

  test('allowing writes both toggles, declining writes both off', () async {
    final settings = await SettingsService.getInstance();

    await applyTraktSendConsent(true);
    expect(settings.read(SettingsService.enableTraktScrobble), isTrue);
    expect(settings.read(SettingsService.enableTraktWatchedSync), isTrue);

    await applyTraktSendConsent(false);
    expect(settings.read(SettingsService.enableTraktScrobble), isFalse);
    expect(settings.read(SettingsService.enableTraktWatchedSync), isFalse);
  });
}

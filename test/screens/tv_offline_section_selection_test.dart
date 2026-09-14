import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';

void main() {
  group('shouldCancelAutoSwitchedToDownloads', () {
    test('cancels when offline, auto-switched, and picking a different section', () {
      expect(
        shouldCancelAutoSwitchedToDownloads(
          isOffline: true,
          autoSwitchedToDownloads: true,
          nextSection: TvMyPleyaSection.watchlist,
        ),
        isTrue,
      );
    });

    test('does not cancel when re-opening Downloads itself', () {
      expect(
        shouldCancelAutoSwitchedToDownloads(
          isOffline: true,
          autoSwitchedToDownloads: true,
          nextSection: TvMyPleyaSection.downloads,
        ),
        isFalse,
      );
    });

    test('does not cancel while back online', () {
      expect(
        shouldCancelAutoSwitchedToDownloads(
          isOffline: false,
          autoSwitchedToDownloads: true,
          nextSection: TvMyPleyaSection.watchlist,
        ),
        isFalse,
      );
    });

    test('does not cancel when nothing was auto-switched', () {
      expect(
        shouldCancelAutoSwitchedToDownloads(
          isOffline: true,
          autoSwitchedToDownloads: false,
          nextSection: TvMyPleyaSection.watchlist,
        ),
        isFalse,
      );
    });
  });
}

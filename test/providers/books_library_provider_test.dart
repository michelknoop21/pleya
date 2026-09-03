import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/primary_mobile_destination_policy.dart';
import 'package:pleya/providers/books_library_provider.dart';

void main() {
  test('it starts unknown, so the bar reserves the slot rather than filling it', () {
    final provider = BooksLibraryProvider(probe: () async => true);

    expect(provider.availability, BooksAvailability.unknown);
    expect(provider.isResolved, isFalse);
  });

  test('a probe that finds books resolves to available', () async {
    final provider = BooksLibraryProvider(probe: () async => true);

    await provider.refresh(profileId: 'a');

    expect(provider.availability, BooksAvailability.available);
    expect(provider.isResolved, isTrue);
  });

  test('a probe that finds none resolves to unavailable, which is a decision', () async {
    final provider = BooksLibraryProvider(probe: () async => false);

    await provider.refresh(profileId: 'a');

    expect(provider.availability, BooksAvailability.unavailable);
  });

  test('a failing probe stays unknown instead of reporting no books', () async {
    // A timeout is not an answer. Reporting "unavailable" here would move the
    // fourth slot to Live TV on a flaky network and back on the retry.
    final provider = BooksLibraryProvider(probe: () async => throw StateError('offline'));

    await provider.refresh(profileId: 'a');

    expect(provider.availability, BooksAvailability.unknown);
  });

  test('switching profile drops the previous answer before asking again', () async {
    var answer = true;
    final provider = BooksLibraryProvider(probe: () async => answer);
    await provider.refresh(profileId: 'a');
    expect(provider.availability, BooksAvailability.available);

    answer = false;
    final seen = <BooksAvailability>[];
    provider.addListener(() => seen.add(provider.availability));
    await provider.refresh(profileId: 'b');

    expect(seen, [BooksAvailability.unknown, BooksAvailability.unavailable]);
  });

  test('a superseded probe cannot overwrite a newer answer', () async {
    // Two refreshes in flight, the first one slower. Without the generation
    // guard the stale reply lands last and wins.
    final slow = Completer<bool>();
    final fast = Completer<bool>();
    var call = 0;
    final provider = BooksLibraryProvider(probe: () => (call++ == 0 ? slow : fast).future);

    final first = provider.refresh(profileId: 'a');
    final second = provider.refresh(profileId: 'a');
    fast.complete(true);
    await second;
    slow.complete(false);
    await first;

    expect(provider.availability, BooksAvailability.available);
  });

  test('reset puts it back to unknown', () async {
    final provider = BooksLibraryProvider(probe: () async => true);
    await provider.refresh(profileId: 'a');

    provider.reset();

    expect(provider.availability, BooksAvailability.unknown);
  });

  test('notifications only fire on a real change', () async {
    final provider = BooksLibraryProvider(probe: () async => true);
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.refresh(profileId: 'a');
    await provider.refresh(profileId: 'a');

    expect(notifications, 1);
  });
}

import 'package:flutter/foundation.dart';

import '../navigation/primary_mobile_destination_policy.dart';
import '../utils/app_logger.dart';

/// Asks whether the acting profile has at least one e-book it may open.
///
/// Injected rather than reached for, so the provider can be driven from a test
/// or a Pleya Verify build without the navigation policy knowing where books
/// come from.
typedef BooksProbe = Future<bool> Function();

/// Whether this build ships the e-book surfaces at all.
///
/// The e-book data layer does not exist yet; this branch builds the navigation
/// that it will land in. Until the real source is wired, the default probe
/// answers from this compile-time flag, so a production build behaves exactly
/// as it did before ([BooksAvailability.unavailable], fourth slot goes to Live
/// TV / Watchlist / Downloads) while a Verify or development build can prove
/// the Boeken slot end to end with `--dart-define=PLEYA_BOOKS=true`.
const bool kBooksEnabled = bool.fromEnvironment('PLEYA_BOOKS');

/// Tri-state availability of the profile's e-books, for
/// [PrimaryMobileDestinationPolicy].
///
/// The three states are the point. A bool would force "not resolved yet" to
/// pick a side, and picking `false` is what makes the fourth slot flap on
/// startup; see [PrimaryMobileDestinationPolicy.dynamicDestination].
class BooksLibraryProvider extends ChangeNotifier {
  BooksLibraryProvider({BooksProbe? probe}) : _probe = probe ?? _defaultProbe;

  static Future<bool> _defaultProbe() async => kBooksEnabled;

  final BooksProbe _probe;

  BooksAvailability _availability = BooksAvailability.unknown;
  BooksAvailability get availability => _availability;

  /// Whether an answer has landed at all. `false` between construction and the
  /// first completed [refresh].
  bool get isResolved => _availability != BooksAvailability.unknown;

  /// The profile the current answer belongs to, so a switch invalidates it
  /// rather than showing the previous user's slot.
  String? _profileId;
  int _generation = 0;

  /// Resolve availability for [profileId].
  ///
  /// Re-entrant by design: a second call supersedes the first, and a late reply
  /// from a superseded probe is dropped instead of overwriting a newer answer.
  Future<void> refresh({String? profileId}) async {
    final generation = ++_generation;
    if (profileId != _profileId) {
      _profileId = profileId;
      _set(BooksAvailability.unknown);
    }
    try {
      final hasBooks = await _probe();
      if (generation != _generation) return;
      _set(hasBooks ? BooksAvailability.available : BooksAvailability.unavailable);
    } catch (error) {
      if (generation != _generation) return;
      // An unreachable source is not a resolved "no books": staying unknown
      // keeps the slot reserved instead of handing it to Live TV on a timeout.
      appLogger.w('BooksLibraryProvider: books probe failed: $error');
      _set(BooksAvailability.unknown);
    }
  }

  /// Forget the current answer, e.g. on sign-out.
  void reset() {
    _generation++;
    _profileId = null;
    _set(BooksAvailability.unknown);
  }

  @visibleForTesting
  void debugSetAvailability(BooksAvailability value) => _set(value);

  void _set(BooksAvailability value) {
    if (_availability == value) return;
    _availability = value;
    notifyListeners();
  }
}

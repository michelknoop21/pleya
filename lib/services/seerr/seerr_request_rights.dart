import '../../models/seerr/seerr_request.dart';

/// What the signed-in Seerr user may do with one request, as far as this
/// client can tell before asking.
///
/// Deliberately narrower than the server where the two differ: a manager may
/// delete any request on the server, and this still only offers Annuleren on a
/// viewer's own pending one, which is what the list did before. The server
/// remains the authority, so a 401, 403 or 409 on any of these is an answer to
/// show, never a reason to offer more.
class SeerrRequestRights {
  const SeerrRequestRights._({
    required this.canApprove,
    required this.canDecline,
    required this.canCancel,
    required this.canEditSeasons,
    required this.canEditTarget,
  });

  /// [ownUserId] is the Seerr user id of the session. Null means it is not
  /// known, and then nothing counts as the viewer's own.
  factory SeerrRequestRights.of(
    SeerrRequest request, {
    required int? ownUserId,
    required bool canManage,
    required bool isAdmin,
  }) {
    final pending = request.isPending;
    final own = ownUserId != null && request.requestedById == ownUserId;
    return SeerrRequestRights._(
      canApprove: pending && canManage,
      canDecline: pending && canManage,
      canCancel: pending && own,
      // The route lets the requester change the seasons of a series. A film
      // has no seasons, and its only editable fields are the target below.
      canEditSeasons: pending && request.mediaType == 'tv' && (own || canManage),
      // Server, profile and root folder are the admin-only section of the
      // request form, and editing does not open them to anyone else.
      canEditTarget: pending && isAdmin,
    );
  }

  final bool canApprove;
  final bool canDecline;
  final bool canCancel;
  final bool canEditSeasons;
  final bool canEditTarget;

  bool get canEdit => canEditSeasons || canEditTarget;
  bool get hasAny => canApprove || canDecline || canCancel || canEdit;
}

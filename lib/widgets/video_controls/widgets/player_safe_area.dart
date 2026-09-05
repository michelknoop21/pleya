/// The measurable title-safe rect of the player overlay, for Pleya Verify.
///
/// Same construction and same reasoning as `TvDiscoverySafeArea`: a node whose
/// bounds *are* the safe area, registered inside the inset the overlay pays,
/// so `notClipped` against it asks the question the overscan rule of
/// hoofdstuk 8.1 asks. Draws nothing, takes no input, and exists only in a
/// `kPleyaVerify` build; [maybe] is null everywhere else.
library;

import 'package:flutter/widgets.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/pleya_verify.dart';
import '../../../utils/layout_constants.dart';
import '../../tv/tv_page_surface.dart';
import '../../tv/tv_unified_layout.dart';

class PlayerSafeArea {
  const PlayerSafeArea._();

  /// A `Positioned.fill` overlay carrying [AutomationIds.playerSafeArea], or
  /// null outside a Pleya Verify build. Sides: [tvPageInset]; top and bottom:
  /// the catalog's safe insets, the same band every TV page keeps clear.
  static Widget? maybe(BuildContext context) {
    if (!kPleyaVerify) return null;
    final scale = TvLayoutConstants.scaleOf(context);
    final side = tvPageInset(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              TvCatalogLayout.topSafeInset * scale,
              side,
              TvCatalogLayout.bottomSafeInset * scale,
            ),
            child: const AutomationNode(id: AutomationIds.playerSafeArea, role: 'region', child: SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

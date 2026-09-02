/// The measurable title-safe rect of a TV discovery surface, for Pleya Verify.
///
/// `notClipped` is a binary predicate: subject rect fully inside a second
/// node's rect. To ask "is this focus ring inside the safe area" there has to
/// be a node whose bounds *are* the safe area — and `insideViewport` is not
/// that, because the viewport is the whole panel including the overscan band
/// (hoofdstuk 8.1) that the assertion exists to keep content out of.
///
/// So this draws nothing, takes no input, and exists only to be measured. The
/// obvious alternative — hanging an `AutomationNode` on the page's outer
/// `Padding` — measures the *outside* of the inset, which is the full viewport
/// again, and would make every overscan assertion pass by construction.
///
/// It is built only under `kPleyaVerify`. In an ordinary build [maybe] returns
/// null and there is no extra widget in the tree at all.
library;

import 'package:flutter/widgets.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/pleya_verify.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';

class TvDiscoverySafeArea {
  const TvDiscoverySafeArea._();

  /// A `Positioned.fill` overlay carrying [AutomationIds.discoverSafeArea], or
  /// null outside a Pleya Verify build.
  ///
  /// The insets mirror what the page itself pays: [TvDiscoveryLayout.pageInset]
  /// on the sides, [TvCatalogLayout.topSafeInset] above and
  /// [TvCatalogLayout.bottomSafeInset] below — the wider bottom band of P12.
  static Widget? maybe(BuildContext context) {
    if (!kPleyaVerify) return null;
    final scale = TvLayoutConstants.scaleOf(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              TvDiscoveryLayout.pageInset * scale,
              TvCatalogLayout.topSafeInset * scale,
              TvDiscoveryLayout.pageInset * scale,
              TvCatalogLayout.bottomSafeInset * scale,
            ),
            child: const AutomationNode(id: AutomationIds.discoverSafeArea, role: 'region', child: SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

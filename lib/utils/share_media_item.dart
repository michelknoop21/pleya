import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import 'snackbar_helper.dart';

/// The system share sheet with the title and year of [item], anchored to the
/// box of [anchor]. share_plus needs that origin for the popover: required on
/// iPad, and without it the sheet could fail to appear or leave the UI
/// unresponsive, which Michel saw on 24 September ("delen werkt niet"). A
/// failure to present the sheet is shown, a dismissed sheet is not.
///
/// Text and no link: the app knows no address for a title that someone else
/// could open, so this is what every backend can share.
Future<void> shareMediaItem(BuildContext anchor, MediaItem item) async {
  final box = anchor.findRenderObject();
  final origin = box is RenderBox && box.hasSize && !box.size.isEmpty
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final year = item.year;
  final text = year == null ? item.displayTitle : '${item.displayTitle} ($year)';
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: item.displayTitle, sharePositionOrigin: origin));
  } catch (_) {
    if (!anchor.mounted) return;
    showErrorSnackBar(anchor, t.errors.failedToLoad(context: t.common.share));
  }
}

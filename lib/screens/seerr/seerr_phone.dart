import 'package:flutter/widgets.dart';

import '../../utils/platform_detector.dart';

/// A real iPhone. The compact request list and the own-chrome title page are
/// phone-only: an iPad keeps the inline approve/decline buttons and the
/// standard app bar, and the Mac container ("Designed for iPad") reports iOS
/// too but is neither.
bool seerrIsIPhone(BuildContext context) =>
    PlatformDetector.isHandheldIOS(context) &&
    PlatformDetector.isPhone(context) &&
    !TvDetectionService.isIOSAppOnMacSync();

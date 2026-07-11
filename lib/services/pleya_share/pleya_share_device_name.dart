import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../../utils/app_logger.dart';

/// Human-readable name for this device, shown to peers during pairing.
Future<String> pleyaShareDeviceName() async {
  try {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return '${info.brand} ${info.model}';
    } else if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).name;
    } else if (Platform.isMacOS) {
      return (await deviceInfo.macOsInfo).computerName;
    } else if (Platform.isWindows) {
      return (await deviceInfo.windowsInfo).computerName;
    }
  } catch (e) {
    appLogger.d('PleyaShare: device name lookup failed', error: e);
  }
  final host = Platform.localHostname.trim();
  return host.isNotEmpty ? host : 'Pleya';
}

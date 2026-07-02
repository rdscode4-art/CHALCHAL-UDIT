import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceUtils {
  static Future<String> getDeviceInfo() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (kIsWeb) {
        final webBrowserInfo = await deviceInfo.webBrowserInfo;
        return 'Web (${webBrowserInfo.browserName.name})';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return '${iosInfo.name} (${iosInfo.systemName} ${iosInfo.systemVersion})';
      }
    } catch (e) {
      debugPrint('[DeviceUtils] Error getting device info: $e');
    }
    return 'Unknown Device';
  }
}

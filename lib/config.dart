import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

String get baseUrl => AppConfig.baseUrl;

class AppConfig {
  static const String lanIP = "192.168.10.234";
  static const String project = "reshub";

  // ✅ จะเข้า emulator เฉพาะตอนสั่ง USE_EMULATOR=true
  static const bool useEmulator = bool.fromEnvironment(
    'USE_EMULATOR',
    defaultValue: false,
  );

  static String get baseUrl {
    if (kIsWeb) return "http://$lanIP/$project";

    if (useEmulator) {
      // Android Emulator
      if (Platform.isAndroid) return "http://192.168.10.234/$project";
      // iOS Simulator
      if (Platform.isIOS) return "http://192.168.10.234/$project";
    }

    // มือถือจริง / APK
    return "http://$lanIP/$project";
  }

  static String url(String path) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return "$baseUrl/$p";
  }
}

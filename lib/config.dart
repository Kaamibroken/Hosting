import 'package:flutter/foundation.dart';

class AppConfig {

  static String get baseUrl {
    if (kIsWeb) {
      return ""; 
    } else {
      return "https://www.silenthost.pro"; 
    }
  }
}
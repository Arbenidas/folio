import 'package:flutter/foundation.dart';

/// Shared layout values for Folio's toolbar inside the macOS titlebar.
class FolioWindowChrome {
  const FolioWindowChrome._();

  static const double toolbarHeight = 40;
  static const double trafficLightInset = 82;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'thermal_printer_platform_interface.dart';

/// An implementation of [ThermalPrinterPlatform] that uses method channels.
class MethodChannelThermalPrinter extends ThermalPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('thermal_printer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}

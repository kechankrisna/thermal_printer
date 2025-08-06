import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'thermal_printer_method_channel.dart';

abstract class ThermalPrinterPlatform extends PlatformInterface {
  /// Constructs a ThermalPrinterPlatform.
  ThermalPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static ThermalPrinterPlatform _instance = MethodChannelThermalPrinter();

  /// The default instance of [ThermalPrinterPlatform] to use.
  ///
  /// Defaults to [MethodChannelThermalPrinter].
  static ThermalPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ThermalPrinterPlatform] when
  /// they register themselves.
  static set instance(ThermalPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

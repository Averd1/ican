import 'package:flutter/foundation.dart';
import '../services/ble_service.dart';
import '../protocol/ble_protocol.dart';

/// Represents the current state of connected iCan devices.
class DeviceState extends ChangeNotifier {
  // Cane connection
  BleConnectionState _caneConnection = BleConnectionState.disconnected;
  BleConnectionState get caneConnection => _caneConnection;

  // Eye connection
  BleConnectionState _eyeConnection = BleConnectionState.disconnected;
  BleConnectionState get eyeConnection => _eyeConnection;

  // Latest telemetry
  TelemetryPacket? _telemetry;
  TelemetryPacket? get telemetry => _telemetry;

  // Battery
  int get batteryPercent => _telemetry?.batteryPercent ?? -1;
  bool get isFallDetected => _telemetry?.fallDetected ?? false;
  int get pulseBpm => _telemetry?.pulseBpm ?? 0;

  void updateCaneConnection(BleConnectionState state) {
    _caneConnection = state;
    notifyListeners();
  }

  void updateEyeConnection(BleConnectionState state) {
    _eyeConnection = state;
    notifyListeners();
  }

  void updateTelemetry(TelemetryPacket pkt) {
    _telemetry = pkt;
    notifyListeners();
  }
}

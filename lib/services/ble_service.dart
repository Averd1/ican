import 'dart:async';
import 'package:flutter/foundation.dart';
import '../protocol/ble_protocol.dart';

/// BLE connection status.
enum BleConnectionState { disconnected, scanning, connecting, connected }

/// BLE Service — wraps BLE scanning, connection, and data exchange.
///
/// Uses UUIDs and codecs from [BleCharacteristics] and [BleServices].
/// Actual BLE library integration (flutter_reactive_ble) will be wired
/// in once the dependency is added and platform permissions configured.
class BleService extends ChangeNotifier {
  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get state => _state;

  // Latest telemetry from the cane
  TelemetryPacket? _lastTelemetry;
  TelemetryPacket? get lastTelemetry => _lastTelemetry;

  // Streams for real-time data
  final _telemetryController = StreamController<TelemetryPacket>.broadcast();
  Stream<TelemetryPacket> get telemetryStream => _telemetryController.stream;

  final _obstacleController = StreamController<ObstacleAlert>.broadcast();
  Stream<ObstacleAlert> get obstacleStream => _obstacleController.stream;

  final _instantTextController = StreamController<String>.broadcast();
  Stream<String> get instantTextStream => _instantTextController.stream;

  // ---------------------------------------------------------------------------
  // Scan & Connect
  // ---------------------------------------------------------------------------

  /// Start scanning for iCan devices.
  Future<void> startScan() async {
    _setState(BleConnectionState.scanning);
    // TODO: Implement with flutter_reactive_ble
    // - Scan for devices advertising ICAN_CANE_SERVICE_UUID or ICAN_EYE_SERVICE_UUID
    // - Store discovered device IDs
    debugPrint('[BLE] Scanning for iCan devices...');
  }

  /// Connect to a discovered iCan Cane device.
  Future<void> connectToCane(String deviceId) async {
    _setState(BleConnectionState.connecting);
    // TODO: Implement connection and characteristic subscription
    // - Connect to deviceId
    // - Subscribe to CHAR_OBSTACLE_ALERT_TX → parse → _obstacleController
    // - Subscribe to CHAR_IMU_TELEMETRY_TX → parse → _telemetryController
    debugPrint('[BLE] Connecting to Cane: $deviceId');
    _setState(BleConnectionState.connected);
  }

  /// Connect to a discovered iCan Eye device.
  Future<void> connectToEye(String deviceId) async {
    // TODO: Subscribe to CHAR_EYE_INSTANT_TEXT_TX → _instantTextController
    // TODO: Subscribe to CHAR_EYE_IMAGE_STREAM_TX → reassemble JPEG
    debugPrint('[BLE] Connecting to Eye: $deviceId');
  }

  // ---------------------------------------------------------------------------
  // Write Commands
  // ---------------------------------------------------------------------------

  /// Send a navigation command to the cane.
  Future<void> sendNavCommand(NavCommand command) async {
    if (_state != BleConnectionState.connected) return;
    // TODO: Write command.opcode to CHAR_NAV_COMMAND_RX
    debugPrint(
      '[BLE] Sending nav command: ${command.name} (0x${command.opcode.toRadixString(16)})',
    );
  }

  /// Remotely trigger image capture on the Eye.
  Future<void> triggerEyeCapture() async {
    // TODO: Write 0x01 to CHAR_EYE_CAPTURE_RX
    debugPrint('[BLE] Triggering Eye capture.');
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _setState(BleConnectionState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Parse raw telemetry bytes from BLE notification.
  /// Called by the BLE subscription callback when data arrives.
  void onTelemetryReceived(Uint8List data) {
    try {
      final pkt = TelemetryPacket.fromBytes(data);
      _lastTelemetry = pkt;
      _telemetryController.add(pkt);
      notifyListeners();
    } catch (e) {
      debugPrint('[BLE] Telemetry parse error: $e');
    }
  }

  @override
  void dispose() {
    _telemetryController.close();
    _obstacleController.close();
    _instantTextController.close();
    super.dispose();
  }
}

/// Simple obstacle alert data class.
class ObstacleAlert {
  final ObstacleSide side;
  final int distanceCm;

  const ObstacleAlert({required this.side, required this.distanceCm});

  factory ObstacleAlert.fromBytes(Uint8List data) {
    if (data.length < 3) throw ArgumentError('Obstacle alert must be 3 bytes');
    return ObstacleAlert(
      side: ObstacleSide.fromCode(data[0]),
      distanceCm: data[1] | (data[2] << 8),
    );
  }
}

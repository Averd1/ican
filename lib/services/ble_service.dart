import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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

  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  BluetoothCharacteristic? _navRxChar;
  BluetoothCharacteristic? _eyeCaptureRxChar;

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
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      debugPrint('[BLE] Bluetooth is not turned on.');
      return;
    }

    _setState(BleConnectionState.scanning);
    debugPrint('[BLE] Scanning for iCan devices...');

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == 'iCan Cane') {
          FlutterBluePlus.stopScan();
          connectToCane(r.device);
          break;
        } else if (r.device.platformName == 'iCan Eye') {
          // Connect to Eye if preferred
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(BleServices.caneServiceUuid)],
      timeout: const Duration(seconds: 15),
    );

    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  /// Connect to a discovered iCan Cane device.
  Future<void> connectToCane(BluetoothDevice device) async {
    _setState(BleConnectionState.connecting);
    debugPrint('[BLE] Connecting to Cane: ${device.remoteId}');

    try {
      await device.connect(autoConnect: false);
      _connectedDevice = device;

      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _setState(BleConnectionState.disconnected);
          _connectedDevice = null;
        }
      });

      _setState(BleConnectionState.connected);
      await _discoverCaneServices(device);
    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
      _setState(BleConnectionState.disconnected);
    }
  }

  Future<void> _discoverCaneServices(BluetoothDevice device) async {
    final List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == Guid(BleServices.caneServiceUuid)) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          // Nav RX
          if (characteristic.uuid == Guid(BleCharacteristics.navCommandRx)) {
            _navRxChar = characteristic;
          }
          // Obstacle TX (Notify)
          else if (characteristic.uuid == Guid(BleCharacteristics.obstacleAlertTx)) {
            await characteristic.setNotifyValue(true);
            characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                try {
                  final alert = ObstacleAlert.fromBytes(Uint8List.fromList(value));
                  _obstacleController.add(alert);
                } catch (e) {
                  debugPrint('[BLE] Obstacle parse error: $e');
                }
              }
            });
          }
          // Telemetry TX (Notify)
          else if (characteristic.uuid == Guid(BleCharacteristics.imuTelemetryTx)) {
            await characteristic.setNotifyValue(true);
            characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                onTelemetryReceived(Uint8List.fromList(value));
              }
            });
          }
        }
      }
    }
  }

  /// Connect to a discovered iCan Eye device.
  Future<void> connectToEye(BluetoothDevice device) async {
    debugPrint('[BLE] Connecting to Eye: ${device.remoteId}');
    // Implementation for connecting to Eye and discovering its custom services
  }

  // ---------------------------------------------------------------------------
  // Write Commands
  // ---------------------------------------------------------------------------

  /// Send a navigation command to the cane.
  Future<void> sendNavCommand(NavCommand command) async {
    if (_state != BleConnectionState.connected || _navRxChar == null) return;

    debugPrint(
      '[BLE] Sending nav command: ${command.name} (0x${command.opcode.toRadixString(16)})',
    );
    await _navRxChar!.write([command.opcode], withoutResponse: true);
  }

  /// Remotely trigger image capture on the Eye.
  Future<void> triggerEyeCapture() async {
    if (_state != BleConnectionState.connected || _eyeCaptureRxChar == null) {
      return;
    }
    debugPrint('[BLE] Triggering Eye capture.');
    await _eyeCaptureRxChar!.write([0x01], withoutResponse: true);
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
      // In complete app, handle properly. Can ignore partial packets silently here.
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _connectedDevice?.disconnect();
    _telemetryController.close();
    _obstacleController.close();
    _instantTextController.close();
    super.dispose();
  }
}

/// Simple obstacle alert data class.
class ObstacleAlert {
  const ObstacleAlert({required this.side, required this.distanceCm});

  factory ObstacleAlert.fromBytes(Uint8List data) {
    if (data.length < 3) throw ArgumentError('Obstacle alert must be 3 bytes');
    return ObstacleAlert(
      side: ObstacleSide.fromCode(data[0]),
      distanceCm: data[1] | (data[2] << 8),
    );
  }
  final ObstacleSide side;
  final int distanceCm;
}

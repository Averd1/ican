import 'dart:async';
import 'package:flutter/material.dart';
import '../protocol/ble_protocol.dart';
import '../services/ble_service.dart';

/// GPS Monitor Screen — displays live GPS data streamed from the iCan Cane.
///
/// Connects to [BleService.gpsDataStream] for 1 Hz position updates.
/// Shows fix status, coordinates, altitude, speed, and satellite count.
class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  GpsPacket? _latest;
  DateTime? _lastUpdated;
  StreamSubscription<GpsPacket>? _gpsSub;

  @override
  void initState() {
    super.initState();
    BleService.instance.addListener(_onBleStateChanged);

    // Seed with last known value so UI isn't blank if data already arrived
    _latest = BleService.instance.lastGps;

    _gpsSub = BleService.instance.gpsDataStream.listen((pkt) {
      if (mounted) {
        setState(() {
          _latest = pkt;
          _lastUpdated = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    BleService.instance.removeListener(_onBleStateChanged);
    super.dispose();
  }

  void _onBleStateChanged() => setState(() {});

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatCoord(double deg, bool isLat) {
    final direction = isLat ? (deg >= 0 ? 'N' : 'S') : (deg >= 0 ? 'E' : 'W');
    return '${deg.abs().toStringAsFixed(6)}° $direction';
  }

  String _caneStatusText() {
    switch (BleService.instance.caneState) {
      case BleConnectionState.connected:
        return 'Connected to iCan Cane';
      case BleConnectionState.connecting:
        return 'Connecting...';
      case BleConnectionState.scanning:
        return 'Scanning...';
      case BleConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  Color _caneStatusColor(ThemeData theme) {
    switch (BleService.instance.caneState) {
      case BleConnectionState.connected:
        return Colors.green;
      case BleConnectionState.connecting:
      case BleConnectionState.scanning:
        return theme.colorScheme.secondary;
      case BleConnectionState.disconnected:
        return theme.colorScheme.error;
    }
  }

  String _fixQualityLabel(int quality) {
    switch (quality) {
      case 1:
        return 'GPS Fix';
      case 2:
        return 'DGPS Fix';
      default:
        return 'No Fix';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFix = _latest?.fixValid == true;
    final isConnected =
        BleService.instance.caneState == BleConnectionState.connected;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'GPS Monitor',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Connection Card ---
              _buildCard(
                theme,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _caneStatusColor(theme).withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.bluetooth_rounded,
                        color: _caneStatusColor(theme),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'iCan Cane',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(153),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _caneStatusText(),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _caneStatusColor(theme),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isConnected)
                      TextButton(
                        onPressed: () => BleService.instance.startScanForCane(),
                        child: const Text('Scan'),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // --- Fix Status Card ---
              Semantics(
                liveRegion: true,
                label: hasFix
                    ? 'GPS fix acquired, ${_latest!.satellites} satellites'
                    : 'Searching for GPS satellites',
                child: _buildCard(
                  theme,
                  child: Column(
                    children: [
                      Icon(
                        hasFix
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_not_fixed_rounded,
                        size: 56,
                        color: hasFix
                            ? Colors.green
                            : theme.colorScheme.onSurface.withAlpha(100),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasFix
                            ? 'GPS Fix Acquired'
                            : 'Searching for satellites...',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: hasFix
                              ? Colors.green
                              : theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.satellite_alt_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurface.withAlpha(180),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_latest?.satellites ?? '--'} satellites in view',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(180),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_latest != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: hasFix
                                    ? Colors.green.withAlpha(30)
                                    : theme.colorScheme.error.withAlpha(30),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _fixQualityLabel(_latest!.fixQuality),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: hasFix
                                      ? Colors.green
                                      : theme.colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- Coordinates Card ---
              _buildCard(
                theme,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(
                      theme,
                      Icons.location_on_rounded,
                      'Coordinates',
                    ),
                    const SizedBox(height: 16),
                    _coordRow(
                      theme,
                      label: 'Latitude',
                      value: (hasFix && _latest != null)
                          ? _formatCoord(_latest!.latitude, true)
                          : '--',
                    ),
                    const Divider(height: 24),
                    _coordRow(
                      theme,
                      label: 'Longitude',
                      value: (hasFix && _latest != null)
                          ? _formatCoord(_latest!.longitude, false)
                          : '--',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // --- Altitude & Speed Row ---
              Row(
                children: [
                  Expanded(
                    child: _buildCard(
                      theme,
                      child: Column(
                        children: [
                          _sectionLabel(
                            theme,
                            Icons.terrain_rounded,
                            'Altitude',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            (hasFix && _latest != null)
                                ? '${_latest!.altitudeM.toStringAsFixed(1)} m'
                                : '--',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCard(
                      theme,
                      child: Column(
                        children: [
                          _sectionLabel(theme, Icons.speed_rounded, 'Speed'),
                          const SizedBox(height: 12),
                          Text(
                            (hasFix && _latest != null)
                                ? '${_latest!.speedKnots.toStringAsFixed(1)} kts'
                                : '--',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // --- Last updated ---
              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    'Last updated: ${_lastUpdated!.toLocal().toString().substring(11, 19)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(100),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-widgets
  // ---------------------------------------------------------------------------

  Widget _buildCard(ThemeData theme, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.onSurface.withAlpha(13),
          width: 1,
        ),
      ),
      child: child,
    );
  }

  Widget _sectionLabel(ThemeData theme, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(180),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _coordRow(
    ThemeData theme, {
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(153),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/app_router.dart';
import '../core/theme.dart';
import '../protocol/ble_protocol.dart';
import '../services/ble_service.dart';
import '../services/notification_service.dart';

class CaretakerDashboardScreen extends StatefulWidget {
  const CaretakerDashboardScreen({super.key});

  @override
  State<CaretakerDashboardScreen> createState() =>
      _CaretakerDashboardScreenState();
}

class _CaretakerDashboardScreenState extends State<CaretakerDashboardScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<TelemetryPacket>? _telemetrySub;

  TelemetryPacket? _latest;
  bool _fallAcknowledged = false;
  DateTime? _fallTime;
  bool _fallDialogShown = false;

  // Heartbeat animation
  late final AnimationController _heartController;
  late final Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();

    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.easeOut),
    );

    _telemetrySub = BleService.instance.telemetryStream.listen(_onTelemetry);

    debugPrint('[Caretaker] Dashboard started, listening to telemetry stream.');
  }

  void _onTelemetry(TelemetryPacket pkt) {
    setState(() {
      _latest = pkt;
    });

    // Animate heartbeat on each valid pulse packet
    if (pkt.pulseValid) {
      _heartController.forward(from: 0);
    }

    // Show fall alert modal on first detection (rising edge)
    if (pkt.fallDetected && !_fallAcknowledged) {
      if (_fallTime == null) {
        setState(() {
          _fallTime = DateTime.now();
        });
        _showFallDialog();
      }
    }

    // Reset acknowledged state when firmware clears the fall flag
    if (!pkt.fallDetected && _fallAcknowledged) {
      setState(() {
        _fallAcknowledged = false;
        _fallTime = null;
        _fallDialogShown = false;
      });
    }
  }

  void _showFallDialog() {
    if (_fallDialogShown) return;
    _fallDialogShown = true;
    // Wait one frame so the widget tree is stable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: ICanTheme.surfaceCard,
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 8),
              Text('Fall Detected',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'iCan Cane has detected a fall event.\n\nCheck on the user immediately.',
            style: TextStyle(color: ICanTheme.textPrimary, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _acknowledgeFall();
              },
              child: const Text('Acknowledge',
                  style: TextStyle(
                      color: ICanTheme.accentOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ],
        ),
      );
    });
  }

  void _acknowledgeFall() {
    setState(() {
      _fallAcknowledged = true;
    });
    NotificationService.cancelFallAlert();
    debugPrint('[Caretaker] Fall alert acknowledged by caretaker.');
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _heartController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool get _caneConnected =>
      BleService.instance.caneState == BleConnectionState.connected;

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // Heart rate status label + color
  String _hrLabel(int bpm) {
    if (bpm < 40) return 'Too Low';
    if (bpm < 60) return 'Low';
    if (bpm <= 100) return 'Normal';
    if (bpm <= 140) return 'Elevated';
    return 'Too High';
  }

  Color _hrColor(int bpm) {
    if (bpm < 40 || bpm > 140) return ICanTheme.error;
    if (bpm < 60 || bpm > 100) return ICanTheme.accentOrange;
    return ICanTheme.success;
  }

  // BPM as fraction 0–1 mapped to a 40–180 range for the range bar
  double _hrFraction(int bpm) => ((bpm - 40) / (180 - 40)).clamp(0.0, 1.0);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasFall =
        (_latest?.fallDetected ?? false) && !_fallAcknowledged;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Caretaker Dashboard'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () =>
              Navigator.pushReplacementNamed(context, AppRouter.roleSelection),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _ConnectionCard(connected: _caneConnected),
            const SizedBox(height: 12),
            _HeartRateCard(
              pkt: _latest,
              heartScale: _heartScale,
              hrLabel: _hrLabel,
              hrColor: _hrColor,
              hrFraction: _hrFraction,
            ),
            const SizedBox(height: 12),
            _BatteryCard(pkt: _latest),
            const SizedBox(height: 12),
            _FallAlertCard(
              hasFall: hasFall,
              fallTime: _fallTime,
              onAcknowledge: _acknowledgeFall,
            ),
            const SizedBox(height: 24),
            // Debug info strip
            if (_latest != null)
              _DebugStrip(pkt: _latest!),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _DashCard extends StatelessWidget {
  const _DashCard({required this.child, this.borderColor});
  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ICanTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1.5)
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: child,
    );
  }
}

// --- Connection Status ---
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? ICanTheme.success : ICanTheme.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connected ? 'iCan Cane Connected' : 'iCan Cane Not Connected',
              style: const TextStyle(
                  color: ICanTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: connected ? ICanTheme.success : ICanTheme.textSecondary,
            size: 22,
          ),
        ],
      ),
    );
  }
}

// --- Heart Rate ---
class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({
    required this.pkt,
    required this.heartScale,
    required this.hrLabel,
    required this.hrColor,
    required this.hrFraction,
  });

  final TelemetryPacket? pkt;
  final Animation<double> heartScale;
  final String Function(int) hrLabel;
  final Color Function(int) hrColor;
  final double Function(int) hrFraction;

  @override
  Widget build(BuildContext context) {
    final bool valid = pkt?.pulseValid ?? false;
    final int bpm = pkt?.pulseBpm ?? 0;
    final Color color = valid ? hrColor(bpm) : ICanTheme.textSecondary;

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ScaleTransition(
                scale: heartScale,
                child: Icon(Icons.favorite_rounded, color: color, size: 22),
              ),
              const SizedBox(width: 8),
              const Text('Heart Rate',
                  style: TextStyle(
                      color: ICanTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                valid ? '$bpm' : '--',
                style: TextStyle(
                  color: color,
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  valid ? 'BPM' : 'No Signal',
                  style: const TextStyle(
                      color: ICanTheme.textSecondary, fontSize: 16),
                ),
              ),
              const Spacer(),
              if (valid)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withAlpha(38),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hrLabel(bpm),
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          if (valid) ...[
            const SizedBox(height: 12),
            _HrRangeBar(fraction: hrFraction(bpm), color: color),
          ],
        ],
      ),
    );
  }
}

class _HrRangeBar extends StatelessWidget {
  const _HrRangeBar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      return Stack(
        children: [
          // Background track
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // Filled portion
          Container(
            height: 6,
            width: constraints.maxWidth * fraction,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // Normal zone markers (60–100 BPM = 31%–42% of 40–180 range)
          Positioned(
            left: constraints.maxWidth * 0.148, // 60 BPM
            child: Container(width: 2, height: 6, color: Colors.white24),
          ),
          Positioned(
            left: constraints.maxWidth * 0.429, // 100 BPM
            child: Container(width: 2, height: 6, color: Colors.white24),
          ),
        ],
      );
    });
  }
}

// --- Battery ---
class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.pkt});
  final TelemetryPacket? pkt;

  @override
  Widget build(BuildContext context) {
    final int pct = pkt?.batteryPercent ?? 0;
    final bool hasData = pkt != null;
    final Color barColor = pct <= 20
        ? ICanTheme.error
        : pct <= 40
            ? ICanTheme.accentOrange
            : ICanTheme.success;

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pct <= 20
                    ? Icons.battery_alert_rounded
                    : pct <= 50
                        ? Icons.battery_4_bar_rounded
                        : Icons.battery_full_rounded,
                color: barColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text('Battery',
                  style: TextStyle(
                      color: ICanTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(
                hasData ? '$pct%' : '--',
                style: TextStyle(
                    color: hasData ? ICanTheme.textPrimary : ICanTheme.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: hasData ? pct / 100.0 : 0,
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Fall Alert ---
class _FallAlertCard extends StatelessWidget {
  const _FallAlertCard({
    required this.hasFall,
    required this.fallTime,
    required this.onAcknowledge,
  });

  final bool hasFall;
  final DateTime? fallTime;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    if (!hasFall) {
      return _DashCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: ICanTheme.success, size: 22),
            const SizedBox(width: 12),
            const Text(
              'No falls detected',
              style: TextStyle(color: ICanTheme.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return _DashCard(
      borderColor: Colors.redAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded,
                  color: Colors.redAccent, size: 24),
              const SizedBox(width: 10),
              const Text(
                'FALL DETECTED',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
              ),
              const Spacer(),
              if (fallTime != null)
                Text(
                  _formatTime(fallTime!),
                  style: const TextStyle(
                      color: ICanTheme.textSecondary, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'iCan Cane has detected a fall event. Check on the user immediately.',
            style: TextStyle(color: ICanTheme.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: onAcknowledge,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                foregroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Acknowledge',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// --- Debug Strip ---
class _DebugStrip extends StatelessWidget {
  const _DebugStrip({required this.pkt});
  final TelemetryPacket pkt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'DEBUG: $pkt',
        style: const TextStyle(
            color: ICanTheme.textSecondary,
            fontSize: 11,
            fontFamily: 'monospace'),
      ),
    );
  }
}

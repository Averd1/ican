// Usage:
//
//   DeviceStatusCard(
//     deviceName: 'iCan Cane',
//     connectionState: deviceState.caneConnection,
//     batteryPercent: deviceState.batteryPercent,
//     onTap: () => _reconnectCane(),
//     tapHint: 'Opens cane connection settings',
//   )
//
//   DeviceStatusCard(
//     deviceName: 'iCan Eye',
//     connectionState: deviceState.eyeConnection,
//     batteryPercent: -1,  // unknown — card hides battery section
//     onTap: () => _reconnectEye(),
//     tapHint: 'Opens camera connection settings',
//   )

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/theme.dart';
import '../services/ble_service.dart';

class DeviceStatusCard extends StatefulWidget {
  final String deviceName;
  final BleConnectionState connectionState;
  final int batteryPercent;
  final VoidCallback onTap;
  final String tapHint;

  const DeviceStatusCard({
    super.key,
    required this.deviceName,
    required this.connectionState,
    required this.batteryPercent,
    required this.onTap,
    required this.tapHint,
  });

  @override
  State<DeviceStatusCard> createState() => _DeviceStatusCardState();
}

class _DeviceStatusCardState extends State<DeviceStatusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ellipsisController;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ellipsisController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ellipsisController.dispose();
    super.dispose();
  }

  bool get _isSearching =>
      widget.connectionState == BleConnectionState.scanning ||
      widget.connectionState == BleConnectionState.connecting;

  bool get _isConnected =>
      widget.connectionState == BleConnectionState.connected;

  bool get _hasBattery => widget.batteryPercent >= 0;

  // ── Semantic label construction ──
  // Reads as a single phrase: "iCan Cane. Status: Connected. Battery: 85%"
  // so VoiceOver / TalkBack delivers all info in one swipe-focus.
  String get _semanticLabel {
    final status = _statusText;
    final battery =
        _hasBattery ? ' Battery: ${widget.batteryPercent} percent.' : '';
    return '${widget.deviceName}. Status: $status.$battery';
  }

  String get _statusText {
    if (_isConnected) return 'Connected';
    if (_isSearching) return 'Searching';
    return 'Disconnected';
  }

  void _handleTapDown(TapDownDetails _) => setState(() => _pressed = true);
  void _handleTapUp(TapUpDetails _) => setState(() => _pressed = false);
  void _handleTapCancel() => setState(() => _pressed = false);

  void _handleTap() {
    HapticFeedback.mediumImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = _pressed
        ? (isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF0F0F0))
        : (isDark ? AppColors.backgroundDark : AppColors.backgroundLight);
    final Color border =
        isDark ? AppColors.borderDark : AppColors.textOnLight;
    final Color focusColor =
        isDark ? AppColors.focusRingOnDark : AppColors.focusRing;

    return Semantics(
      button: true,
      label: _semanticLabel,
      hint: widget.tapHint,
      child: Focus(
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;

          return GestureDetector(
            onTapDown: _handleTapDown,
            onTapUp: _handleTapUp,
            onTapCancel: _handleTapCancel,
            onTap: _handleTap,
            child: AnimatedContainer(
              duration: AppAccessibility.reduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              constraints: const BoxConstraints(minHeight: 80),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused ? focusColor : border,
                  width: focused ? 3 : 1,
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(isDark),
                    const SizedBox(height: AppSpacing.xs),
                    _buildStatusRow(context, isDark),
                    if (_hasBattery) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _buildBatteryRow(isDark),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Text(
      widget.deviceName,
      style: TextStyle(
        fontSize: 20.sp,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textOnDark : AppColors.textOnLight,
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, bool isDark) {
    final Color primaryText =
        isDark ? AppColors.textOnDark : AppColors.textOnLight;

    if (_isConnected) {
      return Row(
        children: [
          // ACCESSIBILITY NOTE: checkmark shape conveys status for users
          // who cannot perceive green; text "Connected" is the primary signal.
          Icon(Icons.check_circle, color: AppColors.success, size: 24),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Connected',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      );
    }

    if (_isSearching) {
      return Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: isDark
                  ? AppColors.interactiveOnDark
                  : AppColors.interactive,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _SearchingText(
            controller: _ellipsisController,
            color: primaryText,
            reduceMotion: AppAccessibility.reduceMotion(context),
          ),
        ],
      );
    }

    // Disconnected
    return Row(
      children: [
        // ACCESSIBILITY NOTE: X-circle shape conveys status for users
        // who cannot perceive red; text "Disconnected" is the primary signal.
        Icon(Icons.cancel, color: AppColors.error, size: 24),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Disconnected',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.error,
          ),
        ),
      ],
    );
  }

  Widget _buildBatteryRow(bool isDark) {
    final percent = widget.batteryPercent.clamp(0, 100);
    final Color barFill = _batteryColor(percent);
    final Color barTrack = isDark ? AppColors.borderDark : AppColors.borderLight;
    final Color text =
        isDark ? AppColors.textSecondaryOnDark : AppColors.textSecondaryOnLight;

    return Row(
      children: [
        Text(
          'Battery: $percent%',
          style: TextStyle(fontSize: 16.sp, color: text),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: barTrack,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: percent / 100,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: barFill,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Color _batteryColor(int percent) {
    if (percent <= 15) return AppColors.error;
    if (percent <= 30) return AppColors.warning;
    return AppColors.success;
  }
}

/// Animated "Searching..." text that cycles dots 0→3.
/// When reduceMotion is true, renders static "Searching..." with no animation.
class _SearchingText extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  final bool reduceMotion;

  const _SearchingText({
    required this.controller,
    required this.color,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return Text(
        'Searching...',
        style: TextStyle(
          fontSize: 18.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final dotCount = (controller.value * 4).floor() % 4;
        final dots = '.' * dotCount;
        return Text(
          'Searching$dots',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        );
      },
    );
  }
}

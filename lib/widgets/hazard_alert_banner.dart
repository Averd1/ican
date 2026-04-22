// Usage — as an overlay at the top of a screen:
//
//   // In a StatefulWidget that listens to BleService.instance.obstacleStream:
//   StreamSubscription<ObstacleAlert>? _obstacleSub;
//   final GlobalKey<HazardAlertBannerState> _alertKey = GlobalKey();
//
//   @override
//   void initState() {
//     super.initState();
//     _obstacleSub = BleService.instance.obstacleStream.listen((alert) {
//       _alertKey.currentState?.show(
//         side: alert.side,
//         distanceCm: alert.distanceCm,
//       );
//     });
//   }
//
//   // In build():
//   Stack(
//     children: [
//       // ... screen content ...
//       Positioned(
//         top: MediaQuery.of(context).padding.top,
//         left: 0,
//         right: 0,
//         child: HazardAlertBanner(
//           key: _alertKey,
//           onDismissed: () => debugPrint('Alert dismissed'),
//         ),
//       ),
//     ],
//   )
//
// Direct show with custom text:
//
//   _alertKey.currentState?.showCustom('Fall detected — requesting help');

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/theme.dart';
import '../protocol/ble_protocol.dart';

class HazardAlertBanner extends StatefulWidget {
  final VoidCallback? onDismissed;

  const HazardAlertBanner({
    super.key,
    this.onDismissed,
  });

  @override
  State<HazardAlertBanner> createState() => HazardAlertBannerState();
}

class HazardAlertBannerState extends State<HazardAlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;

  String _alertText = '';
  bool _visible = false;

  // Screen reader auto-dismiss guard: when VoiceOver / TalkBack is active
  // the timer extends to 10s so the announcement has time to be read.
  static const _defaultDuration = Duration(seconds: 5);
  static const _accessibilityDuration = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  /// Show an obstacle alert from cane sensor data.
  void show({required ObstacleSide side, required int distanceCm}) {
    final direction = _directionLabel(side);
    final distance = _distanceLabel(distanceCm);
    showCustom('Obstacle $direction — $distance');
  }

  /// Show a custom alert string (e.g. fall detection, drop-off).
  void showCustom(String text) {
    _autoDismissTimer?.cancel();

    setState(() {
      _alertText = text;
      _visible = true;
    });

    HapticFeedback.vibrate();

    // reduceMotion: skip animation, appear instantly
    if (_isReduceMotion) {
      _slideController.value = 1.0;
    } else {
      _slideController.forward(from: 0);
    }

    SemanticsService.announce(_alertText, TextDirection.ltr);

    _startAutoDismiss();
  }

  void _startAutoDismiss() {
    _autoDismissTimer?.cancel();

    final duration = _isAccessibilityActive
        ? _accessibilityDuration
        : _defaultDuration;

    _autoDismissTimer = Timer(duration, dismiss);
  }

  /// Dismiss the banner. Safe to call when already hidden.
  void dismiss() {
    _autoDismissTimer?.cancel();
    if (!_visible) return;

    if (_isReduceMotion) {
      _slideController.value = 0;
      _onDismissComplete();
    } else {
      _slideController.reverse().then((_) => _onDismissComplete());
    }
  }

  void _onDismissComplete() {
    if (!mounted) return;
    setState(() => _visible = false);
    widget.onDismissed?.call();
  }

  bool get _isReduceMotion =>
      AppAccessibility.reduceMotion(context);

  bool get _isAccessibilityActive =>
      MediaQuery.of(context).accessibleNavigation;

  String _directionLabel(ObstacleSide side) {
    switch (side) {
      case ObstacleSide.left:
        return 'to your left';
      case ObstacleSide.right:
        return 'to your right';
      case ObstacleSide.head:
        return 'above';
      case ObstacleSide.front:
        return 'ahead';
      case ObstacleSide.none:
        return 'nearby';
    }
  }

  String _distanceLabel(int cm) {
    if (cm < 30) return 'very close';
    if (cm < 100) {
      final feet = (cm / 30.48).round();
      return feet <= 1 ? '1 foot away' : '$feet feet away';
    }
    final meters = (cm / 100).round();
    return meters <= 1 ? '1 meter away' : '$meters meters away';
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final banner = SlideTransition(
      position: _slideAnimation,
      child: Semantics(
        liveRegion: true,
        label: _alertText,
        hint: 'Tap to dismiss alert',
        child: GestureDetector(
          onTap: dismiss,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 80),
            decoration: BoxDecoration(
              color: AppColors.backgroundDark,
              border: Border.all(
                color: const Color(0xFFCC0000),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: const Color(0xFFCC0000),
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hazard Alert',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFCC0000),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _alertText,
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textOnDark,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _DismissButton(onTap: dismiss),
              ],
            ),
          ),
        ),
      ),
    );

    return banner;
  }
}

class _DismissButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DismissButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Dismiss alert',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textOnDark, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'X',
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

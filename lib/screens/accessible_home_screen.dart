import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/home_view_model.dart';
import '../services/ble_service.dart';
import '../services/device_prefs_service.dart';
import '../widgets/accessible_button.dart';
import '../widgets/device_status_card.dart';
import '../widgets/hazard_alert_banner.dart';

class AccessibleHomeScreen extends StatefulWidget {
  const AccessibleHomeScreen({super.key});

  @override
  State<AccessibleHomeScreen> createState() => _AccessibleHomeScreenState();
}

class _AccessibleHomeScreenState extends State<AccessibleHomeScreen> {
  final GlobalKey<HazardAlertBannerState> _alertKey = GlobalKey();
  StreamSubscription<ObstacleAlert>? _obstacleSub;

  @override
  void initState() {
    super.initState();

    _obstacleSub = BleService.instance.obstacleStream.listen((alert) {
      _alertKey.currentState?.show(
        side: alert.side,
        distanceCm: alert.distanceCm,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SemanticsService.announce('Home screen', TextDirection.ltr);
      // If we arrive at home still disconnected (e.g. after first-time pairing
      // flow or a cold launch where BLE wasn't ready), kick off a fresh connect.
      _retryBleIfNeeded();
    });
  }

  Future<void> _retryBleIfNeeded() async {
    if (BleService.instance.state != BleConnectionState.disconnected) return;
    final savedId = await DevicePrefsService.instance.getLastDeviceId();
    if (savedId == null || savedId.isEmpty) return;
    BleService.instance.connectToEyeByMac(savedId);
  }

  @override
  void dispose() {
    _obstacleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          SafeArea(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Screen title (visually hidden, semantics heading)
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: Semantics(
                        header: true,
                        label: 'iCan Home',
                        child: const SizedBox.shrink(),
                      ),
                    ),

                    // 1. Device status cards
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: _buildStatusSection(vm),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // 2. Live description area
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: _buildDescriptionArea(vm),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // 3. Context-sensitive actions
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: _buildActions(vm),
                    ),

                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),

          // Hazard alert overlay
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            child: HazardAlertBanner(key: _alertKey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(HomeViewModel vm) {
    return Column(
      children: [
        DeviceStatusCard(
          deviceName: 'iCan Eye',
          connectionState: vm.eyeConnection,
          batteryPercent: -1,
          onTap: () => vm.startScanForEye(),
          tapHint: 'Scans for iCan Eye camera over Bluetooth',
        ),
        const SizedBox(height: AppSpacing.xs),
        DeviceStatusCard(
          deviceName: 'iCan Cane',
          connectionState: vm.caneConnection,
          batteryPercent: vm.batteryPercent,
          onTap: () => vm.startScanForCane(),
          tapHint: 'Scans for iCan Cane over Bluetooth',
        ),
      ],
    );
  }

  Widget _buildDescriptionArea(HomeViewModel vm) {
    final bool hasDescription = vm.lastDescription.isNotEmpty;
    final String displayText = hasDescription
        ? vm.lastDescription
        : 'Waiting for scene description…';

    final String semanticText = vm.isProcessing
        ? 'Processing image. Please wait.'
        : hasDescription
            ? vm.lastDescription
            : 'No scene description yet. Tap Describe surroundings to start.';

    return Semantics(
      liveRegion: true,
      label: semanticText,
      child: GestureDetector(
        onTap: () {
          if (hasDescription) {
            HapticFeedback.lightImpact();
            vm.repeatLast();
          }
        },
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 160),
          decoration: BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.textOnLight,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Scene Description',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOnLight,
                      ),
                    ),
                    if (vm.isProcessing) ...[
                      const SizedBox(width: AppSpacing.xs),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.interactive,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight:
                        hasDescription ? FontWeight.normal : FontWeight.w300,
                    color: hasDescription
                        ? AppColors.textOnLight
                        : AppColors.disabledOnLight,
                    fontStyle:
                        hasDescription ? FontStyle.normal : FontStyle.italic,
                    height: 1.5,
                  ),
                ),
                if (hasDescription) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Tap to hear again',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.interactive,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(HomeViewModel vm) {
    final widgets = <Widget>[];

    // "Describe Surroundings Now" — only when Eye is connected
    if (vm.isEyeConnected) {
      widgets.add(
        AccessibleButton(
          label: vm.isProcessing ? 'Describing…' : 'Describe Surroundings Now',
          hint:
              'Takes a photo with the camera and describes what is around you',
          onPressed: vm.canDescribe ? () => vm.describeNow() : null,
          subtitle: vm.isProcessing ? 'Processing…' : null,
        ),
      );
    }

    // "Repeat Last" — only when there's a description to repeat
    if (vm.lastDescription.isNotEmpty) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: AppSpacing.md));
      widgets.add(
        AccessibleButton(
          label: 'Repeat Last Description',
          hint: 'Reads the last scene description aloud again',
          onPressed: () => vm.repeatLast(),
        ),
      );
    }

    // "Pause/Resume" — only when a device is connected
    if (vm.hasAnyDevice) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: AppSpacing.md));
      widgets.add(
        AccessibleButton(
          label: vm.isPaused ? 'Resume Descriptions' : 'Pause Descriptions',
          hint: vm.isPaused
              ? 'Resumes automatic scene descriptions from camera'
              : 'Pauses all automatic scene descriptions',
          onPressed: () {
            if (vm.isPaused) {
              vm.resumeDescriptions();
            } else {
              vm.pauseDescriptions();
            }
          },
        ),
      );
    }

    // "Start Live Detection" — only when Eye is connected
    if (vm.isEyeConnected) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: AppSpacing.md));
      widgets.add(
        AccessibleButton(
          label: 'Start Live Detection',
          hint: 'Continuously announces objects the Eye sees with audio',
          onPressed: () => context.pushNamed('live-detection'),
        ),
      );
    }

    // Empty state — no devices connected
    if (widgets.isEmpty) {
      return Semantics(
        label: 'Connect a device to get started. Tap a device card above.',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceCardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: ExcludeSemantics(
            child: Text(
              'Connect a device to get started.\nTap a device card above to scan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18.sp,
                color: AppColors.textSecondaryOnLight,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }

    return Column(children: widgets);
  }
}

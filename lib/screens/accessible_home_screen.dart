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
      SemanticsService.announce(
        'Home screen. Camera and cane active.',
        TextDirection.ltr,
      );
      final vm = context.read<HomeViewModel>();
      vm.ttsService.speak('Home screen. Camera and cane active.');
    });
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
          // ── Main content ──
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
                    // ── Screen title (visually hidden, semantics heading) ──
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: Semantics(
                        header: true,
                        label: 'iCan Home',
                        child: const SizedBox.shrink(),
                      ),
                    ),

                    // ── 1. Device status cards ──
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: _buildStatusSection(vm),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 2. Live description area ──
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: _buildDescriptionArea(vm),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 3. Primary actions ──
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: _buildActions(vm),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 4. Quick settings ──
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: _buildSettings(vm),
                    ),

                    // ── 5. Navigation shortcut ──
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(5),
                      child: Padding(
                        padding:
                            const EdgeInsets.only(top: AppSpacing.md),
                        child: AccessibleButton(
                          label: 'Open Navigation',
                          hint: 'Opens turn-by-turn walking directions',
                          onPressed: () =>
                                  context.pushNamed('nav'),
                        ),
                      ),
                    ),

                    // ── 6. Live Detection shortcut ──
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(6),
                      child: Padding(
                        padding:
                            const EdgeInsets.only(top: AppSpacing.md),
                        child: AccessibleButton(
                          label: 'Start Live Detection',
                          hint:
                              'Continuously announces objects the Eye sees with audio',
                          onPressed: () =>
                                  context.pushNamed('live-detection'),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),

          // ── Hazard alert overlay ──
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

  // ═══════════════════════════════════════════════════════════════════════════
  // Section 1 — Device status
  // ═══════════════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════════════
  // Section 2 — Live description
  // ═══════════════════════════════════════════════════════════════════════════

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
                        fontSize: 14.sp * vm.fontScale.value,
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
                    fontSize: 18.sp * vm.fontScale.value,
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
                      fontSize: 13.sp * vm.fontScale.value,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // Section 3 — Primary actions
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActions(HomeViewModel vm) {
    return Column(
      children: [
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
        const SizedBox(height: AppSpacing.md),
        AccessibleButton(
          label: 'Repeat Last',
          hint: 'Reads the last scene description aloud again',
          onPressed: vm.lastDescription.isNotEmpty ? () => vm.repeatLast() : null,
        ),
        const SizedBox(height: AppSpacing.md),
        AccessibleButton(
          label: 'Describe Surroundings Now',
          hint:
              'Takes a photo with the camera and describes what is around you',
          onPressed: vm.canDescribe ? () => vm.describeNow() : null,
          subtitle: !vm.isEyeConnected
              ? 'Camera not connected'
              : vm.isProcessing
                  ? 'Processing…'
                  : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Section 4 — Quick settings
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSettings(HomeViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Font size toggle ──
        Semantics(
          label:
              'Text size. Current: ${vm.fontScale.label}',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceCardLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    'Text Size',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnLight,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<FontScale>(
                    segments: FontScale.values
                        .map((s) => ButtonSegment<FontScale>(
                              value: s,
                              label: Text(s.label),
                            ))
                        .toList(),
                    selected: {vm.fontScale},
                    onSelectionChanged: (selected) {
                      HapticFeedback.selectionClick();
                      vm.setFontScale(selected.first);
                    },
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(
                          Size(0, 48)),
                      foregroundColor: WidgetStatePropertyAll(
                          AppColors.textOnLight),
                      textStyle: WidgetStatePropertyAll(TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      )),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Speech rate slider ──
        Semantics(
          label:
              'Speech rate. ${(vm.ttsService.rate * 100).round()} percent',
          slider: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceCardLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    'Speech Rate',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnLight,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ExcludeSemantics(
                  child: Row(
                    children: [
                      Text(
                        'Slow',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.textSecondaryOnLight,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: AppColors.interactive,
                            inactiveTrackColor: AppColors.borderLight,
                            thumbColor: AppColors.interactive,
                            overlayColor:
                                AppColors.interactive.withAlpha(40),
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 14),
                            trackHeight: 6,
                          ),
                          child: Slider(
                            value: vm.ttsService.rate,
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            onChanged: (value) {
                              HapticFeedback.selectionClick();
                              vm.ttsService.setRate(value);
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                      Text(
                        'Fast',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.textSecondaryOnLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

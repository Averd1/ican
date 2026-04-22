import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/home_view_model.dart';
import '../models/settings_provider.dart';
import '../services/ble_service.dart';
import '../services/device_prefs_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  VoidCallback? _bleListener;

  @override
  void initState() {
    super.initState();
    _bleListener = () {
      if (mounted) setState(() {});
    };
    BleService.instance.addListener(_bleListener!);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SemanticsService.announce('Settings screen.', TextDirection.ltr);
    });
  }

  @override
  void dispose() {
    if (_bleListener != null) {
      BleService.instance.removeListener(_bleListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: CustomScrollView(
            slivers: [
              // ── Title ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                    0,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textOnLight,
                      ),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: AppSpacing.sm),

                    // ── 1. Audio ──
                    _buildAudioSection(settings),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 2. Descriptions ──
                    _buildDescriptionsSection(settings),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 3. Live Detection ──
                    _buildLiveDetectionSection(settings),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 4. Devices ──
                    _buildDevicesSection(),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 5. Accessibility ──
                    _buildAccessibilitySection(settings),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 6. About ──
                    _buildAboutSection(),
                    const SizedBox(height: AppSpacing.xl),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Audio
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAudioSection(SettingsProvider s) {
    return _Section(
      title: 'Audio',
      children: [
        // ── Speech speed ──
        _SettingTile(
          semanticLabel:
              'Description speed. ${s.wordsPerMinute} words per minute. Adjust with swipe up or down.',
          semanticSlider: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingLabel('Description Speed'),
              const SizedBox(height: 4),
              _SettingValue('${s.wordsPerMinute} words per minute'),
              const SizedBox(height: AppSpacing.xs),
              _AccessibleSlider(
                value: s.speechRate,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  s.setSpeechRate(v);
                },
              ),
              _SliderLabels(left: 'Slower', right: 'Faster'),
            ],
          ),
        ),

        const _Divider(),

        // ── Volume ──
        _SettingTile(
          semanticLabel:
              'Volume. ${(s.volume * 100).round()} percent.',
          semanticSlider: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingLabel('Volume'),
              const SizedBox(height: 4),
              _SettingValue('${(s.volume * 100).round()}%'),
              const SizedBox(height: AppSpacing.xs),
              _AccessibleSlider(
                value: s.volume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  s.setVolume(v);
                },
              ),
              _SliderLabels(left: 'Quiet', right: 'Loud'),
            ],
          ),
        ),

        const _Divider(),

        // ── Voice type ──
        _SettingTile(
          semanticLabel: 'Voice type. Currently ${s.voiceType.label}.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingLabel('Voice Type'),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<VoiceType>(
                  segments: VoiceType.values
                      .map((v) => ButtonSegment<VoiceType>(
                            value: v,
                            label: Text(v.label),
                          ))
                      .toList(),
                  selected: {s.voiceType},
                  onSelectionChanged: (sel) {
                    HapticFeedback.selectionClick();
                    s.setVoiceType(sel.first);
                  },
                  style: _segmentedStyle(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Descriptions
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDescriptionsSection(SettingsProvider s) {
    return _Section(
      title: 'Descriptions',
      children: [
        // ── Detail level ──
        _SettingTile(
          semanticLabel:
              'Detail level. Currently ${s.detailLevel.label}. '
              'Brief gives short summaries. Detailed gives full scene descriptions.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingLabel('Detail Level'),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<DetailLevel>(
                  segments: DetailLevel.values
                      .map((d) => ButtonSegment<DetailLevel>(
                            value: d,
                            label: Text(d.label),
                          ))
                      .toList(),
                  selected: {s.detailLevel},
                  onSelectionChanged: (sel) {
                    HapticFeedback.selectionClick();
                    s.setDetailLevel(sel.first);
                  },
                  style: _segmentedStyle(),
                ),
              ),
            ],
          ),
        ),

        const _Divider(),

        // ── Hazard sensitivity ──
        _SettingTile(
          semanticLabel:
              'Hazard alert sensitivity. Currently ${s.hazardSensitivity.label}. '
              'Low alerts for very close obstacles only. '
              'Medium alerts within arm\'s reach. '
              'High alerts for anything nearby.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingLabel('Hazard Alert Sensitivity'),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<HazardSensitivity>(
                  segments: HazardSensitivity.values
                      .map((h) => ButtonSegment<HazardSensitivity>(
                            value: h,
                            label: Text(h.label),
                          ))
                      .toList(),
                  selected: {s.hazardSensitivity},
                  onSelectionChanged: (sel) {
                    HapticFeedback.selectionClick();
                    s.setHazardSensitivity(sel.first);
                  },
                  style: _segmentedStyle(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. Live Detection
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLiveDetectionSection(SettingsProvider s) {
    return _Section(
      title: 'Live Detection',
      children: [
        _SettingTile(
          semanticLabel:
              'Live detection verbosity. Currently ${s.liveDetectionVerbosity.label}. '
              '${s.liveDetectionVerbosity.description}.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingLabel('Announcement Detail'),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<LiveDetectionVerbosity>(
                  segments: LiveDetectionVerbosity.values
                      .map((v) => ButtonSegment<LiveDetectionVerbosity>(
                            value: v,
                            label: Text(v.label),
                          ))
                      .toList(),
                  selected: {s.liveDetectionVerbosity},
                  onSelectionChanged: (sel) {
                    HapticFeedback.selectionClick();
                    s.setLiveDetectionVerbosity(sel.first);
                  },
                  style: _segmentedStyle(),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.liveDetectionVerbosity.description,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.textSecondaryOnLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Devices
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDevicesSection() {
    final eyeConnected =
        BleService.instance.state == BleConnectionState.connected;
    final caneConnected =
        BleService.instance.caneState == BleConnectionState.connected;

    return _Section(
      title: 'Devices',
      children: [
        _DeviceRow(
          name: 'iCan Eye Camera',
          isConnected: eyeConnected,
          onForget: () => _confirmForgetDevice(
            'iCan Eye Camera',
            () async {
              await BleService.instance.disconnectAndForget();
              if (mounted) {
                HapticFeedback.mediumImpact();
                SemanticsService.announce(
                    'iCan Eye Camera forgotten.', TextDirection.ltr);
                setState(() {});
              }
            },
          ),
          onReconnect: () {
            HapticFeedback.mediumImpact();
            BleService.instance.startScan();
          },
        ),
        const _Divider(),
        _DeviceRow(
          name: 'iCan Cane',
          isConnected: caneConnected,
          onForget: () => _confirmForgetDevice(
            'iCan Cane',
            () async {
              await DevicePrefsService.instance.saveLastCaneDeviceId('');
              if (mounted) {
                HapticFeedback.mediumImpact();
                SemanticsService.announce(
                    'iCan Cane forgotten.', TextDirection.ltr);
                setState(() {});
              }
            },
          ),
          onReconnect: () {
            HapticFeedback.mediumImpact();
            BleService.instance.startScanForCane();
          },
        ),
      ],
    );
  }

  void _confirmForgetDevice(String name, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundLight,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: Semantics(
          header: true,
          child: Text(
            'Forget $name?',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnLight,
            ),
          ),
        ),
        content: Text(
          'This will disconnect and remove $name. '
          'You will need to search for it again to reconnect.',
          style: TextStyle(
            fontSize: 18.sp,
            color: AppColors.textOnLight,
            height: 1.4,
          ),
        ),
        actions: [
          Semantics(
            button: true,
            label: 'Cancel, keep device',
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 56),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOnLight,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Confirm forget $name',
            focusable: true,
            child: TextButton(
              autofocus: true,
              onPressed: () {
                Navigator.pop(ctx);
                onConfirm();
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 56),
              ),
              child: Text(
                'Forget',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Accessibility
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAccessibilitySection(SettingsProvider s) {
    return _Section(
      title: 'Accessibility',
      children: [
        // ── Font size ──
        _SettingTile(
          semanticLabel: 'Text size. Currently ${s.fontScale.label}.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingLabel('Text Size'),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<FontScale>(
                  segments: FontScale.values
                      .map((f) => ButtonSegment<FontScale>(
                            value: f,
                            label: Text(f.label),
                          ))
                      .toList(),
                  selected: {s.fontScale},
                  onSelectionChanged: (sel) {
                    HapticFeedback.selectionClick();
                    s.setFontScale(sel.first);
                  },
                  style: _segmentedStyle(),
                ),
              ),
            ],
          ),
        ),

        const _Divider(),

        // ── High contrast ──
        _SwitchTile(
          label: 'High Contrast',
          semanticLabel: 'High contrast mode. '
              'Currently ${s.highContrast ? "on" : "off"}. '
              '${s.highContrast ? "Using pure black and white for maximum readability." : "Using standard colors."}',
          value: s.highContrast,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            s.setHighContrast(v);
          },
        ),

        const _Divider(),

        // ── Reduce motion ──
        _SwitchTile(
          label: 'Reduce Motion',
          semanticLabel: 'Reduce motion. '
              'Currently ${s.reduceMotion ? "on" : "off"}. '
              '${s.reduceMotion ? "Animations are disabled." : "Animations are enabled."}',
          value: s.reduceMotion,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            s.setReduceMotion(v);
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. About
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAboutSection() {
    return _Section(
      title: 'About',
      children: [
        GestureDetector(
          onLongPress: () {
            HapticFeedback.heavyImpact();
            context.pushNamed('vision-diagnostic');
          },
          child: _SettingTile(
            semanticLabel: 'App version 1.0.0',
            child: Row(
              children: [
                Expanded(child: _SettingLabel('Version')),
                _SettingValue('1.0.0'),
              ],
            ),
          ),
        ),

        const _Divider(),

        _TapTile(
          label: 'Help & Instructions',
          hint: 'Opens help information for using the iCan app',
          onTap: () {
            HapticFeedback.lightImpact();
            context.goNamed('help');
          },
        ),

        const _Divider(),

        _TapTile(
          label: 'Send Feedback',
          hint: 'Opens a way to send feedback to the iCan team',
          onTap: () {
            HapticFeedback.lightImpact();
            // TODO: open feedback flow
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Shared style
  // ═══════════════════════════════════════════════════════════════════════════

  ButtonStyle _segmentedStyle() {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      foregroundColor:
          WidgetStatePropertyAll(AppColors.textOnLight),
      textStyle: WidgetStatePropertyAll(TextStyle(
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnLight,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceCardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Setting tile — generic wrapper with outer Semantics
// ─────────────────────────────────────────────────────────────────────────────

class _SettingTile extends StatelessWidget {
  final String semanticLabel;
  final bool semanticSlider;
  final Widget child;

  const _SettingTile({
    required this.semanticLabel,
    this.semanticSlider = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      slider: semanticSlider,
      child: ExcludeSemantics(child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Switch tile — toggle with full semantic state
// ─────────────────────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnLight,
                    ),
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeColor: AppColors.interactive,
                  inactiveThumbColor: AppColors.disabledOnLight,
                  inactiveTrackColor: AppColors.borderLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tap tile — simple row that navigates or triggers an action
// ─────────────────────────────────────────────────────────────────────────────

class _TapTile extends StatelessWidget {
  final String label;
  final String hint;
  final VoidCallback onTap;

  const _TapTile({
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: hint,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.interactive,
                    ),
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondaryOnLight,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device row
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceRow extends StatelessWidget {
  final String name;
  final bool isConnected;
  final VoidCallback onForget;
  final VoidCallback onReconnect;

  const _DeviceRow({
    required this.name,
    required this.isConnected,
    required this.onForget,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$name. ${isConnected ? "Connected" : "Not connected"}.',
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        child: ExcludeSemantics(
          child: Row(
            children: [
              // Status icon
              if (isConnected)
                Icon(Icons.check_circle,
                    color: AppColors.success, size: 24)
              else
                Icon(Icons.circle_outlined,
                    color: AppColors.disabledOnLight, size: 24),
              const SizedBox(width: AppSpacing.xs),

              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textOnLight,
                      ),
                    ),
                    Text(
                      isConnected ? 'Connected' : 'Not connected',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: isConnected
                            ? AppColors.success
                            : AppColors.textSecondaryOnLight,
                      ),
                    ),
                  ],
                ),
              ),

              // Action button
              Semantics(
                button: true,
                label: isConnected
                    ? 'Forget $name'
                    : 'Reconnect $name',
                hint: isConnected
                    ? 'Disconnects and removes this device'
                    : 'Searches for this device to reconnect',
                child: GestureDetector(
                  onTap: isConnected ? onForget : onReconnect,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 88, minHeight: 48),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppColors.backgroundLight
                          : AppColors.interactive,
                      borderRadius: BorderRadius.circular(10),
                      border: isConnected
                          ? Border.all(color: AppColors.error, width: 1.5)
                          : null,
                    ),
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      isConnected ? 'Forget' : 'Reconnect',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: isConnected
                            ? AppColors.error
                            : AppColors.textOnDark,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SettingLabel extends StatelessWidget {
  final String text;
  const _SettingLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 18.sp,
        fontWeight: FontWeight.w600,
        color: AppColors.textOnLight,
      ),
    );
  }
}

class _SettingValue extends StatelessWidget {
  final String text;
  const _SettingValue(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16.sp,
        color: AppColors.textSecondaryOnLight,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Divider(
        height: 1,
        color: AppColors.borderLight,
      ),
    );
  }
}

class _SliderLabels extends StatelessWidget {
  final String left;
  final String right;
  const _SliderLabels({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(left,
            style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textSecondaryOnLight)),
        Text(right,
            style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textSecondaryOnLight)),
      ],
    );
  }
}

class _AccessibleSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _AccessibleSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: AppColors.interactive,
        inactiveTrackColor: AppColors.borderLight,
        thumbColor: AppColors.interactive,
        overlayColor: AppColors.interactive.withAlpha(40),
        thumbShape:
            const RoundSliderThumbShape(enabledThumbRadius: 14),
        trackHeight: 6,
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}

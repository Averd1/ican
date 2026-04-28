import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../main.dart' show voiceCommandService;
import '../models/home_view_model.dart';
import '../models/settings_provider.dart';
import '../services/ble_service.dart';
import '../services/device_prefs_service.dart';
import '../services/scene_description_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';
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
    final voice = _voiceCommandServiceFor(context);
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

                    const SizedBox(height: AppSpacing.sm),

                    FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: _buildModeSection(context, vm, voice),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // 2. Live description area
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: _buildDescriptionArea(vm),
                    ),

                    if (vm.lastDiagnostic.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3.5),
                        child: _buildDiagnosticPanel(context, vm),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.md),

                    // 3. Voice command trigger
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: _buildVoiceCommandSection(voice),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // 4. Context-sensitive actions
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(5),
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

  Widget _buildModeSection(
    BuildContext context,
    HomeViewModel vm,
    VoiceCommandService voice,
  ) {
    final settings = vm.settingsProvider;
    final modeLabels = [
      'Focus: ${settings.promptProfile.label}',
      'Detail: ${settings.detailLevel.label}',
      'Live: ${settings.liveDetectionVerbosity.label}',
      'Vision: ${vm.sceneService.mode.label}',
      if (vm.offlineVisionStatus != null)
        'Local: ${vm.offlineVisionStatus!.bestLocalBackendLabel}',
    ];

    return Semantics(
      label: 'Current modes. ${modeLabels.join('. ')}.',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _ModeChip(
              label: 'Focus',
              value: settings.promptProfile.label,
              profile: settings.promptProfile,
              onTap: () => _showFocusSheet(context, settings),
            ),
            _ModeChip(
              label: 'Detail',
              value: settings.detailLevel.label,
              onTap: () => _showDetailSheet(context, settings),
            ),
            _ModeChip(
              label: 'Live',
              value: settings.liveDetectionVerbosity.label,
              onTap: () => _showLiveVerbositySheet(context, settings),
            ),
            _ModeChip(
              label: 'Vision',
              value: vm.sceneService.mode.label,
              onTap: () => _showVisionSourceSheet(context, vm),
            ),
            _ModeChip(
              label: 'Voice',
              value: voice.state == VoiceCommandState.listening
                  ? 'Listening'
                  : 'Ready',
              onTap: () => _showVoiceSheet(context, settings),
            ),
            _ModeChip(
              label: 'Speech',
              value: '${settings.wordsPerMinute} wpm',
              onTap: () => _showSpeechStyleSheet(context, settings),
            ),
            if (vm.offlineVisionStatus != null)
              _ModeChip(
                label: 'Local',
                value: vm.offlineVisionStatus!.bestLocalBackendLabel,
              ),
          ],
        ),
      ),
    );
  }

  void _showFocusSheet(BuildContext context, SettingsProvider settings) {
    _showModeSheet(
      context,
      title: 'Description Focus',
      children: PromptProfile.values.map((profile) {
        return _ModeSheetOption(
          label: profile.label,
          subtitle: profile.description,
          selected: settings.promptProfile == profile,
          onTap: () {
            HapticFeedback.selectionClick();
            settings.setPromptProfile(profile);
            Navigator.of(context).pop();
          },
        );
      }).toList(),
    );
  }

  void _showDetailSheet(BuildContext context, SettingsProvider settings) {
    _showModeSheet(
      context,
      title: 'Description Detail',
      children: DetailLevel.values.map((level) {
        return _ModeSheetOption(
          label: level.label,
          subtitle: level == DetailLevel.brief
              ? 'Short summaries unless safety needs more detail.'
              : 'Four to six concise sentences when useful.',
          selected: settings.detailLevel == level,
          onTap: () {
            HapticFeedback.selectionClick();
            settings.setDetailLevel(level);
            Navigator.of(context).pop();
          },
        );
      }).toList(),
    );
  }

  void _showLiveVerbositySheet(
    BuildContext context,
    SettingsProvider settings,
  ) {
    _showModeSheet(
      context,
      title: 'Live Announcements',
      children: LiveDetectionVerbosity.values.map((verbosity) {
        return _ModeSheetOption(
          label: verbosity.label,
          subtitle: verbosity.description,
          selected: settings.liveDetectionVerbosity == verbosity,
          onTap: () {
            HapticFeedback.selectionClick();
            settings.setLiveDetectionVerbosity(verbosity);
            Navigator.of(context).pop();
          },
        );
      }).toList(),
    );
  }

  void _showVisionSourceSheet(BuildContext context, HomeViewModel vm) {
    _showModeSheet(
      context,
      title: 'Vision Source',
      children: VisionMode.values.map((mode) {
        return _ModeSheetOption(
          label: mode.label,
          subtitle: mode.description,
          selected: vm.sceneService.mode == mode,
          onTap: () {
            HapticFeedback.selectionClick();
            unawaited(vm.sceneService.setMode(mode));
            Navigator.of(context).pop();
          },
        );
      }).toList(),
    );
  }

  void _showVoiceSheet(BuildContext context, SettingsProvider settings) {
    _showModeSheet(
      context,
      title: 'Voice',
      children: [
        FutureBuilder<List<TtsVoiceOption>>(
          future: settings.availableVoices(),
          builder: (context, snapshot) {
            final voices = snapshot.data ?? const <TtsVoiceOption>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (voices.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Text('System voice'),
              );
            }
            return Column(
              children: voices.take(8).map((voice) {
                return _ModeSheetOption(
                  label: voice.label,
                  subtitle: voice.locale,
                  selected: settings.selectedVoiceId == voice.id,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    unawaited(settings.setVoiceOption(voice));
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        AccessibleButton(
          label: 'Preview Voice',
          hint: 'Plays a short sample with the selected voice',
          onPressed: () => unawaited(settings.previewVoice()),
        ),
      ],
    );
  }

  void _showSpeechStyleSheet(BuildContext context, SettingsProvider settings) {
    _showModeSheet(
      context,
      title: 'Speech Style',
      children: [
        AnimatedBuilder(
          animation: settings,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetSlider(
                  label: 'Speed',
                  valueLabel: '${settings.wordsPerMinute} words per minute',
                  value: settings.speechRate,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  onChanged: settings.setSpeechRate,
                ),
                const SizedBox(height: AppSpacing.sm),
                _SheetSlider(
                  label: 'Pitch',
                  valueLabel: settings.pitch.toStringAsFixed(1),
                  value: settings.pitch,
                  min: 0.5,
                  max: 2,
                  divisions: 15,
                  onChanged: settings.setPitch,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showModeSheet(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textOnLight,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...children,
              ],
            ),
          ),
        );
      },
    );
  }

  VoiceCommandService _voiceCommandServiceFor(BuildContext context) {
    try {
      return Provider.of<VoiceCommandService>(context, listen: false);
    } on ProviderNotFoundException {
      return voiceCommandService;
    }
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
            border: Border.all(color: AppColors.textOnLight, width: 1),
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
                      const SizedBox(
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
                    fontWeight: hasDescription
                        ? FontWeight.normal
                        : FontWeight.w300,
                    color: hasDescription
                        ? AppColors.textOnLight
                        : AppColors.disabledOnLight,
                    fontStyle: hasDescription
                        ? FontStyle.normal
                        : FontStyle.italic,
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

  Widget _buildDiagnosticPanel(BuildContext context, HomeViewModel vm) {
    final diagnostic = vm.lastDiagnostic.trim();

    return Semantics(
      liveRegion: true,
      label: 'Latest vision diagnostic. $diagnostic',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceCardLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error, width: 2),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Latest Vision Diagnostic',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Copy diagnostic',
                    child: IconButton(
                      icon: const Icon(Icons.copy),
                      color: AppColors.interactive,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: diagnostic),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Diagnostic copied'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                diagnostic,
                style: TextStyle(
                  fontSize: 16.sp,
                  color: AppColors.textOnLight,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceCommandSection(VoiceCommandService voice) {
    return AnimatedBuilder(
      animation: voice,
      builder: (context, _) {
        final isListening = voice.state == VoiceCommandState.listening;
        final isProcessing = voice.state == VoiceCommandState.processing;
        final status = switch (voice.state) {
          VoiceCommandState.idle => 'Ready',
          VoiceCommandState.listening => 'Listening',
          VoiceCommandState.processing => 'Processing',
        };
        final transcript = voice.partialText.trim();
        final result = voice.lastResult.trim();
        final details = <String>[
          'Status: $status',
          if (isListening && transcript.isNotEmpty) 'Heard: $transcript',
          if (isProcessing && transcript.isNotEmpty) 'Processing: $transcript',
          if (result.isNotEmpty) 'Last result: $result',
        ];

        return Semantics(
          liveRegion: true,
          label: details.join('. '),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccessibleButton(
                label: isListening
                    ? 'Listening for Command'
                    : isProcessing
                    ? 'Processing Voice Command'
                    : 'Start Voice Command',
                hint:
                    'Starts voice control without needing the Eye button. Try describe now, repeat last, or scan devices.',
                subtitle: 'Status: $status',
                onPressed: voice.state == VoiceCommandState.idle
                    ? () => voice.activateVoiceCommand()
                    : null,
              ),
              if (transcript.isNotEmpty || result.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      [
                        if (transcript.isNotEmpty) 'Heard: $transcript',
                        if (result.isNotEmpty) 'Last result: $result',
                      ].join('\n'),
                      style: TextStyle(
                        fontSize: 15.sp,
                        color: AppColors.textSecondaryOnLight,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.md));
      }
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
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.md));
      }
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
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.md));
      }
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

class _ModeChip extends StatelessWidget {
  final String label;
  final String value;
  final PromptProfile? profile;
  final VoidCallback? onTap;

  const _ModeChip({
    required this.label,
    required this.value,
    this.profile,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = switch (profile) {
      PromptProfile.safety => const Color(0xFFFFE8E8),
      PromptProfile.reading => const Color(0xFFE9F3FF),
      PromptProfile.navigation => const Color(0xFFEAF8EF),
      _ => AppColors.surfaceCardLight,
    };

    return Semantics(
      button: onTap != null,
      label: '$label $value',
      hint: onTap == null ? null : 'Opens $label options',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: ExcludeSemantics(
            child: Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textOnLight,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSheetOption extends StatelessWidget {
  const _ModeSheetOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $subtitle',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xs,
            horizontal: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.success : AppColors.disabledOnLight,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnLight,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.textSecondaryOnLight,
                          height: 1.25,
                        ),
                      ),
                    ],
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

class _SheetSlider extends StatelessWidget {
  const _SheetSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      label: '$label. $valueLabel',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textOnLight,
                    ),
                  ),
                ),
                Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColors.textSecondaryOnLight,
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

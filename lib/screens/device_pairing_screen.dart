// Usage — from role_selection or splash:
//
//   Navigator.pushNamed(context, AppRouter.devicePairing);
//
//   DevicePairingScreen(
//     onPairingComplete: () {
//       Navigator.pushReplacementNamed(context, AppRouter.accessibleHome);
//     },
//   )

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/theme.dart';
import '../services/ble_service.dart';
import '../widgets/accessible_button.dart';

class DevicePairingScreen extends StatefulWidget {
  final VoidCallback? onPairingComplete;
  final VoidCallback? onSkip;

  const DevicePairingScreen({
    super.key,
    this.onPairingComplete,
    this.onSkip,
  });

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  VoidCallback? _bleListener;
  Timer? _scanTimeoutTimer;

  bool _isScanning = false;
  bool _eyeConnected = false;
  bool _caneConnected = false;
  bool _scanTimedOut = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _bleListener = _onBleStateChanged;
    BleService.instance.addListener(_bleListener!);

    // Check if already connected (e.g. auto-reconnect from splash)
    _eyeConnected =
        BleService.instance.state == BleConnectionState.connected;
    _caneConnected =
        BleService.instance.caneState == BleConnectionState.connected;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SemanticsService.announce(
        'Connect your devices. Turn on your iCan Cane and Camera, then tap Search for devices.',
        TextDirection.ltr,
      );
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanTimeoutTimer?.cancel();
    if (_bleListener != null) {
      BleService.instance.removeListener(_bleListener!);
    }
    super.dispose();
  }

  void _onBleStateChanged() {
    if (!mounted) return;

    final eyeNow =
        BleService.instance.state == BleConnectionState.connected;
    final caneNow =
        BleService.instance.caneState == BleConnectionState.connected;

    if (eyeNow && !_eyeConnected) {
      _eyeConnected = true;
      HapticFeedback.heavyImpact();
      SemanticsService.announce(
          'iCan Eye camera connected successfully.', TextDirection.ltr);
    }

    if (caneNow && !_caneConnected) {
      _caneConnected = true;
      HapticFeedback.heavyImpact();
      SemanticsService.announce(
          'iCan Cane connected successfully.', TextDirection.ltr);
    }

    // Both connected — cancel timeout, announce
    if (_eyeConnected && _caneConnected && _isScanning) {
      _scanTimeoutTimer?.cancel();
      _isScanning = false;
      SemanticsService.announce(
          'Both devices connected. Tap Continue to proceed.',
          TextDirection.ltr);
    }

    setState(() {});
  }

  void _startScan() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isScanning = true;
      _scanTimedOut = false;
      _errorMessage = null;
    });
    SemanticsService.announce(
        'Searching for devices. This may take a few seconds.',
        TextDirection.ltr);

    BleService.instance.startScan();
    BleService.instance.startScanForCane();

    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      if (!_eyeConnected && !_caneConnected) {
        _onScanTimeout();
      } else {
        // At least one connected — just stop scanning
        setState(() => _isScanning = false);
      }
    });
  }

  void _onScanTimeout() {
    HapticFeedback.vibrate();
    setState(() {
      _isScanning = false;
      _scanTimedOut = true;
      _errorMessage =
          'No devices found. Make sure your iCan Cane and Camera are turned on and within 3 feet of your phone, then try again.';
    });
    SemanticsService.announce(_errorMessage!, TextDirection.ltr);
  }

  bool get _hasAnyConnection => _eyeConnected || _caneConnected;
  bool get _hasBothConnections => _eyeConnected && _caneConnected;

  String get _statusText {
    if (_errorMessage != null) return 'Search failed';
    if (_hasBothConnections) return 'Both devices connected';
    if (_isScanning) return 'Searching for devices…';
    if (_eyeConnected && !_caneConnected) return 'Camera connected. Cane not found.';
    if (_caneConnected && !_eyeConnected) return 'Cane connected. Camera not found.';
    if (_scanTimedOut) return 'Search failed';
    return 'Ready to search';
  }

  String get _statusSemantic {
    if (_hasBothConnections) {
      return 'Both devices connected. Tap Continue to proceed.';
    }
    if (_isScanning) return 'Searching for devices. Please wait.';
    if (_eyeConnected && !_caneConnected) {
      return 'iCan Eye camera connected. iCan Cane not found yet. You can search again or continue with just the camera.';
    }
    if (_caneConnected && !_eyeConnected) {
      return 'iCan Cane connected. iCan Eye camera not found yet. You can search again or continue with just the cane.';
    }
    if (_errorMessage != null) return _errorMessage!;
    return 'Ready to search. Tap Search for devices to begin.';
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppAccessibility.reduceMotion(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
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
                // ── 1. Heading ──
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: Semantics(
                    header: true,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.md,
                        bottom: AppSpacing.xs,
                      ),
                      child: Text(
                        'Connect Your Devices',
                        style: TextStyle(
                          fontSize: 32.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textOnLight,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),

                // ── 2. Instructions ──
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: Semantics(
                    label: 'Instructions. '
                        'First, turn on your iCan Cane and iCan Eye camera. '
                        'Then, tap the Search for devices button below. '
                        'You will hear a confirmation when each device connects.',
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      margin: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCardLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InstructionStep(
                              number: '1',
                              text:
                                  'Turn on your iCan Cane and iCan Eye camera.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            _InstructionStep(
                              number: '2',
                              text:
                                  'Tap "Search for devices" below.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            _InstructionStep(
                              number: '3',
                              text:
                                  'You will hear a confirmation when each device connects.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── 3. Scan button ──
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: AccessibleButton(
                    label: _isScanning
                        ? 'Searching…'
                        : _scanTimedOut || _errorMessage != null
                            ? 'Try Again'
                            : _hasAnyConnection && !_hasBothConnections
                                ? 'Search Again'
                                : 'Search for Devices',
                    hint: _isScanning
                        ? 'Currently searching for nearby devices'
                        : 'Searches for iCan Cane and iCan Eye camera nearby',
                    onPressed: _isScanning ? null : _startScan,
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── 4. Live status area ──
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: _buildStatusArea(reduceMotion),
                ),

                const SizedBox(height: AppSpacing.sm),

                // ── 5. Connection indicators ──
                FocusTraversalOrder(
                  order: const NumericFocusOrder(4),
                  child: _buildConnectionIndicators(),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── 6. Continue / Skip / Help ──
                FocusTraversalOrder(
                  order: const NumericFocusOrder(5),
                  child: _buildBottomActions(),
                ),

                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Status area — liveRegion for screen reader auto-announce
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatusArea(bool reduceMotion) {
    final bool isError = _errorMessage != null;

    return Semantics(
      liveRegion: true,
      label: _statusSemantic,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isError
              ? const Color(0xFFFFF0F0)
              : _hasBothConnections
                  ? const Color(0xFFF0F8F0)
                  : AppColors.surfaceCardLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isError
                ? AppColors.error
                : _hasBothConnections
                    ? AppColors.success
                    : AppColors.borderLight,
            width: isError || _hasBothConnections ? 2 : 1,
          ),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_isScanning) ...[
                    _ScanningIndicator(
                      controller: _pulseController,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  if (_hasBothConnections) ...[
                    Icon(Icons.check_circle,
                        color: AppColors.success, size: 24),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  if (isError) ...[
                    Icon(Icons.error_outline,
                        color: AppColors.error, size: 24),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      _statusText,
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: isError
                            ? AppColors.error
                            : _hasBothConnections
                                ? AppColors.success
                                : AppColors.textOnLight,
                      ),
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: AppColors.textOnLight,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Connection indicators — one row per device, always visible
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConnectionIndicators() {
    return Column(
      children: [
        _ConnectionRow(
          deviceName: 'iCan Eye Camera',
          isConnected: _eyeConnected,
          isSearching: _isScanning && !_eyeConnected,
        ),
        const SizedBox(height: AppSpacing.xs),
        _ConnectionRow(
          deviceName: 'iCan Cane',
          isConnected: _caneConnected,
          isSearching: _isScanning && !_caneConnected,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Bottom actions
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomActions() {
    return Column(
      children: [
        if (_hasAnyConnection)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AccessibleButton(
              label: _hasBothConnections
                  ? 'Continue'
                  : 'Continue with ${_eyeConnected ? 'Camera' : 'Cane'} Only',
              hint: _hasBothConnections
                  ? 'Both devices are connected. Opens the home screen.'
                  : 'Proceeds with only one device connected. You can connect the other later.',
              onPressed: widget.onPairingComplete,
            ),
          ),
        Semantics(
          button: true,
          label: 'Skip pairing',
          hint:
              'Continues without connecting devices. You can connect later from the home screen.',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onSkip?.call();
            },
            child: Container(
              constraints:
                  const BoxConstraints(minHeight: 48, minWidth: 48),
              alignment: Alignment.center,
              child: Text(
                'Skip for now',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.interactive,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.interactive,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          button: true,
          label: 'Need help pairing',
          hint: 'Opens troubleshooting tips for connecting your devices',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showHelpDialog();
            },
            child: Container(
              constraints:
                  const BoxConstraints(minHeight: 48, minWidth: 48),
              alignment: Alignment.center,
              child: Text(
                'Need help?',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: AppColors.textSecondaryOnLight,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.textSecondaryOnLight,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.backgroundLight,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: Semantics(
          header: true,
          child: Text(
            'Troubleshooting',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnLight,
            ),
          ),
        ),
        content: Semantics(
          label: 'Troubleshooting tips. '
              'Make sure Bluetooth is turned on in your phone settings. '
              'Hold each device close to your phone, within 3 feet. '
              'The iCan Cane has a small power button on the handle. Press and hold it for 2 seconds. '
              'The iCan Eye camera turns on automatically when plugged in. '
              'If devices still do not connect, turn them off, wait 5 seconds, and turn them back on.',
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _helpItem(
                    'Make sure Bluetooth is turned on in your phone settings.'),
                _helpItem(
                    'Hold each device close to your phone — within 3 feet.'),
                _helpItem(
                    'The Cane has a power button on the handle. Press and hold it for 2 seconds.'),
                _helpItem(
                    'The Eye camera turns on when plugged in.'),
                _helpItem(
                    'If devices still won\'t connect, turn them off, wait 5 seconds, then turn them back on.'),
              ],
            ),
          ),
        ),
        actions: [
          Semantics(
            button: true,
            label: 'Close help',
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              child: Text(
                'Close',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.interactive,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ',
              style: TextStyle(
                  fontSize: 16.sp, color: AppColors.textOnLight)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16.sp,
                color: AppColors.textOnLight,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection row — shows status of a single device
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionRow extends StatelessWidget {
  final String deviceName;
  final bool isConnected;
  final bool isSearching;

  const _ConnectionRow({
    required this.deviceName,
    required this.isConnected,
    required this.isSearching,
  });

  String get _statusLabel {
    if (isConnected) return 'Connected';
    if (isSearching) return 'Searching…';
    return 'Not connected';
  }

  String get _semanticLabel =>
      '$deviceName. $_statusLabel.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs + 4,
        ),
        decoration: BoxDecoration(
          color: isConnected
              ? const Color(0xFFF0F8F0)
              : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConnected
                ? AppColors.success
                : AppColors.borderLight,
            width: isConnected ? 2 : 1,
          ),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              // Status icon — shape conveys meaning, not just color
              if (isConnected)
                Icon(Icons.check_circle,
                    color: AppColors.success, size: 28)
              else if (isSearching)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.interactive,
                  ),
                )
              else
                Icon(Icons.circle_outlined,
                    color: AppColors.disabledOnLight, size: 28),
              const SizedBox(width: AppSpacing.xs),

              // Device name
              Expanded(
                child: Text(
                  deviceName,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textOnLight,
                  ),
                ),
              ),

              // Status text
              Text(
                _statusLabel,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: isConnected
                      ? AppColors.success
                      : isSearching
                          ? AppColors.interactive
                          : AppColors.disabledOnLight,
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
// Instruction step
// ─────────────────────────────────────────────────────────────────────────────

class _InstructionStep extends StatelessWidget {
  final String number;
  final String text;

  const _InstructionStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.interactive,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnDark,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 18.sp,
                color: AppColors.textOnLight,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanning indicator (respects reduceMotion)
// ─────────────────────────────────────────────────────────────────────────────

class _ScanningIndicator extends StatelessWidget {
  final AnimationController controller;
  final bool reduceMotion;

  const _ScanningIndicator({
    required this.controller,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return Icon(
        Icons.bluetooth_searching,
        color: AppColors.interactive,
        size: 24,
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Opacity(
          opacity: 0.4 + (controller.value * 0.6),
          child: Icon(
            Icons.bluetooth_searching,
            color: AppColors.interactive,
            size: 24,
          ),
        );
      },
    );
  }
}

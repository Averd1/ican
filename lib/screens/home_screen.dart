import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_router.dart';
import '../services/ble_service.dart';
import '../services/vertex_ai_service.dart';
import '../services/tts_service.dart';

/// Camera quality profiles — matches firmware profile indices.
enum CameraProfile {
  fast(profileIndex: 0, label: 'Fast', description: '640x480 — quick capture'),
  balanced(profileIndex: 1, label: 'Balanced', description: '800x600 — recommended'),
  quality(profileIndex: 2, label: 'Quality', description: '1024x768 — sharp text'),
  max(profileIndex: 3, label: 'Max', description: '1600x1200 — highest detail');

  const CameraProfile({
    required this.profileIndex,
    required this.label,
    required this.description,
  });

  final int profileIndex;
  final String label;
  final String description;
}

/// Home Screen — Main entry point for the iCan App.
///
/// Designed for accessibility: large tap targets, high contrast,
/// voice-driven interaction. Shows connection status and primary actions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VertexAiService _aiService = VertexAiService();
  final TtsService _ttsService = TtsService();

  String _aiStatusMessage = '';
  bool _isProcessing = false;
  String? _lastImageFingerprint;
  DateTime? _lastImageTime;

  StreamSubscription? _captureSub;
  StreamSubscription? _imageSub;
  CameraProfile _cameraProfile = CameraProfile.balanced;

  @override
  void initState() {
    super.initState();

    // Initialize services
    _ttsService.init();
    _aiService.loadSavedModel();
    _aiService.addListener(_onModelChanged);
    _loadCameraProfile();

    // Listen to BLE Connection State Changes
    BleService.instance.addListener(_onBleStateChanged);

    // Listen for hardware-initiated captures
    _captureSub = BleService.instance.captureStartedStream.listen((_) {
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _aiStatusMessage = 'Receiving image from eye...';
        });
      }
    });

    // Listen to incoming completed images from the Eye
    _imageSub = BleService.instance.imageStream.listen((Uint8List imageBytes) async {
      final now = DateTime.now();
      final fingerprint = _computeImageFingerprint(imageBytes);
      if (_lastImageFingerprint == fingerprint &&
          _lastImageTime != null &&
          now.difference(_lastImageTime!) < const Duration(seconds: 2)) {
        debugPrint('[AI] Skipping duplicate image frame within dedupe window.');
        return;
      }
      _lastImageFingerprint = fingerprint;
      _lastImageTime = now;
      await _processImage(imageBytes);
    });
  }

  String _computeImageFingerprint(Uint8List data) {
    if (data.isEmpty) return 'empty';
    final headLen = data.length < 16 ? data.length : 16;
    final tailLen = data.length < 16 ? data.length : 16;
    final head = data.sublist(0, headLen);
    final tail = data.sublist(data.length - tailLen);
    return '${data.length}:${head.join(',')}:${tail.join(',')}';
  }

  @override
  void dispose() {
    _captureSub?.cancel();
    _imageSub?.cancel();
    BleService.instance.removeListener(_onBleStateChanged);
    _aiService.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onBleStateChanged() {
    setState(() {});
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCameraProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('camera_profile');
      if (saved != null && saved >= 0 && saved < CameraProfile.values.length) {
        _cameraProfile = CameraProfile.values[saved];
        // Sync to Eye if already connected
        if (BleService.instance.state == BleConnectionState.connected) {
          BleService.instance.setEyeProfile(_cameraProfile.profileIndex);
        }
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _setCameraProfile(CameraProfile profile) async {
    if (_cameraProfile == profile) return;
    _cameraProfile = profile;
    setState(() {});
    BleService.instance.setEyeProfile(profile.profileIndex);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('camera_profile', CameraProfile.values.indexOf(profile));
    } catch (_) {}
  }

  Future<void> _processImage(Uint8List imageBytes) async {
    // Validate JPEG before sending to API
    if (imageBytes.length < 2 || imageBytes[0] != 0xFF || imageBytes[1] != 0xD8) {
      debugPrint(
        '[AI] Skipping corrupted image (not JPEG). First bytes: '
        '${imageBytes.length >= 2 ? "0x${imageBytes[0].toRadixString(16)} 0x${imageBytes[1].toRadixString(16)}" : "too short"}',
      );
      setState(() {
        _aiStatusMessage = 'Received corrupted image — please retry.';
        _isProcessing = false;
      });
      // Safely speak error message without crashing if TTS fails
      try {
        await _ttsService.speak('The image was corrupted. Please try again.');
      } catch (e) {
        debugPrint('[TTS] Failed to speak error: $e');
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _aiStatusMessage = 'Analyzing with ${_aiService.model.label}... (${imageBytes.lengthInBytes} bytes)';
    });

    try {
      final text = await _aiService.generateContentFromImage(
        imageBytes,
        'You are the eyes of a blind person. This photo is from a camera on their chest. '
        'Respond in plain spoken English (no markdown, no bullets — this is read aloud by TTS). '
        'Priority order: '
        '1) SAFETY: obstacles, stairs, curbs, vehicles, people nearby — use clock positions (e.g. "person at your 2 o\'clock"). '
        '2) TEXT: read ALL visible text — signs, labels, screens, menus, price tags — word for word. '
        '3) SCENE: briefly describe the environment, layout, and key landmarks. '
        'Be direct and concise. Maximum 4 sentences.',
      );

      // --- Save image to local captures folder ---
      try {
        final directory = Directory('captures');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        final timestamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .replaceAll('.', '-');
        final file = File('captures/capture_$timestamp.jpg');
        await file.writeAsBytes(imageBytes);
        debugPrint('[AI] Saved image to: ${file.path}');
      } catch (e) {
        debugPrint('[AI] Failed to save image to folder: $e');
      }

      setState(() {
        _aiStatusMessage = 'Done!';
        _isProcessing = false;
      });

      // Read aloud the AI response safely
      try {
        await _ttsService.speak(text);
      } catch (e) {
        debugPrint('[TTS] Failed to speak AI response: $e');
        // Still consider this a successful image processing even if TTS fails
        if (mounted) {
          setState(() {
            _aiStatusMessage = 'Image processed (TTS unavailable)';
          });
        }
      }
    } catch (e, stack) {
      debugPrint('[AI] Error processing image: $e');
      debugPrint('[AI] Stack trace: $stack');
      setState(() {
        _aiStatusMessage = 'Error: $e';
        _isProcessing = false;
      });
      // Safely speak error message without crashing if TTS fails
      try {
        await _ttsService.speak('Sorry, there was an error processing the image. $e');
      } catch (ttsError) {
        debugPrint('[TTS] Failed to speak error message: $ttsError');
      }
    }
  }

  String _getBleStatusText() {
    switch (BleService.instance.state) {
      case BleConnectionState.disconnected:
        return 'iCan Eye: Disconnected';
      case BleConnectionState.scanning:
        return 'Scanning...';
      case BleConnectionState.connecting:
        return 'Connecting...';
      case BleConnectionState.connected:
        return 'iCan Eye: Connected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'iCan User',
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Connection Status ---
              _buildStatusCard(context),

              const SizedBox(height: 12),

              // --- AI Model Picker ---
              _buildModelPicker(context),

              const SizedBox(height: 8),

              // --- Camera Profile Picker ---
              _buildCameraProfilePicker(context),

              const SizedBox(height: 12),

              // --- AI Feedback Status ---
              if (_aiStatusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Text(
                    _aiStatusMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _isProcessing ? theme.colorScheme.secondary : Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              // --- Primary Action: Take Picture ---
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Take picture and describe scene',
                  child: GestureDetector(
                    onTap: _isProcessing
                        ? null
                        : () {
                            if (BleService.instance.state != BleConnectionState.connected) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please connect device first')),
                              );
                              return;
                            }

                            setState(() {
                              _isProcessing = true;
                              _aiStatusMessage = 'Capturing photo...';
                            });
                            BleService.instance.triggerEyeCapture();
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: _isProcessing
                            ? theme.colorScheme.surface
                            : theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: [
                          if (!_isProcessing)
                            BoxShadow(
                              color: theme.colorScheme.primary.withAlpha(77),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            )
                        ],
                        border: _isProcessing
                            ? Border.all(color: theme.colorScheme.onSurface.withAlpha(26), width: 1)
                            : null,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.camera_alt_rounded,
                              size: 48,
                              color: _isProcessing
                                  ? theme.colorScheme.onSurface.withAlpha(128)
                                  : theme.colorScheme.onPrimary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Describe Scene',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: _isProcessing
                                    ? theme.colorScheme.onSurface.withAlpha(128)
                                    : theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // --- Secondary: Connection Control ---
              Semantics(
                button: true,
                label: _getConnectionButtonLabel(),
                child: _buildConnectionButton(context, theme),
              ),
              
              // --- GPS Monitor shortcut ---
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Semantics(
                  button: true,
                  label: 'View GPS data from iCan Cane',
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed(AppRouter.gps),
                    icon: const Icon(Icons.gps_fixed_rounded),
                    label: const Text('View GPS'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),

              // --- Tertiary: Disconnect and Forget (only when connected) ---
              if (BleService.instance.state == BleConnectionState.connected)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Semantics(
                    button: true,
                    label: 'Disconnect from device and forget it for next startup',
                    child: TextButton.icon(
                      onPressed: _handleDisconnectAndForget,
                      icon: Icon(Icons.bluetooth_disabled_rounded, color: theme.colorScheme.error),
                      label: Text('Forget Device', style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelPicker(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'AI model selector. Current: ${_aiService.model.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.onSurface.withAlpha(13),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Text('AI Model:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<AiModel>(
                segments: AiModel.values.map((m) => ButtonSegment<AiModel>(
                  value: m,
                  label: Text(m.label, style: const TextStyle(fontSize: 12)),
                  tooltip: m.description,
                )).toList(),
                selected: {_aiService.model},
                onSelectionChanged: _isProcessing ? null : (selected) {
                  _aiService.setModel(selected.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraProfilePicker(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Camera quality. Current: ${_cameraProfile.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.onSurface.withAlpha(13),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.camera_rounded, size: 18, color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Text('Camera:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<CameraProfile>(
                segments: CameraProfile.values.map((p) => ButtonSegment<CameraProfile>(
                  value: p,
                  label: Text(p.label, style: const TextStyle(fontSize: 12)),
                  tooltip: p.description,
                )).toList(),
                selected: {_cameraProfile},
                onSelectionChanged: _isProcessing ? null : (selected) {
                  _setCameraProfile(selected.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = BleService.instance.state == BleConnectionState.connected;

    return Semantics(
      label: 'Device connection status',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(38),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ],
          border: Border.all(
            color: theme.colorScheme.onSurface.withAlpha(13),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isConnected ? Colors.green.withAlpha(26) : theme.colorScheme.primary.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bluetooth_rounded,
                color: isConnected ? Colors.green : theme.colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'iCan Eye',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(153),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getBleStatusText(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isConnected ? Colors.green : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getConnectionButtonLabel() {
    switch (BleService.instance.state) {
      case BleConnectionState.disconnected:
        return 'Scan for and connect to iCan Eye device';
      case BleConnectionState.scanning:
        return 'Scanning for devices';
      case BleConnectionState.connecting:
        return 'Connecting to device';
      case BleConnectionState.connected:
        return 'Device connected (tap to scan for another)';
    }
  }

  Widget _buildConnectionButton(BuildContext context, ThemeData theme) {
    final isConnected = BleService.instance.state == BleConnectionState.connected;
    final isScanning = BleService.instance.state == BleConnectionState.scanning;
    final isConnecting = BleService.instance.state == BleConnectionState.connecting;

    return GestureDetector(
      onTap: isScanning || isConnecting ? null : () => BleService.instance.startScan(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.onSurface.withAlpha(26),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isConnected
                  ? Icons.bluetooth_connected_rounded
                  : isScanning
                      ? Icons.bluetooth_searching_rounded
                      : Icons.bluetooth_rounded,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 12),
            Text(
              isConnected ? 'Device Connected' : 'Connect Devices',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDisconnectAndForget() async {
    if (!mounted) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Forget Device?'),
          content: const Text(
            'This will disconnect and clear the saved device. '
            'Auto-connect will not happen on next app start.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(100, 48),
              ),
              child: const Text('Forget'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        // Disconnect and clear saved device ID
        await BleService.instance.disconnectAndForget();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device forgotten. You can connect again anytime.'),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error forgetting device: $e'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }
}

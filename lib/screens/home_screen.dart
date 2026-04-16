import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_router.dart';
import '../services/ble_service.dart';
import '../services/model_download_service.dart';
import '../services/on_device_vision_service.dart';
import '../services/scene_description_service.dart';
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
  final OnDeviceVisionService _onDeviceService = OnDeviceVisionService();
  late final SceneDescriptionService _sceneService;
  late final ModelDownloadService _downloadService;
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
    _sceneService = SceneDescriptionService(
      cloudService: _aiService,
      onDeviceService: _onDeviceService,
    );
    _sceneService.loadSavedMode();
    _sceneService.addListener(_onModeChanged);
    _downloadService = ModelDownloadService(
      visionService: _onDeviceService,
      ttsService: _ttsService,
    );
    _downloadService.addListener(_onDownloadChanged);
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
    _sceneService.removeListener(_onModeChanged);
    _downloadService.removeListener(_onDownloadChanged);
    _downloadService.dispose();
    super.dispose();
  }

  void _onBleStateChanged() {
    setState(() {});
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  void _onModeChanged() {
    if (mounted) setState(() {});
  }

  void _onDownloadChanged() {
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
      _aiStatusMessage = 'Enhancing image...';
    });

    // Enhance on a background isolate: crop black bars + boost contrast/exposure
    final enhancedBytes = await compute(_enhanceImageForApi, imageBytes);
    debugPrint('[AI] Enhanced: ${imageBytes.length} → ${enhancedBytes.length} bytes');

    // --- Save both raw and enhanced for debugging ---
    try {
      final directory = Directory('captures');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      await File('captures/capture_${timestamp}_raw.jpg').writeAsBytes(imageBytes);
      await File('captures/capture_$timestamp.jpg').writeAsBytes(enhancedBytes);
      debugPrint('[AI] Saved raw (${imageBytes.length}B) + enhanced (${enhancedBytes.length}B) to captures/');
    } catch (e) {
      debugPrint('[AI] Failed to save images: $e');
    }

    const systemPrompt =
        'You are the vision system for a blind person wearing a chest camera. '
        'Speak in plain, conversational English — no markdown, no bullet points, no lists — '
        'everything you say is read aloud by a text-to-speech engine. '
        'Describe the scene in 4–6 sentences:\n'
        '1) Start with WHERE you are (room type, indoor/outdoor, general setting).\n'
        '2) SAFETY: name any obstacles, steps, edges, vehicles, or people. '
        'Use clock positions for direction (e.g. "chair at 2 o\'clock").\n'
        '3) Describe what is DIRECTLY AHEAD and within arm\'s reach.\n'
        '4) Read any visible text verbatim — signs, labels, screens, buttons.\n'
        '5) Mention notable objects, colors, or landmarks that help orientation.\n'
        'Be specific and spatial. Never say "I see" — describe as if you are the person\'s eyes.';

    try {
      // Stream response (cloud or local) and start TTS as soon as first sentence arrives.
      // Regex matches punctuation followed by whitespace (mid-stream) OR
      // punctuation at end-of-string (last sentence in final chunk).
      final textBuffer = StringBuffer();
      final sentenceEnd = RegExp(r'[.!?](?:\s|$)');
      int chunkCount = 0;

      await for (final chunk in _sceneService.describeScene(
        enhancedBytes,
        systemPrompt: systemPrompt,
        onStatusUpdate: (status, backend) {
          if (mounted) {
            setState(() => _aiStatusMessage = status);
          }
        },
      )) {
        chunkCount++;
        debugPrint('[AI] Stream chunk #$chunkCount (${chunk.length} chars): "$chunk"');
        textBuffer.write(chunk);

        // Drain ALL complete sentences from the buffer — not just the first.
        // Without the loop, multi-sentence chunks leave sentences stranded in
        // the buffer, which then get spoken as one big block at stream end
        // (the "repeats halfway" bug).
        while (true) {
          final accumulated = textBuffer.toString();
          final match = sentenceEnd.firstMatch(accumulated);
          if (match == null) break;

          final sentence = accumulated.substring(0, match.end).trim();
          final leftover = accumulated.substring(match.end);
          textBuffer.clear();
          textBuffer.write(leftover);
          debugPrint('[AI] Sentence ready → TTS: "$sentence" | leftover: "${leftover.trim()}"');
          try {
            await _ttsService.speak(sentence);
          } catch (e) {
            debugPrint('[AI] TTS error during streaming: $e');
          }
        }
      }

      final fullResponse = textBuffer.toString().trim();
      debugPrint('[AI] Stream complete. $chunkCount chunks. Remaining: "${fullResponse.isEmpty ? "(none)" : fullResponse}"');

      // Speak any remaining text after stream ends
      if (fullResponse.isNotEmpty) {
        debugPrint('[AI] Speaking remaining text → TTS: "$fullResponse"');
        try {
          await _ttsService.speak(fullResponse);
        } catch (e) {
          debugPrint('[AI] TTS error for remaining text: $e');
        }
      }

      if (mounted) {
        setState(() {
          _aiStatusMessage = 'Done!';
          _isProcessing = false;
        });
      }
    } catch (e, stack) {
      debugPrint('[AI] Error processing image: $e');
      debugPrint('[AI] Stack trace: $stack');
      if (mounted) {
        setState(() {
          _aiStatusMessage = 'Error: $e';
          _isProcessing = false;
        });
      }
      try {
        await _ttsService.speak('Sorry, there was an error processing the image.');
      } catch (_) {}
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
    final isConnected = BleService.instance.state == BleConnectionState.connected;
    final isDisabled = !isConnected || _isProcessing;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final maxW = isWide ? 500.0 : constraints.maxWidth;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- Connection Status ---
                      _buildStatusCard(context),

                      const SizedBox(height: 12),

                      // --- Vision Mode Picker (Auto / Offline / Cloud) ---
                      _buildModePicker(context),

                      const SizedBox(height: 8),

                      // --- AI Model Picker (only relevant when cloud is possible) ---
                      if (_sceneService.mode != VisionMode.offlineOnly)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildModelPicker(context),
                        ),

                      // --- Camera Profile Picker ---
                      _buildCameraProfilePicker(context),

                      const SizedBox(height: 8),

                      // --- Offline Model Download Card ---
                      if (_sceneService.mode != VisionMode.cloudOnly)
                        _buildOfflineModelCard(context),

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
                            onTap: isDisabled
                                ? null
                                : () {
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
                                color: isDisabled
                                    ? theme.colorScheme.surface
                                    : theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(36),
                                boxShadow: [
                                  if (!isDisabled)
                                    BoxShadow(
                                      color: theme.colorScheme.primary.withAlpha(77),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    )
                                ],
                                border: isDisabled
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
                                      color: isDisabled
                                          ? theme.colorScheme.onSurface.withAlpha(128)
                                          : theme.colorScheme.onPrimary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Describe Scene',
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        color: isDisabled
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
                        padding: const EdgeInsets.only(top: 12),
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
          },
        ),
      ),
    );
  }

  Widget _buildModePicker(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Vision mode. Current: ${_sceneService.mode.label}',
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
            Icon(Icons.wifi_off_rounded, size: 18, color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Text('Mode:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<VisionMode>(
                segments: VisionMode.values.map((m) => ButtonSegment<VisionMode>(
                  value: m,
                  label: Text(m.label, style: const TextStyle(fontSize: 12)),
                  tooltip: m.description,
                )).toList(),
                selected: {_sceneService.mode},
                onSelectionChanged: _isProcessing ? null : (selected) {
                  _sceneService.setMode(selected.first);
                },
                style: const ButtonStyle(
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

  Widget _buildOfflineModelCard(BuildContext context) {
    final theme = Theme.of(context);

    if (_downloadService.isDownloading) {
      // Download in progress — show progress bar
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.onSurface.withAlpha(13)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.downloading_rounded, size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Downloading offline model... ${(_downloadService.progress * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: TextButton(
                    onPressed: () => _downloadService.cancelDownload(),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text('Cancel', style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadService.progress,
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    }

    // Check model status and show appropriate card
    return FutureBuilder<ModelStatus>(
      future: _onDeviceService.getModelStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? ModelStatus.notDownloaded;

        if (status == ModelStatus.loaded || status == ModelStatus.ready) {
          // Model available — show compact status
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withAlpha(40)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status == ModelStatus.loaded
                        ? 'Offline AI model loaded'
                        : 'Offline AI model ready',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Model not downloaded — show download prompt
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.secondary.withAlpha(40)),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_download_outlined, size: 18, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Download AI model for offline use (546 MB)',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : () => _downloadService.startDownload(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Download'),
                ),
              ),
            ],
          ),
        );
      },
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
            Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.secondary),
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

// ---------------------------------------------------------------------------
// Image enhancement — top-level so it can be run via compute() in an isolate
// ---------------------------------------------------------------------------

/// Adaptive image enhancement for the vision API. Runs in a background isolate
/// via compute(). Handles truncated BLE transfers, dark scenes, and text
/// sharpening without over-processing bright or complete images.
Uint8List _enhanceImageForApi(Uint8List rawBytes) {
  final decoded = img.decodeJpg(rawBytes);
  if (decoded == null) return rawBytes;

  var image = decoded;

  // 1. Only crop black bars if JPEG is truncated (missing EOI marker 0xFF 0xD9).
  //    Complete images may have legitimately dark bottom content (night, floors).
  final isTruncated = rawBytes.length < 2 ||
      rawBytes[rawBytes.length - 2] != 0xFF ||
      rawBytes[rawBytes.length - 1] != 0xD9;
  if (isTruncated) {
    image = _cropBottomBlackBar(image);
  }

  // 2. Adaptive enhancement based on scene brightness
  final meanLuma = _computeMeanLuminance(image);
  if (meanLuma < 80) {
    // Dark scene: auto-levels via histogram stretch
    image = img.normalize(image, min: 10, max: 245);
  } else if (meanLuma <= 180) {
    // Normal scene: gentle contrast boost only
    image = img.adjustColor(image, contrast: 1.1);
  }
  // Bright scenes (>180): no color adjustment — avoid washing out

  // 3. Subtle sharpen for text readability (30% blend to avoid amplifying JPEG artifacts)
  image = img.convolution(image,
    filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
    amount: 0.3,
  );

  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Fast mean luminance sampling (every 8th pixel in both axes).
double _computeMeanLuminance(img.Image src) {
  double sum = 0;
  int count = 0;
  for (int y = 0; y < src.height; y += 8) {
    for (int x = 0; x < src.width; x += 8) {
      final p = src.getPixel(x, y);
      sum += 0.299 * p.r.toDouble() + 0.587 * p.g.toDouble() + 0.114 * p.b.toDouble();
      count++;
    }
  }
  return count > 0 ? sum / count : 128;
}

/// Crop black bar from the bottom of a truncated JPEG.
img.Image _cropBottomBlackBar(img.Image src) {
  const brightnessThreshold = 20;
  for (int y = src.height - 1; y >= src.height * 2 ~/ 3; y--) {
    for (int x = 0; x < src.width; x += 16) {
      final p = src.getPixel(x, y);
      if (p.r > brightnessThreshold ||
          p.g > brightnessThreshold ||
          p.b > brightnessThreshold) {
        final cropTo = y + 1;
        if (cropTo < src.height - 8) {
          return img.copyCrop(src, x: 0, y: 0, width: src.width, height: cropTo);
        }
        return src;
      }
    }
  }
  return src;
}

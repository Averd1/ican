import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connectivity_service.dart';
import 'on_device_vision_service.dart';
import 'vertex_ai_service.dart';

/// User-selectable vision processing mode.
enum VisionMode {
  auto('Auto', 'Uses cloud when online, offline model when not'),
  offlineOnly('Offline', 'Always uses on-device processing'),
  cloudOnly('Cloud', 'Always uses Gemini cloud API');

  const VisionMode(this.label, this.description);
  final String label;
  final String description;
}

/// Which backend was used for the most recent description.
enum VisionBackend {
  cloud,
  foundationModels, // Apple Foundation Models (iOS 26+)
  vlm, // SmolVLM-500M via llama.cpp mtmd
  visionOnly, // Layer 1 template only
}

enum SceneDescriptionFailureStage { cloudVision, localVision }

class SceneDescriptionException implements Exception {
  const SceneDescriptionException._(
    this.stage,
    this.message,
    this.cause, {
    this.cloudFailure,
  });

  factory SceneDescriptionException.localVision(
    Object cause, {
    Object? cloudFailure,
  }) {
    return SceneDescriptionException._(
      SceneDescriptionFailureStage.localVision,
      'Local vision failed',
      cause,
      cloudFailure: cloudFailure,
    );
  }

  factory SceneDescriptionException.cloudVision(Object cause) {
    return SceneDescriptionException._(
      SceneDescriptionFailureStage.cloudVision,
      'Cloud vision failed',
      cause,
    );
  }

  final SceneDescriptionFailureStage stage;
  final String message;
  final Object cause;
  final Object? cloudFailure;

  String get userMessage {
    switch (stage) {
      case SceneDescriptionFailureStage.cloudVision:
        final failure = cause;
        if (failure is CloudVisionException) return failure.userMessage;
        return 'Cloud vision failed';
      case SceneDescriptionFailureStage.localVision:
        return 'Local vision failed';
    }
  }

  @override
  String toString() => '$message: $cause';
}

/// Unified scene description service.
/// Selects the best available backend and streams text chunks to the caller.
class SceneDescriptionService extends ChangeNotifier {
  SceneDescriptionService({
    required this.cloudService,
    required this.onDeviceService,
    ConnectivityService? connectivityService,
  }) : _connectivity = connectivityService ?? ConnectivityService();

  final VertexAiService cloudService;
  final OnDeviceVisionService onDeviceService;
  final ConnectivityService _connectivity;

  static const String _prefsKey = 'vision_mode';

  VisionMode _mode = VisionMode.auto;
  VisionMode get mode => _mode;

  VisionBackend? _lastBackend;
  VisionBackend? get lastBackend => _lastBackend;

  Object? _lastCloudFailure;
  Object? get lastCloudFailure => _lastCloudFailure;

  /// Load saved mode preference. Call once at app startup.
  Future<void> loadSavedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        _mode = VisionMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => VisionMode.auto,
        );
      }
    } catch (_) {}
  }

  /// Switch vision mode and persist.
  Future<void> setMode(VisionMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, newMode.name);
    } catch (_) {}
    debugPrint('[SceneDescription] Mode changed to: ${newMode.name}');
  }

  /// Describe a scene from a JPEG image.
  /// Yields text chunks for the sentence-splitting TTS loop in HomeViewModel.
  Stream<String> describeScene(
    Uint8List imageBytes, {
    required String systemPrompt,
    void Function(String status, VisionBackend backend)? onStatusUpdate,
  }) async* {
    _lastCloudFailure = null;

    switch (_mode) {
      case VisionMode.cloudOnly:
        _lastBackend = VisionBackend.cloud;
        debugPrint('[SceneDescription] Using backend: cloud');
        onStatusUpdate?.call(
          'Analyzing with ${cloudService.model.label}...',
          VisionBackend.cloud,
        );
        yield* _describeWithCloud(imageBytes, systemPrompt: systemPrompt);

      case VisionMode.offlineOnly:
        yield* _describeWithBestLocal(
          imageBytes,
          systemPrompt: systemPrompt,
          onStatusUpdate: onStatusUpdate,
        );

      case VisionMode.auto:
        final online = await _connectivity.hasInternet();
        if (online) {
          _lastBackend = VisionBackend.cloud;
          debugPrint('[SceneDescription] Using backend: cloud');
          onStatusUpdate?.call(
            'Analyzing with ${cloudService.model.label}...',
            VisionBackend.cloud,
          );
          try {
            await for (final chunk in _describeWithCloud(
              imageBytes,
              systemPrompt: systemPrompt,
            )) {
              yield chunk;
            }
            return;
          } catch (e) {
            _lastCloudFailure = _asCloudFailure(e);
            debugPrint('[SceneDescription] Cloud failed: $_lastCloudFailure');
          }
        }

        yield* _describeWithBestLocal(
          imageBytes,
          systemPrompt: systemPrompt,
          onStatusUpdate: onStatusUpdate,
          cloudFailure: _lastCloudFailure,
        );
    }
  }

  // Single-backend entry points for diagnostics.

  Stream<String> describeWithGemini(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return _describeWithCloud(imageBytes, systemPrompt: systemPrompt);
  }

  Stream<String> describeWithFoundationModels(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return _describeWithFoundationModels(
      imageBytes,
      systemPrompt: systemPrompt,
    );
  }

  Stream<String> describeWithSmolVLM(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return _describeWithVlm(imageBytes, systemPrompt: systemPrompt);
  }

  Stream<String> describeWithVisionTemplate(Uint8List imageBytes) {
    return _describeWithVisionOnly(imageBytes);
  }

  Future<VisionBackend> _bestOfflineBackend() async {
    final fmAvailable = await onDeviceService.isFoundationModelsAvailable();
    if (fmAvailable) return VisionBackend.foundationModels;

    final status = await onDeviceService.getModelStatus();
    if (status == ModelStatus.loaded) return VisionBackend.vlm;
    if (status == ModelStatus.ready) {
      final loaded = await onDeviceService.loadVlmModel();
      if (loaded) return VisionBackend.vlm;
    }

    return VisionBackend.visionOnly;
  }

  Stream<String> _describeWithBestLocal(
    Uint8List imageBytes, {
    required String systemPrompt,
    required void Function(String status, VisionBackend backend)?
    onStatusUpdate,
    Object? cloudFailure,
  }) async* {
    try {
      final backend = await _bestOfflineBackend();
      _lastBackend = backend;
      debugPrint('[SceneDescription] Using backend: ${backend.name}');
      _sendStatusUpdate(backend, onStatusUpdate);
      yield* _describeWithBackend(
        backend,
        imageBytes,
        systemPrompt: systemPrompt,
      );
    } catch (e) {
      debugPrint('[SceneDescription] Local vision failed: $e');
      throw SceneDescriptionException.localVision(
        e,
        cloudFailure: cloudFailure,
      );
    }
  }

  void _sendStatusUpdate(
    VisionBackend backend,
    void Function(String status, VisionBackend backend)? onStatusUpdate,
  ) {
    switch (backend) {
      case VisionBackend.cloud:
        onStatusUpdate?.call(
          'Analyzing with ${cloudService.model.label}...',
          backend,
        );
      case VisionBackend.foundationModels:
        onStatusUpdate?.call('Analyzing on-device...', backend);
      case VisionBackend.vlm:
        onStatusUpdate?.call('Analyzing offline with AI model...', backend);
      case VisionBackend.visionOnly:
        onStatusUpdate?.call('Reading scene...', backend);
    }
  }

  Stream<String> _describeWithBackend(
    VisionBackend backend,
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    switch (backend) {
      case VisionBackend.cloud:
        return _describeWithCloud(imageBytes, systemPrompt: systemPrompt);
      case VisionBackend.foundationModels:
        return _describeWithFoundationModels(
          imageBytes,
          systemPrompt: systemPrompt,
        );
      case VisionBackend.vlm:
        return _describeWithVlm(imageBytes, systemPrompt: systemPrompt);
      case VisionBackend.visionOnly:
        return _describeWithVisionOnly(imageBytes);
    }
  }

  Object _asCloudFailure(Object error) {
    if (error is CloudVisionException) return error;
    if (error is SceneDescriptionException) return error;
    return CloudVisionException.network(error);
  }

  /// Cloud path: stream directly from Gemini.
  Stream<String> _describeWithCloud(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return cloudService.streamContentFromImage(
      imageBytes,
      systemPrompt: systemPrompt,
    );
  }

  /// Foundation Models path: Layer 1 perception -> Apple LLM synthesis.
  Stream<String> _describeWithFoundationModels(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) async* {
    final perception = await onDeviceService.analyzeScene(imageBytes);
    final context = perception.toPromptContext();

    debugPrint('[SceneDescription] FM context: $context');

    var gotTokens = false;
    try {
      await for (final token in onDeviceService.synthesizeWithFoundationModels(
        context,
        systemPrompt: systemPrompt,
      )) {
        gotTokens = true;
        yield token;
      }
    } catch (e) {
      debugPrint('[SceneDescription] Foundation Models failed: $e');
    }

    if (!gotTokens) {
      debugPrint('[SceneDescription] FM produced no output; using template');
      yield perception.toTemplateDescription();
    }
  }

  /// VLM path: Layer 1 perception context fed into SmolVLM.
  Stream<String> _describeWithVlm(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) async* {
    final perception = await onDeviceService.analyzeScene(imageBytes);
    final context = perception.toPromptContext();

    debugPrint('[SceneDescription] VLM context: $context');

    final enhancedPrompt = context.isNotEmpty
        ? '$systemPrompt\n\n$context\n\nDescribe this scene incorporating the context above.'
        : systemPrompt;

    var gotTokens = false;
    try {
      await for (final token in onDeviceService.describeWithVlm(
        imageBytes,
        systemPrompt: enhancedPrompt,
      )) {
        gotTokens = true;
        yield token;
      }
    } catch (e) {
      debugPrint('[SceneDescription] VLM inference failed: $e');
    }

    if (!gotTokens) {
      debugPrint('[SceneDescription] VLM produced no output; using template');
      yield perception.toTemplateDescription();
    }
  }

  /// Vision-only path: Layer 1 template, no VLM needed.
  Stream<String> _describeWithVisionOnly(Uint8List imageBytes) async* {
    final perception = await onDeviceService.analyzeScene(imageBytes);
    yield perception.toTemplateDescription();
  }
}

extension ScenePerceptionResultTemplate on ScenePerceptionResult {
  /// Assemble a spoken description from Layer 1 data alone.
  String toTemplateDescription() {
    final sentences = <String>[];

    if (sceneClassification != 'unknown' && sceneConfidence > 0.15) {
      final label = sceneClassification.replaceAll('_', ' ');
      sentences.add('You appear to be in a $label setting.');
    } else {
      sentences.add('The scene could not be clearly identified.');
    }

    final close = detectedObjects
        .where((o) => (o.relativeDepth ?? 1.0) < 0.50)
        .toList();
    if (close.isNotEmpty) {
      final descs = close.take(3).map((o) => o.spatialLabel).join(', ');
      sentences.add('Caution: $descs.');
    }

    if (personCount > 0) {
      final noun = personCount == 1 ? '1 person is' : '$personCount people are';
      sentences.add(
        '${noun[0].toUpperCase()}${noun.substring(1)} detected nearby.',
      );
    }

    if (ocrTexts.isNotEmpty) {
      if (ocrTexts.length == 1) {
        sentences.add('Text reads: ${ocrTexts.first}.');
      } else {
        sentences.add('Visible text includes: ${ocrTexts.take(3).join(', ')}.');
      }
    }

    final others = detectedObjects
        .where((o) => (o.relativeDepth ?? 0.0) >= 0.50)
        .take(4);
    if (others.isNotEmpty) {
      sentences.add(
        'Also nearby: ${others.map((o) => o.spatialLabel).join(', ')}.',
      );
    }

    return sentences.join(' ');
  }
}
